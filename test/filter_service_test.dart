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

    test('achromatopsia 適用で isActive=true / sensusFilter=achromatopsia', () {
      final service = FilterService()
        ..applyFilter(ColorVisionType.achromatopsia);
      expect(service.isActive, isTrue);
      expect(service.currentFilter, ColorVisionType.achromatopsia);
      expect(service.sensusFilter, const VisionFilter.achromatopsia());
    });

    test('anomaly 型適用で intensity が渡した値のまま state に保持される', () {
      final service = FilterService()
        ..applyFilter(ColorVisionType.deuteranomaly, intensity: 0.6);
      expect(service.currentFilter, ColorVisionType.deuteranomaly);
      expect(service.intensity, 0.6);
      // anomaly は対応する -opia と同一 VisionFilter にマップされる契約
      expect(service.sensusFilter, const VisionFilter.deuteranopia());
    });

    test('anomalyDefaultSeverity は旧 simulator の severity 0.6 を保持する', () {
      final service = FilterService();
      expect(service.anomalyDefaultSeverity, 0.6);
    });
  });

  group('recommendedStrength / kAnomalyDefaultSeverity', () {
    test('kAnomalyDefaultSeverity は 0.6', () {
      expect(kAnomalyDefaultSeverity, 0.6);
    });

    test('anomaly 系は kAnomalyDefaultSeverity を返す', () {
      expect(
        recommendedStrength(ColorVisionType.protanomaly),
        kAnomalyDefaultSeverity,
      );
      expect(
        recommendedStrength(ColorVisionType.deuteranomaly),
        kAnomalyDefaultSeverity,
      );
      expect(
        recommendedStrength(ColorVisionType.tritanomaly),
        kAnomalyDefaultSeverity,
      );
    });

    test('opia 系および achromatopsia は 1.0 を返す', () {
      expect(recommendedStrength(ColorVisionType.protanopia), 1.0);
      expect(recommendedStrength(ColorVisionType.deuteranopia), 1.0);
      expect(recommendedStrength(ColorVisionType.tritanopia), 1.0);
      expect(recommendedStrength(ColorVisionType.achromatopsia), 1.0);
    });

    test('none は 0.0 を返す', () {
      expect(recommendedStrength(ColorVisionType.none), 0.0);
    });

    test('recommendedStrengthForCurrent は選択中タイプに連動する', () {
      final service = FilterService()..applyFilter(ColorVisionType.protanomaly);
      expect(service.recommendedStrengthForCurrent, kAnomalyDefaultSeverity);
      service.applyFilter(ColorVisionType.protanopia);
      expect(service.recommendedStrengthForCurrent, 1.0);
    });
  });
}
