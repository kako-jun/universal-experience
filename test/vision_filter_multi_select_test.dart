// 多症状の選択 API（#119）の単体テスト。
//
// 対象は VisionFilterState の toggle / remove / setLayerStrength / setLayerParams /
// replaceWith / clear と、その結果を描画へ渡す pipelineSteps。ADR
// `docs/adr/2026-09-30-multi-select-filter-state-model.md` の段階 3 の受け入れ条件を
// 1 つずつテストにしている。
//
//  - 色覚グループは排他（選ぶと既存の色覚層を置き換える）
//  - 上限は kMaxVisionLayers。上限で未選択を足すと no-op + 理由。例外は「色覚層が
//    既にあるときの色覚行（置換）」と「体験プリセット（全置換）」
//  - 体験プリセットは層全体の置換。層の集合がそのフィルタ 1 つ以外になったら外れ、戻らない
//  - フォーカス: 最後に足した/触れた層。外れたら適用順で最後の層
//  - 強度 0 の層は描画（pipelineSteps）から除くが、層としては残り上限にも数える
//  - 結果は選択の順に依存しない（段順）
//  - 再起動をまたぐ保存（v2）との整合
//
// 実際の描画の byte-exact 合成は #118 の Rust 側テストが担う。ここは「どの層を、どの
// 順で、どの強度・payload で渡すか」までを検証する（描画器を呼ぶ側の検証は
// test/home_screen_multi_layer_preview_test.dart）。

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/models/vision_filter_stage.dart';
import 'package:universal_experience/services/vision_filter_metadata.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/services/vision_filter_store.dart';
import 'package:universal_experience/services/vision_layer.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';

import 'support/vision_filter_metadata_fixture.dart';

/// 色覚以外で、段がすべて違う 6 フィルタ（motion → optics → media → retina →
/// visualField → perception の順）。上限 5 を 1 つ超える数。
const _nonColor = <String>[
  'vertigo',
  'myopia',
  'floaters',
  'night_blindness',
  'glaucoma',
  'teichopsia',
];

List<String> _ids(VisionFilterState s) => [for (final l in s.layers) l.id];

void main() {
  late VisionFilterState state;

  setUp(() {
    installVisionFilterMetadataFixture();
    state = VisionFilterState();
  });
  tearDown(resetVisionFilterMetadataProviders);

  group('toggle: 足す・外す', () {
    test('未選択を足すと added、層は段順に並びフォーカスは足した層へ', () {
      expect(state.toggle('glaucoma'), VisionLayerResult.added);
      expect(state.toggle('vertigo'), VisionLayerResult.added);
      expect(state.toggle('myopia'), VisionLayerResult.added);

      // 選んだ順（glaucoma, vertigo, myopia）ではなく段順。
      expect(_ids(state), ['vertigo', 'myopia', 'glaucoma']);
      expect(state.focusedId, 'myopia');
    });

    test('選択済みをもう一度 toggle すると removed、強度の記憶は残る', () {
      state.toggle('myopia');
      state.setLayerStrength('myopia', 0.4);
      expect(state.toggle('myopia'), VisionLayerResult.removed);
      expect(state.layers, isEmpty);
      expect(state.focusedId, isNull);

      state.toggle('myopia');
      expect(state.strength, 0.4, reason: '外しても強度の記憶は消えない（#117）');
    });

    test('フォーカス中の層を外すと、適用順で最後の層へ移る', () {
      state.toggle('vertigo');
      state.toggle('glaucoma');
      state.toggle('myopia'); // フォーカス = myopia。適用順は vertigo, myopia, glaucoma
      expect(state.focusedId, 'myopia');

      state.remove('myopia');
      expect(state.focusedId, 'glaucoma', reason: '適用順で最後の層');
    });

    test('フォーカス外の層を外してもフォーカスは動かない', () {
      state.toggle('vertigo');
      state.toggle('myopia'); // フォーカス = myopia
      state.remove('vertigo');
      expect(state.focusedId, 'myopia');
    });

    test('remove は未選択なら false で何も通知しない', () {
      var notified = 0;
      state.addListener(() => notified++);
      expect(state.remove('myopia'), isFalse);
      expect(notified, 0);
    });

    test('toggle は通知を 1 回だけ行う', () {
      var notified = 0;
      state.addListener(() => notified++);
      state.toggle('myopia');
      state.toggle('vertigo');
      state.toggle('myopia');
      expect(notified, 3);
    });

    test('未知の id は ArgumentError', () {
      expect(() => state.toggle('no_such_filter'), throwsArgumentError);
    });
  });

  group('色覚グループの排他', () {
    test('色覚を選ぶと既存の色覚層を置き換える（replaced、層数は増えない）', () {
      state.toggle('myopia');
      expect(state.toggle('protanopia'), VisionLayerResult.added);
      expect(state.toggle('deuteranopia'), VisionLayerResult.replaced);

      expect(_ids(state), ['myopia', 'deuteranopia']);
      expect(state.focusedId, 'deuteranopia');
    });

    test('-opia ⇄ -omaly（同じカタログ id の別名）も置換になる', () {
      state.toggle('protanopia', origin: VisionLayerOrigin.quick);
      expect(
        state.toggle(
          'protanopia',
          variantId: 'protanomaly',
          origin: VisionLayerOrigin.quick,
        ),
        VisionLayerResult.replaced,
      );
      expect(state.layers.single.variantId, 'protanomaly');
      expect(state.colorVisionType, ColorVisionType.protanomaly);

      // 同じ別名をもう一度 toggle すると外れる。
      expect(
        state.toggle(
          'protanopia',
          variantId: 'protanomaly',
          origin: VisionLayerOrigin.quick,
        ),
        VisionLayerResult.removed,
      );
      expect(state.layers, isEmpty);
    });

    test('対応しない別名は ArgumentError で状態を変えない', () {
      state.toggle('myopia');
      expect(
        () => state.toggle('protanopia', variantId: 'deuteranomaly'),
        throwsArgumentError,
      );
      expect(_ids(state), ['myopia']);
    });

    test('色覚層は常に列の末尾（色覚は最終段）', () {
      state.toggle('protanopia');
      state.toggle('vertigo');
      state.toggle('glaucoma');
      expect(_ids(state), ['vertigo', 'glaucoma', 'protanopia']);
    });
  });

  group('上限（kMaxVisionLayers）', () {
    test('上限は 5', () {
      expect(kMaxVisionLayers, 5);
    });

    test('6 つ目の未選択は no-op で理由を返し、状態も通知も変わらない', () {
      for (final id in _nonColor.take(5)) {
        expect(state.toggle(id).changed, isTrue);
      }
      var notified = 0;
      state.addListener(() => notified++);
      final before = _ids(state);
      final focusBefore = state.focusedId;

      final result = state.toggle(_nonColor[5]);

      expect(result.change, VisionLayerChange.blocked);
      expect(result.blockedBy, VisionLayerBlockReason.layerLimit);
      expect(result.changed, isFalse);
      expect(_ids(state), before);
      expect(state.focusedId, focusBefore);
      expect(notified, 0);
    });

    test('blockReasonFor は UI の無効化用に同じ判定を返す', () {
      for (final id in _nonColor.take(5)) {
        expect(state.blockReasonFor(id), isNull);
        state.toggle(id);
      }
      expect(state.blockReasonFor(_nonColor[5]),
          VisionLayerBlockReason.layerLimit);
      // 選択済みの行は外せるので無効化しない。
      expect(state.blockReasonFor(_nonColor[0]), isNull);
      // 色覚層が無いまま上限のときは色覚行も足せない。
      expect(state.blockReasonFor('protanopia'),
          VisionLayerBlockReason.layerLimit);
    });

    test('1 つ外すと足せるようになる', () {
      for (final id in _nonColor.take(5)) {
        state.toggle(id);
      }
      expect(state.toggle(_nonColor[5]).change, VisionLayerChange.blocked);

      state.remove('vertigo');
      expect(state.toggle(_nonColor[5]), VisionLayerResult.added);
      expect(state.layers, hasLength(5));
    });

    test('例外: 色覚層が既にあるときは、上限でも色覚行は置換として受け付ける', () {
      for (final id in _nonColor.take(4)) {
        state.toggle(id);
      }
      state.toggle('protanopia'); // 4 + 色覚 1 = 5（上限）
      expect(state.layers, hasLength(5));

      expect(state.blockReasonFor('tritanopia'), isNull);
      expect(state.toggle('tritanopia'), VisionLayerResult.replaced);
      expect(state.layers, hasLength(5));
      expect(_ids(state).last, 'tritanopia');
    });

    test('上限で色覚層が無いときの色覚行は no-op', () {
      for (final id in _nonColor.take(5)) {
        state.toggle(id);
      }
      final result = state.toggle('protanopia');
      expect(result.blockedBy, VisionLayerBlockReason.layerLimit);
      expect(_ids(state), isNot(contains('protanopia')));
    });

    test('例外: 体験プリセットは上限でも全置換で受け付ける', () {
      for (final id in _nonColor.take(5)) {
        state.toggle(id);
      }
      state.selectPreset('meniere', 'vertigo');
      expect(_ids(state), ['vertigo']);
      expect(state.selectedPresetId, 'meniere');
    });

    test('replaceWith（従来の単一選択）は上限でも常に成立する', () {
      for (final id in _nonColor.take(5)) {
        state.toggle(id);
      }
      state.replaceWith('protanopia');
      expect(_ids(state), ['protanopia']);
    });

    test('強度 0 の層も層としては残り、上限に数える', () {
      for (final id in _nonColor.take(5)) {
        state.toggle(id);
      }
      state.setLayerStrength('vertigo', 0.0);
      expect(state.layers, hasLength(5));
      expect(state.toggle(_nonColor[5]).change, VisionLayerChange.blocked);
    });
  });

  group('体験プリセット', () {
    test('プリセットは全層を置き換える（強度・payload は推奨値・既定値）', () {
      visionFilterRecommendedStrengthProvider = (_) => 0.6;
      state.toggle('myopia');
      state.toggle('glaucoma');
      state.setLayerStrength('glaucoma', 0.2);

      state.selectPreset('meniere', 'vertigo');

      expect(_ids(state), ['vertigo']);
      expect(state.selectedPresetId, 'meniere');
      expect(state.strength, 0.6);
    });

    test('別の層を足すとプリセット選択は外れ、その層を外しても戻らない', () {
      state.selectPreset('meniere', 'vertigo');
      state.toggle('myopia');
      expect(state.selectedPresetId, isNull);

      state.remove('myopia');
      expect(_ids(state), ['vertigo']);
      expect(state.selectedPresetId, isNull, reason: '一度外れたプリセットは復元しない');
    });

    test('プリセットの層を外してもプリセット選択は外れる', () {
      state.selectPreset('meniere', 'vertigo');
      state.remove('vertigo');
      expect(state.selectedPresetId, isNull);
    });

    test('プリセット選択中にそのフィルタ自身を toggle で外すと外れ、付け直しても戻らない', () {
      state.selectPreset('meniere', 'vertigo');
      state.toggle('vertigo'); // 外す
      state.toggle('vertigo'); // 付け直す
      expect(state.selectedPresetId, isNull);
    });

    test('層の集合が変わらない操作（強度・payload の調整）は従来どおりプリセット表示だけ解除', () {
      state.selectPreset('meniere', 'vertigo');
      state.setLayerStrength('vertigo', 0.5);
      expect(state.selectedPresetId, isNull);
      expect(_ids(state), ['vertigo']);
    });

    test('replaceWith / clear もプリセット選択を外す', () {
      state.selectPreset('meniere', 'vertigo');
      state.replaceWith('vertigo');
      expect(state.selectedPresetId, isNull);

      state.selectPreset('meniere', 'vertigo');
      state.clear();
      expect(state.selectedPresetId, isNull);
      expect(state.layers, isEmpty);
    });
  });

  group('setLayerStrength / setLayerParams', () {
    test('強度はその層のキーだけに書き、他の層は変えない', () {
      state.toggle('myopia');
      state.toggle('glaucoma');
      state.setLayerStrength('myopia', 0.3);

      final byId = {for (final l in state.layers) l.id: state.strengthOf(l)};
      expect(byId['myopia'], 0.3);
      expect(byId['glaucoma'], 1.0);
    });

    test('触れた層がフォーカスの移り先になる', () {
      state.toggle('myopia');
      state.toggle('glaucoma'); // フォーカス = glaucoma
      state.setLayerStrength('myopia', 0.5);
      expect(state.focusedId, 'myopia');

      state.setLayerParams('glaucoma', const {});
      expect(state.focusedId, 'glaucoma');
    });

    test('0..1 に clamp される', () {
      state.toggle('myopia');
      state.setLayerStrength('myopia', 7);
      expect(state.strength, 1.0);
      state.setLayerStrength('myopia', -1);
      expect(state.strength, 0.0);
    });

    test('未選択の id への操作は何もしない（通知もしない）', () {
      var notified = 0;
      state.addListener(() => notified++);
      state.setLayerStrength('myopia', 0.2);
      state.setLayerParams('astigmatism', const {'axisDeg': 10.0});
      expect(notified, 0);
      expect(state.strengthByKey, isEmpty);
    });

    test('payload はその層だけを置き換え、id ごとの記憶にも残る', () {
      state.toggle('astigmatism');
      state.toggle('starbursts');
      state.setLayerParams('astigmatism', const {'axisDeg': 30.0});

      expect(
        state.layers.firstWhere((l) => l.id == 'astigmatism').params,
        {'axisDeg': 30.0},
      );
      // 外して付け直しても記憶から戻る。
      state.remove('astigmatism');
      state.toggle('astigmatism');
      expect(
        state.layers.firstWhere((l) => l.id == 'astigmatism').params,
        {'axisDeg': 30.0},
      );
    });
  });

  group('単一選択との互換', () {
    test('select / replaceWith は層を 1 つにする', () {
      state.toggle('myopia');
      state.toggle('glaucoma');
      state.replaceWith('vertigo');
      expect(_ids(state), ['vertigo']);
      expect(state.focusedId, 'vertigo');

      state.select('glaucoma');
      expect(_ids(state), ['glaucoma']);
    });

    test('selectColorVisionType は層を 1 つの quick 層にする（-omaly は別名付き）', () {
      state.toggle('myopia');
      state.selectColorVisionType(
          ColorVisionType.deuteranomaly, 'deuteranopia');

      expect(state.layers, hasLength(1));
      expect(state.layers.single.id, 'deuteranopia');
      expect(state.layers.single.variantId, 'deuteranomaly');
      expect(state.isColorQuickSelection, isTrue);
      expect(state.colorVisionType, ColorVisionType.deuteranomaly);
    });

    test('selectColorVisionType(none) は全層を解除する', () {
      state.toggle('myopia');
      state.selectColorVisionType(ColorVisionType.none);
      expect(state.layers, isEmpty);
    });

    test('単一選択のとき selectedId / build / strength は従来と同じ（フォーカス中の層）', () {
      state.select('starbursts');
      state.setStrength(0.4);
      expect(state.selectedId, 'starbursts');
      expect(state.focusedId, 'starbursts');
      expect(state.build(), isA<VisionFilter>());
      expect(state.strength, 0.4);
    });

    test('多層のとき selectedId / build / strength はフォーカス中の層を指す', () {
      state.toggle('myopia');
      state.toggle('vertigo');
      state.setLayerStrength('myopia', 0.25);
      expect(state.selectedId, 'myopia');
      expect(state.build(), const VisionFilter.myopia());
      expect(state.strength, 0.25);
    });

    test('clear は全層・フォーカス・プリセットを解除する', () {
      state.toggle('myopia');
      state.toggle('vertigo');
      state.clear();
      expect(state.layers, isEmpty);
      expect(state.focusedId, isNull);
      expect(state.pipelineSteps(), isEmpty);
    });

    test('toggle は原画比較（bypass）を解除する', () {
      final holder = Object();
      state.toggle('myopia');
      state.acquireBypass(holder);
      expect(state.bypassed, isTrue);
      state.toggle('vertigo');
      expect(state.bypassed, isFalse);
    });
  });

  group('pipelineSteps（描画へ渡す列）', () {
    test('段順に、各層の strength で並ぶ', () {
      state.toggle('night_blindness');
      state.toggle('myopia');
      state.toggle('vertigo');
      state.setLayerStrength('night_blindness', 0.5);
      state.setLayerStrength('myopia', 0.25);

      expect(state.pipelineSteps(), [
        const VisionStep(filter: VisionFilter.vertigo(), strength: 1.0),
        const VisionStep(filter: VisionFilter.myopia(), strength: 0.25),
        const VisionStep(filter: VisionFilter.nightBlindness(), strength: 0.5),
      ]);
    });

    test('選ぶ順を入れ替えても同じ列になる（履歴に依存しない）', () {
      VisionFilterState build(List<String> order) {
        final s = VisionFilterState();
        for (final id in order) {
          s.toggle(id);
        }
        s.setLayerStrength('myopia', 0.6);
        return s;
      }

      final a = build(['vertigo', 'myopia', 'night_blindness', 'protanopia']);
      final b = build(['protanopia', 'night_blindness', 'myopia', 'vertigo']);
      expect(a.pipelineSteps(), b.pipelineSteps());
      expect(a.pipelineSteps(), hasLength(4));
    });

    test('上限ちょうど 5 層: 選ぶ順を変えても、同じ 5 ステップが段順で並ぶ（リテラルで固定）', () {
      // 段: motion / optics / retina / perception / colorVision。
      const strengths = {
        'vertigo': 0.1,
        'myopia': 0.2,
        'night_blindness': 0.3,
        'teichopsia': 0.4,
        'protanopia': 0.5,
      };
      const orders = [
        ['vertigo', 'myopia', 'night_blindness', 'teichopsia', 'protanopia'],
        ['protanopia', 'teichopsia', 'night_blindness', 'myopia', 'vertigo'],
        ['night_blindness', 'protanopia', 'vertigo', 'teichopsia', 'myopia'],
      ];
      const expected = [
        VisionStep(filter: VisionFilter.vertigo(), strength: 0.1),
        VisionStep(filter: VisionFilter.myopia(), strength: 0.2),
        VisionStep(filter: VisionFilter.nightBlindness(), strength: 0.3),
        VisionStep(filter: VisionFilter.teichopsia(), strength: 0.4),
        VisionStep(filter: VisionFilter.protanopia(), strength: 0.5),
      ];
      for (final order in orders) {
        final s = VisionFilterState();
        for (final id in order) {
          expect(s.toggle(id), VisionLayerResult.added, reason: '$order');
        }
        strengths.forEach(s.setLayerStrength);
        expect(s.layers, hasLength(kMaxVisionLayers));
        expect(s.pipelineSteps(), expected, reason: '選択順 $order');

        // 6 つ目は足せず、列も変わらない。
        expect(
          s.toggle('glaucoma'),
          const VisionLayerResult.blocked(VisionLayerBlockReason.layerLimit),
        );
        expect(s.pipelineSteps(), expected);
      }
    });

    test('同じ段の 3 層は段内の宣言順（選んだ順でなく）で並ぶ', () {
      // optics 段の宣言順: myopia → hyperopia → astigmatism → presbyopia。
      for (final order in const [
        ['presbyopia', 'hyperopia', 'myopia'],
        ['myopia', 'hyperopia', 'presbyopia'],
        ['hyperopia', 'presbyopia', 'myopia'],
      ]) {
        final s = VisionFilterState();
        for (final id in order) {
          s.toggle(id);
        }
        s.setLayerStrength('myopia', 0.3);
        s.setLayerStrength('hyperopia', 0.6);
        s.setLayerStrength('presbyopia', 0.9);
        expect(
            s.pipelineSteps(),
            const [
              VisionStep(filter: VisionFilter.myopia(), strength: 0.3),
              VisionStep(filter: VisionFilter.hyperopia(), strength: 0.6),
              VisionStep(filter: VisionFilter.presbyopia(), strength: 0.9),
            ],
            reason: '選択順 $order');
      }
    });

    test('payload はそれぞれの層のものを使う', () {
      state.toggle('astigmatism');
      state.toggle('starbursts');
      state.setLayerParams('astigmatism', const {'axisDeg': 30.0});

      final steps = state.pipelineSteps();
      expect(steps.first.filter, const VisionFilter.astigmatism(axisDeg: 30.0));
    });

    test('強度 0 の層は列から除く（層は残る）', () {
      state.toggle('vertigo');
      state.toggle('myopia');
      state.toggle('night_blindness');
      state.setLayerStrength('myopia', 0.0);

      expect(state.layers, hasLength(3));
      expect(state.pipelineSteps().map((s) => s.filter), [
        const VisionFilter.vertigo(),
        const VisionFilter.nightBlindness(),
      ]);
    });

    test('全層が強度 0 なら空（原画のまま）', () {
      state.toggle('vertigo');
      state.setLayerStrength('vertigo', 0.0);
      expect(state.pipelineSteps(), isEmpty);
    });

    test('強度を触っていない層は推奨強度を使い、記憶へは書かない', () {
      visionFilterRecommendedStrengthProvider = (_) => 0.7;
      state.toggle('vertigo');
      expect(state.pipelineSteps().single.strength, 0.7);
      expect(state.strengthByKey, isEmpty);
    });

    test('色覚層は列の末尾で、-omaly も同じ VisionFilter になる', () {
      state.toggle('protanopia',
          variantId: 'protanomaly', origin: VisionLayerOrigin.quick);
      state.toggle('vertigo');
      final steps = state.pipelineSteps();
      expect(steps.last.filter, const VisionFilter.protanopia());
      expect(steps.first.filter, const VisionFilter.vertigo());
    });
  });

  group('再起動をまたぐ保存（v2）との整合', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('足す・強度・payload・プリセット外れの後に保存して復元すると同じ状態になる', () async {
      final store = VisionFilterStore(debounce: Duration.zero);
      store.bind(state);

      state.toggle('vertigo');
      state.toggle('astigmatism');
      state.toggle('glaucoma');
      state.toggle('protanopia',
          variantId: 'protanomaly', origin: VisionLayerOrigin.quick);
      state.setLayerStrength('astigmatism', 0.35);
      state.setLayerParams('astigmatism', const {'axisDeg': 45.0});
      state.setLayerStrength('glaucoma', 0.0);
      state.toggle('vertigo'); // 外す → フォーカス移動
      await store.flush();

      final restored = VisionFilterState();
      final restoredOk = await VisionFilterStore(debounce: Duration.zero)
          .restoreAndBind(restored);

      expect(restoredOk, isTrue);
      expect(_ids(restored), _ids(state));
      expect(restored.focusedId, state.focusedId);
      expect(restored.pipelineSteps(), state.pipelineSteps());
      expect(restored.layers.last.variantId, 'protanomaly');
      expect(restored.strengthByKey, state.strengthByKey);
      expect(restored.layers.length, 3, reason: '強度 0 の glaucoma も層として残る');
    });

    test('復元した集合が上限・排他に従い、プリセット選択は層 1 つのときだけ戻る', () async {
      final store = VisionFilterStore(debounce: Duration.zero);
      store.bind(state);
      state.selectPreset('meniere', 'vertigo');
      await store.flush();

      final restored = VisionFilterState();
      await VisionFilterStore(debounce: Duration.zero).restoreAndBind(
        restored,
        isValidPreset: (presetId, catalogId) =>
            presetId == 'meniere' && catalogId == 'vertigo',
      );
      expect(restored.selectedPresetId, 'meniere');

      // 足してから保存 → 復元ではプリセット選択は付かない。
      state.toggle('myopia');
      await store.flush();
      final restored2 = VisionFilterState();
      await VisionFilterStore(debounce: Duration.zero).restoreAndBind(
        restored2,
        isValidPreset: (_, __) => true,
      );
      expect(restored2.selectedPresetId, isNull);
      expect(_ids(restored2), ['vertigo', 'myopia']);
    });
  });
}
