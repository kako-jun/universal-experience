// VisionFilterState.snapshot()/restore() と VisionFilterStore（#65）のテスト。
//
// - 選択（advanced / 体験プリセット / 色覚クイック選択）・強度・payload が
//   snapshot → JSON → restore で戻る。
// - 復元できない選択（未知 id・無効なプリセット・色覚型とカタログ id の不一致）は
//   安全側に倒れ、起動を止めない。
// - store: 変更は flush で書かれ、壊れた JSON・未知の版は無視して state を
//   触らない。
//
// urgency/推奨強度は sensus ブリッジを要求するためフィクスチャに差し替える。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/services/vision_filter_metadata.dart';
import 'package:universal_experience/services/vision_filter_snapshot.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/services/vision_filter_store.dart';

import 'support/vision_filter_metadata_fixture.dart';

/// 保存 → 読み込みを実際の JSON 文字列越しに行う（state の写しが in-memory の
/// 参照共有で通ってしまわないように）。
VisionFilterSnapshot _viaJson(VisionFilterSnapshot s) =>
    VisionFilterSnapshot.fromJson(jsonDecode(jsonEncode(s.toJson())))!;

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

    test('色覚クイック選択: -omaly の型も含めて起源が戻る', () {
      final a = VisionFilterState()
        ..selectColorVisionType(ColorVisionType.protanomaly, 'protanopia');

      final b = VisionFilterState()..restore(_viaJson(a.snapshot()));

      expect(b.selectedId, 'protanopia');
      expect(b.isColorQuickSelection, isTrue);
      expect(b.colorVisionType, ColorVisionType.protanomaly);
    });

    test('色覚型と選択 id が食い違う保存値は色覚クイック選択にしない', () {
      const mismatched = VisionFilterSnapshot(
        selectedId: 'myopia',
        colorVisionType: ColorVisionType.protanopia,
      );

      final s = VisionFilterState()..restore(mismatched);

      expect(s.selectedId, 'myopia');
      expect(s.isColorQuickSelection, isFalse);
      expect(s.colorVisionType, isNull);
    });

    test('未選択の snapshot は選択を解除する', () {
      final s = VisionFilterState()..select('myopia');

      s.restore(const VisionFilterSnapshot());

      expect(s.selectedId, isNull);
      expect(s.build(), isNull);
    });

    test('カタログに無い id の snapshot（手組み）でも例外を出さず未選択にする', () {
      final s = VisionFilterState()..select('myopia');

      s.restore(const VisionFilterSnapshot(selectedId: 'removed_in_sensus'));

      expect(s.selectedId, isNull);
    });

    test('選択中フィルタの強度の記憶が無ければ推奨強度で初期化する', () {
      visionFilterRecommendedStrengthProvider = (_) => 0.6;

      final s = VisionFilterState()
        ..restore(const VisionFilterSnapshot(selectedId: 'myopia'));

      expect(s.strength, 0.6);
    });

    test('復元は記憶を置き換える（復元前の記憶は残らない）', () {
      final s = VisionFilterState()
        ..select('astigmatism')
        ..setParam('axisDeg', 10.0);

      s.restore(const VisionFilterSnapshot(selectedId: 'myopia'));
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

      s.restore(const VisionFilterSnapshot(selectedId: 'myopia'));

      expect(notified, 1);
    });
  });

  group('VisionFilterStore', () {
    late VisionFilterState state;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      state = VisionFilterState();
    });

    Future<Map<String, Object?>?> storedJson() async {
      final raw = (await SharedPreferences.getInstance())
          .getString(VisionFilterStore.keySnapshot);
      return raw == null ? null : jsonDecode(raw) as Map<String, Object?>;
    }

    test('変更は flush で書かれ、別の store が読んで復元できる', () async {
      final store = VisionFilterStore();
      await store.restoreAndBind(state);
      state
        ..select('starbursts')
        ..setStrength(0.4)
        ..setParam('numRays', 9);
      await store.flush();

      final saved = await storedJson();
      expect(saved!['version'], kVisionFilterSnapshotVersion);
      expect(saved['selectedId'], 'starbursts');

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
      expect(await storedJson(), isNull, reason: 'まだデバウンス中');

      await Future<void>.delayed(const Duration(milliseconds: 200));
      final saved = await storedJson();
      expect(saved!['selectedId'], 'starbursts');
      expect(
        ((saved['filters'] as Map)['starbursts'] as Map)['strength'],
        0.2,
      );
    });

    test('保留が無ければ flush は何もしない', () async {
      final store = VisionFilterStore();
      await store.restoreAndBind(state);

      await store.flush();

      expect(await storedJson(), isNull);
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

      expect(await storedJson(), isNull);
    });

    test('保存が無ければ復元せず state は触らない（購読は張る）', () async {
      state.select('myopia');
      final store = VisionFilterStore();

      final restored = await store.restoreAndBind(state);

      expect(restored, isFalse);
      expect(state.selectedId, 'myopia');
      state.setStrength(0.5);
      await store.flush();
      expect((await storedJson())!['selectedId'], 'myopia');
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
          'selectedId': 'removed_in_sensus',
          'filters': {
            'removed_in_sensus': {'strength': 0.4},
            'myopia': {'strength': 0.7},
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
          'selectedId': 'starbursts',
          'filters': {
            'starbursts': {
              'strength': 3,
              'params': {'numRays': 9999, 'rayLengthRatio': -4},
            },
          },
        }),
      });

      await VisionFilterStore().restoreAndBind(state);

      expect(state.strength, 1.0);
      expect(state.params['numRays'], 24);
      expect(state.params['rayLengthRatio'], 0.0);
      expect(state.build(), isNotNull);
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

      expect(jsonDecode(afterDispose!)['selectedId'], 'myopia');
      expect(prefs.getString(VisionFilterStore.keySnapshot), afterDispose);
    });
  });
}
