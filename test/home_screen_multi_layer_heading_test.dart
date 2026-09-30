// 複数層のときの比較ビューの見出しと、暫定の書き出し無効（#120）。
//
// after の見出しは、層が 1 つなら従来どおりそのフィルタ名、複数なら「名前 + 名前 …（+N）」
// の要約（適用順。2 つまでは全部、3 つ目以降は「…（+N）」）。原画ペインの見出しは変わらない。
// PNG 書き出しは複数層の間（#121 で解除するまで）無効で、理由を画面に出す。

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/rendering/cpu_vision_renderer.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';

import 'support/home_screen_harness.dart';
import 'support/sample_image_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ui.Image master;

  setUp(installHomeScreenFixtures);
  tearDown(() {
    resetHomeScreenFixtures();
    CpuVisionRenderer.pipelineApplier = CpuVisionRenderer.applyPipeline;
  });

  Future<void> installFakes(WidgetTester tester) async {
    await tester.runAsync(() async {
      master = await generateSampleImage(64);
    });
    addTearDown(master.dispose);
    previewSourceImageLoader = (source, size) async => master.clone();
    afterImageRenderer = (source, filter, strength) async => master.clone();
    CpuVisionRenderer.pipelineApplier = (source, steps) async => master.clone();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
  }

  const wide = Size(1400, 1000);

  Future<AppLocalizations> pumpEn(
      WidgetTester tester, HomeScreenHarness h) async {
    await settle(tester);
    return AppLocalizations.of(tester.element(find.byType(BeforeAfterView)))!;
  }

  group('after の見出し', () {
    testWidgets('1 層: 従来どおりそのフィルタ名（要約にしない）', (tester) async {
      await installFakes(tester);
      final h =
          await pumpHomeScreen(tester, size: wide, locale: const Locale('en'));
      h.visionState.toggle('myopia');
      final l10n = await pumpEn(tester, h);

      expect(
          tester
              .widget<BeforeAfterView>(find.byType(BeforeAfterView))
              .layerNames,
          isNull);
      expect(find.text('Myopia'), findsWidgets);
      expect(find.textContaining(' + '), findsNothing);
      expect(find.text(l10n.exportDisabledMultiLayer), findsNothing);
    });

    testWidgets('2 層: 「名前 + 名前」を適用順に出す', (tester) async {
      await installFakes(tester);
      final h =
          await pumpHomeScreen(tester, size: wide, locale: const Locale('en'));
      // 選ぶ順は段順の逆。見出しは段順（光学 → 色覚）になる。
      h.visionState.toggle('protanopia');
      h.visionState.toggle('myopia');
      await pumpEn(tester, h);

      expect(find.text('Myopia + Protanopia'), findsOneWidget);
    });

    testWidgets('3 層: 2 つまで名前を出し、残りは「…（+N）」', (tester) async {
      await installFakes(tester);
      final h =
          await pumpHomeScreen(tester, size: wide, locale: const Locale('en'));
      h.visionState.toggle('protanopia');
      h.visionState.toggle('myopia');
      h.visionState.toggle('vertigo');
      await pumpEn(tester, h);

      expect(find.textContaining('… (+1)'), findsOneWidget);
      final heading = tester.widget<Text>(find.textContaining('… (+1)'));
      expect(heading.data, matches(RegExp(r'^.+ \+ .+ … \(\+1\)$')));
    });

    testWidgets('日本語: 「…（+N）」の全角括弧', (tester) async {
      await installFakes(tester);
      final h = await pumpHomeScreen(tester, size: wide);
      h.visionState.toggle('protanopia');
      h.visionState.toggle('myopia');
      h.visionState.toggle('vertigo');
      await pumpEn(tester, h);

      expect(find.textContaining('…（+1）'), findsOneWidget);
    });

    testWidgets('原画ペインの見出しは変わらない', (tester) async {
      await installFakes(tester);
      final h =
          await pumpHomeScreen(tester, size: wide, locale: const Locale('en'));
      h.visionState.toggle('protanopia');
      h.visionState.toggle('myopia');
      final l10n = await pumpEn(tester, h);

      expect(find.text(l10n.previewPaneOriginal), findsOneWidget);
    });
  });

  group('PNG 書き出し（#121 で解除するまでの暫定）', () {
    testWidgets('複数層: ボタンは無効で、理由を画面に出す', (tester) async {
      await installFakes(tester);
      final h =
          await pumpHomeScreen(tester, size: wide, locale: const Locale('en'));
      h.visionState.toggle('protanopia');
      h.visionState.toggle('myopia');
      final l10n = await pumpEn(tester, h);

      expect(find.text(l10n.exportDisabledMultiLayer), findsOneWidget);
      final button = find.ancestor(
        of: find.byIcon(Icons.download_outlined),
        matching: find.byType(IconButton),
      );
      expect(button, findsOneWidget);
      expect(tester.widget<IconButton>(button).onPressed, isNull);
    });

    testWidgets('1 層に戻すと有効に戻り、理由も消える', (tester) async {
      await installFakes(tester);
      final h =
          await pumpHomeScreen(tester, size: wide, locale: const Locale('en'));
      h.visionState.toggle('protanopia');
      h.visionState.toggle('myopia');
      final l10n = await pumpEn(tester, h);
      h.visionState.remove('myopia');
      await settle(tester);

      expect(find.text(l10n.exportDisabledMultiLayer), findsNothing);
      final button = find.ancestor(
        of: find.byIcon(Icons.download_outlined),
        matching: find.byType(IconButton),
      );
      expect(tester.widget<IconButton>(button).onPressed, isNotNull);
    });
  });
}
