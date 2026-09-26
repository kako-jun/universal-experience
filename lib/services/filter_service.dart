import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/disability_type.dart';
import '../src/rust/api/sensus_bridge.dart';

/// anomaly 系（-omaly）のデフォルト severity（推奨 strength）。
///
/// 旧 `color_vision_simulator.dart`（#13 で撤去）が anomaly を表現していた
/// severity 値と同一。anomaly 型は base の -opia と同じ [VisionFilter] へ
/// マップされるため、両者の区別はこの値を strength（intensity < 1.0）として
/// 渡すことで表現する。
const double kAnomalyDefaultSeverity = 0.6;

/// 各 [ColorVisionType] に推奨される適用強度（strength / intensity）を返す。
///
/// - 2色覚（-opia）系および achromatopsia は 1.0（フル適用）。
/// - 3色覚（-omaly）系は [kAnomalyDefaultSeverity]（弱め適用）。
/// - none は 0.0（適用なし）。
///
/// anomaly と opia は同じ [VisionFilter] にマップされるため、両者の見え方の
/// 違いはこの strength の差で表現する。呼び出し側はこの値を sensus / シェーダへ
/// 渡す strength として用いる責務を持つ。[FilterService] は各タイプを初めて
/// 選んだときの初期強度としてこの値を使う（#57）。
double recommendedStrength(ColorVisionType type) {
  switch (type) {
    case ColorVisionType.none:
      return 0.0;
    case ColorVisionType.protanomaly:
    case ColorVisionType.deuteranomaly:
    case ColorVisionType.tritanomaly:
      return kAnomalyDefaultSeverity;
    case ColorVisionType.protanopia:
    case ColorVisionType.deuteranopia:
    case ColorVisionType.tritanopia:
    case ColorVisionType.achromatopsia:
      return 1.0;
  }
}

/// 色覚フィルタの選択状態を保持するサービス。
///
/// **アルゴリズムは持たない**。色覚変換の正本は sensus-core crate にあり、ue は
/// FRB ブリッジ（`lib/src/rust/api/sensus_bridge.dart`）経由でそれを消費する。
/// 旧 `color_vision_filter` プラグイン（OS 全体 system-wide フィルタ）と
/// `color_vision_simulator.dart`（ue 内 LMS 再実装）は #13 で撤去した。
///
/// このサービスは UI の選択状態（どのフィルタを・どの強度で選んでいるか）だけを
/// 管理する。選んだフィルタを実際の画像へ適用するのは sensus 経路
/// （`lib/rendering/shader_filter.dart` の GPU シェーダ）の役割。before/after
/// プレビュー（`before_after_view.dart`）は protanopia/protanomaly について
/// [intensity] をそのまま描画 strength として使う。それ以外の型はまだ
/// 「描画は近日対応」のプレースホルダ（#59）。
///
/// ## 強度はタイプごとに記憶する（#57）
///
/// [intensity] は色覚タイプ（[ColorVisionType]）ごとに別々に記憶する
/// （内部 `Map<ColorVisionType, double>`）。まだ選んだことのないタイプは
/// [recommendedStrength] を初期値として返す（-opia は 1.0、-omaly は弱め）。
/// [applyFilter] にわざわざ `intensity:` を渡さない限り、フィルタを切り替えても
/// **切替前のタイプの強度は上書きされない** — 元のバグ（#52 監査 must）は
/// `FilterSelector` / トレイの両方が `applyFilter(type)` を既定 intensity 1.0
/// で呼んでいたため、フィルタを選ぶたびに保存済み強度が 1.0 に戻り、かつ
/// protanomaly が protanopia と全く同じ見た目になっていたことだった。
///
/// 永続化は本サービス自身が担う（[load] / [SharedPreferences] キー
/// [keyIntensityByType]、[setIntensity] は 300ms デバウンスして書き込む）。
/// かつては `SettingsService` が単一の `intensity` キーで管理していたが（#17）、
/// スライダーの 1 目盛りごとに `notifyListeners` すると、`SettingsService` を
/// 購読する `MaterialApp`（テーマ/ロケール用の Consumer）まで巻き込んで毎回
/// アプリ全体が再構築されてしまっていた（#57）。intensity の通知を
/// `SettingsService` の外（このサービス自身の `ChangeNotifier`）に出すことで
/// その再構築を止める。`FilterService` の listener は `Consumer<FilterService>`
/// を使うウィジェット（スライダー・プレビュー等）だけを再構築する。
///
/// [load] 時、per-type の保存（[keyIntensityByType]）が無ければ、旧
/// `SettingsService` の単一キー（[legacyIntensityKey]）を一度だけ、呼び出し側が
/// 指定した「起動時に選ばれるタイプ」の初期値として移行する。以降このキーへは
/// 二度と書かない。
class FilterService extends ChangeNotifier {
  FilterService({
    SharedPreferences? prefs,
    Duration debounce = const Duration(milliseconds: 300),
  })  : _prefs = prefs,
        _debounceDuration = debounce;

  /// 旧 `SettingsService.keyIntensity`（#17）と同じキー文字列。[load] が
  /// per-type の保存（[keyIntensityByType]）を見つけられなかったときだけ一度
  /// 読み、移行に使う。
  static const String legacyIntensityKey = 'settings.intensity';

  /// per-type intensity の永続化キー。JSON オブジェクト
  /// （例: `{"protanomaly":0.6,"protanopia":1.0}`）として保存する。
  static const String keyIntensityByType = 'settings.intensityByType';

  SharedPreferences? _prefs;
  final Duration _debounceDuration;
  Timer? _debounce;

  ColorVisionType _currentFilter = ColorVisionType.none;
  final Map<ColorVisionType, double> _intensityByType = {};
  bool _isActive = false;

  /// 現在選択中の色覚タイプ。
  ColorVisionType get currentFilter => _currentFilter;

  /// 現在選択中のタイプの強度 0.0..1.0。そのタイプをまだ選んだことがなければ
  /// [recommendedStrength] を返す（#57）。
  double get intensity =>
      _intensityByType[_currentFilter] ?? recommendedStrength(_currentFilter);

  /// フィルタが選択されている（none 以外）か。
  bool get isActive => _isActive;

  /// anomaly 型（protanomaly / deuteranomaly / tritanomaly）の既定 severity 係数。
  ///
  /// トップレベル定数 [kAnomalyDefaultSeverity] への委譲。anomaly 型は対応する
  /// -opia 型と同一の [VisionFilter] にマップされるため、レンダリング時に
  /// `strength`（[intensity]）を下げることで「軽度（anomaly）」を表現する。
  /// 旧 simulator（`color_vision_simulator.dart`、#13 で撤去）は anomaly を
  /// severity 0.6 相当で表現していた。その知見を失わないための定数。
  double get anomalyDefaultSeverity => kAnomalyDefaultSeverity;

  /// 現在選択中のタイプに推奨される strength（[recommendedStrength] への委譲）。
  double get recommendedStrengthForCurrent =>
      recommendedStrength(_currentFilter);

  /// 現在選択中のタイプに対応する sensus の [VisionFilter]。
  ///
  /// none の場合は null。
  ///
  /// 契約（anomaly）: anomaly 型（protanomaly / deuteranomaly / tritanomaly）は、
  /// 対応する -opia 型（base）と **同一の** VisionFilter を返す。anomaly と opia の
  /// 違いは、この getter ではなく **レンダリング時の strength（[intensity]）** でのみ
  /// 表現される。すなわち anomaly では intensity < 1（推奨値 [anomalyDefaultSeverity]
  /// = 0.6）を渡す責務が **呼び出し側** にある。[intensity] は #57 よりタイプごとに
  /// 記憶されるため、protanomaly を選んだ時点で自動的に 0.6 が使われる。
  VisionFilter? get sensusFilter {
    switch (_currentFilter) {
      case ColorVisionType.none:
        return null;
      // protanopia / protanomaly は同一の変換を返す。強度差は strength（intensity）で表現。
      case ColorVisionType.protanopia:
      case ColorVisionType.protanomaly:
        return const VisionFilter.protanopia();
      // deuteranopia / deuteranomaly は同一の変換を返す。強度差は strength（intensity）で表現。
      case ColorVisionType.deuteranopia:
      case ColorVisionType.deuteranomaly:
        return const VisionFilter.deuteranopia();
      // tritanopia / tritanomaly は同一の変換を返す。強度差は strength（intensity）で表現。
      case ColorVisionType.tritanopia:
      case ColorVisionType.tritanomaly:
        return const VisionFilter.tritanopia();
      case ColorVisionType.achromatopsia:
        return const VisionFilter.achromatopsia();
    }
  }

  /// 永続化されている per-type intensity（[keyIntensityByType]）を読み込む。
  ///
  /// アプリ起動時に一度、`SettingsService.load()` の後・`applyFilter` で起動時の
  /// フィルタ種別をシードする前に呼ぶ（`main.dart` 参照）。
  ///
  /// per-type の保存がまだ無い（#57 より前にインストールされた環境）場合は、旧
  /// 単一キー [legacyIntensityKey] があれば、[migrateLegacyIntensityFor] に一度だけ
  /// 移行する（通常は起動時に復元される `SettingsService.filterType` を渡す）。
  Future<void> load({
    ColorVisionType migrateLegacyIntensityFor = ColorVisionType.none,
  }) async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();

    final json = prefs.getString(keyIntensityByType);
    if (json != null) {
      try {
        final decoded = jsonDecode(json);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            final type = _typeFromName(key.toString());
            if (type != null && value is num) {
              _intensityByType[type] = value.toDouble().clamp(0.0, 1.0);
            }
          });
        }
      } catch (_) {
        // 壊れた JSON は無視する。以降 recommendedStrength へフォールバックする。
      }
      return;
    }

    final legacy = prefs.getDouble(legacyIntensityKey);
    if (legacy != null) {
      _intensityByType[migrateLegacyIntensityFor] = legacy.clamp(0.0, 1.0);
    }
  }

  /// フィルタを選択する（選択状態の更新のみ。OS への system-wide 適用はしない）。
  ///
  /// [intensity] を渡さない場合、[type] を選んだときの強度は変更しない
  /// （そのタイプを前回選んだときの値、または初めてなら [recommendedStrength]
  /// のまま）。[intensity] を渡した場合のみ、そのタイプの記憶を明示的に上書きする
  /// （起動時のシード・テストなどの用途）。
  void applyFilter(ColorVisionType type, {double? intensity}) {
    _currentFilter = type;
    if (intensity != null) {
      _intensityByType[type] = intensity.clamp(0.0, 1.0);
    }
    _isActive = type != ColorVisionType.none;
    notifyListeners();
    if (intensity != null) _schedulePersist();
  }

  /// 現在選択中のタイプの強度を更新する（0.0..1.0 に clamp）。
  ///
  /// [notifyListeners] は `FilterService` の listener（スライダー・プレビュー等の
  /// `Consumer<FilterService>`）だけを再構築する。`SettingsService`
  /// （延いては `MaterialApp`）へは伝播しない（#57）。永続化は 300ms デバウンス
  /// して行う。
  void setIntensity(double intensity) {
    _intensityByType[_currentFilter] = intensity.clamp(0.0, 1.0);
    notifyListeners();
    _schedulePersist();
  }

  /// 選択を解除する（none に戻す）。
  void deactivate() {
    _currentFilter = ColorVisionType.none;
    _isActive = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _schedulePersist() {
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () {
      unawaited(_persist());
    });
  }

  Future<void> _persist() async {
    try {
      final prefs = _prefs ??= await SharedPreferences.getInstance();
      final json = jsonEncode({
        for (final entry in _intensityByType.entries)
          entry.key.name: entry.value,
      });
      await prefs.setString(keyIntensityByType, json);
    } catch (_) {
      // 永続化の失敗は致命的ではない（次回起動時は recommendedStrength への
      // フォールバックに任せる）。UI 側には伝播させない。
    }
  }

  /// テスト専用: デバウンス中の永続化を実タイマーの発火を待たず即座に実行する
  /// （#57）。本体コードからは呼ばない。
  @visibleForTesting
  Future<void> debugFlushPersist() async {
    _debounce?.cancel();
    _debounce = null;
    await _persist();
  }

  static ColorVisionType? _typeFromName(String name) {
    for (final type in ColorVisionType.values) {
      if (type.name == name) return type;
    }
    return null;
  }
}
