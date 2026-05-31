import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/services/filter_service.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';

/// FilterService の選択状態モデルのテスト。
///
/// #13 で plugin/simulator を撤去し、FilterService は「どのフィルタを・どの強度で
/// 選んでいるか」だけを保持する純粋な状態モデルになった。ここではその選択状態と
/// ColorVisionType → sensus VisionFilter マッピングを検証する（GPU 描画は
/// protanopia_golden_test.dart の担当）。
void main() {
  group('FilterService 選択状態', () {
    test('初期状態は none / intensity 1.0 / 非アクティブ', () {
      final service = FilterService();
      expect(service.currentFilter, ColorVisionType.none);
      expect(service.intensity, 1.0);
      expect(service.isActive, isFalse);
      expect(service.sensusFilter, isNull);
    });

    test('applyFilter で currentFilter / isActive が変わり notify される', () {
      final service = FilterService();
      var notified = 0;
      service.addListener(() => notified++);

      service.applyFilter(ColorVisionType.deuteranopia);

      expect(service.currentFilter, ColorVisionType.deuteranopia);
      expect(service.isActive, isTrue);
      expect(notified, 1);
    });

    test('none を選ぶと isActive が false に戻る', () {
      final service = FilterService();
      service.applyFilter(ColorVisionType.protanopia);
      expect(service.isActive, isTrue);

      service.applyFilter(ColorVisionType.none);
      expect(service.currentFilter, ColorVisionType.none);
      expect(service.isActive, isFalse);
      expect(service.sensusFilter, isNull);
    });

    test('deactivate で none に戻る', () {
      final service = FilterService();
      service.applyFilter(ColorVisionType.tritanopia);
      service.deactivate();
      expect(service.currentFilter, ColorVisionType.none);
      expect(service.isActive, isFalse);
    });

    test('applyFilter の intensity は 0..1 に clamp される', () {
      final service = FilterService();
      service.applyFilter(ColorVisionType.protanopia, intensity: 1.7);
      expect(service.intensity, 1.0);
      service.applyFilter(ColorVisionType.protanopia, intensity: -0.5);
      expect(service.intensity, 0.0);
    });

    test('setIntensity は 0..1 に clamp し notify する', () {
      final service = FilterService();
      var notified = 0;
      service.addListener(() => notified++);

      service.setIntensity(0.5);
      expect(service.intensity, 0.5);
      service.setIntensity(2.0);
      expect(service.intensity, 1.0);
      service.setIntensity(-1.0);
      expect(service.intensity, 0.0);
      expect(notified, 3);
    });
  });

  group('sensusFilter マッピング', () {
    test('none は null', () {
      final service = FilterService()..applyFilter(ColorVisionType.none);
      expect(service.sensusFilter, isNull);
    });

    test('-opia は対応する VisionFilter へマップ', () {
      final cases = <ColorVisionType, VisionFilter>{
        ColorVisionType.protanopia: const VisionFilter.protanopia(),
        ColorVisionType.deuteranopia: const VisionFilter.deuteranopia(),
        ColorVisionType.tritanopia: const VisionFilter.tritanopia(),
        ColorVisionType.achromatopsia: const VisionFilter.achromatopsia(),
      };
      cases.forEach((type, expected) {
        final service = FilterService()..applyFilter(type);
        expect(service.sensusFilter, expected, reason: '$type');
      });
    });

    test('-anomaly は base の -opia へマップ（強度 < 1 相当）', () {
      final cases = <ColorVisionType, VisionFilter>{
        ColorVisionType.protanomaly: const VisionFilter.protanopia(),
        ColorVisionType.deuteranomaly: const VisionFilter.deuteranopia(),
        ColorVisionType.tritanomaly: const VisionFilter.tritanopia(),
      };
      cases.forEach((type, expected) {
        final service = FilterService()..applyFilter(type);
        expect(service.sensusFilter, expected, reason: '$type');
      });
    });
  });
}
