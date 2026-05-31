import 'package:flutter/foundation.dart';
import '../models/disability_type.dart';
import '../src/rust/api/sensus_bridge.dart';

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

  /// 現在選択中のタイプに対応する sensus の [VisionFilter]。
  ///
  /// none の場合は null。anomaly（-anomaly）系は sensus が severity を `strength`
  /// で表現するため、対応する -opia バリアント（base）へマップする。anomaly は
  /// 「強度 < 1 相当の -opia」として扱う方針（強度は [intensity] で別途渡す）。
  VisionFilter? get sensusFilter {
    switch (_currentFilter) {
      case ColorVisionType.none:
        return null;
      case ColorVisionType.protanopia:
      // protanomaly は強度 < 1 の protanopia 相当（sensus は base + strength で表現）。
      case ColorVisionType.protanomaly:
        return const VisionFilter.protanopia();
      case ColorVisionType.deuteranopia:
      // deuteranomaly は強度 < 1 の deuteranopia 相当。
      case ColorVisionType.deuteranomaly:
        return const VisionFilter.deuteranopia();
      case ColorVisionType.tritanopia:
      // tritanomaly は強度 < 1 の tritanopia 相当。
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
