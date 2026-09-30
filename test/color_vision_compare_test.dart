import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/models/vision_filter_catalog.dart';
import 'package:universal_experience/services/color_vision_compare.dart';
import 'package:universal_experience/services/filter_service.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/services/vision_layer.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';

import 'support/vision_filter_metadata_fixture.dart';

/// 色覚 4 型の一覧比較（2×2、#84）で何を並べるかを決める pure な部分のテスト。
void main() {
  group('kColorVisionCompareEntries', () {
    test('カタログ id で protanopia・deuteranopia・tritanopia・achromatopsia の順', () {
      expect(
        [for (final e in kColorVisionCompareEntries) e.id],
        ['protanopia', 'deuteranopia', 'tritanopia', 'achromatopsia'],
      );
      expect(kColorVisionCompareEntries.length, 4);
    });

    test('実験的な四色覚は含まない（他の 4 型と同列に比べる対象ではない）', () {
      expect(
        kColorVisionCompareEntries.any((e) => e.id == 'tetrachromacy'),
        isFalse,
      );
      expect(
          kColorVisionCompareEntries.every((e) => !e.isExperimental), isTrue);
    });

    test('色覚カテゴリのカタログ項目のうち非実験的なものと同じ集合・同じ順', () {
      final expected = [
        for (final e in kVisionFilterCatalog)
          if (e.category == VisionFilterCategory.colorVision &&
              !e.isExperimental)
            e.id,
      ];
      expect([for (final e in kColorVisionCompareEntries) e.id], expected);
    });

    test('変更不可のリスト', () {
      expect(
        () => kColorVisionCompareEntries.add(kVisionFilterCatalog.first),
        throwsUnsupportedError,
      );
    });
  });

  group('colorVisionLayerOf（切替を出す条件 = 層の集合に色覚層があるか、#122）', () {
    VisionLayer layer(String id, {String? variantId}) =>
        VisionLayer(id: id, variantId: variantId);

    test('色覚カテゴリの層（四色覚を含む）があればそれを返す', () {
      for (final e in kVisionFilterCatalog) {
        if (e.category == VisionFilterCategory.colorVision) {
          expect(colorVisionLayerOf([layer(e.id)])?.id, e.id, reason: e.id);
        }
      }
      expect(colorVisionLayerOf([layer('tetrachromacy')]), isNotNull);
    });

    test('色覚以外の層だけなら null（切替も 2×2 も出さない）', () {
      for (final e in kVisionFilterCatalog) {
        if (e.category != VisionFilterCategory.colorVision) {
          expect(colorVisionLayerOf([layer(e.id)]), isNull, reason: e.id);
        }
      }
      expect(colorVisionLayerOf([layer('myopia'), layer('vertigo')]), isNull);
    });

    test('層が 0 個なら null', () {
      expect(colorVisionLayerOf(const []), isNull);
    });

    test('他の層と重なっていても色覚層を返す（-omaly の別名も同じ）', () {
      final omaly = layer('protanopia', variantId: 'protanomaly');
      final found = colorVisionLayerOf([layer('myopia'), omaly]);
      expect(identical(found, omaly), isTrue);
    });
  });

  group('colorVisionCompareInputOf', () {
    setUp(installVisionFilterMetadataFixture);
    tearDown(resetVisionFilterMetadataProviders);

    test('色覚層が無ければ null', () {
      expect(colorVisionCompareInputOf(VisionFilterState()), isNull);
      expect(
        colorVisionCompareInputOf(VisionFilterState()..toggle('myopia')),
        isNull,
      );
    });

    test('色覚だけなら土台なし（= 原画）・強さは色覚層の強度', () {
      final state = VisionFilterState()..toggle('protanopia');
      state.setLayerStrength('protanopia', 0.4);
      final input = colorVisionCompareInputOf(state)!;
      expect(input.strength, 0.4);
      expect(input.baseSteps, isEmpty);
      expect(input.baseLayers, isEmpty);
    });

    test('他の層は段順の土台になる（色覚は含まない・選んだ順に依存しない）', () {
      final state = VisionFilterState()
        ..toggle('protanopia')
        ..toggle('myopia')
        ..toggle('vertigo');
      state.setLayerStrength('myopia', 0.5);
      state.setLayerStrength('protanopia', 0.25);
      final input = colorVisionCompareInputOf(state)!;

      expect(input.strength, 0.25);
      expect(
          [for (final l in input.baseLayers) l.layer.id], ['vertigo', 'myopia'],
          reason: '運動 → 光学（色覚は最終段なので土台に入らない）');
      expect(input.baseSteps.length, 2);
      expect([for (final s in input.baseSteps) s.strength], [1.0, 0.5]);
      expect([for (final l in input.baseLayers) l.strength], [1.0, 0.5]);
    });

    test('土台の steps は pipelineSteps から色覚を除いたものと同じ（強度 0 の層は除く）', () {
      final state = VisionFilterState()
        ..toggle('protanopia')
        ..toggle('myopia')
        ..toggle('vertigo');
      state.setLayerStrength('vertigo', 0);
      final input = colorVisionCompareInputOf(state)!;
      final all = state.pipelineSteps();
      expect(all.length, 2, reason: 'vertigo（強度 0）は除かれている');
      expect(input.baseSteps, all.sublist(0, all.length - 1));
      expect([for (final l in input.baseLayers) l.layer.id], ['myopia']);
    });

    test('色覚層の強度が 0 でも入力は作る（2×2 は強度 0 のまま出す）', () {
      final state = VisionFilterState()
        ..toggle('myopia')
        ..toggle('protanopia');
      state.setLayerStrength('protanopia', 0);
      final input = colorVisionCompareInputOf(state)!;
      expect(input.strength, 0);
      expect(input.baseSteps.length, 1);
    });

    test('原画比較中は強度 0・土台なし（選択と強度の記憶は変えない）', () {
      final state = VisionFilterState()
        ..toggle('myopia')
        ..toggle('protanopia');
      state.acquireBypass('test');
      final input = colorVisionCompareInputOf(state)!;
      expect(input.strength, 0);
      expect(input.baseSteps, isEmpty);
      expect(input.baseLayers, isEmpty);
      expect(state.layers.length, 2);
      expect(state.strengthOf(state.layers.last), 1.0);
    });

    test('フォーカス中の層が色覚でなくても、色覚層の強度を使う', () {
      final state = VisionFilterState()
        ..toggle('protanopia')
        ..toggle('myopia');
      state.setLayerStrength('protanopia', 0.3);
      state.focusLayer('myopia');
      expect(colorVisionCompareInputOf(state)!.strength, 0.3);
    });
  });

  group('colorVisionCompareFilter', () {
    test('色覚クイック選択と同じ対応表（visionFilterForColorVisionType）を引く', () {
      const expected = <String, VisionFilter>{
        'protanopia': VisionFilter.protanopia(),
        'deuteranopia': VisionFilter.deuteranopia(),
        'tritanopia': VisionFilter.tritanopia(),
        'achromatopsia': VisionFilter.achromatopsia(),
      };
      for (final entry in kColorVisionCompareEntries) {
        final type =
            ColorVisionType.values.singleWhere((t) => t.id == entry.id);
        expect(colorVisionCompareFilter(entry), expected[entry.id],
            reason: entry.id);
        expect(
          colorVisionCompareFilter(entry),
          visionFilterForColorVisionType(type),
          reason: entry.id,
        );
      }
    });

    test('4 セルのフィルタはすべて互いに異なる', () {
      final filters = [
        for (final e in kColorVisionCompareEntries) colorVisionCompareFilter(e),
      ];
      for (var i = 0; i < filters.length; i++) {
        for (var j = i + 1; j < filters.length; j++) {
          expect(filters[i], isNot(filters[j]), reason: '$i vs $j');
        }
      }
    });

    test('色覚型に対応しないカタログ項目は StateError（黙って別物に落とさない）', () {
      expect(
        () => colorVisionCompareFilter(
          kVisionFilterCatalog.firstWhere(
            (e) => e.category != VisionFilterCategory.colorVision,
          ),
        ),
        throwsStateError,
      );
      // 四色覚は色覚カテゴリだが ColorVisionType に対応が無い。
      expect(
        () => colorVisionCompareFilter(
          kVisionFilterCatalog.firstWhere((e) => e.id == 'tetrachromacy'),
        ),
        throwsStateError,
      );
    });
  });
}
