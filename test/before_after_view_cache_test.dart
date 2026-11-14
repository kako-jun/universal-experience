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
}

/// いま組んでいるビューの元画像（フェイクの描画器が、どの元画像の描画かを記録するのに使う）。
PreviewImageSource? currentSource;
