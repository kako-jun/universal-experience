import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/services/color_vision_selection.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';
import 'package:universal_experience/ui/widgets/color_vision_compare_view.dart';
import 'package:universal_experience/ui/widgets/filter_list_tile.dart';

import 'support/home_screen_harness.dart';
import 'support/sample_image_generator.dart';

/// 「2×2 で比較」の切替（#84）が、色覚カテゴリを選んでいるときだけ出て、
/// ON の間は Before / After の代わりに 2×2 を出すことの確認。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const wide = Size(1280, 1000);

  late ui.Image master;

  setUp(installHomeScreenFixtures);
  tearDown(() {
    resetHomeScreenFixtures();
    previewSourceImageLoader = BeforeAfterView.loadPreviewSourceImage;
    afterImageRenderer = BeforeAfterView.renderAfter;
  });

  /// afterImageRenderer に渡された強さの記録（[installFakes] が積む）。
  final renderedStrengths = <double>[];

  /// 描画は実ブリッジを要るのでフェイク（同じ画像の複製）に差し替える。
  Future<void> installFakes(WidgetTester tester) async {
    renderedStrengths.clear();
    await tester.runAsync(() async {
      master = await generateSampleImage(64);
    });
    addTearDown(master.dispose);
    previewSourceImageLoader = (source, size) async => master.clone();
    afterImageRenderer = (source, filter, strength) async {
      renderedStrengths.add(strength);
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
    h.visionState.select('myopia');
    await tester.pump();
    expect(toggle(), findsNothing);
    expect(find.byType(BeforeAfterView), findsOneWidget);
  });

  testWidgets('色覚クイック選択（-opia / -omaly）では切替が出る', (tester) async {
    await installFakes(tester);
    final h = await pumpHomeScreen(tester, size: wide);
    for (final type in [
      ColorVisionType.protanopia,
      ColorVisionType.deuteranomaly,
      ColorVisionType.achromatopsia,
    ]) {
      selectColorVision(h.filterService, h.visionState, type);
      await tester.pump();
      expect(toggle(), findsOneWidget, reason: type.id);
    }
  });

  testWidgets('advanced カタログから色覚（四色覚を含む）を選んでも切替が出る', (tester) async {
    await installFakes(tester);
    final h = await pumpHomeScreen(tester, size: wide);
    for (final id in ['tritanopia', 'tetrachromacy']) {
      h.visionState.select(id);
      await tester.pump();
      expect(toggle(), findsOneWidget, reason: id);
    }
  });

  testWidgets('切替を ON にすると Before / After の代わりに 2×2 が出て、OFF で戻る',
      (tester) async {
    await installFakes(tester);
    final h = await pumpHomeScreen(tester, size: wide);
    selectColorVision(
        h.filterService, h.visionState, ColorVisionType.protanopia);
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
    selectColorVision(
        h.filterService, h.visionState, ColorVisionType.protanopia);
    await tester.pump();
    await tester.tap(toggle());
    await tester.pump();
    expect(find.byType(ColorVisionCompareView), findsOneWidget);

    h.visionState.select('myopia');
    await tester.pump();
    expect(find.byType(ColorVisionCompareView), findsNothing);
    expect(find.byType(BeforeAfterView), findsOneWidget);
    expect(toggle(), findsNothing);

    selectColorVision(
        h.filterService, h.visionState, ColorVisionType.deuteranopia);
    await tester.pump();
    expect(find.byType(ColorVisionCompareView), findsOneWidget);
  });

  testWidgets('2×2 の強さは、現在の強さ（色覚の強度スライダー）が 4 セル共通で使われる', (tester) async {
    await installFakes(tester);
    final h = await pumpHomeScreen(tester, size: wide);
    selectColorVision(
        h.filterService, h.visionState, ColorVisionType.protanopia);
    h.filterService.setIntensity(0.4);
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
    // setIntensity の永続化デバウンス（300ms）を流す。
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('2×2 の間は見出しが「色覚 4 型の比較」になり、OFF で「ビフォー / アフター」に戻る',
      (tester) async {
    await installFakes(tester);
    final h = await pumpHomeScreen(tester, size: wide);
    selectColorVision(
        h.filterService, h.visionState, ColorVisionType.protanopia);
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
    selectColorVision(
        h.filterService, h.visionState, ColorVisionType.protanopia);
    h.filterService.setIntensity(0.6);
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
    expect(renderedStrengths, everyElement(0.6));
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('切替は Tab で入れて、Space で 2×2 に切り替わる（キーボードで操作できる）', (tester) async {
    await installFakes(tester);
    final h = await pumpHomeScreen(tester, size: wide);
    selectColorVision(
        h.filterService, h.visionState, ColorVisionType.protanopia);
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
    await tester.pump(const Duration(milliseconds: 400));
  });

  for (final height in [640.0, 800.0, 1000.0]) {
    testWidgets(
        '色覚の行から → で出た先は、ウィンドウの高さ $height でもショートカット受け口で、'
        '次の ←→ から強度が動く', (tester) async {
      await installFakes(tester);
      final h = await pumpHomeScreen(tester, size: Size(1280, height));
      selectColorVision(
          h.filterService, h.visionState, ColorVisionType.protanopia);
      await tester.pump();
      final before = h.filterService.intensity;

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
      expect(h.filterService.intensity, before,
          reason: '行から出る 1 回目の → は強度を動かさない');
      expect(focusedTile(), isNull);
      expect(tester.binding.focusManager.primaryFocus?.debugLabel,
          'homeShortcuts');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(h.filterService.intensity, lessThan(before),
          reason: '次の ← から強度が動く');
      await h.filterService.flush();
    });
  }
}
