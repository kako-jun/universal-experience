import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/rendering/cpu_vision_renderer.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart'
    show VisionStep;
import 'package:universal_experience/ui/widgets/before_after_view.dart';
import 'package:universal_experience/ui/widgets/color_vision_compare_view.dart';
import 'package:universal_experience/ui/widgets/filter_list_tile.dart';

import 'support/color_vision_select.dart';
import 'support/home_screen_harness.dart';
import 'support/sample_image_generator.dart';

/// 「2×2 で比較」の切替（#84）が、層の集合に色覚層があるときだけ出て（#122）、
/// ON の間は Before / After の代わりに 2×2 を出すことの確認。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const wide = Size(1280, 1000);

  late ui.Image master;

  setUp(installHomeScreenFixtures);
  tearDown(resetHomeScreenFixtures);

  /// afterImageRenderer に渡された強さの記録（[installFakes] が積む）。
  final renderedStrengths = <double>[];

  /// 土台の合成（pipelineApplier）に渡された steps の記録。
  final pipelineCalls = <List<VisionStep>>[];

  /// 描画は実ブリッジを要るのでフェイク（同じ画像の複製）に差し替える。
  Future<void> installFakes(WidgetTester tester) async {
    renderedStrengths.clear();
    pipelineCalls.clear();
    await tester.runAsync(() async {
      master = await generateSampleImage(64);
    });
    addTearDown(master.dispose);
    previewSourceImageLoader = (source, size) async => master.clone();
    afterImageRenderer = (source, filter, strength) async {
      renderedStrengths.add(strength);
      return master.clone();
    };
    CpuVisionRenderer.pipelineApplier = (source, steps) async {
      pipelineCalls.add(steps);
      return master.clone();
    };
  }

  final l10n = lookupAppLocalizations(const Locale('ja'));

  Finder toggle() => find.widgetWithText(FilterChip, l10n.compareToggleLabel);

  testWidgets('何も選んでいないときは切替が出ない', (tester) async {
    await installFakes(tester);
    await pumpHomeScreen(tester, size: wide);
    expect(toggle(), findsNothing);
    expect(find.byType(BeforeAfterView), findsOneWidget);
    expect(find.byType(ColorVisionCompareView), findsNothing);
  });

  testWidgets('色覚以外（advanced カタログ）を選んでいるときは切替が出ない', (tester) async {
    await installFakes(tester);
    final h = await pumpHomeScreen(tester, size: wide);
    h.visionState.replaceWith('myopia');
    await tester.pump();
    expect(toggle(), findsNothing);
    expect(find.byType(BeforeAfterView), findsOneWidget);
  });

  testWidgets('色覚クイック選択（-opia / -omaly）では切替が出る', (tester) async {
    await installFakes(tester);
    final h = await pumpHomeScreen(tester, size: wide);
    for (final key in ['protanopia', 'deuteranomaly', 'achromatopsia']) {
      selectColorVisionKey(h.visionState, key);
      await tester.pump();
      expect(toggle(), findsOneWidget, reason: key);
    }
  });

  testWidgets('advanced カタログから色覚（四色覚を含む）を選んでも切替が出る', (tester) async {
    await installFakes(tester);
    final h = await pumpHomeScreen(tester, size: wide);
    for (final id in ['tritanopia', 'tetrachromacy']) {
      h.visionState.replaceWith(id);
      await tester.pump();
      expect(toggle(), findsOneWidget, reason: id);
    }
  });

  testWidgets('切替を ON にすると Before / After の代わりに 2×2 が出て、OFF で戻る',
      (tester) async {
    await installFakes(tester);
    final h = await pumpHomeScreen(tester, size: wide);
    selectColorVisionKey(h.visionState, 'protanopia');
    await tester.pump();

    expect(find.byType(BeforeAfterView), findsOneWidget);
    expect(find.byType(ColorVisionCompareView), findsNothing);

    await tester.tap(toggle());
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump();
    }
    expect(find.byType(ColorVisionCompareView), findsOneWidget);
    expect(find.byType(BeforeAfterView), findsNothing);
    expect(tester.widget<FilterChip>(toggle()).selected, isTrue);

    await tester.tap(toggle());
    await tester.pump();
    expect(find.byType(ColorVisionCompareView), findsNothing);
    expect(find.byType(BeforeAfterView), findsOneWidget);
    expect(tester.widget<FilterChip>(toggle()).selected, isFalse);
  });

  testWidgets('色覚以外に切り替えると Before / After に戻り、色覚に戻ると 2×2 に戻る', (tester) async {
    await installFakes(tester);
    final h = await pumpHomeScreen(tester, size: wide);
    selectColorVisionKey(h.visionState, 'protanopia');
    await tester.pump();
    await tester.tap(toggle());
    await tester.pump();
    expect(find.byType(ColorVisionCompareView), findsOneWidget);

    h.visionState.replaceWith('myopia');
    await tester.pump();
    expect(find.byType(ColorVisionCompareView), findsNothing);
    expect(find.byType(BeforeAfterView), findsOneWidget);
    expect(toggle(), findsNothing);

    selectColorVisionKey(h.visionState, 'deuteranopia');
    await tester.pump();
    expect(find.byType(ColorVisionCompareView), findsOneWidget);
  });

  testWidgets('層の集合に色覚層があれば、他の層を重ねていても切替が出る（色覚が無ければ出ない、#122）', (tester) async {
    await installFakes(tester);
    final h = await pumpHomeScreen(tester, size: wide);
    h.visionState.toggle('protanopia');
    await tester.pump();
    expect(toggle(), findsOneWidget);
    await tester.tap(toggle());
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump();
    }
    expect(find.byType(ColorVisionCompareView), findsOneWidget);

    // 色覚に別の層を重ねても、切替と 2×2 は残る（調整中が色覚でなくても）。
    h.visionState.toggle('myopia');
    await tester.pump();
    expect(toggle(), findsOneWidget);
    expect(find.byType(ColorVisionCompareView), findsOneWidget);
    expect(find.byType(BeforeAfterView), findsNothing);
    h.visionState.focusLayer('myopia');
    await tester.pump();
    expect(h.visionState.focusedId, 'myopia');
    expect(toggle(), findsOneWidget);
    expect(find.byType(ColorVisionCompareView), findsOneWidget);

    // 色覚層を外すと、切替ごと消えて Before / After に戻る。
    h.visionState.remove('protanopia');
    await tester.pump();
    expect(toggle(), findsNothing);
    expect(find.byType(ColorVisionCompareView), findsNothing);
    expect(find.byType(BeforeAfterView), findsOneWidget);

    // 色覚を足し直すと、直前の選び方（2×2）に戻る。
    h.visionState.toggle('deuteranopia');
    await tester.pump();
    expect(toggle(), findsOneWidget);
    expect(find.byType(ColorVisionCompareView), findsOneWidget);
  });

  testWidgets('色覚以外の層だけ（複数でも）のときは切替が出ない（#122）', (tester) async {
    await installFakes(tester);
    final h = await pumpHomeScreen(tester, size: wide);
    h.visionState.toggle('myopia');
    h.visionState.toggle('vertigo');
    await tester.pump();
    expect(toggle(), findsNothing);
    expect(find.byType(ColorVisionCompareView), findsNothing);
    expect(find.byType(BeforeAfterView), findsOneWidget);
  });

  testWidgets(
      '色覚 + 他の層の 2×2: 土台は色覚以外の層の steps（色覚層は含まない）、強さは色覚層の強度。'
      '色覚の強度だけを動かしても土台は作り直さない（#122）', (tester) async {
    await installFakes(tester);
    final h = await pumpHomeScreen(tester, size: wide);
    h.visionState.toggle('protanopia');
    h.visionState.toggle('myopia');
    h.visionState.setLayerStrength('myopia', 0.5);
    h.visionState.setLayerStrength('protanopia', 0.4);
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(); // 切替前の Before / After の描画を流しきる。
    }
    pipelineCalls.clear();
    await tester.tap(toggle());
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump();
    }

    ColorVisionCompareView view() => tester
        .widget<ColorVisionCompareView>(find.byType(ColorVisionCompareView));
    expect(view().strength, 0.4, reason: '調整中の層ではなく色覚層の強度');
    expect(view().baseSteps.length, 1);
    expect(view().baseSteps.single.strength, 0.5);
    expect([for (final l in view().baseLayers) l.layer.id], ['myopia']);
    expect(find.text(l10n.compareSharedStrengthNote(40)), findsOneWidget);
    expect(find.textContaining(l10n.compareBaseNote('').split('：').first),
        findsOneWidget,
        reason: '土台の注記が出る');
    expect(pipelineCalls.length, 1, reason: '土台は 1 回だけ合成');

    // 色覚の強度だけを動かす: 土台の steps は同じなので再合成しない。
    h.visionState.setLayerStrength('protanopia', 0.8);
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump();
    }
    expect(view().strength, 0.8);
    expect(pipelineCalls.length, 1);

    // 色覚層を調整中にしても同じ。
    h.visionState.focusLayer('protanopia');
    await tester.pump();
    expect(view().strength, 0.8);
  });

  testWidgets('色覚 + 他の層でも、原画に戻す（bypass）は 2×2 に効く（強度 0・土台なし）', (tester) async {
    await installFakes(tester);
    final h = await pumpHomeScreen(tester, size: wide);
    h.visionState.toggle('protanopia');
    h.visionState.toggle('myopia');
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump();
    }
    pipelineCalls.clear();
    await tester.tap(toggle());
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump();
    }
    expect(pipelineCalls.length, 1);

    final holder = Object();
    renderedStrengths.clear();
    final composedBeforeBypass = pipelineCalls.length;
    h.visionState.acquireBypass(holder);
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump();
    }
    final view = tester
        .widget<ColorVisionCompareView>(find.byType(ColorVisionCompareView));
    expect(view.strength, 0.0);
    expect(view.baseSteps, isEmpty);
    expect(find.text(l10n.compareSharedStrengthNote(0)), findsOneWidget);
    expect(h.visionState.layers.length, 2, reason: '選択は残る');
    expect(renderedStrengths.length, 4, reason: 'バイパス中は 4 セルとも描き直す');
    expect(renderedStrengths, everyElement(0.0),
        reason: 'バイパス中は 4 セルとも強度 0（原画）');
    expect(pipelineCalls.length, composedBeforeBypass,
        reason: 'バイパス中は土台を合成しない');

    renderedStrengths.clear();
    h.visionState.releaseBypass(holder);
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump();
    }
    expect(pipelineCalls.length, composedBeforeBypass,
        reason: '解除しても層が同じなら土台を再合成しない');
    expect(renderedStrengths.length, 4, reason: '解除で 4 セルとも描き直す');
    expect(renderedStrengths, everyElement(1.0), reason: '色覚層の強度（既定 100%）に戻る');
    expect(
      tester
          .widget<ColorVisionCompareView>(find.byType(ColorVisionCompareView))
          .baseSteps,
      isNotEmpty,
    );
  });

  testWidgets('2×2 の強さは、現在の強さ（色覚の強度スライダー）が 4 セル共通で使われる', (tester) async {
    await installFakes(tester);
    final h = await pumpHomeScreen(tester, size: wide);
    selectColorVisionKey(h.visionState, 'protanopia');
    h.visionState.setStrength(0.4);
    await tester.pump();
    await tester.tap(toggle());
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump();
    }
    final view = tester
        .widget<ColorVisionCompareView>(find.byType(ColorVisionCompareView));
    expect(view.strength, 0.4);
    expect(find.text(l10n.compareSharedStrengthNote(40)), findsOneWidget);
  });

  testWidgets('2×2 の間は見出しが「色覚 4 型の比較」になり、OFF で「ビフォー / アフター」に戻る',
      (tester) async {
    await installFakes(tester);
    final h = await pumpHomeScreen(tester, size: wide);
    selectColorVisionKey(h.visionState, 'protanopia');
    await tester.pump();
    expect(find.text(l10n.previewSectionTitle), findsOneWidget);
    expect(find.text(l10n.compareSectionTitle), findsNothing);

    await tester.tap(toggle());
    await tester.pump();
    expect(find.text(l10n.compareSectionTitle), findsOneWidget);
    expect(find.text(l10n.previewSectionTitle), findsNothing,
        reason: 'Before / After ではないので、その見出しは残さない');

    await tester.tap(toggle());
    await tester.pump();
    expect(find.text(l10n.previewSectionTitle), findsOneWidget);
    expect(find.text(l10n.compareSectionTitle), findsNothing);
  });

  testWidgets('原画に戻す（bypass、強度 0）も 2×2 にそのまま効く（4 セルとも強さ 0 で描く）',
      (tester) async {
    await installFakes(tester);
    final h = await pumpHomeScreen(tester, size: wide);
    selectColorVisionKey(h.visionState, 'protanopia');
    h.visionState.setStrength(0.6);
    await tester.pump();
    await tester.tap(toggle());
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump();
    }
    // 切替前の Before / After 描画（別の強さ）が混ざるので、末尾 4 セル分を見る。
    expect(renderedStrengths.length, greaterThanOrEqualTo(4));
    expect(renderedStrengths.sublist(renderedStrengths.length - 4),
        everyElement(0.6));

    final holder = Object();
    renderedStrengths.clear();
    h.visionState.acquireBypass(holder);
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump();
    }
    expect(find.byType(ColorVisionCompareView), findsOneWidget,
        reason: 'bypass で表示は切り替わらない');
    expect(
      tester
          .widget<ColorVisionCompareView>(find.byType(ColorVisionCompareView))
          .strength,
      0.0,
    );
    expect(renderedStrengths.length, 4);
    expect(renderedStrengths, everyElement(0.0),
        reason: '4 セルとも強さ 0（原画と同じ見え）で描き直す');
    expect(find.text(l10n.compareSharedStrengthNote(0)), findsOneWidget);

    // 解除すると元の強さに戻る。
    renderedStrengths.clear();
    h.visionState.releaseBypass(holder);
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump();
    }
    expect(renderedStrengths.length, 4, reason: '解除で 4 セルとも描き直す');
    expect(renderedStrengths, everyElement(0.6));
  });

  testWidgets('切替は Tab で入れて、Space で 2×2 に切り替わる（キーボードで操作できる）', (tester) async {
    await installFakes(tester);
    final h = await pumpHomeScreen(tester, size: wide);
    selectColorVisionKey(h.visionState, 'protanopia');
    await tester.pump();
    final chipRect = tester.getRect(toggle());

    // 検索欄から Tab で進め、切替に着地するまで送る。
    await tester.tap(find.byType(TextField));
    await tester.pump();
    var reached = false;
    for (var i = 0; i < 120 && !reached; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focus = tester.binding.focusManager.primaryFocus;
      reached = focus != null && chipRect.contains(focus.rect.center);
    }
    expect(reached, isTrue, reason: 'Tab で「2×2 で比較」の切替に届く');

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump();
    }
    expect(find.byType(ColorVisionCompareView), findsOneWidget);
    expect(tester.widget<FilterChip>(toggle()).selected, isTrue);
  });

  for (final height in [640.0, 800.0, 1000.0]) {
    testWidgets(
        '色覚の行から → で出た先は、ウィンドウの高さ $height でもショートカット受け口で、'
        '次の ←→ から強度が動く', (tester) async {
      await installFakes(tester);
      final h = await pumpHomeScreen(tester, size: Size(1280, height));
      selectColorVisionKey(h.visionState, 'protanopia');
      await tester.pump();
      final before = h.visionState.strength;

      FilterListTile? focusedTile() =>
          tester.binding.focusManager.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<FilterListTile>();
      await tester.tap(find.byType(TextField));
      await tester.pump();
      for (var i = 0; i < 120 && focusedTile()?.selected != true; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(focusedTile()?.selected, isTrue, reason: '選択中の色覚の行に Tab で届く');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(h.visionState.strength, before, reason: '行から出る 1 回目の → は強度を動かさない');
      expect(focusedTile(), isNull);
      expect(tester.binding.focusManager.primaryFocus?.debugLabel,
          'homeShortcuts');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(h.visionState.strength, lessThan(before), reason: '次の ← から強度が動く');
    });
  }
}
