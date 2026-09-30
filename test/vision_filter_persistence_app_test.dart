// フィルタ選択・payload・強度の永続化（#65）を、実アプリの起動経路
// （main.dart の buildRootApp）で確かめるテスト。
//
// 1 回目の起動で選ぶ → 終了（store.flush）→ 共有シングルトンを初期状態に戻す →
// 2 回目の起動（新しい store・新しい SettingsService、SharedPreferences は同じ）
// で、選んだものがそのまま画面に出ることを確認する。原画像・トレイ・ウィンドウは
// このテストの対象外（main() 側に閉じている）。
//
// buildRootApp は main.dart の共有トップレベル singleton
// （visionFilterState / imageSourceState）を直接動かすため、
// 各テストの後に初期状態へ戻す（test/first_run_seed_test.dart と同じ作法）。

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/l10n/l10n_extensions.dart';
import 'package:universal_experience/main.dart';
import 'package:universal_experience/models/sample_catalog.dart';
import 'package:universal_experience/models/vision_filter_catalog.dart'
    show isColorVisionQuickKey;
import 'package:universal_experience/services/settings_service.dart';
import 'package:universal_experience/services/vision_filter_snapshot.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/services/vision_filter_store.dart';
import 'package:universal_experience/ui/screens/home_screen.dart';
import 'package:universal_experience/ui/widgets/adjust_panel.dart';
import 'package:universal_experience/ui/widgets/experience_presets.dart';

import 'support/color_vision_select.dart';
import 'support/home_screen_harness.dart';

/// 保存されている JSON を 1 つの文字列として読む。
Future<String?> _stored() async => (await SharedPreferences.getInstance())
    .getString(VisionFilterStore.keySnapshot);

/// アプリを起動する（新しい store・新しい SettingsService）。
Future<({Widget app, VisionFilterStore store})> _launch() async {
  final store = VisionFilterStore();
  final result = await buildRootApp(
    initBridge: () async => true,
    settings: SettingsService(),
    store: store,
  );
  return (app: result.app, store: store);
}

/// 終了 → 共有シングルトンを再起動直後の空の状態へ戻す。
Future<void> _quitAndResetSingletons(VisionFilterStore store) async {
  await store.dispose();
  visionFilterState.restore(const VisionFilterSnapshot());
  imageSourceState.resetToRecommended(kDefaultSampleId);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installHomeScreenFixtures);
  tearDown(() {
    resetHomeScreenFixtures();
    visionFilterState.restore(const VisionFilterSnapshot());
    imageSourceState.resetToRecommended(kDefaultSampleId);
  });


  testWidgets('advanced フィルタ・強度・payload が再起動後の画面に戻る', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final first = await _launch();
    visionFilterState
      ..replaceWith('starbursts')
      ..setStrength(0.35)
      ..setParam('numRays', 12);
    await first.store.flush();
    await _quitAndResetSingletons(first.store);
    expect(visionFilterState.selectedId, isNull,
        reason: '再起動直後の空状態（この前提が崩れると復元の検証にならない）');

    final second = await _launch();
    addTearDown(() => _quitAndResetSingletons(second.store));
    await tester.pumpWidget(second.app);
    await tester.pump();

    expect(visionFilterState.selectedId, 'starbursts');
    expect(visionFilterState.strength, 0.35);
    expect(visionFilterState.params['numRays'], 12);
    expect(visionFilterState.layers.map((l) => l.id), ['starbursts'],
        reason: '初回起動の層（deuteranomaly）ではなく保存された選択が勝つ');
    expect(visionFilterState.focusedVariantId, isNull);
    final l10n = AppLocalizations.of(tester.element(find.byType(HomeScreen)))!;
    expect(
      find.descendant(
        of: find.byType(AdjustPanel),
        matching: find.text(visionFilterName(l10n, 'starbursts')),
      ),
      findsWidgets,
    );
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('色覚（-omaly）は別名つきの層・強度のまま再起動後に戻る', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final first = await _launch();
    selectColorVisionKey(visionFilterState, 'tritanomaly');
    visionFilterState.setStrength(0.45);
    await first.store.flush();
    await _quitAndResetSingletons(first.store);

    final second = await _launch();
    addTearDown(() => _quitAndResetSingletons(second.store));
    await tester.pumpWidget(second.app);
    await tester.pump();

    expect(visionFilterState.selectedId, 'tritanopia');
    expect(visionFilterState.focusedVariantId, 'tritanomaly');
    expect(visionFilterState.strength, 0.45);
    expect(visionFilterState.strengthForKey('tritanomaly'), 0.45);
    expect(visionFilterState.strengthForKey('tritanopia'), isNull,
        reason: '別名の強度は -opia の記憶と混ざらない');
  });

  testWidgets('フォーカスが色覚以外でも、復元した層の集合に色覚（別名つき）の層が残る（#120）',
      (tester) async {
    // 旧キー（settings.filterType = protanopia）は 1 回目の起動で v2 へ取り込まれ、
    // その後に選んだ層（[deuteranomaly, myopia]・フォーカスは myopia）が保存される。
    SharedPreferences.setMockInitialValues({
      VisionFilterStore.keyLegacyFilterType: 'protanopia',
    });
    final first = await _launch();
    expect(visionFilterState.selectedId, 'protanopia',
        reason: '旧キーを取り込んだ起動直後の層');
    visionFilterState.toggle('deuteranopia', variantId: 'deuteranomaly');
    visionFilterState.toggle('myopia');
    visionFilterState.focusLayer('myopia');
    expect(visionFilterState.focusedVariantId, isNull,
        reason: 'フォーカス層は色覚ではない');
    await first.store.flush();
    await _quitAndResetSingletons(first.store);

    final second = await _launch();
    addTearDown(() => _quitAndResetSingletons(second.store));
    await tester.pumpWidget(second.app);
    await tester.pump();

    expect(visionFilterState.focusedId, 'myopia');
    expect({for (final l in visionFilterState.layers) l.id: l.variantId}, {
      'deuteranopia': 'deuteranomaly',
      'myopia': null,
    }, reason: '旧キー（protanopia）でもフォーカス層でもなく、保存された層の集合が戻る');
  });

  testWidgets('色覚の層を外して終了したなら、旧キー由来の色覚は戻らない（#120）', (tester) async {
    SharedPreferences.setMockInitialValues({
      VisionFilterStore.keyLegacyFilterType: 'protanopia',
    });
    final first = await _launch();
    visionFilterState.replaceWith('myopia');
    await first.store.flush();
    await _quitAndResetSingletons(first.store);

    final second = await _launch();
    addTearDown(() => _quitAndResetSingletons(second.store));
    await tester.pumpWidget(second.app);
    await tester.pump();

    expect(visionFilterState.layers.map((l) => l.id), ['myopia']);
    expect(
      visionFilterState.layers.any((l) => isColorVisionQuickKey(l.strengthKey)),
      isFalse,
      reason: '旧キー（protanopia）が残って色覚の層が復活してはならない',
    );
  });

  testWidgets('選択を解除して終了したなら、旧キーの色覚より「未選択」が優先される', (tester) async {
    // 旧キー（settings.filterType）には前回の色覚が残っているが、1 回目の起動で v2 へ
    // 取り込まれたあとに解除して終了した、という状況。
    SharedPreferences.setMockInitialValues({
      VisionFilterStore.keyLegacyFilterType: 'protanopia',
    });
    final first = await _launch();
    visionFilterState.replaceWith('myopia');
    visionFilterState.clear();
    expect(visionFilterState.selectedId, isNull);
    await first.store.flush();
    await _quitAndResetSingletons(first.store);

    final second = await _launch();
    addTearDown(() => _quitAndResetSingletons(second.store));
    await tester.pumpWidget(second.app);
    await tester.pump();

    expect(visionFilterState.selectedId, isNull);
    expect(visionFilterState.layers, isEmpty,
        reason: '空の v2 は初回起動の層（deuteranomaly）でも旧キーでも上書きされない');
  });

  group('旧い保存の取り込み（#117, #124）', () {
    testWidgets('旧 settings.filterType だけが保存されていても、同じ選択・強度で復元される', (tester) async {
      const cases = <String, (String id, String? variantId, double strength)>{
        'protanopia': ('protanopia', null, 1.0),
        'deuteranopia': ('deuteranopia', null, 1.0),
        'tritanopia': ('tritanopia', null, 1.0),
        'achromatopsia': ('achromatopsia', null, 1.0),
        'protanomaly': ('protanopia', 'protanomaly', 0.6),
        'deuteranomaly': ('deuteranopia', 'deuteranomaly', 0.6),
        'tritanomaly': ('tritanopia', 'tritanomaly', 0.6),
      };
      for (final e in cases.entries) {
        SharedPreferences.setMockInitialValues({
          VisionFilterStore.keyLegacyFilterType: e.key,
        });
        final launched = await _launch();
        if (e == cases.entries.first) {
          await tester.pumpWidget(launched.app);
          await tester.pump();
        }

        final (id, variantId, strength) = e.value;
        expect(visionFilterState.layers, hasLength(1), reason: e.key);
        expect(visionFilterState.selectedId, id, reason: e.key);
        expect(visionFilterState.focusedVariantId, variantId, reason: e.key);
        expect(visionFilterState.strength, strength, reason: e.key);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey(VisionFilterStore.keyLegacyFilterType), isFalse,
            reason: '${e.key}: 取り込み後に旧キーは消える');
        final saved = jsonDecode((await _stored())!) as Map<String, Object?>;
        expect(saved['version'], 2, reason: e.key);
        final layer = (saved['layers'] as List).single as Map;
        expect(layer['id'], id, reason: e.key);
        expect(layer['variantId'], variantId, reason: e.key);

        await _quitAndResetSingletons(launched.store);
      }
    });

    testWidgets('旧 settings.filterType が none なら未選択で復元され、旧キーは消える', (tester) async {
      SharedPreferences.setMockInitialValues({
        VisionFilterStore.keyLegacyFilterType: 'none',
      });

      final launched = await _launch();
      addTearDown(() => _quitAndResetSingletons(launched.store));
      await tester.pumpWidget(launched.app);
      await tester.pump();

      expect(visionFilterState.layers, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(VisionFilterStore.keyLegacyFilterType), isFalse);
      final saved = jsonDecode((await _stored())!) as Map<String, Object?>;
      expect(saved['version'], 2);
      expect(saved['layers'], isEmpty);
    });

    testWidgets('版 1 の settings.visionFilter だけが保存されていても、同じ選択・強度・payload で復元される',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        VisionFilterStore.keySnapshot: jsonEncode({
          'version': 1,
          'selectedId': 'starbursts',
          'presetId': null,
          'colorVisionType': null,
          'filters': {
            'starbursts': {
              'strength': 0.35,
              'params': {'numRays': 12},
            },
          },
        }),
      });

      final launched = await _launch();
      addTearDown(() => _quitAndResetSingletons(launched.store));
      await tester.pumpWidget(launched.app);
      await tester.pump();

      expect(visionFilterState.layers.map((l) => l.id), ['starbursts']);
      expect(visionFilterState.focusedVariantId, isNull);
      expect(visionFilterState.strength, 0.35);
      expect(visionFilterState.params['numRays'], 12);

      final saved = jsonDecode((await _stored())!) as Map<String, Object?>;
      expect(saved['version'], 2, reason: '取り込み後は v2 として書き戻される');
      expect(saved.containsKey('selectedId'), isFalse,
          reason: '版 1 の形（selectedId / filters）は残らない');
      expect(saved['strengthByKey'], {'starbursts': 0.35});
    });

    testWidgets('版 1 の色覚（-omaly）は、旧 settings.intensityByType の強度を重ねて復元され、旧キーは消える',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        VisionFilterStore.keySnapshot: jsonEncode({
          'version': 1,
          'selectedId': 'deuteranopia',
          'presetId': null,
          'colorVisionType': 'deuteranomaly',
          'filters': {
            'deuteranopia': {'strength': 0.9},
          },
        }),
        VisionFilterStore.keyLegacyFilterType: 'deuteranomaly',
        VisionFilterStore.keyIntensityByType: jsonEncode({'deuteranomaly': 0.4}),
      });

      final launched = await _launch();
      addTearDown(() => _quitAndResetSingletons(launched.store));
      await tester.pumpWidget(launched.app);
      await tester.pump();

      expect(visionFilterState.selectedId, 'deuteranopia');
      expect(visionFilterState.focusedVariantId, 'deuteranomaly');
      expect(visionFilterState.strength, 0.4,
          reason: '色覚の強度の正本は旧 per-type 強度（版 1 の強度 0.9 は持ち越さない）');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(VisionFilterStore.keyLegacyFilterType), isFalse);
      expect(prefs.containsKey(VisionFilterStore.keyIntensityByType), isFalse);
      final saved = jsonDecode((await _stored())!) as Map<String, Object?>;
      expect(saved['version'], 2);
      expect(saved.containsKey('selectedId'), isFalse);
    });

    testWidgets('旧 settings.intensityByType は起動時に v2 へ取り込まれ、強度が画面側に出る（#117）',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        VisionFilterStore.keyLegacyFilterType: 'protanomaly',
        VisionFilterStore.keyIntensityByType:
            jsonEncode({'protanomaly': 0.35, 'deuteranopia': 0.8}),
      });

      final first = await _launch();
      addTearDown(() => _quitAndResetSingletons(first.store));
      await tester.pumpWidget(first.app);
      await tester.pump();

      expect(visionFilterState.selectedId, 'protanopia');
      expect(visionFilterState.focusedVariantId, 'protanomaly');
      expect(visionFilterState.strength, 0.35);
      expect(visionFilterState.strengthForKey('deuteranopia'), 0.8);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(VisionFilterStore.keyIntensityByType), isFalse,
          reason: '取り込み後に旧キーは消える');
      expect(prefs.containsKey(VisionFilterStore.keyLegacyFilterType), isFalse,
          reason: '取り込み後に旧キーは消える');
      final saved = jsonDecode((await _stored())!) as Map<String, Object?>;
      expect(saved['version'], 2);
      expect(
          saved['strengthByKey'], {'protanomaly': 0.35, 'deuteranopia': 0.8});
    });

    testWidgets('取り込みの後の再起動では、取り込み済みの v2 がそのまま戻る（#117）', (tester) async {
      SharedPreferences.setMockInitialValues({
        VisionFilterStore.keyLegacyFilterType: 'protanopia',
        VisionFilterStore.keyIntensityByType: jsonEncode({'protanopia': 0.4}),
      });
      final first = await _launch();
      await _quitAndResetSingletons(first.store);

      final second = await _launch();
      addTearDown(() => _quitAndResetSingletons(second.store));
      await tester.pumpWidget(second.app);
      await tester.pump();

      expect(visionFilterState.selectedId, 'protanopia');
      expect(visionFilterState.focusedVariantId, isNull);
      expect(visionFilterState.strength, 0.4);
    });

    testWidgets('旧単一キー settings.intensity は値を見ずに消される', (tester) async {
      SharedPreferences.setMockInitialValues({
        VisionFilterStore.legacyIntensityKey: 0.2,
      });

      final launched = await _launch();
      addTearDown(() => _quitAndResetSingletons(launched.store));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(VisionFilterStore.legacyIntensityKey), isFalse);
      expect(visionFilterState.strength, 0.6,
          reason: '値は取り込まない（初回起動の層の推奨強度のまま）');
    });
  });

  testWidgets('体験プリセットは今も有効なときだけプリセット選択として戻る', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final first = await _launch();
    visionFilterState.selectPreset('labyrinthitis', 'vertigo');
    await first.store.flush();
    await _quitAndResetSingletons(first.store);

    final second = await _launch();
    addTearDown(() => _quitAndResetSingletons(second.store));
    await tester.pumpWidget(second.app);
    await tester.pump();

    expect(visionFilterState.selectedId, 'vertigo');
    expect(visionFilterState.selectedPresetId, 'labyrinthitis');
    await _quitAndResetSingletons(second.store);

    // sensus の体験一覧から labyrinthitis が消えた場合は、advanced の
    // vertigo 選択として戻る（プリセットの点灯だけが外れる）。
    experiencesProvider = () =>
        fixtureExperiences().where((e) => e.id != 'labyrinthitis').toList();
    final third = await _launch();
    addTearDown(() => _quitAndResetSingletons(third.store));
    expect(visionFilterState.selectedId, 'vertigo');
    expect(visionFilterState.selectedPresetId, isNull);
  });

  testWidgets('復元中に sensus 呼び出しが例外を投げても起動し、初回起動の層で始まる', (_) async {
    // 保存はプリセット選択。プリセットの有効性確認（体験一覧の取得）が失敗する。
    final saved = VisionFilterState()..selectPreset('labyrinthitis', 'vertigo');
    SharedPreferences.setMockInitialValues({
      VisionFilterStore.keySnapshot: jsonEncode(saved.snapshot().toJson()),
    });
    experiencesProvider = () => throw StateError('sensus failed');

    final launched = await _launch();
    addTearDown(() => _quitAndResetSingletons(launched.store));

    // buildRootApp が例外で落ちないこと（体験一覧の取得は画面側でも使うため、
    // 一覧が壊れたままの画面は出さず、起動処理だけを検証する）。復元は巻き戻され、
    // 先に入れた初回起動の層（deuteranomaly）のまま起動する。
    expect(visionFilterState.selectedId, 'deuteranopia');
    expect(visionFilterState.focusedVariantId, 'deuteranomaly');
    expect(visionFilterState.selectedPresetId, isNull);
  });

  testWidgets('壊れた保存値でもアプリは起動し、初回起動の層で始まる（壊れた値は上書きしない）',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      VisionFilterStore.keySnapshot: '{"version":1,"selectedId":',
    });

    final launched = await _launch();
    addTearDown(() => _quitAndResetSingletons(launched.store));
    await tester.pumpWidget(launched.app);
    await tester.pump();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(visionFilterState.selectedId, 'deuteranopia');
    expect(visionFilterState.focusedVariantId, 'deuteranomaly');
    expect(await _stored(), '{"version":1,"selectedId":',
        reason: '旧キーが無く、起動しただけでは（変更が無いので）壊れた値を上書きしない');
  });

  testWidgets('壊れた保存値と旧 settings.filterType が並んでいたら、旧キーの色覚で始まり v2 に直る',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      VisionFilterStore.keyLegacyFilterType: 'protanopia',
      VisionFilterStore.keySnapshot: '{"version":1,"selectedId":',
    });

    final launched = await _launch();
    addTearDown(() => _quitAndResetSingletons(launched.store));
    await tester.pumpWidget(launched.app);
    await tester.pump();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(visionFilterState.selectedId, 'protanopia');
    expect(visionFilterState.focusedVariantId, isNull);
    final saved = jsonDecode((await _stored())!) as Map<String, Object?>;
    expect(saved['version'], 2, reason: '旧キーを取り込んだ結果が v2 として壊れた値の代わりに保存される');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(VisionFilterStore.keyLegacyFilterType), isFalse);
  });

  testWidgets('保存に sensus に無いフィルタ id・範囲外の値が混ざっていても起動する', (tester) async {
    // 版 1 の保存は、旧 settings.filterType（none）より優先して取り込まれる。
    SharedPreferences.setMockInitialValues({
      VisionFilterStore.keyLegacyFilterType: 'none',
      VisionFilterStore.keySnapshot: '''
{"version":1,"selectedId":"starbursts","presetId":null,"colorVisionType":null,
 "filters":{
  "starbursts":{"strength":9,"params":{"numRays":-3,"gone":1}},
  "removed_in_sensus":{"strength":0.5}
 }}''',
    });

    final launched = await _launch();
    addTearDown(() => _quitAndResetSingletons(launched.store));
    await tester.pumpWidget(launched.app);
    await tester.pump();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(visionFilterState.selectedId, 'starbursts');
    expect(visionFilterState.strength, 1.0);
    expect(visionFilterState.params['numRays'], 2);
    expect(visionFilterState.params.containsKey('gone'), isFalse);
    expect(visionFilterState.build(), isNotNull);
  });
}
