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

/// [ColorVisionType] → sensus [VisionFilter] の対応表（単一の正本）。
///
/// [type] が [ColorVisionType.none] なら null。
///
/// 契約（anomaly）: anomaly 型（protanomaly / deuteranomaly / tritanomaly）は、
/// 対応する -opia 型（base）と **同一の** VisionFilter を返す。anomaly と opia の
/// 違いは、この関数ではなく **レンダリング時の strength（[recommendedStrength]
/// / [FilterService.intensity]）** でのみ表現される。すなわち anomaly では
/// strength < 1（推奨値 [kAnomalyDefaultSeverity] = 0.6）を渡す責務が
/// **呼び出し側** にある。
///
/// `lib/services/color_vision_selection.dart` の `selectColorVision`（色覚
/// クイック選択を [VisionFilterState] へ写す、#60）、2×2 比較の
/// `color_vision_compare.dart`（#84）、プレビューの CPU レンダラ（#85）が
/// この対応表を参照する。複数箇所が別々に対応表を持つと、色覚クイック選択と
/// プレビュー描画で別々のフィルタが適用されるバグ（#52 と同種）を起こしうる
/// ため、ここ 1 箇所に集約する。
VisionFilter? visionFilterForColorVisionType(ColorVisionType type) {
  switch (type) {
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

/// 色覚フィルタの選択状態を保持するサービス。
///
/// **アルゴリズムは持たない**。色覚変換の正本は sensus-core crate にあり、ue は
/// FRB ブリッジ（`lib/src/rust/api/sensus_bridge.dart`）経由でそれを消費する。
/// 旧 `color_vision_filter` プラグイン（OS 全体 system-wide フィルタ）と
/// `color_vision_simulator.dart`（ue 内 LMS 再実装）は #13 で撤去した。
///
/// このサービスは UI の選択状態（どのフィルタを・どの強度で選んでいるか）だけを
/// 管理する。実描画のフィルタ適用は sensus 経路（`lib/rendering/
/// cpu_vision_renderer.dart` の CPU `apply()`、#85）の役割で、このサービス
/// 自身は呼ばない。色覚のクイック選択（`FilterBrowser`/トレイ）は
/// `lib/services/color_vision_selection.dart` の `selectColorVision` を経由
/// してこのサービスと [VisionFilterState] の両方を明示的に更新し、before/after
/// プレビュー（`before_after_view.dart`）は常に [VisionFilterState] だけを
/// 描画対象にする（#60）。このサービス自身の [currentFilter]/[intensity] は、
/// 色覚のクイック選択 UI（チップの点灯・強度スライダー）の表示状態と、
/// 色覚タイプごとの強度の記憶（下記）のために存在する。
///
/// ## 強度はタイプごとに記憶する（#57）
///
/// [intensity] は色覚タイプ（[ColorVisionType]）ごとに別々に記憶する
/// （内部 `Map<ColorVisionType, double>`）。まだ選んだことのないタイプは
/// [recommendedStrength] を初期値として返す（-opia は 1.0、-omaly は弱め）。
/// [applyFilter] にわざわざ `intensity:` を渡さない限り、フィルタを切り替えても
/// **切替前のタイプの強度は上書きされない** — 元のバグ（#52 監査 must）は
/// `FilterBrowser` / トレイの両方が `applyFilter(type)` を既定 intensity 1.0
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
/// 旧 `SettingsService` の単一キー（[legacyIntensityKey]）からの移行は行わない
/// （#57 時点でアプリは未リリースで既存ユーザーがいないため）。[load] はこの
/// キーを一切読まず、残っていれば削除するだけ。
class FilterService extends ChangeNotifier {
  FilterService({
    SharedPreferences? prefs,
    Duration debounce = const Duration(milliseconds: 300),
  })  : _prefs = prefs,
        _debounceDuration = debounce;

  /// 旧 `SettingsService.keyIntensity`（#17、#57 で撤去）と同じキー文字列。
  /// [load] はこの値を読まない（移行しない）。ディスクに残っていれば
  /// [load] が削除するだけの、掃除専用のキー名。
  static const String legacyIntensityKey = 'settings.intensity';

  /// per-type intensity の永続化キー。JSON オブジェクト
  /// （例: `{"protanomaly":0.6,"protanopia":1.0}`）として保存する。
  static const String keyIntensityByType = 'settings.intensityByType';

  SharedPreferences? _prefs;
  final Duration _debounceDuration;
  Timer? _debounce;

  ColorVisionType _currentFilter = ColorVisionType.none;
  final Map<ColorVisionType, double> _intensityByType = {};

  /// 現在選択中の色覚タイプ。
  ColorVisionType get currentFilter => _currentFilter;

  /// 現在選択中のタイプの強度 0.0..1.0。そのタイプをまだ選んだことがなければ
  /// [recommendedStrength] を返す（#57）。
  double get intensity =>
      _intensityByType[_currentFilter] ?? recommendedStrength(_currentFilter);

  /// 永続化されている per-type intensity（[keyIntensityByType]）を読み込む。
  ///
  /// アプリ起動時に一度、`SettingsService.load()` の後・`applyFilter` で起動時の
  /// フィルタ種別をシードする前に呼ぶ（`main.dart` 参照）。
  ///
  /// 旧単一キー [legacyIntensityKey] は読まない（移行はしない。アプリは
  /// #57 時点で未リリースのため既存ユーザーはいない）。ディスクに残っていれば
  /// 値を見ずに削除するだけで、以降のタイプ選択は素直に [recommendedStrength]
  /// から始まる。
  Future<void> load() async {
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
    }

    await prefs.remove(legacyIntensityKey);
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
    notifyListeners();
  }

  @override
  void dispose() {
    // 保留中のデバウンス書き込みがあれば、実タイマーの発火を待たず飛ばす
    // （待つと dispose() が完了するまでの間、直近の intensity 変更が失われうる）。
    // dispose() 自体は同期 API なので await はできない。
    if (_debounce != null) {
      _debounce!.cancel();
      _debounce = null;
      unawaited(_persist());
    }
    super.dispose();
  }

  void _schedulePersist() {
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () {
      _debounce = null;
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

  /// 保留中のデバウンス書き込みがあれば、実タイマーの発火を待たず即座に実行する
  /// （#57）。アプリ終了シーケンス（トレイの終了・ウィンドウを閉じて終了する
  /// 経路・`AppLifecycleListener.onExitRequested`、`main.dart` 参照）で、
  /// デバウンス待ち（既定 300ms）のせいで直近の intensity 変更が失われないよう
  /// 呼ぶ。保留中の書き込みが無ければ何もしない（無条件に書くと、変更が無い
  /// のに毎回 SharedPreferences へ書き込むことになる）。テストでも、実タイマーの
  /// 発火を待たず永続化結果を検証するのに使える。
  Future<void> flush() async {
    if (_debounce == null) return;
    _debounce!.cancel();
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
