import 'package:flutter/foundation.dart';

import '../models/disability_type.dart';
import '../src/rust/api/sensus_bridge.dart';
import 'vision_filter_state.dart';

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
/// 渡す strength として用いる責務を持つ。[VisionFilterState] は、強度の記憶が無い
/// 色覚層の強度としてこの値を導出する（#57, #117）。
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

/// 色覚フィルタのクイック選択 UI（チップの点灯・強度スライダー・トレイ）の
/// 表示状態を保持するサービス。
///
/// **アルゴリズムは持たない**。色覚変換の正本は sensus-core crate にあり、ue は
/// FRB ブリッジ（`lib/src/rust/api/sensus_bridge.dart`）経由でそれを消費する。
/// 旧 `color_vision_filter` プラグイン（OS 全体 system-wide フィルタ）と
/// `color_vision_simulator.dart`（ue 内 LMS 再実装）は #13 で撤去した。
///
/// 実描画のフィルタ適用は sensus 経路（`lib/rendering/cpu_vision_renderer.dart` の
/// CPU `apply()`、#85）の役割で、このサービス自身は呼ばない。色覚のクイック選択
/// （`FilterBrowser`/トレイ）は `lib/services/color_vision_selection.dart` の
/// `selectColorVision` を経由してこのサービスと [VisionFilterState] の両方を明示的に
/// 更新し、before/after プレビュー（`before_after_view.dart`）は常に
/// [VisionFilterState] だけを描画対象にする（#60）。
///
/// ## 強度は [VisionFilterState] のキーごとの記憶に 1 つだけある（#57, #117）
///
/// このサービスは強度を**自前で持たない**。[intensity] は [VisionFilterState] の
/// 「キー（別名 id ?? カタログ id）ごとの強度の記憶」のうち、[currentFilter] のキー
/// （[ColorVisionType.name]）を読み、無ければ [recommendedStrength] を返す
/// （-opia は 1.0、-omaly は弱め）。[setIntensity] / [applyFilter] の `intensity:` は
/// その記憶へ書く。[applyFilter] に `intensity:` を渡さない限り、フィルタを切り替えても
/// **切替前のタイプの強度は上書きされない**（#52 監査 must の再発防止）。
///
/// 強度の書き込みは [VisionFilterState] の listener にも届く（プレビューが再描画
/// される）。このサービス自身の listener にも通知する（スライダー・トレイが見る）。
/// 強度の永続化は [VisionFilterState] の保存（`VisionFilterStore`）が担い、かつての
/// `settings.intensityByType` はそこへ一度だけ取り込んで捨てる
/// （`VisionFilterStore.migrateLegacyStrengths`）。このサービスはもう SharedPreferences
/// を読み書きしない。
class FilterService extends ChangeNotifier {
  FilterService({required VisionFilterState visionState})
      : _visionState = visionState;

  final VisionFilterState _visionState;

  ColorVisionType _currentFilter = ColorVisionType.none;

  /// 現在選択中の色覚タイプ。
  ColorVisionType get currentFilter => _currentFilter;

  /// 現在選択中のタイプの強度 0.0..1.0。そのタイプの記憶が無ければ
  /// [recommendedStrength] を返す（記憶へは書かない）。none は 0.0。
  double get intensity {
    if (_currentFilter == ColorVisionType.none) return 0.0;
    return _visionState.strengthForKey(_currentFilter.name) ??
        recommendedStrength(_currentFilter);
  }

  /// フィルタを選択する（選択状態の更新のみ。OS への system-wide 適用はしない）。
  ///
  /// [intensity] を渡さない場合、[type] を選んだときの強度は変更しない
  /// （そのタイプの記憶、または無ければ [recommendedStrength] のまま）。
  /// [intensity] を渡した場合のみ、そのタイプの記憶を明示的に上書きする
  /// （起動時のシード・テストなどの用途。none には記憶を持たないので無視する）。
  void applyFilter(ColorVisionType type, {double? intensity}) {
    _currentFilter = type;
    if (intensity != null && type != ColorVisionType.none) {
      _visionState.setStrengthForKey(type.name, intensity);
    }
    notifyListeners();
  }

  /// 現在選択中のタイプの強度を更新する（0.0..1.0 に clamp）。none のときは記憶を
  /// 持たないので何も書かず、通知だけする。
  ///
  /// [notifyListeners] は `FilterService` の listener（スライダー・トレイ等）へ。
  /// `SettingsService`（延いては `MaterialApp`）へは伝播しない（#57）。
  void setIntensity(double intensity) {
    if (_currentFilter != ColorVisionType.none) {
      _visionState.setStrengthForKey(_currentFilter.name, intensity);
    }
    notifyListeners();
  }

  /// 選択を解除する（none に戻す）。
  void deactivate() {
    _currentFilter = ColorVisionType.none;
    notifyListeners();
  }
}
