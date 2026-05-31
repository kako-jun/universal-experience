import 'package:flutter/foundation.dart';
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
/// 渡す strength として用いる責務を持つ。
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
/// （`lib/rendering/shader_filter.dart` の GPU シェーダ）の役割であり、ライブ
/// 画面キャプチャ経路は別 Issue（#1/#3/#4）で実装する。
class FilterService extends ChangeNotifier {
  ColorVisionType _currentFilter = ColorVisionType.none;
  double _intensity = 1.0;
  bool _isActive = false;

  /// 現在選択中の色覚タイプ。
  ColorVisionType get currentFilter => _currentFilter;

  /// フィルタ強度 0.0..1.0。
  double get intensity => _intensity;

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
  /// = 0.6）を渡す責務が **呼び出し側** にある。低い strength を渡さない限り、anomaly は
  /// end-to-end では opia と区別されない（intensity 既定 1.0）。
  ///
  // TODO(#1,#3,#4): 現状 UI からは intensity が sensusFilter / 描画 strength と
  // 未結合のため、ライブ適用（anomaly の軽度表現）は #1/#3/#4 のブリッジ結線待ち。
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

  /// フィルタを選択する（選択状態の更新のみ。OS への system-wide 適用はしない）。
  void applyFilter(ColorVisionType type, {double intensity = 1.0}) {
    _currentFilter = type;
    _intensity = intensity.clamp(0.0, 1.0);
    _isActive = type != ColorVisionType.none;
    notifyListeners();
  }

  /// 強度を更新する（0.0..1.0 に clamp）。
  void setIntensity(double intensity) {
    _intensity = intensity.clamp(0.0, 1.0);
    notifyListeners();
  }

  /// 選択を解除する（none に戻す）。
  void deactivate() {
    _currentFilter = ColorVisionType.none;
    _isActive = false;
    notifyListeners();
  }
}
