// preview_selection.dart（#60/#63）の単体テスト。

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/models/vision_filter_catalog.dart';
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
      final filterService = FilterService();
      final visionState = VisionFilterState();

      // advanced 選択（isColorQuickSelection == false）。
      visionState.select('cataract');
      visionState.setStrength(0.8);
      visionState.setBypassed(true);
      expect(previewStrength(visionState, filterService), 0.0);

      // 色覚クイック選択（isColorQuickSelection == true）でも同様。
      selectColorVision(filterService, visionState, ColorVisionType.protanopia);
      visionState.setBypassed(true);
      expect(previewStrength(visionState, filterService), 0.0);

      // 解除すれば直前の強度に戻る。
      visionState.setBypassed(false);
      expect(previewStrength(visionState, filterService), filterService.intensity);
    });

    test('色覚クイック選択なら FilterService.intensity を使う', () {
      final filterService = FilterService();
      final visionState = VisionFilterState();
      selectColorVision(filterService, visionState, ColorVisionType.protanopia);
      filterService.setIntensity(0.6);

      expect(previewStrength(visionState, filterService), 0.6);
    });

    test('advanced/プリセット選択なら VisionFilterState.strength を使う', () {
      final filterService = FilterService();
      final visionState = VisionFilterState();
      visionState.select('cataract');
      visionState.setStrength(0.42);

      expect(previewStrength(visionState, filterService), 0.42);
    });
  });

  group('adjustPreviewStrength', () {
    test('未選択なら何もしない', () {
      final filterService = FilterService();
      final visionState = VisionFilterState();

      adjustPreviewStrength(visionState, filterService, kKeyboardStrengthStep);

      expect(visionState.selectedId, isNull);
      expect(visionState.strength, 1.0);
    });

    test('色覚クイック選択なら FilterService.intensity を動かす', () {
      final filterService = FilterService();
      final visionState = VisionFilterState();
      selectColorVision(filterService, visionState, ColorVisionType.protanopia);
      filterService.setIntensity(0.5);

      adjustPreviewStrength(visionState, filterService, kKeyboardStrengthStep);
      expect(filterService.intensity, closeTo(0.55, 1e-9));
      // VisionFilterState.strength は変わらない。
      expect(visionState.strength, 1.0);
    });

    test('色覚クイック選択で bypassed=true でも呼べば解除される', () {
      final filterService = FilterService();
      final visionState = VisionFilterState();
      selectColorVision(filterService, visionState, ColorVisionType.protanopia);
      visionState.setBypassed(true);
      expect(visionState.bypassed, isTrue);

      adjustPreviewStrength(visionState, filterService, kKeyboardStrengthStep);

      expect(visionState.bypassed, isFalse);
    });

    test('advanced 選択なら VisionFilterState.strength を動かす', () {
      final filterService = FilterService();
      final visionState = VisionFilterState();
      visionState.select('cataract');
      visionState.setStrength(0.5);

      adjustPreviewStrength(visionState, filterService, -kKeyboardStrengthStep);
      expect(visionState.strength, closeTo(0.45, 1e-9));
    });

    test('clamp が 0.0..1.0 で効く', () {
      final filterService = FilterService();
      final visionState = VisionFilterState();
      visionState.select('cataract');
      visionState.setStrength(0.0);

      adjustPreviewStrength(visionState, filterService, -kKeyboardStrengthStep);
      expect(visionState.strength, 0.0);

      visionState.setStrength(1.0);
      adjustPreviewStrength(visionState, filterService, kKeyboardStrengthStep);
      expect(visionState.strength, 1.0);
    });
  });

  group('cycleAdvancedFilter', () {
    test('未選択から forward で先頭を選ぶ', () {
      final visionState = VisionFilterState();
      cycleAdvancedFilter(visionState, forward: true);
      expect(visionState.selectedId, kVisionFilterCatalog.first.id);
    });

    test('未選択から backward で末尾を選ぶ', () {
      final visionState = VisionFilterState();
      cycleAdvancedFilter(visionState, forward: false);
      expect(visionState.selectedId, kVisionFilterCatalog.last.id);
    });

    test('forward はカタログ順で次に進み、末尾から先頭へ wraparound する', () {
      final visionState = VisionFilterState()
        ..select(kVisionFilterCatalog.last.id);
      cycleAdvancedFilter(visionState, forward: true);
      expect(visionState.selectedId, kVisionFilterCatalog.first.id);
    });

    test('backward はカタログ順で前に戻り、先頭から末尾へ wraparound する', () {
      final visionState = VisionFilterState()
        ..select(kVisionFilterCatalog.first.id);
      cycleAdvancedFilter(visionState, forward: false);
      expect(visionState.selectedId, kVisionFilterCatalog.last.id);
    });

    test('色覚クイック選択中は advanced の選択中とみなさず先頭/末尾から始める', () {
      final filterService = FilterService();
      final visionState = VisionFilterState();
      selectColorVision(filterService, visionState, ColorVisionType.protanopia);
      expect(visionState.isColorQuickSelection, isTrue);

      cycleAdvancedFilter(visionState, forward: true);
      expect(visionState.selectedId, kVisionFilterCatalog.first.id);
      expect(visionState.isColorQuickSelection, isFalse,
          reason: 'advanced への select は色覚クイック選択の記録を解除する');
    });
  });
}
