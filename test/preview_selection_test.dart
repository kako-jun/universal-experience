// preview_selection.dart（#60/#63/#117）の単体テスト。
//
// 強度の正本は VisionFilterState のキーごとの記憶 1 つなので、色覚（-opia / -omaly）の
// 層でも advanced の層でも、ここの関数は同じ値を読み書きする。

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/models/vision_filter_catalog.dart';
import 'package:universal_experience/services/preview_selection.dart';
import 'package:universal_experience/services/vision_filter_state.dart';

import 'support/vision_filter_metadata_fixture.dart';
import 'support/color_vision_select.dart';

void main() {
  setUp(installVisionFilterMetadataFixture);
  tearDown(resetVisionFilterMetadataProviders);

  group('previewStrength', () {
    test('bypassed のときは層の種類に関わらず常に 0.0', () {
      final visionState = VisionFilterState();

      // advanced の層。
      visionState.replaceWith('cataract');
      visionState.setStrength(0.8);
      visionState.acquireBypass('test');
      expect(previewStrength(visionState), 0.0);

      // 色覚（-opia）の層でも同様。
      selectColorVisionKey(visionState, 'protanopia');
      visionState.acquireBypass('test');
      expect(
          isColorVisionQuickKey(visionState.focusedLayer!.strengthKey), isTrue);
      expect(previewStrength(visionState), 0.0);

      // 解除すれば直前の強度（-opia の既定 1.0）に戻る。
      visionState.releaseBypass('test');
      expect(previewStrength(visionState), 1.0);
      expect(previewStrength(visionState), visionState.strength);
    });

    test('色覚の層の強度は VisionFilterState.setStrength の値と一致する', () {
      final visionState = VisionFilterState();
      selectColorVisionKey(visionState, 'protanopia');
      visionState.setStrength(0.6);

      expect(previewStrength(visionState), 0.6);
      expect(visionState.strength, 0.6);
    });

    test('advanced/プリセット選択なら VisionFilterState.strength を使う', () {
      final visionState = VisionFilterState();
      visionState.replaceWith('cataract');
      visionState.setStrength(0.42);

      expect(previewStrength(visionState), 0.42);
    });
  });

  group('selectedStrength (#79)', () {
    test('bypassed でも素の強度を返す（previewStrength と違い 0.0 にしない）', () {
      final visionState = VisionFilterState();

      visionState.replaceWith('cataract');
      visionState.setStrength(0.8);
      visionState.acquireBypass('test');

      expect(previewStrength(visionState), 0.0);
      expect(selectedStrength(visionState), 0.8);
    });

    test('色覚の層でも VisionFilterState の記憶を返す', () {
      final visionState = VisionFilterState();
      selectColorVisionKey(visionState, 'protanopia');
      visionState.setStrength(0.6);

      expect(selectedStrength(visionState), 0.6);
    });

    test('-omaly の層は既定 0.6 から始まる', () {
      final visionState = VisionFilterState();
      selectColorVisionKey(visionState, 'deuteranomaly');

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

    test('色覚の層なら、その層のキーの記憶を動かす', () {
      final visionState = VisionFilterState();
      selectColorVisionKey(visionState, 'protanopia');
      visionState.setStrength(0.5);

      adjustPreviewStrength(visionState, kKeyboardStrengthStep);

      expect(visionState.strengthForKey('protanopia'), closeTo(0.55, 1e-9));
      expect(visionState.strength, closeTo(0.55, 1e-9));
    });

    test('-omaly の層は別名のキーの記憶を動かす（-opia の記憶は変わらない）', () {
      final visionState = VisionFilterState();
      selectColorVisionKey(visionState, 'protanomaly');

      adjustPreviewStrength(visionState, kKeyboardStrengthStep);

      expect(visionState.strengthForKey('protanomaly'),
          closeTo(kAnomalyDefaultSeverity + kKeyboardStrengthStep, 1e-9));
      expect(visionState.strengthForKey('protanopia'), isNull);
    });

    test('色覚の層で bypassed=true でも呼べば解除される', () {
      final visionState = VisionFilterState();
      selectColorVisionKey(visionState, 'protanopia');
      visionState.acquireBypass('test');
      expect(visionState.bypassed, isTrue);

      adjustPreviewStrength(visionState, kKeyboardStrengthStep);

      expect(visionState.bypassed, isFalse);
    });

    test('advanced 選択なら VisionFilterState.strength を動かす', () {
      final visionState = VisionFilterState();
      visionState.replaceWith('cataract');
      visionState.setStrength(0.5);

      adjustPreviewStrength(visionState, -kKeyboardStrengthStep);
      expect(visionState.strength, closeTo(0.45, 1e-9));
    });

    test('clamp が 0.0..1.0 で効く', () {
      final visionState = VisionFilterState();
      visionState.replaceWith('cataract');
      visionState.setStrength(0.0);

      adjustPreviewStrength(visionState, -kKeyboardStrengthStep);
      expect(visionState.strength, 0.0);

      visionState.setStrength(1.0);
      adjustPreviewStrength(visionState, kKeyboardStrengthStep);
      expect(visionState.strength, 1.0);
    });
  });
}
