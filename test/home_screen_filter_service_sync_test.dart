// 画面の足し引き・プリセット選択のあとで FilterService（settings.filterType・トレイの
// 読み口）が層の集合から導かれること（#120）。
//
// 層の集合が変わったのに `settings.filterType` に「いまは無い色覚」が残ると、次の起動の
// 色覚シードやトレイの表示がずれる。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/services/color_vision_selection.dart';

import 'support/home_screen_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installHomeScreenFixtures);
  tearDown(resetHomeScreenFixtures);

  const wide = Size(1280, 800);

  testWidgets('体験プリセットを選ぶと、色覚の層が無くなり settings.filterType も none になる',
      (tester) async {
    final h = await pumpHomeScreen(tester, size: wide);
    // 画面が組まれたあとの操作として選ぶ（永続化の listener は組んだ後の通知で動く）。
    selectColorVision(
        h.filterService, h.visionState, ColorVisionType.protanopia);
    await tester.pump();
    expect(h.settings.filterType, ColorVisionType.protanopia);

    selectExperiencePreset(
        h.filterService, h.visionState, 'meniere', 'vertigo');
    await tester.pump();

    expect(h.visionState.layers.map((l) => l.id), ['vertigo']);
    expect(h.filterService.currentFilter, ColorVisionType.none);
    expect(h.settings.filterType, ColorVisionType.none,
        reason: '「いまは無い色覚」が settings に残ってはならない');
  });

  testWidgets('プリセットの後で色覚を足すと、その色覚が FilterService・settings に入る',
      (tester) async {
    final h = await pumpHomeScreen(tester, size: wide);
    selectExperiencePreset(
        h.filterService, h.visionState, 'meniere', 'vertigo');
    await tester.pump();

    toggleColorVision(
        h.filterService, h.visionState, ColorVisionType.deuteranopia);
    await tester.pump();

    expect(h.filterService.currentFilter, ColorVisionType.deuteranopia);
    expect(h.settings.filterType, ColorVisionType.deuteranopia);
  });
}
