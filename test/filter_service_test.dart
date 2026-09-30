import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/services/filter_service.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';

/// FilterService の選択状態モデルのテスト。
///
/// #13 で plugin/simulator を撤去し、FilterService は「どの色覚タイプを選んでいるか」
/// だけを持つ。強度の正本は #117 で [VisionFilterState] のキーごとの記憶 1 つになり、
/// FilterService はそれへの薄い窓になった（永続化は VisionFilterStore の担当で、
/// vision_filter_store_test.dart が見る）。ここではその選択状態・委譲と
/// ColorVisionType → sensus VisionFilter マッピングを検証する（GPU 描画は
/// protanopia_golden_test.dart の担当）。
FilterService _service([VisionFilterState? state]) =>
    FilterService(visionState: state ?? VisionFilterState());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FilterService 選択状態', () {
    test('初期状態は none / 非アクティブ。intensity は none の recommendedStrength（0.0）', () {
      final service = _service();
      expect(service.currentFilter, ColorVisionType.none);
      expect(service.intensity, 0.0);
    });

    test('applyFilter で currentFilter が変わり notify される', () {
      final service = _service();
      var notified = 0;
      service.addListener(() => notified++);

      service.applyFilter(ColorVisionType.deuteranopia);

      expect(service.currentFilter, ColorVisionType.deuteranopia);
      expect(notified, 1);
    });

    test('none を選ぶと currentFilter が none に戻る', () {
      final service = _service();
      service.applyFilter(ColorVisionType.protanopia);
      expect(service.currentFilter, ColorVisionType.protanopia);

      service.applyFilter(ColorVisionType.none);
      expect(service.currentFilter, ColorVisionType.none);
    });

    test('deactivate で none に戻る', () {
      final service = _service();
      service.applyFilter(ColorVisionType.tritanopia);
      service.deactivate();
      expect(service.currentFilter, ColorVisionType.none);
    });

    test('applyFilter の intensity は 0..1 に clamp される', () {
      final service = _service();
      service.applyFilter(ColorVisionType.protanopia, intensity: 1.7);
      expect(service.intensity, 1.0);
      service.applyFilter(ColorVisionType.protanopia, intensity: -0.5);
      expect(service.intensity, 0.0);
    });

    test('setIntensity は 0..1 に clamp し notify する', () {
      final service = _service()..applyFilter(ColorVisionType.protanopia);
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

  group('visionFilterForColorVisionType マッピング', () {
    test('none は null', () {
      expect(visionFilterForColorVisionType(ColorVisionType.none), isNull);
    });

    test('-opia は対応する VisionFilter へマップ', () {
      final cases = <ColorVisionType, VisionFilter>{
        ColorVisionType.protanopia: const VisionFilter.protanopia(),
        ColorVisionType.deuteranopia: const VisionFilter.deuteranopia(),
        ColorVisionType.tritanopia: const VisionFilter.tritanopia(),
        ColorVisionType.achromatopsia: const VisionFilter.achromatopsia(),
      };
      cases.forEach((type, expected) {
        expect(visionFilterForColorVisionType(type), expected, reason: '$type');
      });
    });

    test('-anomaly は base の -opia へマップ（強度 < 1 相当）', () {
      final cases = <ColorVisionType, VisionFilter>{
        ColorVisionType.protanomaly: const VisionFilter.protanopia(),
        ColorVisionType.deuteranomaly: const VisionFilter.deuteranopia(),
        ColorVisionType.tritanomaly: const VisionFilter.tritanopia(),
      };
      cases.forEach((type, expected) {
        expect(visionFilterForColorVisionType(type), expected, reason: '$type');
      });
    });

    test('anomaly 型適用で intensity が渡した値のまま state に保持される', () {
      final service = _service()
        ..applyFilter(ColorVisionType.deuteranomaly, intensity: 0.6);
      expect(service.currentFilter, ColorVisionType.deuteranomaly);
      expect(service.intensity, 0.6);
      // anomaly は対応する -opia と同一 VisionFilter にマップされる契約
      expect(
        visionFilterForColorVisionType(service.currentFilter),
        const VisionFilter.deuteranopia(),
      );
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
  });

  group('強度はタイプごとに記憶する（#57）', () {
    test('intensity: を渡さない applyFilter は初めて選ぶタイプで recommendedStrength になる', () {
      final service = _service();
      service.applyFilter(ColorVisionType.protanomaly);
      expect(service.intensity, kAnomalyDefaultSeverity);
      service.applyFilter(ColorVisionType.protanopia);
      expect(service.intensity, 1.0);
    });

    test('protanomaly と protanopia は既定強度が異なる（同じ見た目にならない）', () {
      final service = _service();
      service.applyFilter(ColorVisionType.protanomaly);
      final protanomalyIntensity = service.intensity;
      service.applyFilter(ColorVisionType.protanopia);
      final protanopiaIntensity = service.intensity;
      expect(protanomalyIntensity, isNot(equals(protanopiaIntensity)));
      expect(protanomalyIntensity, kAnomalyDefaultSeverity);
      expect(protanopiaIntensity, 1.0);
    });

    test('タイプを切り替えても、切替前のタイプの強度は変わらず保持される', () {
      final service = _service();
      service.applyFilter(ColorVisionType.protanopia);
      service.setIntensity(0.3);

      service.applyFilter(ColorVisionType.deuteranopia);
      service.setIntensity(0.9);

      // deuteranopia を選んでいる間に protanopia へ戻っても、0.3 のまま。
      service.applyFilter(ColorVisionType.protanopia);
      expect(service.intensity, 0.3);

      service.applyFilter(ColorVisionType.deuteranopia);
      expect(service.intensity, 0.9);
    });

    test('applyFilter に intensity: を渡すと、そのタイプの記憶を明示的に上書きする', () {
      final service = _service();
      service.applyFilter(ColorVisionType.protanopia, intensity: 0.2);
      service.applyFilter(ColorVisionType.deuteranopia);
      service.applyFilter(ColorVisionType.protanopia);
      expect(service.intensity, 0.2);
    });

    test('フィルタを切り替えても選択中でない他タイプの記憶は変わらない', () {
      final service = _service();
      service.applyFilter(ColorVisionType.protanomaly);
      service.setIntensity(0.4);
      // 選択を protanopia に切り替える（intensity: を渡さない = 記憶を壊さない）。
      service.applyFilter(ColorVisionType.protanopia);
      service.applyFilter(ColorVisionType.protanomaly);
      expect(service.intensity, 0.4);
    });
  });

  group('強度は VisionFilterState の記憶に委譲する（#117）', () {
    test('setIntensity は state のキー（ColorVisionType.name）の記憶へ書く', () {
      final state = VisionFilterState();
      final service = _service(state);
      service.applyFilter(ColorVisionType.deuteranomaly);

      service.setIntensity(0.35);

      expect(state.strengthForKey('deuteranomaly'), 0.35);
      expect(state.strengthByKey, {'deuteranomaly': 0.35});
      expect(service.intensity, 0.35);
    });

    test('applyFilter(intensity:) も state の記憶へ書く（none には書かない）', () {
      final state = VisionFilterState();
      final service = _service(state);

      service.applyFilter(ColorVisionType.tritanopia, intensity: 0.2);
      expect(state.strengthByKey, {'tritanopia': 0.2});

      service.applyFilter(ColorVisionType.none, intensity: 0.9);
      expect(state.strengthByKey, {'tritanopia': 0.2});
      expect(service.intensity, 0.0);
    });

    test('記憶が無いうちは推奨強度を返すだけで、記憶へは書かない', () {
      final state = VisionFilterState();
      final service = _service(state);

      service.applyFilter(ColorVisionType.protanomaly);
      expect(service.intensity, kAnomalyDefaultSeverity);
      service.applyFilter(ColorVisionType.achromatopsia);
      expect(service.intensity, 1.0);

      expect(state.strengthByKey, isEmpty);
    });

    test('state 側で変えた強度を intensity が読む（強度の持ち主は state 1 つ）', () {
      final state = VisionFilterState();
      final service = _service(state);
      service.applyFilter(ColorVisionType.protanopia);

      state.setStrengthForKey('protanopia', 0.45);

      expect(service.intensity, 0.45);
    });

    test('none で setIntensity しても記憶は書かれず、intensity は 0.0 のまま', () {
      final state = VisionFilterState();
      final service = _service(state);

      service.setIntensity(0.7);

      expect(state.strengthByKey, isEmpty);
      expect(service.intensity, 0.0);
    });

    test('setIntensity は state と FilterService の双方の listener に通知する', () {
      final state = VisionFilterState();
      final service = _service(state);
      service.applyFilter(ColorVisionType.protanopia);
      var stateNotified = 0;
      var serviceNotified = 0;
      state.addListener(() => stateNotified++);
      service.addListener(() => serviceNotified++);

      service.setIntensity(0.5);

      expect(stateNotified, 1, reason: 'プレビューが再描画される');
      expect(serviceNotified, 1, reason: 'スライダー・トレイが更新される');
    });

    test('同じ state を共有する 2 つの FilterService は同じ記憶を見る', () {
      final state = VisionFilterState();
      final a = _service(state)..applyFilter(ColorVisionType.tritanopia);
      final b = _service(state)..applyFilter(ColorVisionType.tritanopia);

      a.setIntensity(0.25);

      expect(b.intensity, 0.25);
    });

    test('FilterService の選択（currentFilter）は state の層を変えない', () {
      final state = VisionFilterState();
      final service = _service(state);

      service.applyFilter(ColorVisionType.deuteranopia);

      expect(state.layers, isEmpty);
      expect(state.selectedId, isNull);
    });
  });
}
