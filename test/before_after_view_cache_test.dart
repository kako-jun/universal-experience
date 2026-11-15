// BeforeAfterView の描画結果のキャッシュと、読み込んだ画像（ユーザー画像）の扱い（#185 (b)）:
// 別の画像へ替えたらその画像から描いた結果は残さない（遅れて終わった描画も入れない）。

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/models/preview_image_source.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';
import 'package:universal_experience/ui/widgets/preview_rendering.dart';

import 'support/home_screen_harness.dart';

void main() {
  late ui.Image imageA;
  late ui.Image imageB;
  late UserPreviewImageSource sourceA;
  late UserPreviewImageSource sourceB;
  late List<PreviewImageSource> rendered;
  Completer<void>? gateA;

  setUp(() {
    imageA = fixturePreviewImage();
    imageB = fixturePreviewImage();
    sourceA = UserPreviewImageSource(imageA, 1);
    sourceB = UserPreviewImageSource(imageB, 2);
    rendered = [];
    gateA = null;
    previewSourceImageLoader = (source, size) async => fixturePreviewImage();
    afterImageRenderer = (input, filter, strength) async {
      // 描画器に渡るのは before の複製なので、どの元画像かは呼び出し時点の記録で見る。
      final source = currentSource!;
      rendered.add(source);
      final gate = gateA;
      if (source == sourceA && gate != null) await gate.future;
      return fixturePreviewImage();
    };
  });

  tearDown(() {
    previewSourceImageLoader = loadDefaultPreviewSourceImage;
    afterImageRenderer = renderDefaultAfter;
    imageA.dispose();
    imageB.dispose();
  });

  Widget view(PreviewImageSource source) {
    currentSource = source;
    return MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: BeforeAfterView(
          filter: const VisionFilter.myopia(),
          filterId: 'myopia',
          strength: 0.5,
          imageSource: source,
          sampleSize: 16,
        ),
      ),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
  }

  testWidgets('別の画像へ替えたら、前の画像から描いた結果はキャッシュから捨てる', (tester) async {
    await tester.pumpWidget(view(sourceA));
    await settle(tester);
    await tester.pumpWidget(view(sourceB));
    await settle(tester);
    await tester.pumpWidget(view(sourceA));
    await settle(tester);
    expect(rendered, [sourceA, sourceB, sourceA],
        reason: 'A に戻したら描き直す（A の結果を覚えたままにしない）');
  });

  testWidgets('別の画像へ替えた後に遅れて終わった前の画像の描画は、キャッシュに入れない', (tester) async {
    gateA = Completer<void>();
    await tester.pumpWidget(view(sourceA));
    await settle(tester);
    expect(rendered, [sourceA]);

    // A の描画が終わらないまま B へ替える（B の読み込みはすぐ終わり、A の分を捨てる）。
    await tester.pumpWidget(view(sourceB));
    await settle(tester);
    gateA!.complete();
    gateA = null;
    await settle(tester);
    expect(rendered, [sourceA, sourceB]);

    await tester.pumpWidget(view(sourceA));
    await settle(tester);
    expect(rendered, [sourceA, sourceB, sourceA],
        reason: '遅れて終わった A の結果は覚えていないので、A に戻したら描き直す');
  });

  testWidgets(
      '同じ入力へ戻ってキャッシュから出したときも、原画を出したときも、表示を観測口へ知らせる'
      '（integration_test のプリセット 4 種の結線テストが観測する、#185）', (tester) async {
    final shown = <PreviewAfterShown>[];
    debugBeforeAfterShownHook = shown.add;
    addTearDown(() => debugBeforeAfterShownHook = null);
    var calls = 0;
    afterImageRenderer = (input, filter, strength) async {
      calls++;
      return fixturePreviewImage();
    };
    Widget withFilter(VisionFilter? filter, String? id) => MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: BeforeAfterView(
              filter: filter,
              filterId: id,
              strength: 0.5,
              imageSource: const SamplePreviewImageSource('info_board'),
              sampleSize: 16,
            ),
          ),
        );
    // meniere（vertigo）→ bppv（別のフィルタ）→ labyrinthitis（また vertigo・同じ強度）と同じ形。
    await tester.pumpWidget(withFilter(const VisionFilter.vertigo(), 'vertigo'));
    await settle(tester);
    await tester.pumpWidget(
        withFilter(const VisionFilter.bppvRotation(), 'bppv_rotation'));
    await settle(tester);
    await tester.pumpWidget(withFilter(const VisionFilter.vertigo(), 'vertigo'));
    await settle(tester);
    await tester.pumpWidget(withFilter(null, null));
    await settle(tester);

    expect(calls, 2, reason: '3 回目は同じ入力なので描画器を呼ばない');
    expect([for (final e in shown) (e.filter, e.origin)], [
      (const VisionFilter.vertigo(), PreviewAfterOrigin.rendered),
      (const VisionFilter.bppvRotation(), PreviewAfterOrigin.rendered),
      (const VisionFilter.vertigo(), PreviewAfterOrigin.cache),
      (null, PreviewAfterOrigin.original),
    ]);
    expect(shown.every((e) => !e.provisional && e.strength == 0.5), isTrue);
  });
}

/// いま組んでいるビューの元画像（フェイクの描画器が、どの元画像の描画かを記録するのに使う）。
PreviewImageSource? currentSource;
