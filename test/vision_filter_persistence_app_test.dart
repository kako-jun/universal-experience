// フィルタ選択・payload・強度の永続化（#65）を、実アプリの起動経路
// （main.dart の buildRootApp）で確かめるテスト。
//
// 1 回目の起動で選ぶ → 終了（store.flush）→ 共有シングルトンを初期状態に戻す →
// 2 回目の起動（新しい store・新しい SettingsService、SharedPreferences は同じ）
// で、選んだものがそのまま画面に出ることを確認する。原画像・トレイ・ウィンドウは
// このテストの対象外（main() 側に閉じている）。
//
// buildRootApp は main.dart の共有トップレベル singleton
// （filterService / visionFilterState / imageSourceState）を直接動かすため、
// 各テストの後に初期状態へ戻す（test/first_run_seed_test.dart と同じ作法）。

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/l10n/l10n_extensions.dart';
import 'package:universal_experience/main.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/models/sample_catalog.dart';
import 'package:universal_experience/services/color_vision_selection.dart';
import 'package:universal_experience/services/settings_service.dart';
import 'package:universal_experience/services/vision_filter_snapshot.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/services/vision_filter_store.dart';
import 'package:universal_experience/ui/screens/home_screen.dart';
import 'package:universal_experience/ui/widgets/adjust_panel.dart';
import 'package:universal_experience/ui/widgets/experience_presets.dart';

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
  filterService.deactivate();
  visionFilterState.restore(const VisionFilterSnapshot());
  imageSourceState.resetToRecommended(kDefaultSampleId);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installHomeScreenFixtures);
  tearDown(() {
    resetHomeScreenFixtures();
    filterService.deactivate();
    visionFilterState.restore(const VisionFilterSnapshot());
    imageSourceState.resetToRecommended(kDefaultSampleId);
  });

  testWidgets('advanced フィルタ・強度・payload が再起動後の画面に戻る', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final first = await _launch();
    visionFilterState
      ..select('starbursts')
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
    expect(visionFilterState.isColorQuickSelection, isFalse,
        reason: '設定側の色覚シードではなく保存された advanced が勝つ');
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

  testWidgets('色覚クイック選択（-omaly）は FilterService とともに戻る', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final first = await _launch();
    selectColorVision(
        filterService, visionFilterState, ColorVisionType.tritanomaly);
    await first.store.flush();
    await _quitAndResetSingletons(first.store);

    final second = await _launch();
    addTearDown(() => _quitAndResetSingletons(second.store));
    await tester.pumpWidget(second.app);
    await tester.pump();

    expect(visionFilterState.isColorQuickSelection, isTrue);
    expect(visionFilterState.colorVisionType, ColorVisionType.tritanomaly);
    expect(filterService.currentFilter, ColorVisionType.tritanomaly,
        reason: 'トレイもウィンドウ内 UI も同じ filterService を見る');
  });

  testWidgets('選択を解除して終了したなら、設定側の色覚シードより「未選択」が優先される', (tester) async {
    // 設定（settings.filterType）には前回の色覚が残っているが、その後に解除して
    // 終了した、という状況（設定の書き込みは画面側のリスナ経由のため、ここでは
    // 画面を出さずに再現する）。
    SharedPreferences.setMockInitialValues({
      SettingsService.keyFilterType: ColorVisionType.protanopia.name,
    });
    final first = await _launch();
    visionFilterState.select('myopia');
    deactivateColorVision(filterService, visionFilterState);
    expect(visionFilterState.selectedId, isNull);
    await first.store.flush();
    await _quitAndResetSingletons(first.store);

    final second = await _launch();
    addTearDown(() => _quitAndResetSingletons(second.store));
    await tester.pumpWidget(second.app);
    await tester.pump();

    expect(visionFilterState.selectedId, isNull);
    expect(visionFilterState.isColorQuickSelection, isFalse);
  });

  testWidgets('旧 settings.intensityByType は起動時に v2 へ取り込まれ、強度が画面側に出る（#117）',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      SettingsService.keyFilterType: ColorVisionType.protanomaly.name,
      VisionFilterStore.keyIntensityByType:
          jsonEncode({'protanomaly': 0.35, 'deuteranopia': 0.8}),
    });

    final first = await _launch();
    addTearDown(() => _quitAndResetSingletons(first.store));
    await tester.pumpWidget(first.app);
    await tester.pump();

    expect(filterService.currentFilter, ColorVisionType.protanomaly);
    expect(filterService.intensity, 0.35);
    expect(visionFilterState.colorVisionType, ColorVisionType.protanomaly);
    expect(visionFilterState.strength, 0.35);
    expect(visionFilterState.strengthForKey('deuteranopia'), 0.8);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(VisionFilterStore.keyIntensityByType), isFalse,
        reason: '取り込み後に旧キーは消える');
    final saved = jsonDecode((await _stored())!) as Map<String, Object?>;
    expect(saved['version'], 2);
    expect(saved['strengthByKey'], {'protanomaly': 0.35, 'deuteranopia': 0.8});
  });

  testWidgets('取り込みの後の再起動では、取り込み済みの v2 がそのまま戻る（#117）', (tester) async {
    SharedPreferences.setMockInitialValues({
      SettingsService.keyFilterType: ColorVisionType.protanopia.name,
      VisionFilterStore.keyIntensityByType: jsonEncode({'protanopia': 0.4}),
    });
    final first = await _launch();
    await _quitAndResetSingletons(first.store);

    final second = await _launch();
    addTearDown(() => _quitAndResetSingletons(second.store));
    await tester.pumpWidget(second.app);
    await tester.pump();

    expect(visionFilterState.colorVisionType, ColorVisionType.protanopia);
    expect(filterService.intensity, 0.4);
    expect(visionFilterState.strength, 0.4);
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

  testWidgets('復元中に sensus 呼び出しが例外を投げても起動し、色覚シードで始まる', (_) async {
    // 保存はプリセット選択。プリセットの有効性確認（体験一覧の取得）が失敗する。
    final saved = VisionFilterState()..selectPreset('labyrinthitis', 'vertigo');
    SharedPreferences.setMockInitialValues({
      SettingsService.keyFilterType: ColorVisionType.protanopia.name,
      VisionFilterStore.keySnapshot: jsonEncode(saved.snapshot().toJson()),
    });
    experiencesProvider = () => throw StateError('sensus failed');

    final launched = await _launch();
    addTearDown(() => _quitAndResetSingletons(launched.store));

    // buildRootApp が例外で落ちないこと（体験一覧の取得は画面側でも使うため、
    // 一覧が壊れたままの画面は出さず、起動処理だけを検証する）。
    expect(visionFilterState.colorVisionType, ColorVisionType.protanopia);
    expect(visionFilterState.selectedPresetId, isNull);
  });

  testWidgets('壊れた保存値でもアプリは起動し、設定の色覚シードで始まる', (tester) async {
    SharedPreferences.setMockInitialValues({
      SettingsService.keyFilterType: ColorVisionType.protanopia.name,
      VisionFilterStore.keySnapshot: '{"version":1,"selectedId":',
    });

    final launched = await _launch();
    addTearDown(() => _quitAndResetSingletons(launched.store));
    await tester.pumpWidget(launched.app);
    await tester.pump();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(visionFilterState.colorVisionType, ColorVisionType.protanopia);
    expect(await _stored(), '{"version":1,"selectedId":',
        reason: '起動しただけでは（変更が無いので）壊れた値を上書きしない');
  });

  testWidgets('保存に sensus に無いフィルタ id・範囲外の値が混ざっていても起動する', (tester) async {
    SharedPreferences.setMockInitialValues({
      SettingsService.keyFilterType: ColorVisionType.none.name,
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
