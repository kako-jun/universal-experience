import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/models/vision_filter_catalog.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';

/// vision_filter_catalog（#16）の不変条件と vision_filter_state.build() の検証。
///
/// 正本は sensus_bridge.dart の `VisionFilter` sealed（30 variant）。このテストは
/// カタログがその 30 種を漏れ・重複なく全カテゴリに分類していること、payload 付き
/// フィルタの parameters 数が sensus payload と一致すること、build() が選択 +
/// パラメータから正しい VisionFilter を構築することを保証する。
void main() {
  group('カタログの網羅性・一意性', () {
    test('カタログは 30 フィルタちょうど（sensus VisionFilter variant 数）', () {
      expect(kVisionFilterCatalog.length, 30);
    });

    test('id は重複なし', () {
      final ids = kVisionFilterCatalog.map((e) => e.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('全エントリが既知の id（期待集合と完全一致）', () {
      final expected = {
        // 色覚
        'protanopia', 'deuteranopia', 'tritanopia', 'achromatopsia',
        'tetrachromacy',
        // 屈折
        'myopia', 'hyperopia', 'presbyopia', 'astigmatism',
        // 視野
        'glaucoma', 'macular_degeneration', 'hemianopia', 'tunnel_vision',
        // 光・透明度
        'cataract', 'floaters', 'photophobia', 'night_blindness', 'starbursts',
        // 前庭・めまい
        'vertigo', 'bppv_rotation', 'vestibular_neuritis', 'nystagmus',
        // 眼精疲労
        'eye_strain', 'dry_eye', 'contrast_sensitivity',
        // その他
        'diplopia', 'metamorphopsia', 'detail_loss', 'teichopsia',
        'flickering_stars',
      };
      final actual = kVisionFilterCatalog.map((e) => e.id).toSet();
      expect(actual, expected);
    });

    test('全 7 カテゴリにエントリが分類されている（空カテゴリなし）', () {
      for (final category in VisionFilterCategory.values) {
        expect(
          visionFilterEntriesByCategory(category),
          isNotEmpty,
          reason: '$category にエントリが無い',
        );
      }
      // 7 カテゴリの合計が 30
      final total = VisionFilterCategory.values
          .map((c) => visionFilterEntriesByCategory(c).length)
          .fold<int>(0, (a, b) => a + b);
      expect(total, 30);
    });

    test('カテゴリ内訳（5/4/4/5/4/3/5）', () {
      expect(
        visionFilterEntriesByCategory(VisionFilterCategory.colorVision).length,
        5,
      );
      expect(
        visionFilterEntriesByCategory(VisionFilterCategory.refraction).length,
        4,
      );
      expect(
        visionFilterEntriesByCategory(VisionFilterCategory.visualField).length,
        4,
      );
      expect(
        visionFilterEntriesByCategory(
          VisionFilterCategory.lightAndTransparency,
        ).length,
        5,
      );
      expect(
        visionFilterEntriesByCategory(VisionFilterCategory.vestibular).length,
        4,
      );
      expect(
        visionFilterEntriesByCategory(VisionFilterCategory.eyeStrain).length,
        3,
      );
      expect(
        visionFilterEntriesByCategory(VisionFilterCategory.other).length,
        5,
      );
    });

    test('byId マップは 30 件で全 id をカバー', () {
      expect(kVisionFilterCatalogById.length, 30);
      for (final e in kVisionFilterCatalog) {
        expect(kVisionFilterCatalogById[e.id], same(e));
      }
    });
  });

  group('payload パラメータ定義数が sensus payload と一致', () {
    void expectParamCount(String id, int count) {
      final entry = kVisionFilterCatalogById[id]!;
      expect(entry.parameters.length, count, reason: id);
    }

    test('payload 付きフィルタの parameters 数', () {
      expectParamCount('astigmatism', 1); // axisDeg
      expectParamCount('glaucoma', 1); // mode
      expectParamCount('hemianopia', 1); // side
      expectParamCount('cataract', 1); // seed
      expectParamCount('floaters', 5); // seed,density,size,gazeX,gazeY
      expectParamCount('starbursts', 4); // numRays,rayLengthRatio,threshold,dispersion
      expectParamCount('nystagmus', 2); // amplitude,directionDeg
      expectParamCount('diplopia', 3); // offsetX,offsetY,ghostStrength
      expectParamCount('metamorphopsia', 2); // freq,seed
      expectParamCount('detail_loss', 1); // cellSize
      expectParamCount('flickering_stars', 1); // seed
    });

    test('payload を持たないフィルタは parameters が空', () {
      const noPayload = [
        'protanopia',
        'deuteranopia',
        'tritanopia',
        'achromatopsia',
        'tetrachromacy',
        'myopia',
        'hyperopia',
        'presbyopia',
        'macular_degeneration',
        'tunnel_vision',
        'photophobia',
        'night_blindness',
        'vertigo',
        'bppv_rotation',
        'vestibular_neuritis',
        'eye_strain',
        'dry_eye',
        'contrast_sensitivity',
        'teichopsia',
      ];
      for (final id in noPayload) {
        expect(kVisionFilterCatalogById[id]!.parameters, isEmpty, reason: id);
      }
    });

    test('enum パラメータには options がある / 非 enum は空', () {
      for (final entry in kVisionFilterCatalog) {
        for (final p in entry.parameters) {
          if (p.kind == VisionParamKind.enumValue) {
            expect(p.options, isNotEmpty, reason: '${entry.id}.${p.name}');
          } else {
            expect(p.options, isEmpty, reason: '${entry.id}.${p.name}');
          }
        }
      }
    });

    test('glaucoma の mode 選択肢は 4（VisionGlaucomaMode と同数）', () {
      final mode = kVisionFilterCatalogById['glaucoma']!.parameters.single;
      expect(mode.kind, VisionParamKind.enumValue);
      expect(mode.options.length, VisionGlaucomaMode.values.length);
    });

    test('hemianopia の side options が kHemianopiaSideValues と一致（drift 検出）',
        () {
      // 単一の写像源（kHemianopiaSideValues）と catalog の option value 集合が
      // ずれていないことを検証する。どちらか片方だけ変更すると失敗する。
      final side = kVisionFilterCatalogById['hemianopia']!.parameters.single;
      final optionKeys = side.options.map((o) => o.value).toSet();
      expect(optionKeys, kHemianopiaSideValues.keys.toSet());
      // 既定値も写像源のキーであること。
      expect(kHemianopiaSideValues.containsKey(side.defaultValue), isTrue);
      // 写像の実値（left=0.0 / right=1.0）が固定であること。
      expect(kHemianopiaSideValues['left'], 0.0);
      expect(kHemianopiaSideValues['right'], 1.0);
    });
  });

  group('VisionFilterState.build()', () {
    test('未選択なら null', () {
      final state = VisionFilterState();
      expect(state.build(), isNull);
    });

    test('select は notify する / clear で null に戻る', () {
      final state = VisionFilterState();
      var notified = 0;
      state.addListener(() => notified++);
      state.select('protanopia');
      expect(state.selectedId, 'protanopia');
      expect(notified, 1);
      state.clear();
      expect(state.selectedId, isNull);
      expect(state.build(), isNull);
      expect(notified, 2);
    });

    test('未知 id の select は ArgumentError', () {
      final state = VisionFilterState();
      expect(() => state.select('nope'), throwsArgumentError);
    });

    test('payload なし: protanopia を構築', () {
      final state = VisionFilterState()..select('protanopia');
      expect(state.build(), const VisionFilter.protanopia());
    });

    test('payload なし全種が例外なく構築できる', () {
      for (final entry in kVisionFilterCatalog) {
        final state = VisionFilterState()..select(entry.id);
        expect(state.build(), isNotNull, reason: entry.id);
      }
    });

    test('float payload: astigmatism の axisDeg を反映', () {
      final state = VisionFilterState()..select('astigmatism');
      // デフォルト 90.0
      expect(state.build(), const VisionFilter.astigmatism(axisDeg: 90.0));
      state.setParam('axisDeg', 45.0);
      expect(state.build(), const VisionFilter.astigmatism(axisDeg: 45.0));
    });

    test('enum payload: glaucoma の mode を反映', () {
      final state = VisionFilterState()..select('glaucoma');
      // デフォルト vignette
      expect(
        state.build(),
        const VisionFilter.glaucoma(mode: VisionGlaucomaMode.vignette),
      );
      state.setParam('mode', 'arcuateSuperior');
      expect(
        state.build(),
        const VisionFilter.glaucoma(
          mode: VisionGlaucomaMode.arcuateSuperior,
        ),
      );
    });

    test('seed + float payload: floaters を全パラメータで構築', () {
      final state = VisionFilterState()..select('floaters');
      state.setParam('seed', 7);
      state.setParam('density', 0.3);
      state.setParam('size', 0.4);
      state.setParam('gazeX', 0.2);
      state.setParam('gazeY', 0.8);
      expect(
        state.build(),
        VisionFilter.floaters(
          seed: BigInt.from(7),
          density: 0.3,
          size: 0.4,
          gazeX: 0.2,
          gazeY: 0.8,
        ),
      );
    });

    test('enum payload: hemianopia の side が left=0.0 / right=1.0', () {
      final state = VisionFilterState()..select('hemianopia');
      // デフォルト left
      expect(state.build(), const VisionFilter.hemianopia(side: 0.0));
      state.setParam('side', 'right');
      expect(state.build(), const VisionFilter.hemianopia(side: 1.0));
    });

    test('int payload: detail_loss の cellSize を反映', () {
      final state = VisionFilterState()..select('detail_loss');
      state.setParam('cellSize', 16);
      expect(state.build(), const VisionFilter.detailLoss(cellSize: 16));
    });

    test('select でパラメータが当該フィルタの default に初期化される', () {
      final state = VisionFilterState()..select('floaters');
      // floaters の default を保持
      expect(state.params['density'], 0.5);
      // 別フィルタへ切替えると floaters の param は消える
      state.select('astigmatism');
      expect(state.params.containsKey('density'), isFalse);
      expect(state.params['axisDeg'], 90.0);
    });

    test('strength は 0..1 に clamp して notify', () {
      final state = VisionFilterState();
      var notified = 0;
      state.addListener(() => notified++);
      state.setStrength(0.5);
      expect(state.strength, 0.5);
      state.setStrength(2.0);
      expect(state.strength, 1.0);
      state.setStrength(-1.0);
      expect(state.strength, 0.0);
      expect(notified, 3);
    });

    test('select で seed param の既定値が BigInt.zero（int/double を経由しない）',
        () {
      final state = VisionFilterState()..select('cataract');
      expect(state.params['seed'], isA<BigInt>());
      expect(state.params['seed'], BigInt.zero);
    });

    test('randomizeSeed は seed param を 0..u64max の BigInt に更新', () {
      final state = VisionFilterState()..select('cataract');
      state.randomizeSeed('seed');
      final v = state.params['seed'];
      expect(v, isA<BigInt>());
      final big = v as BigInt;
      expect(big, greaterThanOrEqualTo(BigInt.zero));
      expect(big, lessThanOrEqualTo(kSeedMax));
      expect(kSeedMax, (BigInt.one << 64) - BigInt.one);
    });

    test('randomizeSeed は 2^53 超の値にも到達できる（BigInt 経路の証跡）', () {
      final state = VisionFilterState()..select('cataract');
      final threshold = BigInt.one << 53;
      var sawLarge = false;
      // u64 範囲では 1 回の生成が 2^53 を超える確率が 99.9% 超。数十回試せば
      // 偽陰性は天文学的に低い。int/double 経由ならこの範囲に到達できない。
      for (var i = 0; i < 50 && !sawLarge; i++) {
        state.randomizeSeed('seed');
        if ((state.params['seed'] as BigInt) >= threshold) sawLarge = true;
      }
      expect(sawLarge, isTrue);
    });

    test('seed は 2^53 超の BigInt を精度欠落なく往復できる', () {
      final state = VisionFilterState()..select('floaters');
      // double 経由なら丸められてしまう値。
      final big = (BigInt.one << 63) + BigInt.from(123456789);
      state.setParam('seed', big);
      expect(
        state.build(),
        VisionFilter.floaters(
          seed: big,
          density: 0.5,
          size: 0.5,
          gazeX: 0.5,
          gazeY: 0.5,
        ),
      );
    });
  });
}
