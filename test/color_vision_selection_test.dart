// `lib/services/color_vision_selection.dart` の単体テスト（#60）。
//
// `selectColorVision`/`deactivateColorVision` は FilterBrowser・トレイ（両方
// とも `TrayService._handleClick` から同じ関数を呼ぶ、`lib/services/
// tray_service.dart` 参照）共通の唯一の入口。ここでは widget を介さず、
// サービス 2 つの状態遷移だけを直接検証する。
//
// 中心的な回帰: 以前の実装（home_screen.dart の listener ミラー）は
// 「FilterService.currentFilter が変わったときだけ」VisionFilterState へ
// 反映していたため、advanced/プリセットを経由したあとに *同じ* 色覚型を
// 再選択しても（型そのものは変わっていないので）反映されなかった。
// FilterBrowser のチップ・トレイのメニューはどちらもこの関数を直接呼ぶだけ
// なので、この関数が「呼ばれるたびに無条件で反映する」ことさえ検証すれば、
// トレイから再選択した場合も同じように直る。

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/services/color_vision_selection.dart';
import 'package:universal_experience/services/filter_service.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/services/vision_layer.dart';

import 'support/vision_filter_metadata_fixture.dart';

void main() {
  late FilterService filterService;
  late VisionFilterState visionState;

  setUp(() {
    installVisionFilterMetadataFixture();
    visionState = VisionFilterState();
    filterService = FilterService(visionState: visionState);
  });
  tearDown(resetVisionFilterMetadataProviders);

  group('selectColorVision', () {
    test('色覚型を選ぶと FilterService と VisionFilterState の両方が更新される', () {
      selectColorVision(filterService, visionState, ColorVisionType.protanopia);

      expect(filterService.currentFilter, ColorVisionType.protanopia);
      expect(visionState.selectedId, 'protanopia');
      expect(visionState.isColorQuickSelection, isTrue);
      expect(visionState.colorVisionType, ColorVisionType.protanopia);
    });

    test(
        '-omaly はカタログ id が base の -opia に写りつつ colorVisionType は -omaly のまま保持する',
        () {
      selectColorVision(
          filterService, visionState, ColorVisionType.deuteranomaly);

      expect(filterService.currentFilter, ColorVisionType.deuteranomaly);
      expect(visionState.selectedId, 'deuteranopia',
          reason: 'カタログは色覚 5 種しか持たず -omaly は base の -opia に写る');
      expect(visionState.colorVisionType, ColorVisionType.deuteranomaly,
          reason: '見出し・caption・ファイル名で -omaly の名前を正しく出すために保持する');
    });

    test(
        'ColorVisionType.none を渡すと解除と同じ効果になり isColorQuickSelection は false のまま',
        () {
      selectColorVision(filterService, visionState, ColorVisionType.none);

      expect(filterService.currentFilter, ColorVisionType.none);
      expect(visionState.selectedId, isNull);
      expect(visionState.isColorQuickSelection, isFalse,
          reason: 'none はカタログにも強度概念にも対応しないので「選択中」扱いにしない');
    });

    test('advanced 選択中に呼んでも上書きする（別のフィルタを手動で選ぶ操作として扱う）', () {
      visionState.select('starbursts');
      expect(visionState.isColorQuickSelection, isFalse);

      selectColorVision(filterService, visionState, ColorVisionType.protanopia);

      expect(visionState.selectedId, 'protanopia');
      expect(visionState.isColorQuickSelection, isTrue);
    });

    test('プリセット選択中に呼んでも上書きし、selectedPresetId は解除される', () {
      visionState.selectPreset('meniere', 'vertigo');
      expect(visionState.selectedPresetId, 'meniere');

      selectColorVision(filterService, visionState, ColorVisionType.protanopia);

      expect(visionState.selectedPresetId, isNull);
      expect(visionState.selectedId, 'protanopia');
    });

    test(
        '回帰: advanced を経由したあとに同じ色覚型を再選択しても正しく反映される '
        '（#60。以前の listener ミラーは currentFilter が変わらないため反応しなかった）', () {
      // 1. protanopia を選ぶ（FilterBrowser のチップ、またはトレイのメニュー
      //    どちらも selectColorVision を呼ぶだけなので区別なく再現できる）。
      selectColorVision(filterService, visionState, ColorVisionType.protanopia);
      expect(visionState.isColorQuickSelection, isTrue);

      // 2. advanced へ切り替える。FilterService.currentFilter は
      //    protanopia のまま変わらない（advanced 選択は FilterService に
      //    触れない）。
      visionState.select('starbursts');
      expect(filterService.currentFilter, ColorVisionType.protanopia);
      expect(visionState.isColorQuickSelection, isFalse);

      // 3. 同じ protanopia を再選択する（トレイのチェックボックスを再クリック
      //    する操作、または FilterBrowser の同じチップを再タップする操作に
      //    相当）。FilterService.currentFilter は型としては変化しない
      //    （protanopia → protanopia）が、選択操作そのものは行われている。
      selectColorVision(filterService, visionState, ColorVisionType.protanopia);

      expect(visionState.selectedId, 'protanopia');
      expect(visionState.isColorQuickSelection, isTrue,
          reason: '同じ型への再選択でも VisionFilterState は必ず反映されるべき');
    });
  });

  group('deactivateColorVision', () {
    test('selectColorVision(none) と同じ効果になる', () {
      selectColorVision(filterService, visionState, ColorVisionType.protanopia);

      deactivateColorVision(filterService, visionState);

      expect(filterService.currentFilter, ColorVisionType.none);
      expect(visionState.selectedId, isNull);
      expect(visionState.isColorQuickSelection, isFalse);
    });
  });

  group('toggleColorVision（多選択、#120）', () {
    test('他の層を残したまま色覚の層を足し、FilterService を同期する', () {
      visionState.toggle('glaucoma');
      final r = toggleColorVision(
          filterService, visionState, ColorVisionType.protanopia);
      expect(r, VisionLayerResult.added);
      expect([for (final l in visionState.layers) l.id],
          ['glaucoma', 'protanopia']);
      expect(filterService.currentFilter, ColorVisionType.protanopia);
    });

    test('別の色覚は置き換え、同じ色覚をもう一度は外す', () {
      toggleColorVision(filterService, visionState, ColorVisionType.protanopia);
      final replaced = toggleColorVision(
          filterService, visionState, ColorVisionType.deuteranopia);
      expect(replaced, VisionLayerResult.replaced);
      expect(filterService.currentFilter, ColorVisionType.deuteranopia);

      final removed = toggleColorVision(
          filterService, visionState, ColorVisionType.deuteranopia);
      expect(removed, VisionLayerResult.removed);
      expect(visionState.layers, isEmpty);
      expect(filterService.currentFilter, ColorVisionType.none);
    });

    test('none は色覚の層だけを外し、他の層は残す', () {
      visionState.toggle('myopia');
      toggleColorVision(filterService, visionState, ColorVisionType.tritanopia);
      toggleColorVision(filterService, visionState, ColorVisionType.none);
      expect([for (final l in visionState.layers) l.id], ['myopia']);
      expect(filterService.currentFilter, ColorVisionType.none);
    });

    test('quick 以外（advanced 由来）の色覚層は FilterService の対象にしない', () {
      visionState.toggle('protanopia'); // origin 既定 = advanced
      syncFilterServiceWithLayers(filterService, visionState);
      expect(filterService.currentFilter, ColorVisionType.none);
    });
  });
}
