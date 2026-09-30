import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/services/color_vision_selection.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';
import 'package:universal_experience/ui/widgets/color_vision_compare_view.dart';

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

  /// 描画は実ブリッジを要るのでフェイク（同じ画像の複製）に差し替える。
  Future<void> installFakes(WidgetTester tester) async {
    await tester.runAsync(() async {
      master = await generateSampleImage(64);
    });
    addTearDown(master.dispose);
    previewSourceImageLoader = (source, size) async => master.clone();
    afterImageRenderer = (source, filter, strength) async => master.clone();
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
}
