// preview_selection.dart（#60/#63/#117）の単体テスト。
//
// #117 で強度の正本が VisionFilterState のキーごとの記憶 1 つになったので、色覚
// クイック選択でも advanced 選択でも、ここの関数は同じ値を読み書きする。

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/services/color_vision_selection.dart';
import 'package:universal_experience/services/filter_service.dart';
import 'package:universal_experience/services/preview_selection.dart';
import 'package:universal_experience/services/vision_filter_state.dart';

import 'support/vision_filter_metadata_fixture.dart';

void main() {
  setUp(installVisionFilterMetadataFixture);
  tearDown(resetVisionFilterMetadataProviders);

  group('previewStrength', () {
    test('bypassed のときは isColorQuickSelection に関わらず常に 0.0', () {
      final visionState = VisionFilterState();
      final filterService = FilterService(visionState: visionState);

      // advanced 選択（isColorQuickSelection == false）。
      visionState.select('cataract');
      visionState.setStrength(0.8);
      visionState.acquireBypass('test');
      expect(previewStrength(visionState), 0.0);

      // 色覚クイック選択（isColorQuickSelection == true）でも同様。
      selectColorVision(filterService, visionState, ColorVisionType.protanopia);
      visionState.acquireBypass('test');
      expect(visionState.isColorQuickSelection, isTrue);
      expect(previewStrength(visionState), 0.0);

      // 解除すれば直前の強度（-opia の既定 1.0）に戻る。
      visionState.releaseBypass('test');
      expect(previewStrength(visionState), 1.0);
      expect(previewStrength(visionState), filterService.intensity);
    });

    test('色覚クイック選択の強度は FilterService.setIntensity の値と一致する', () {
      final visionState = VisionFilterState();
      final filterService = FilterService(visionState: visionState);
      selectColorVision(filterService, visionState, ColorVisionType.protanopia);
      filterService.setIntensity(0.6);

      expect(previewStrength(visionState), 0.6);
      expect(visionState.strength, 0.6);
    });

    test('advanced/プリセット選択なら VisionFilterState.strength を使う', () {
      final visionState = VisionFilterState();
      visionState.select('cataract');
      visionState.setStrength(0.42);

      expect(previewStrength(visionState), 0.42);
    });
  });

  group('selectedStrength (#79)', () {
    test('bypassed でも素の強度を返す（previewStrength と違い 0.0 にしない）', () {
      final visionState = VisionFilterState();

      visionState.select('cataract');
      visionState.setStrength(0.8);
      visionState.acquireBypass('test');

      expect(previewStrength(visionState), 0.0);
      expect(selectedStrength(visionState), 0.8);
    });

    test('色覚クイック選択でも VisionFilterState の記憶を返す', () {
      final visionState = VisionFilterState();
      final filterService = FilterService(visionState: visionState);
      selectColorVision(filterService, visionState, ColorVisionType.protanopia);
      filterService.setIntensity(0.6);

      expect(selectedStrength(visionState), 0.6);
    });

    test('-omaly の色覚クイック選択は既定 0.6 から始まる', () {
      final visionState = VisionFilterState();
      final filterService = FilterService(visionState: visionState);
      selectColorVision(
          filterService, visionState, ColorVisionType.deuteranomaly);

      expect(selectedStrength(visionState), kAnomalyDefaultSeverity);
    });
  });

  group('adjustPreviewStrength', () {
    test('未選択なら何もしない', () {
      final visionState = VisionFilterState();

      adjustPreviewStrength(visionState, kKeyboardStrengthStep);

      expect(visionState.selectedId, isNull);
      expect(visionState.strength, 1.0);
      expect(visionState.strengthByKey, isEmpty);
    });

    test('色覚クイック選択なら記憶（FilterService.intensity）を動かす', () {
      final visionState = VisionFilterState();
      final filterService = FilterService(visionState: visionState);
      selectColorVision(filterService, visionState, ColorVisionType.protanopia);
      filterService.setIntensity(0.5);

      adjustPreviewStrength(visionState, kKeyboardStrengthStep);

      expect(filterService.intensity, closeTo(0.55, 1e-9));
      expect(visionState.strength, closeTo(0.55, 1e-9));
    });

    test('色覚クイック選択で bypassed=true でも呼べば解除される', () {
      final visionState = VisionFilterState();
      final filterService = FilterService(visionState: visionState);
      selectColorVision(filterService, visionState, ColorVisionType.protanopia);
      visionState.acquireBypass('test');
      expect(visionState.bypassed, isTrue);

      adjustPreviewStrength(visionState, kKeyboardStrengthStep);

      expect(visionState.bypassed, isFalse);
    });

    test('advanced 選択なら VisionFilterState.strength を動かす', () {
      final visionState = VisionFilterState();
      visionState.select('cataract');
      visionState.setStrength(0.5);

      adjustPreviewStrength(visionState, -kKeyboardStrengthStep);
      expect(visionState.strength, closeTo(0.45, 1e-9));
    });

    test('clamp が 0.0..1.0 で効く', () {
      final visionState = VisionFilterState();
      visionState.select('cataract');
      visionState.setStrength(0.0);

      adjustPreviewStrength(visionState, -kKeyboardStrengthStep);
      expect(visionState.strength, 0.0);

      visionState.setStrength(1.0);
      adjustPreviewStrength(visionState, kKeyboardStrengthStep);
      expect(visionState.strength, 1.0);
    });
  });
}
