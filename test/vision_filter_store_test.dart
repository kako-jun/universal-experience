// VisionFilterState.snapshot()/restore() と VisionFilterStore（#65, #117）のテスト。
//
// - 層（advanced / 体験プリセット / 色覚クイック選択）・強度の記憶・payload が
//   snapshot → JSON → restore で戻る。
// - 復元できない層（未知 id・無効なプリセット・色覚型とカタログ id の不一致）は
//   安全側に倒れ、起動を止めない。
// - store: 変更は flush で書かれ、壊れた JSON・未知の版は無視して state を
//   触らない。版 1 の保存は v2 の形へ変換して復元する。
// - 旧 `settings.intensityByType` の取り込み（migrateLegacyStrengths）: (a) 読める v2
//   が無い / (b) 読める v2 がある / (c) 旧キーが無い、と失敗系（JSON 欠落・壊れ・
//   空・書き込み失敗）。
//
// urgency/推奨強度は sensus ブリッジを要求するためフィクスチャに差し替える。

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/services/vision_layer.dart';
import 'package:universal_experience/services/vision_filter_metadata.dart';
import 'package:universal_experience/services/vision_filter_snapshot.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/services/vision_filter_store.dart';

import 'support/vision_filter_metadata_fixture.dart';

/// 保存 → 読み込みを実際の JSON 文字列越しに行う（state の写しが in-memory の
/// 参照共有で通ってしまわないように）。
VisionFilterSnapshot _viaJson(VisionFilterSnapshot s) =>
    VisionFilterSnapshot.fromJson(jsonDecode(jsonEncode(s.toJson())))!;

Future<Map<String, Object?>?> _storedJson() async {
  final raw = (await SharedPreferences.getInstance())
      .getString(VisionFilterStore.keySnapshot);
  return raw == null ? null : jsonDecode(raw) as Map<String, Object?>;
}

void main() {
  setUp(installVisionFilterMetadataFixture);
  tearDown(resetVisionFilterMetadataProviders);

  group('snapshot()/restore()', () {
    test('advanced の選択・強度・payload が別インスタンスへ戻る', () {
      final a = VisionFilterState()
        ..select('starbursts')
        ..setStrength(0.35)
        ..setParam('numRays', 12)
        ..setParam('rayLengthRatio', 0.8);

      final b = VisionFilterState()..restore(_viaJson(a.snapshot()));

      expect(b.selectedId, 'starbursts');
      expect(b.strength, 0.35);
      expect(b.params['numRays'], 12);
      expect(b.params['rayLengthRatio'], 0.8);
      expect(b.isColorQuickSelection, isFalse);
      expect(b.selectedPresetId, isNull);
    });

    test('他のフィルタの記憶も戻り、選び直すと復元される（#77 の記憶）', () {
      final a = VisionFilterState()
        ..select('astigmatism')
        ..setParam('axisDeg', 45.0)
        ..setStrength(0.2)
        ..select('myopia')
        ..setStrength(0.9);

      final b = VisionFilterState()..restore(_viaJson(a.snapshot()));
      expect(b.selectedId, 'myopia');
      expect(b.strength, 0.9);

      b.select('astigmatism');
      expect(b.params['axisDeg'], 45.0);
      expect(b.strength, 0.2);
    });

    test('seed（u64）が精度を保って戻り、build() まで通る', () {
      final seed = (BigInt.one << 64) - BigInt.from(7);
      final a = VisionFilterState()
        ..select('floaters')
        ..setParam('seed', seed);

      final b = VisionFilterState()..restore(_viaJson(a.snapshot()));

      expect(b.params['seed'], seed);
      expect(b.build(), isNotNull);
    });

    test('体験プリセット: 検証が通れば selectedPresetId ごと戻る', () {
      final a = VisionFilterState()..selectPreset('labyrinthitis', 'vertigo');

      final b = VisionFilterState()
        ..restore(
          _viaJson(a.snapshot()),
          isValidPreset: (presetId, catalogId) =>
              presetId == 'labyrinthitis' && catalogId == 'vertigo',
        );

      expect(b.selectedId, 'vertigo');
      expect(b.selectedPresetId, 'labyrinthitis');
    });

    test('体験プリセット: 検証が通らない・検証なしなら advanced の選択として戻る', () {
      final snapshot = _viaJson(
        (VisionFilterState()..selectPreset('removed_preset', 'vertigo'))
            .snapshot(),
      );

      final rejected = VisionFilterState()
        ..restore(snapshot, isValidPreset: (_, __) => false);
      final unchecked = VisionFilterState()..restore(snapshot);

      for (final s in [rejected, unchecked]) {
        expect(s.selectedId, 'vertigo');
        expect(s.selectedPresetId, isNull);
      }
    });

    test('復元の途中で例外が出たら、呼び出し前の状態へ巻き戻して rethrow する', () {
      final s = VisionFilterState()
        ..select('starbursts')
        ..setStrength(0.35)
        ..setParam('numRays', 12)
        ..select('myopia');
      final before = jsonEncode(s.snapshot().toJson());
      final presetSnapshot = _viaJson(
        (VisionFilterState()..selectPreset('labyrinthitis', 'vertigo'))
            .snapshot(),
      );
      var notified = 0;
      s.addListener(() => notified++);

      expect(
        () => s.restore(
          presetSnapshot,
          isValidPreset: (_, __) => throw StateError('sensus failed'),
        ),
        throwsStateError,
      );

      expect(jsonEncode(s.snapshot().toJson()), before,
          reason: '記憶（強度・payload）も選択も半端に消えない');
      expect(s.selectedId, 'myopia');
      expect(s.selectedPresetId, isNull);
      expect(notified, 0);
      expect(s.build(), isNotNull);
    });

    test('色覚クイック選択: -omaly の型も含めて起源が戻る', () {
      final a = VisionFilterState()
        ..selectColorVisionType(ColorVisionType.protanomaly, 'protanopia');

      final b = VisionFilterState()..restore(_viaJson(a.snapshot()));

      expect(b.selectedId, 'protanopia');
      expect(b.isColorQuickSelection, isTrue);
      expect(b.colorVisionType, ColorVisionType.protanomaly);
    });

    test('色覚型と選択 id が食い違う保存値は色覚クイック選択にしない', () {
      // myopia は色覚ではない。tritanopia に protanomaly の別名は付かない。
      for (final layer in [
        VisionLayer(id: 'myopia', origin: VisionLayerOrigin.quick),
        VisionLayer(
          id: 'tritanopia',
          variantId: 'protanomaly',
          origin: VisionLayerOrigin.quick,
        ),
      ]) {
        final s = VisionFilterState()
          ..restore(VisionFilterSnapshot(layers: [layer]));

        expect(s.selectedId, layer.id);
        expect(s.isColorQuickSelection, isFalse, reason: '$layer');
        expect(s.colorVisionType, isNull, reason: '$layer');
        expect(s.focusedLayer!.variantId, isNull, reason: '$layer');
      }
    });

    test('層の列は不変条件に整え直して復元する（手組みの snapshot でも）', () {
      final s = VisionFilterState()
        ..restore(VisionFilterSnapshot(layers: [
          VisionLayer(id: 'protanopia'),
          VisionLayer(id: 'tritanopia'),
          VisionLayer(id: 'myopia'),
          VisionLayer(id: 'myopia'),
          VisionLayer(id: 'removed_in_sensus'),
        ]));

      expect([for (final l in s.layers) l.id], ['myopia', 'protanopia']);
    });

    test('フォーカスは保存された id が層にあればそれ、無ければ適用順で最後の層', () {
      final layers = [
        VisionLayer(id: 'myopia'),
        VisionLayer(id: 'floaters'),
        VisionLayer(id: 'protanopia'),
      ];

      final saved = VisionFilterState()
        ..restore(VisionFilterSnapshot(layers: layers, focusedId: 'floaters'));
      final missing = VisionFilterState()
        ..restore(VisionFilterSnapshot(layers: layers, focusedId: 'glaucoma'));
      final none = VisionFilterState()
        ..restore(VisionFilterSnapshot(layers: layers));

      expect(saved.focusedId, 'floaters');
      expect(missing.focusedId, 'protanopia');
      expect(none.focusedId, 'protanopia');
    });

    test('プリセットは層が 2 つ以上なら、検証が通っても戻さない', () {
      final s = VisionFilterState()
        ..restore(
          VisionFilterSnapshot(
            layers: [VisionLayer(id: 'vertigo'), VisionLayer(id: 'myopia')],
            presetId: 'labyrinthitis',
          ),
          isValidPreset: (_, __) => true,
        );

      expect(s.selectedPresetId, isNull);
      expect(s.layers, hasLength(2));
    });

    test('未選択の snapshot は選択を解除する', () {
      final s = VisionFilterState()..select('myopia');

      s.restore(const VisionFilterSnapshot());

      expect(s.selectedId, isNull);
      expect(s.build(), isNull);
    });

    test('カタログに無い id の snapshot（手組み）でも例外を出さず未選択にする', () {
      final s = VisionFilterState()..select('myopia');

      s.restore(VisionFilterSnapshot(
        layers: [VisionLayer(id: 'removed_in_sensus')],
        focusedId: 'removed_in_sensus',
      ));

      expect(s.selectedId, isNull);
      expect(s.layers, isEmpty);
    });

    test('強度の記憶が無い層は推奨強度を導出するだけで、記憶へは書かない', () {
      visionFilterRecommendedStrengthProvider = (_) => 0.6;

      final s = VisionFilterState()
        ..restore(VisionFilterSnapshot(layers: [VisionLayer(id: 'myopia')]));

      expect(s.strength, 0.6);
      expect(s.strengthByKey, isEmpty);
      expect(s.snapshot().strengthByKey, isEmpty);
    });

    test('記憶があれば推奨強度より優先される', () {
      visionFilterRecommendedStrengthProvider = (_) => 0.6;

      final s = VisionFilterState()
        ..restore(VisionFilterSnapshot(
          layers: [VisionLayer(id: 'myopia')],
          strengthByKey: const {'myopia': 0.25},
        ));

      expect(s.strength, 0.25);
    });

    test('復元は記憶を置き換える（復元前の記憶は残らない）', () {
      final s = VisionFilterState()
        ..select('astigmatism')
        ..setParam('axisDeg', 10.0);

      s.restore(VisionFilterSnapshot(layers: [VisionLayer(id: 'myopia')]));
      s.select('astigmatism');

      expect(s.params['axisDeg'], 90.0, reason: '既定値。復元前の 10.0 は消える');
    });

    test('原画比較（bypass）は復元しない', () {
      final s = VisionFilterState()..select('myopia');
      final holder = Object();
      s.acquireBypass(holder);

      s.restore(_viaJson(s.snapshot()));

      expect(s.bypassed, isFalse);
    });

    test('snapshot() は写し: 以後の state の変更は写しに影響しない', () {
      final s = VisionFilterState()
        ..select('astigmatism')
        ..setParam('axisDeg', 10.0);
      final snapshot = s.snapshot();

      s.setParam('axisDeg', 170.0);

      expect(snapshot.paramsById['astigmatism']!['axisDeg'], 10.0);
    });

    test('復元は 1 回だけ通知する', () {
      var notified = 0;
      final s = VisionFilterState()..addListener(() => notified++);

      s.restore(VisionFilterSnapshot(layers: [VisionLayer(id: 'myopia')]));

      expect(notified, 1);
    });
  });

  group('VisionFilterStore', () {
    late VisionFilterState state;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      state = VisionFilterState();
    });

    test('変更は flush で書かれ、別の store が読んで復元できる', () async {
      final store = VisionFilterStore();
      await store.restoreAndBind(state);
      state
        ..select('starbursts')
        ..setStrength(0.4)
        ..setParam('numRays', 9);
      await store.flush();

      final saved = await _storedJson();
      expect(saved!['version'], kVisionFilterSnapshotVersion);
      expect(saved['focusedId'], 'starbursts');
      expect((saved['layers'] as List).single['id'], 'starbursts');
      expect((saved['strengthByKey'] as Map)['starbursts'], 0.4);

      final next = VisionFilterState();
      final restored = await VisionFilterStore().restoreAndBind(next);
      expect(restored, isTrue);
      expect(next.selectedId, 'starbursts');
      expect(next.strength, 0.4);
      expect(next.params['numRays'], 9);
    });

    test('デバウンス中は書かれず、時間が経つと 1 回にまとめて書かれる', () async {
      final store = VisionFilterStore(
        debounce: const Duration(milliseconds: 20),
      );
      await store.restoreAndBind(state);

      state.select('starbursts');
      state.setStrength(0.1);
      state.setStrength(0.2);
      expect(await _storedJson(), isNull, reason: 'まだデバウンス中');

      await Future<void>.delayed(const Duration(milliseconds: 200));
      final saved = await _storedJson();
      expect(saved!['focusedId'], 'starbursts');
      expect((saved['strengthByKey'] as Map)['starbursts'], 0.2);
    });

    test('保留が無ければ flush は何もしない', () async {
      final store = VisionFilterStore();
      await store.restoreAndBind(state);

      await store.flush();

      expect(await _storedJson(), isNull);
    });

    test('永続対象が変わらない通知（原画比較）では書き直さない', () async {
      final store = VisionFilterStore();
      await store.restoreAndBind(state);
      state.select('myopia');
      await store.flush();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(VisionFilterStore.keySnapshot);

      state.acquireBypass(Object());
      await store.flush();

      expect(await _storedJson(), isNull);
    });

    test('保存が無ければ復元せず state は触らない（購読は張る）', () async {
      state.select('myopia');
      final store = VisionFilterStore();

      final restored = await store.restoreAndBind(state);

      expect(restored, isFalse);
      expect(state.selectedId, 'myopia');
      state.setStrength(0.5);
      await store.flush();
      expect((await _storedJson())!['focusedId'], 'myopia');
    });

    test('壊れた JSON は無視して state を触らない', () async {
      SharedPreferences.setMockInitialValues({
        VisionFilterStore.keySnapshot: '{not json',
      });
      state.select('myopia');

      final restored = await VisionFilterStore().restoreAndBind(state);

      expect(restored, isFalse);
      expect(state.selectedId, 'myopia');
    });

    test('未知の版・旧形式・Map でない保存値は無視して state を触らない', () async {
      for (final raw in [
        jsonEncode({'version': 99, 'selectedId': 'starbursts'}),
        jsonEncode({'version': 3, 'layers': []}),
        jsonEncode({'selectedId': 'starbursts', 'strength': 0.4}),
        jsonEncode(['starbursts']),
        jsonEncode('starbursts'),
        'null',
      ]) {
        SharedPreferences.setMockInitialValues({
          VisionFilterStore.keySnapshot: raw,
        });
        final s = VisionFilterState()..select('myopia');

        final restored = await VisionFilterStore().restoreAndBind(s);

        expect(restored, isFalse, reason: 'raw=$raw');
        expect(s.selectedId, 'myopia', reason: 'raw=$raw');
      }
    });

    test('カタログに無い id を選んでいた保存値は、未選択として復元する', () async {
      SharedPreferences.setMockInitialValues({
        VisionFilterStore.keySnapshot: jsonEncode({
          'version': kVisionFilterSnapshotVersion,
          'layers': [
            {'id': 'removed_in_sensus'},
          ],
          'focusedId': 'removed_in_sensus',
          'strengthByKey': {
            'removed_in_sensus': 0.4,
            'myopia': 0.7,
          },
        }),
      });

      final restored = await VisionFilterStore().restoreAndBind(state);

      expect(restored, isTrue);
      expect(state.selectedId, isNull);
      state.select('myopia');
      expect(state.strength, 0.7, reason: '残った記憶は生きている');
    });

    test('範囲外の保存値は定義の範囲に丸めて復元する', () async {
      SharedPreferences.setMockInitialValues({
        VisionFilterStore.keySnapshot: jsonEncode({
          'version': kVisionFilterSnapshotVersion,
          'layers': [
            {
              'id': 'starbursts',
              'params': {'numRays': 9999, 'rayLengthRatio': -4},
            },
          ],
          'focusedId': 'starbursts',
          'strengthByKey': {'starbursts': 3},
        }),
      });

      await VisionFilterStore().restoreAndBind(state);

      expect(state.strength, 1.0);
      expect(state.params['numRays'], 24);
      expect(state.params['rayLengthRatio'], 0.0);
      expect(state.build(), isNotNull);
    });

    test('復元が例外で失敗しても起動は続き、state は元のまま・保存は始まる', () async {
      final saved = VisionFilterState()
        ..selectPreset('labyrinthitis', 'vertigo');
      SharedPreferences.setMockInitialValues({
        VisionFilterStore.keySnapshot: jsonEncode(saved.snapshot().toJson()),
      });
      state
        ..select('myopia')
        ..setStrength(0.6);
      final store = VisionFilterStore();

      final restored = await store.restoreAndBind(
        state,
        isValidPreset: (_, __) => throw StateError('sensus failed'),
      );

      expect(restored, isFalse);
      expect(state.selectedId, 'myopia');
      expect(state.strength, 0.6);

      state.select('hyperopia');
      await store.flush();
      expect((await _storedJson())!['focusedId'], 'hyperopia',
          reason: '復元に失敗しても以後の変更は保存される');
    });

    test('flush は実行中の書き込みの完了も待つ', () async {
      final prefs = _GatedPrefs();
      final store = VisionFilterStore(
        prefs: prefs,
        debounce: const Duration(milliseconds: 5),
      );
      await store.restoreAndBind(state);
      state.select('myopia');
      await prefs.writeStarted.future; // タイマーが発火し、書き込みが走り始めた

      var flushed = false;
      final flushing = store.flush().then((_) => flushed = true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(flushed, isFalse, reason: '書き込み中は終了を許可しない');

      prefs.releaseWrite();
      await flushing;
      expect(flushed, isTrue);
      expect(jsonDecode(prefs.written!)['focusedId'], 'myopia');
    });

    test('dispose は保留分を確定して購読を外す', () async {
      final store = VisionFilterStore();
      await store.restoreAndBind(state);
      state.select('myopia');

      await store.dispose();
      final prefs = await SharedPreferences.getInstance();
      final afterDispose = prefs.getString(VisionFilterStore.keySnapshot);
      state.select('hyperopia');
      await store.flush();

      expect(jsonDecode(afterDispose!)['focusedId'], 'myopia');
      expect(prefs.getString(VisionFilterStore.keySnapshot), afterDispose);
    });
  });
  group('版 1 の保存の復元（旧 per-type 強度の取り込みが無い場合）', () {
    late VisionFilterState state;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      state = VisionFilterState();
    });

    test('版 1 の選択は v2 の層へ変換して復元し、以後は v2 で書かれる', () async {
      SharedPreferences.setMockInitialValues({
        VisionFilterStore.keySnapshot: jsonEncode({
          'version': 1,
          'selectedId': 'starbursts',
          'presetId': null,
          'colorVisionType': null,
          'filters': {
            'starbursts': {
              'strength': 0.4,
              'params': {'numRays': 9},
            },
          },
        }),
      });
      final store = VisionFilterStore();

      final restored = await store.restoreAndBind(state);

      expect(restored, isTrue);
      expect(state.selectedId, 'starbursts');
      expect(state.strength, 0.4);
      expect(state.params['numRays'], 9);
      expect(state.isColorQuickSelection, isFalse);

      state.setStrength(0.5);
      await store.flush();
      final saved = (await _storedJson())!;
      expect(saved['version'], 2);
      expect(saved['focusedId'], 'starbursts');
    });

    test('版 1 の色覚クイック選択（-omaly）は別名つきの quick 層として戻る', () async {
      SharedPreferences.setMockInitialValues({
        VisionFilterStore.keySnapshot: jsonEncode({
          'version': 1,
          'selectedId': 'deuteranopia',
          'colorVisionType': 'deuteranomaly',
          'filters': <String, Object?>{},
        }),
      });

      await VisionFilterStore().restoreAndBind(state);

      expect(state.isColorQuickSelection, isTrue);
      expect(state.colorVisionType, ColorVisionType.deuteranomaly);
      expect(state.focusedLayer!.variantId, 'deuteranomaly');
    });
  });

  group('空の保存の扱い（restoreAndBind）', () {
    test('空の v2（未選択で終了した）は復元され、先にシードした選択を解除する', () async {
      SharedPreferences.setMockInitialValues({
        VisionFilterStore.keySnapshot: jsonEncode({
          'version': 2,
          'layers': <Object?>[],
          'strengthByKey': <String, Object?>{},
          'paramsById': <String, Object?>{},
        }),
      });
      final state = VisionFilterState()
        ..selectColorVisionType(ColorVisionType.protanopia, 'protanopia');

      final restored = await VisionFilterStore().restoreAndBind(state);

      expect(restored, isTrue);
      expect(state.layers, isEmpty);
      expect(state.selectedId, isNull);
    });

    test('空の版 1 は何も運んでこないので復元せず、シードした選択を残す', () async {
      SharedPreferences.setMockInitialValues({
        VisionFilterStore.keySnapshot: jsonEncode({
          'version': 1,
          'selectedId': null,
          'filters': <String, Object?>{},
        }),
      });
      final state = VisionFilterState()
        ..selectColorVisionType(ColorVisionType.protanopia, 'protanopia');

      final restored = await VisionFilterStore().restoreAndBind(state);

      expect(restored, isFalse);
      expect(state.selectedId, 'protanopia');
    });
  });

  group('-opia の強度だけを持つ版 1（旧実装は非空として復元していた）', () {
    test('復元され、先にシードした色覚選択は解除される（未選択で始まる）', () async {
      SharedPreferences.setMockInitialValues({
        VisionFilterStore.keySnapshot: jsonEncode({
          'version': 1,
          'selectedId': null,
          'filters': {
            'protanopia': {'strength': 1.0},
          },
        }),
      });
      final state = VisionFilterState()
        ..selectColorVisionType(ColorVisionType.protanopia, 'protanopia');

      final store = VisionFilterStore();
      final migrated = await store.migrateLegacyStrengths(
          seedType: ColorVisionType.protanopia);
      final restored = await store.restoreAndBind(state, snapshot: migrated);

      expect(migrated, isNull, reason: '旧キーが無いので移行は何もしない');
      expect(restored, isTrue);
      expect(state.layers, isEmpty);
      expect(state.selectedId, isNull);
    });
  });

  group('migrateLegacyStrengths（旧 settings.intensityByType の取り込み）', () {
    late VisionFilterState state;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      state = VisionFilterState();
    });

    const legacyKey = VisionFilterStore.keyIntensityByType;

    Future<VisionFilterSnapshot?> migrate({
      ColorVisionType seedType = ColorVisionType.none,
    }) =>
        VisionFilterStore().migrateLegacyStrengths(seedType: seedType);

    Future<bool> hasLegacyKey() async =>
        (await SharedPreferences.getInstance()).containsKey(legacyKey);

    test('(c) 旧キーが無ければ何もしない（null・保存にも触れない）', () async {
      final v1 = jsonEncode({
        'version': 1,
        'selectedId': 'myopia',
        'filters': <String, Object?>{},
      });
      SharedPreferences.setMockInitialValues({
        VisionFilterStore.keySnapshot: v1,
      });

      final result = await migrate(seedType: ColorVisionType.protanopia);

      expect(result, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(VisionFilterStore.keySnapshot), v1,
          reason: '版 1 のまま。v2 への書き換えは restoreAndBind 側の通常保存に任せる');
    });

    test('(c) さらに古い単一キー settings.intensity は値を見ずに消す', () async {
      SharedPreferences.setMockInitialValues({
        VisionFilterStore.legacyIntensityKey: 0.3,
      });

      final result = await migrate();

      expect(result, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(VisionFilterStore.legacyIntensityKey), isFalse);
    });

    test('(a) 保存が無い: 旧強度を記憶に取り込み、seedType の quick 層を v2 で書く', () async {
      SharedPreferences.setMockInitialValues({
        legacyKey: jsonEncode({'protanopia': 0.4, 'protanomaly': 0.7}),
      });

      final result = await migrate(seedType: ColorVisionType.protanomaly);

      expect(result!.fromLegacy, isFalse);
      expect(result.strengthByKey, {'protanopia': 0.4, 'protanomaly': 0.7});
      final layer = result.layers.single;
      expect(layer.id, 'protanopia');
      expect(layer.variantId, 'protanomaly');
      expect(layer.origin, VisionLayerOrigin.quick);
      expect(result.focusedId, 'protanopia');

      final saved = (await _storedJson())!;
      expect(saved['version'], 2);
      expect((saved['layers'] as List).single['variantId'], 'protanomaly');
      expect(saved['strengthByKey'], {'protanopia': 0.4, 'protanomaly': 0.7});
      expect(await hasLegacyKey(), isFalse, reason: '書き込みに成功したので旧キーは消す');
    });

    test('(a) seedType が none なら層は作らず、記憶だけ取り込む', () async {
      SharedPreferences.setMockInitialValues({
        legacyKey: jsonEncode({'deuteranopia': 0.5}),
      });

      final result = await migrate();

      expect(result!.layers, isEmpty);
      expect(result.focusedId, isNull);
      expect(result.strengthByKey, {'deuteranopia': 0.5});
      expect((await _storedJson())!['strengthByKey'], {'deuteranopia': 0.5});
      expect(await hasLegacyKey(), isFalse);
    });

    test('(a) 版 1 がある: 版 1 の層・強度（-opia 4 種を除く）に旧強度を重ねる', () async {
      SharedPreferences.setMockInitialValues({
        VisionFilterStore.keySnapshot: jsonEncode({
          'version': 1,
          'selectedId': 'myopia',
          'filters': {
            'myopia': {'strength': 0.5},
            'protanopia': {'strength': 0.3}, // 持ち越さない
            'tetrachromacy': {'strength': 0.8},
          },
        }),
        legacyKey: jsonEncode({'protanopia': 0.9}),
      });

      // seedType があっても、版 1 に層があればそちらを優先する。
      final result = await migrate(seedType: ColorVisionType.tritanopia);

      expect([for (final l in result!.layers) l.id], ['myopia']);
      expect(result.layers.single.origin, VisionLayerOrigin.advanced);
      expect(result.strengthByKey,
          {'myopia': 0.5, 'tetrachromacy': 0.8, 'protanopia': 0.9});
      expect((await _storedJson())!['version'], 2);
      expect(await hasLegacyKey(), isFalse);
    });

    test('(a) 版 1 の色覚クイック選択は quick 層のまま取り込む', () async {
      SharedPreferences.setMockInitialValues({
        VisionFilterStore.keySnapshot: jsonEncode({
          'version': 1,
          'selectedId': 'tritanopia',
          'colorVisionType': 'tritanomaly',
          'filters': <String, Object?>{},
        }),
        legacyKey: jsonEncode({'tritanomaly': 0.45}),
      });

      final result = await migrate(seedType: ColorVisionType.protanopia);

      final layer = result!.layers.single;
      expect(layer.id, 'tritanopia');
      expect(layer.variantId, 'tritanomaly');
      expect(layer.origin, VisionLayerOrigin.quick);
      expect(result.strengthByKey, {'tritanomaly': 0.45});
    });

    test('(a) 版 1 に選択が無く強度だけあるなら、seedType の層は足さない（従来どおり未選択）', () async {
      SharedPreferences.setMockInitialValues({
        VisionFilterStore.keySnapshot: jsonEncode({
          'version': 1,
          'filters': {
            'myopia': {'strength': 0.5},
          },
        }),
        legacyKey: jsonEncode({'protanopia': 0.9}),
      });

      final result = await migrate(seedType: ColorVisionType.protanopia);

      expect(result!.layers, isEmpty);
      expect(result.strengthByKey, {'myopia': 0.5, 'protanopia': 0.9});
    });

    test('(a) 版 1 が -opia の強度だけなら、空とみなさず seedType の層は足さない', () async {
      SharedPreferences.setMockInitialValues({
        VisionFilterStore.keySnapshot: jsonEncode({
          'version': 1,
          'selectedId': null,
          'filters': {
            'protanopia': {'strength': 1.0},
          },
        }),
        legacyKey: jsonEncode({'protanopia': 0.4}),
      });

      final result = await migrate(seedType: ColorVisionType.protanopia);

      expect(result!.layers, isEmpty, reason: '旧実装は非空として復元し、未選択で始まった');
      expect(result.focusedId, isNull);
      expect(result.strengthByKey, {'protanopia': 0.4},
          reason: '版 1 の -opia 強度は持ち越さず、旧 per-type 強度だけが残る');
      final saved = (await _storedJson())!;
      expect(saved['version'], 2);
      expect(saved['layers'], isEmpty);
      expect(saved['strengthByKey'], {'protanopia': 0.4});
      expect(await hasLegacyKey(), isFalse);
    });

    test('(a) 版 1 が空（選択も記憶も無い）なら seedType の層を入れる', () async {
      SharedPreferences.setMockInitialValues({
        VisionFilterStore.keySnapshot: jsonEncode({
          'version': 1,
          'filters': <String, Object?>{},
        }),
        legacyKey: jsonEncode({'protanopia': 0.9}),
      });

      final result = await migrate(seedType: ColorVisionType.protanopia);

      expect([for (final l in result!.layers) l.id], ['protanopia']);
      expect(result.layers.single.origin, VisionLayerOrigin.quick);
      expect(result.strengthByKey, {'protanopia': 0.9});
    });

    test('(a) 保存が壊れている・未知の版でも、seedType の層と旧強度で作り直す', () async {
      for (final raw in [
        '{not json',
        jsonEncode({'version': 99, 'layers': []}),
        jsonEncode(['x']),
      ]) {
        SharedPreferences.setMockInitialValues({
          VisionFilterStore.keySnapshot: raw,
          legacyKey: jsonEncode({'achromatopsia': 0.2}),
        });

        final result = await migrate(seedType: ColorVisionType.achromatopsia);

        expect([for (final l in result!.layers) l.id], ['achromatopsia'],
            reason: 'raw=$raw');
        expect(result.strengthByKey, {'achromatopsia': 0.2},
            reason: 'raw=$raw');
        expect((await _storedJson())!['version'], 2, reason: 'raw=$raw');
        expect(await hasLegacyKey(), isFalse, reason: 'raw=$raw');
      }
    });

    test('(a) 旧強度は有効な色覚型名・有限の数値だけを 0..1 に丸めて取り込む', () async {
      SharedPreferences.setMockInitialValues({
        legacyKey: jsonEncode({
          'protanopia': 5,
          'deuteranopia': -1,
          'tritanopia': 'strong',
          'achromatopsia': null,
          'none': 0.5,
          'myopia': 0.5,
          'bogus': 0.5,
          'deuteranomaly': 0.25,
        }),
      });

      final result = await migrate();

      expect(result!.strengthByKey, {
        'protanopia': 1.0,
        'deuteranopia': 0.0,
        'deuteranomaly': 0.25,
      });
    });

    test('(a) 旧キーの JSON が壊れていても、旧キーを片付けて移行は完了する', () async {
      for (final raw in ['not json', '[1,2]', '"x"']) {
        SharedPreferences.setMockInitialValues({legacyKey: raw});

        final result = await migrate(seedType: ColorVisionType.protanopia);

        expect(result!.strengthByKey, isEmpty, reason: 'raw=$raw');
        expect([for (final l in result.layers) l.id], ['protanopia'],
            reason: 'raw=$raw');
        expect(await hasLegacyKey(), isFalse, reason: 'raw=$raw');
      }
    });

    test('(b) 読める v2 がある: v2 に無いキーだけ旧強度で補い、v2 の値・層を保つ', () async {
      SharedPreferences.setMockInitialValues({
        VisionFilterStore.keySnapshot: jsonEncode({
          'version': 2,
          'layers': [
            {
              'id': 'vertigo',
              'params': <String, Object?>{},
              'origin': 'advanced',
            },
          ],
          'focusedId': 'vertigo',
          'presetId': 'labyrinthitis',
          'strengthByKey': {'protanopia': 0.2},
          'paramsById': <String, Object?>{},
        }),
        legacyKey: jsonEncode({'protanopia': 0.9, 'deuteranopia': 0.4}),
      });

      final result = await migrate(seedType: ColorVisionType.tritanopia);

      expect(result!.strengthByKey, {'protanopia': 0.2, 'deuteranopia': 0.4});
      expect([for (final l in result.layers) l.id], ['vertigo'],
          reason: 'seedType の層は足さない');
      expect(result.focusedId, 'vertigo');
      expect(result.presetId, 'labyrinthitis');
      final saved = (await _storedJson())!;
      expect(saved['strengthByKey'], {'protanopia': 0.2, 'deuteranopia': 0.4});
      expect(saved['presetId'], 'labyrinthitis');
      expect(await hasLegacyKey(), isFalse);
    });

    test('(b) 層が空の v2 でも「読める v2」として扱う（seedType の層を足さない）', () async {
      SharedPreferences.setMockInitialValues({
        VisionFilterStore.keySnapshot: jsonEncode({
          'version': 2,
          'layers': <Object?>[],
          'strengthByKey': {'myopia': 0.5},
        }),
        legacyKey: jsonEncode({'protanopia': 0.9}),
      });

      final result = await migrate(seedType: ColorVisionType.protanopia);

      expect(result!.layers, isEmpty);
      expect(result.strengthByKey, {'myopia': 0.5, 'protanopia': 0.9});
    });

    test('移行は一度きり: 2 回目は (c) で何もしない', () async {
      SharedPreferences.setMockInitialValues({
        legacyKey: jsonEncode({'protanopia': 0.4}),
      });
      await migrate(seedType: ColorVisionType.protanopia);
      final afterFirst = (await SharedPreferences.getInstance())
          .getString(VisionFilterStore.keySnapshot);

      final second = await migrate(seedType: ColorVisionType.deuteranopia);

      expect(second, isNull);
      expect(
          (await SharedPreferences.getInstance())
              .getString(VisionFilterStore.keySnapshot),
          afterFirst);
    });

    test('取り込み → restoreAndBind(snapshot:) → 再起動で同じ状態に戻る', () async {
      SharedPreferences.setMockInitialValues({
        legacyKey: jsonEncode({'deuteranomaly': 0.35}),
      });
      final store = VisionFilterStore();
      final migrated = await store.migrateLegacyStrengths(
          seedType: ColorVisionType.deuteranomaly);

      final restored = await store.restoreAndBind(state, snapshot: migrated);

      expect(restored, isTrue);
      expect(state.colorVisionType, ColorVisionType.deuteranomaly);
      expect(state.strength, 0.35);

      final next = VisionFilterState();
      await VisionFilterStore().restoreAndBind(next);
      expect(next.colorVisionType, ColorVisionType.deuteranomaly);
      expect(next.strength, 0.35);
    });

    test('書き込みに失敗したら旧キーを残すが、取り込み結果はメモリへ反映される', () async {
      for (final mode in _WriteFailure.values) {
        final prefs = _MapPrefs(
          {
            VisionFilterStore.keySnapshot: jsonEncode({
              'version': 1,
              'selectedId': 'myopia',
              'filters': {
                'myopia': {'strength': 0.5},
              },
            }),
            legacyKey: jsonEncode({'protanopia': 0.9}),
          },
          failure: mode,
        );
        final store = VisionFilterStore(prefs: prefs);

        final migrated = await store.migrateLegacyStrengths(
            seedType: ColorVisionType.protanopia);

        expect(prefs.data.containsKey(legacyKey), isTrue,
            reason: '$mode: 書けなかったので次回起動でもう一度取り込む');
        expect(
            jsonDecode(prefs.data[VisionFilterStore.keySnapshot]! as String)[
                'version'],
            1,
            reason: '$mode: 保存は元のまま');
        expect(migrated!.strengthByKey, {'myopia': 0.5, 'protanopia': 0.9});

        // restoreAndBind は保存（版 1）を読み直さず、取り込み結果を復元する。
        final s = VisionFilterState()..select('hyperopia');
        final restored = await store.restoreAndBind(s, snapshot: migrated);
        expect(restored, isTrue, reason: '$mode');
        expect(s.selectedId, 'myopia', reason: '$mode');
        expect(s.strengthForKey('protanopia'), 0.9, reason: '$mode');
        expect(s.strengthForKey('myopia'), 0.5, reason: '$mode');
      }
    });

    test('取り込み結果が空（層も記憶も無い）でも旧キーは消え、空の v2 が保存される', () async {
      SharedPreferences.setMockInitialValues({legacyKey: jsonEncode({})});
      final store = VisionFilterStore();

      final migrated =
          await store.migrateLegacyStrengths(seedType: ColorVisionType.none);

      expect(migrated!.isEmpty, isTrue);
      expect(migrated.layers, isEmpty);
      expect((await _storedJson())!['version'], 2);
      expect(
          await SharedPreferences.getInstance()
              .then((p) => p.containsKey(legacyKey)),
          isFalse);
    });
  });
}

/// setString を外から解放するまで完了させない SharedPreferences（書き込み中の
/// 状態を作るための差し替え）。使うのは getString / setString だけ。
class _GatedPrefs implements SharedPreferences {
  final Completer<void> writeStarted = Completer<void>();
  final Completer<void> _release = Completer<void>();
  String? written;

  void releaseWrite() => _release.complete();

  @override
  String? getString(String key) => null;

  @override
  Future<bool> setString(String key, String value) async {
    if (!writeStarted.isCompleted) writeStarted.complete();
    await _release.future;
    written = value;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

enum _WriteFailure { returnsFalse, throwsError }

/// メモリ上の SharedPreferences（書き込み失敗を作るための差し替え）。使うのは
/// getString / setString / remove / containsKey だけ。
class _MapPrefs implements SharedPreferences {
  _MapPrefs(this.data, {required this.failure});

  final Map<String, Object> data;
  final _WriteFailure failure;

  @override
  String? getString(String key) => data[key] as String?;

  @override
  bool containsKey(String key) => data.containsKey(key);

  @override
  Future<bool> remove(String key) async {
    data.remove(key);
    return true;
  }

  @override
  Future<bool> setString(String key, String value) async {
    switch (failure) {
      case _WriteFailure.returnsFalse:
        return false;
      case _WriteFailure.throwsError:
        throw StateError('disk full');
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
