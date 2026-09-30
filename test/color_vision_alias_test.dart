// 色覚 7 種（-opia 4 + -omaly 3）の別名表と、別名を解いて選ぶ入口（#60, #124）の
// 単体テスト。
//
// 状態モデルは `VisionFilterState` だけで、-omaly は独立したフィルタではなく対応する
// -opia と同じカタログ id に写る別名（`VisionLayer.variantId`）。違いは既定の強度
// （0.6）と、強度の記憶のキー（別名 id ?? カタログ id）だけ。ここでは widget を介さず、
//  * 別名表（`resolveVisionKey` / `colorVisionDefaultStrength` / `isColorVisionQuickKey`）
//  * テスト用の入口 `selectColorVisionKey`（本番の `VisionFilterState.replaceWith` に
//    別名を解いて渡すだけ）と、`none` 相当の `clear`
//  * 色覚グループの排他（-opia ⇄ -omaly の置き換え）
// の状態遷移を直接検証する。
//
// 中心的な回帰: 以前の実装（home_screen.dart の listener ミラー）は「色覚型が変わった
// ときだけ」状態へ反映していたため、advanced/プリセットを経由したあとに *同じ* 色覚を
// 再選択しても反映されなかった。選択の入口が「呼ばれるたびに無条件で反映する」ことを
// 検証しておく（回帰テストは FilterBrowser の行もトレイも通る toggleFilterListEntry で行う）。

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/models/vision_filter_catalog.dart';
import 'package:universal_experience/services/filter_list_selection.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/services/vision_layer.dart';

import 'support/color_vision_select.dart';
import 'support/vision_filter_metadata_fixture.dart';

void main() {
  late VisionFilterState visionState;

  setUp(() {
    installVisionFilterMetadataFixture();
    visionState = VisionFilterState();
  });
  tearDown(resetVisionFilterMetadataProviders);

  group('別名表', () {
    test('-omaly 3 種は対応する -opia のカタログ id に写り、別名 id を variantId に持つ', () {
      expect(resolveVisionKey('protanomaly'),
          (id: 'protanopia', variantId: 'protanomaly'));
      expect(resolveVisionKey('deuteranomaly'),
          (id: 'deuteranopia', variantId: 'deuteranomaly'));
      expect(resolveVisionKey('tritanomaly'),
          (id: 'tritanopia', variantId: 'tritanomaly'));
    });

    test('-opia 4 種はカタログ id のまま（variantId なし）', () {
      for (final id in kColorVisionQuickCatalogIds) {
        expect(resolveVisionKey(id), (id: id, variantId: null), reason: id);
      }
    });

    test('カタログにも別名表にも無いキーは null', () {
      expect(resolveVisionKey('normal'), isNull);
      expect(resolveVisionKey('none'), isNull);
      expect(resolveVisionKey(''), isNull);
    });

    test('色覚クイック選択の 7 種だけが isColorVisionQuickKey', () {
      const quick = [
        'protanopia',
        'deuteranopia',
        'tritanopia',
        'achromatopsia',
        'protanomaly',
        'deuteranomaly',
        'tritanomaly',
      ];
      for (final key in quick) {
        expect(isColorVisionQuickKey(key), isTrue, reason: key);
      }
      expect(isColorVisionQuickKey('starbursts'), isFalse);
      expect(isColorVisionQuickKey('none'), isFalse);
    });

    test('既定の強度は -opia が 1.0、-omaly が 0.6、色覚以外は null', () {
      for (final id in kColorVisionQuickCatalogIds) {
        expect(colorVisionDefaultStrength(id), 1.0, reason: id);
      }
      for (final alias in kVisionAliases) {
        expect(colorVisionDefaultStrength(alias.id), 0.6, reason: alias.id);
        expect(colorVisionDefaultStrength(alias.id), kAnomalyDefaultSeverity);
      }
      expect(colorVisionDefaultStrength('starbursts'), isNull);
      expect(colorVisionDefaultStrength('unknown'), isNull);
    });

    test('別名表の写り先はすべて色覚クイック選択のカタログ id', () {
      for (final alias in kVisionAliases) {
        expect(kColorVisionQuickCatalogIds, contains(alias.catalogId),
            reason: alias.id);
        expect(kVisionAliasById[alias.id], same(alias));
      }
    });
  });

  group('selectColorVisionKey', () {
    test('-opia を選ぶと、別名なしのカタログ id の層が 1 つ・強度 1.0 で入る', () {
      selectColorVisionKey(visionState, 'protanopia');

      expect(visionState.selectedId, 'protanopia');
      expect(visionState.focusedVariantId, isNull);
      expect(visionState.layers, hasLength(1));
      expect(visionState.layers.single.variantId, isNull);
      expect(visionState.layers.single.strengthKey, 'protanopia');
      expect(visionState.strength, 1.0);
    });

    test('-omaly は -opia と同じカタログ id + variantId + 強度 0.6 で入る', () {
      for (final alias in kVisionAliases) {
        final state = VisionFilterState();
        selectColorVisionKey(state, alias.id);

        expect(state.selectedId, alias.catalogId, reason: alias.id);
        expect(state.focusedVariantId, alias.id,
            reason: '見出し・書き出しで -omaly の名前を正しく出すために別名 id を保持する');
        expect(state.focusedLayer!.strengthKey, alias.id);
        expect(state.strength, 0.6, reason: alias.id);
        expect(state.strengthForKey(alias.id), isNull,
            reason: '推奨強度は記憶へ書かず、読むときに導出する');
      }
    });

    test('-omaly と対応する -opia は同じ -opia のフィルタに写る', () {
      selectColorVisionKey(visionState, 'deuteranopia');
      final opia = visionState.buildAll().single;
      selectColorVisionKey(visionState, 'deuteranomaly');
      final omaly = visionState.buildAll().single;

      expect(omaly, opia, reason: '見え方の違いは強度（0.6）だけで表す');
    });

    test('-opia と -omaly の強度の記憶は別キーで、互いに干渉しない', () {
      selectColorVisionKey(visionState, 'protanopia');
      visionState.setStrength(0.3);
      selectColorVisionKey(visionState, 'protanomaly');
      expect(visionState.strength, 0.6, reason: '-opia の強度を引き継がない');
      visionState.setStrength(0.8);

      expect(visionState.strengthForKey('protanopia'), 0.3);
      expect(visionState.strengthForKey('protanomaly'), 0.8);

      selectColorVisionKey(visionState, 'protanopia');
      expect(visionState.strength, 0.3, reason: '選び直すと -opia の記憶が戻る');
    });

    test('未知のキーは ArgumentError', () {
      expect(() => selectColorVisionKey(visionState, 'normal'),
          throwsArgumentError);
      expect(visionState.layers, isEmpty);
    });

    test('none 相当は clear で、層が無くなり selectedId も無くなる', () {
      selectColorVisionKey(visionState, 'protanomaly');

      visionState.clear();

      expect(visionState.layers, isEmpty);
      expect(visionState.selectedId, isNull);
      expect(visionState.focusedLayer, isNull);
      expect(visionState.focusedVariantId, isNull);
    });

    test('clear は層を外すだけで強度の記憶は残す（選び直すと戻る）', () {
      selectColorVisionKey(visionState, 'deuteranomaly');
      visionState.setStrength(0.25);

      visionState.clear();
      selectColorVisionKey(visionState, 'deuteranomaly');

      expect(visionState.strength, 0.25);
    });

    test('advanced 選択中に呼んでも上書きする（別のフィルタを手動で選ぶ操作として扱う）', () {
      visionState.replaceWith('starbursts');
      expect(visionState.selectedId, 'starbursts');

      selectColorVisionKey(visionState, 'protanopia');

      expect(visionState.selectedId, 'protanopia');
      expect(visionState.layers.map((l) => l.id), ['protanopia']);
    });

    test('プリセット選択中に呼んでも上書きし、selectedPresetId は解除される', () {
      visionState.selectPreset('meniere', 'vertigo');
      expect(visionState.selectedPresetId, 'meniere');

      selectColorVisionKey(visionState, 'protanopia');

      expect(visionState.selectedPresetId, isNull);
      expect(visionState.selectedId, 'protanopia');
    });

    test('複数層を重ねていても単一選択に置き換える', () {
      visionState
        ..toggle('myopia')
        ..toggle('glaucoma');

      selectColorVisionKey(visionState, 'tritanomaly');

      expect(visionState.layers.map((l) => l.strengthKey), ['tritanomaly']);
    });

    test(
        '回帰: advanced を経由したあとに同じ色覚を選び直しても正しく反映される '
        '（#60。本番の入口 toggleFilterListEntry を通す。以前の listener ミラーは色覚型が変わらないため反応しなかった）',
        () {
      final protanopia =
          kFilterListEntries.firstWhere((e) => e.key == 'cv:protanopia');

      // 1. protanopia を選ぶ（FilterBrowser の行もトレイのメニューも同じ入口）。
      toggleFilterListEntry(visionState, protanopia);
      expect(visionState.selectedId, 'protanopia');

      // 2. advanced へ切り替える（単一選択として置き換える）。
      visionState.replaceWith('starbursts');
      expect(visionState.layers.map((l) => l.id), ['starbursts']);

      // 3. 同じ protanopia の行を選び直す。
      toggleFilterListEntry(visionState, protanopia);

      expect(visionState.selectedId, 'protanopia');
      expect(visionState.layers.map((l) => l.id), ['starbursts', 'protanopia'],
          reason: '同じ色覚を選び直しても VisionFilterState は必ず反映されるべき');
    });
  });

  group('色覚グループの排他（toggle、#120）', () {
    test('他の層を残したまま色覚の層を足す', () {
      visionState.toggle('glaucoma');
      final r = visionState.toggle('protanopia');
      expect(r, VisionLayerResult.added);
      expect([for (final l in visionState.layers) l.id],
          ['glaucoma', 'protanopia']);
    });

    test('別の色覚は置き換え、同じ色覚をもう一度は外す', () {
      visionState.toggle('protanopia');
      final replaced = visionState.toggle('deuteranopia');
      expect(replaced, VisionLayerResult.replaced);
      expect([for (final l in visionState.layers) l.id], ['deuteranopia']);

      final removed = visionState.toggle('deuteranopia');
      expect(removed, VisionLayerResult.removed);
      expect(visionState.layers, isEmpty);
    });

    test('-opia ⇄ -omaly は同じカタログ id の別名への置き換えで、層数は増えない', () {
      visionState.toggle('deuteranopia');

      final toOmaly =
          visionState.toggle('deuteranopia', variantId: 'deuteranomaly');
      expect(toOmaly, VisionLayerResult.replaced);
      expect(visionState.layers, hasLength(1));
      expect(visionState.focusedVariantId, 'deuteranomaly');

      final toOpia = visionState.toggle('deuteranopia');
      expect(toOpia, VisionLayerResult.replaced);
      expect(visionState.layers, hasLength(1));
      expect(visionState.focusedVariantId, isNull);
    });

    test('-omaly をもう一度 toggle すると外れる', () {
      visionState.toggle('tritanopia', variantId: 'tritanomaly');
      final removed =
          visionState.toggle('tritanopia', variantId: 'tritanomaly');
      expect(removed, VisionLayerResult.removed);
      expect(visionState.layers, isEmpty);
    });

    test('別名として不正な variantId は ArgumentError', () {
      expect(
          () => visionState.toggle('protanopia', variantId: 'deuteranomaly'),
          throwsArgumentError);
      expect(visionState.layers, isEmpty);
    });

    test('remove は色覚の層だけを外し、他の層は残す', () {
      visionState.toggle('myopia');
      visionState.toggle('tritanopia', variantId: 'tritanomaly');

      expect(visionState.remove('tritanopia'), isTrue);

      expect([for (final l in visionState.layers) l.id], ['myopia']);
    });

    test('色覚の層が無いときの remove は何も変えず false', () {
      visionState.toggle('myopia');

      expect(visionState.remove('tritanopia'), isFalse);

      expect([for (final l in visionState.layers) l.id], ['myopia']);
    });

    test('clear は重ねている全層を外す（ホットキー「フィルタ解除」・トレイの解除、#121）', () {
      selectColorVisionKey(visionState, 'protanopia');
      visionState
        ..toggle('myopia')
        ..toggle('glaucoma');
      expect(visionState.layers.length, 3);

      visionState.clear();

      expect(visionState.layers, isEmpty);
    });
  });
}
