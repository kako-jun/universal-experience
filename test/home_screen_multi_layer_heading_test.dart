// 複数層のときの比較ビューの見出し（#120）と、書き出しへ渡す全層の値（#121）。
//
// after の見出しは、層が 1 つなら従来どおりそのフィルタ名、複数なら「名前 + 名前 …（+N）」
// の要約（適用順。2 つまでは全部、3 つ目以降は「…（+N）」）。原画ペインの見出しは変わらない。
// PNG 書き出しは複数層でも有効で、全層の値（適用順）を [BeforeAfterView] へ渡す。

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/l10n/l10n_extensions.dart';
import 'package:universal_experience/models/preview_image_source.dart';
import 'package:universal_experience/rendering/cpu_vision_renderer.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
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
      await pumpEn(tester, h);

      expect(
          tester
              .widget<BeforeAfterView>(find.byType(BeforeAfterView))
              .layerNames,
          isNull);
      expect(find.text('Myopia'), findsWidgets);
      expect(find.textContaining(' + '), findsNothing);
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

  group('PNG 書き出し（#121）', () {
    Finder exportButton() => find.ancestor(
          of: find.byIcon(Icons.download_outlined),
          matching: find.byType(IconButton),
        );

    testWidgets('複数層: ボタンは有効で、全層の値（適用順）を書き出しへ渡す', (tester) async {
      await installFakes(tester);
      final h =
          await pumpHomeScreen(tester, size: wide, locale: const Locale('en'));
      h.visionState.toggle('protanopia');
      h.visionState.toggle('myopia');
      await pumpEn(tester, h);

      expect(exportButton(), findsOneWidget);
      expect(tester.widget<IconButton>(exportButton()).onPressed, isNotNull);
      final layers = tester
          .widget<BeforeAfterView>(find.byType(BeforeAfterView))
          .exportLayers!;
      // 選ぶ順は段順の逆。渡す値は段順（光学 → 色覚）。
      expect([for (final l in layers) l.layer.id], ['myopia', 'protanopia']);
    });

    testWidgets('1 層: 書き出しへ渡す全層の値は無く、従来どおり有効', (tester) async {
      await installFakes(tester);
      final h =
          await pumpHomeScreen(tester, size: wide, locale: const Locale('en'));
      h.visionState.toggle('protanopia');
      h.visionState.toggle('myopia');
      await pumpEn(tester, h);
      h.visionState.remove('myopia');
      await settle(tester);

      expect(
          tester
              .widget<BeforeAfterView>(find.byType(BeforeAfterView))
              .exportLayers,
          isNull);
      expect(tester.widget<IconButton>(exportButton()).onPressed, isNotNull);
    });
  });

  group('静止フレームの注記（時間依存の層が 1 つでもあるとき）', () {
    testWidgets('3 層（時間依存の vertigo を含む）で、調整中が myopia でも注記は出る',
        (tester) async {
      await installFakes(tester);
      final h =
          await pumpHomeScreen(tester, size: wide, locale: const Locale('en'));
      h.visionState.toggle('protanopia');
      h.visionState.toggle('vertigo');
      h.visionState.toggle('myopia');
      h.visionState.focusLayer('myopia');
      final l10n = await pumpEn(tester, h);

      expect(h.visionState.focusedId, 'myopia');
      expect(find.text(l10n.previewStaticFrameNote), findsOneWidget);
    });

    testWidgets('時間依存の層が無ければ、複数層でも注記は出ない', (tester) async {
      await installFakes(tester);
      final h =
          await pumpHomeScreen(tester, size: wide, locale: const Locale('en'));
      h.visionState.toggle('protanopia');
      h.visionState.toggle('myopia');
      final l10n = await pumpEn(tester, h);

      expect(find.text(l10n.previewStaticFrameNote), findsNothing);
    });

    testWidgets('時間依存の層を外すと注記も消える', (tester) async {
      await installFakes(tester);
      final h =
          await pumpHomeScreen(tester, size: wide, locale: const Locale('en'));
      h.visionState.toggle('vertigo');
      h.visionState.toggle('myopia');
      final l10n = await pumpEn(tester, h);
      expect(find.text(l10n.previewStaticFrameNote), findsOneWidget);

      h.visionState.remove('vertigo');
      await settle(tester);
      expect(find.text(l10n.previewStaticFrameNote), findsNothing);
    });
  });

  group('見出しが長く折り返しても、左右の画像の上端は揃う', () {
    // 横並びになる最小幅（420）の半分のペインで、長い名前 2 つ + 「…（+N）」。見出しは 4 行以上に
    // なりうる。
    Future<void> pumpPanes(WidgetTester tester, List<String> names) async {
      await installFakes(tester);
      tester.view.physicalSize = const Size(440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: BeforeAfterView(
                filter: const VisionFilter.myopia(),
                filterId: 'myopia',
                strength: 1.0,
                imageSource: const SamplePreviewImageSource('test'),
                sampleSize: 32,
                layerNames: names,
                layerIds: const ['myopia', 'glaucoma', 'protanopia'],
                steps: const [],
              ),
            ),
          ),
        ),
      );
      await settle(tester);
    }

    for (final length in [10, 40, 120]) {
      testWidgets('名前の長さ $length 文字: 原画ペインと after ペインの画像の上端が同じ',
          (tester) async {
        final name = List.filled(length, 'W').join();
        await pumpPanes(tester, [name, name, name]);

        final images = find.byType(PreviewImageView);
        expect(images, findsNWidgets(2));
        expect(tester.getTopLeft(images.at(0)).dy,
            tester.getTopLeft(images.at(1)).dy);
        if (length == 120) {
          // 見出しが 64dp（3 行分の最小の高さ）を超えて折り返している場合も測れている。
          expect(tester.getTopLeft(images.at(0)).dy, greaterThan(64 + 8));
        }
      });

      testWidgets('名前の長さ $length 文字: 左右の見出しのラベルの先頭行も同じ高さ', (tester) async {
        final name = List.filled(length, 'W').join();
        final names = [name, name, name];
        await pumpPanes(tester, names);
        final l10n =
            AppLocalizations.of(tester.element(find.byType(BeforeAfterView)))!;

        final before = find.text(l10n.previewPaneOriginal);
        final after = find.text(layerNamesSummary(l10n, names));
        expect(before, findsOneWidget);
        expect(after, findsOneWidget);
        expect(tester.getTopLeft(before).dy, tester.getTopLeft(after).dy);
        // 書き出しボタンは見出しの行の先頭（ラベルの上の余白 14dp と同じ高さ）に置く。
        expect(tester.getTopLeft(find.byType(IconButton)).dy,
            tester.getTopLeft(before).dy - 14);
      });
    }
  });

  group('読み上げの順序は「原画の見出し → after の見出し → after の画像」', () {
    // 見出しの行と画像の行を別々に組んでいても（横並び）、原画の画像は装飾（見出しが説明を担う）で
    // 読み上げ対象が無いため、ペイン単位で組んだ場合と順序は変わらない。
    testWidgets('横並び（複数層）でこの順に読まれる', (tester) async {
      final handle = tester.ensureSemantics();
      final names = ['W' * 10, 'W' * 10, 'W' * 10];
      await installFakes(tester);
      tester.view.physicalSize = const Size(440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: BeforeAfterView(
                filter: const VisionFilter.myopia(),
                filterId: 'myopia',
                strength: 1.0,
                imageSource: const SamplePreviewImageSource('test'),
                sampleSize: 32,
                layerNames: names,
                layerIds: const ['myopia', 'glaucoma', 'protanopia'],
                steps: const [],
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      final l10n =
          AppLocalizations.of(tester.element(find.byType(BeforeAfterView)))!;

      final labels = <String>[];
      void walk(SemanticsNode node) {
        if (node.label.isNotEmpty) labels.add(node.label);
        node.visitChildren((child) {
          walk(child);
          return true;
        });
      }

      walk(tester.getSemantics(find.byType(Scaffold)));

      int indexOf(String text) => labels.indexWhere((l) => l.contains(text));
      final beforeHeading = indexOf(l10n.previewPaneOriginal);
      final afterHeading = indexOf(layerNamesSummary(l10n, names));
      final afterImage =
          indexOf(l10n.previewImageFilteredSemantics(names.join(' + ')));
      expect(beforeHeading, greaterThanOrEqualTo(0), reason: '$labels');
      expect(afterHeading, greaterThan(beforeHeading), reason: '$labels');
      expect(afterImage, greaterThan(afterHeading), reason: '$labels');
      handle.dispose();
    });
  });
}
