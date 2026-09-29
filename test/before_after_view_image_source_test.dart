// BeforeAfterView の PreviewImageSource 対応（#78）のテスト。
//
// before_after_view_test.dart の「生成の世代管理とリソース破棄 (#58)」群と
// 同じ規律を、新しい軸（imageSource の変更）について確認する。filter は
// 常に null にして afterImageRenderer の既定実装（source をそのまま返す）に
// 任せ、CpuVisionRenderer 実ブリッジを踏まずに前段（before 画像の読み込み）
// だけに集中する。

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/models/preview_image_source.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('loadPreviewSourceImage', () {
    test('SamplePreviewImageSource: asset をデコードし size×size に fit する', () async {
      final image = await BeforeAfterView.loadPreviewSourceImage(
        const SamplePreviewImageSource('chart'),
        32,
      );
      addTearDown(image.dispose);
      expect(image.width, 32);
      expect(image.height, 32);
    });

    test('未知の sampleId は ArgumentError', () {
      expect(
        () => BeforeAfterView.loadPreviewSourceImage(
          const SamplePreviewImageSource('no_such_sample'),
          32,
        ),
        throwsArgumentError,
      );
    });

    test('UserPreviewImageSource: 渡された image を size×size に fit し、'
        '元の image は dispose しない', () async {
      final source = await BeforeAfterView.generateSampleImage(10);
      addTearDown(source.dispose);

      final fitted = await BeforeAfterView.loadPreviewSourceImage(
        UserPreviewImageSource(source, 1),
        16,
      );
      addTearDown(fitted.dispose);

      expect(fitted.width, 16);
      expect(fitted.height, 16);
      expect(source.debugDisposed, isFalse);
    });
  });

  group('BeforeAfterView ウィジェット: imageSource 変更時の世代管理 (#78)', () {
    const enLocale = Locale('en');

    Widget localized(Widget child) => MaterialApp(
          locale: enLocale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        );

    tearDown(() {
      previewSourceImageLoader = BeforeAfterView.loadPreviewSourceImage;
    });

    testWidgets('imageSource が非 null なら previewSourceImageLoader 経由で読み込む',
        (tester) async {
      final requested = <PreviewImageSource>[];
      late ui.Image stub;
      await tester.runAsync(() async {
        stub = await BeforeAfterView.generateSampleImage(4);
      });
      previewSourceImageLoader = (source, size) {
        requested.add(source);
        return Future.value(stub);
      };

      await tester.pumpWidget(localized(const BeforeAfterView(
        filter: null,
        filterId: null,
        strength: 1.0,
        sampleSize: 16,
        imageSource: SamplePreviewImageSource('chart'),
      )));
      await tester.pump();
      await tester.pump();

      expect(requested, [const SamplePreviewImageSource('chart')]);
    });

    testWidgets(
        'imageSource が変わると再読み込みし、旧 before/after は dispose される '
        '(#58/#85 と同じ規律)', (tester) async {
      late ui.Image imageA, imageB;
      await tester.runAsync(() async {
        imageA = await BeforeAfterView.generateSampleImage(4);
        imageB = await BeforeAfterView.generateSampleImage(4);
      });
      final images = {
        'a': imageA,
        'b': imageB,
      };
      final requestedSizes = <int>[];
      previewSourceImageLoader = (source, size) {
        requestedSizes.add(size);
        final id = (source as SamplePreviewImageSource).sampleId;
        return Future.value(images[id]);
      };

      Widget build(String sampleId) => localized(BeforeAfterView(
            filter: null,
            filterId: null,
            strength: 1.0,
            sampleSize: 16,
            imageSource: SamplePreviewImageSource(sampleId),
          ));

      await tester.pumpWidget(build('a'));
      await tester.pump();
      await tester.pump();
      expect(imageA.debugDisposed, isFalse);

      await tester.pumpWidget(build('b'));
      await tester.pump();
      await tester.pump();

      expect(imageB.debugDisposed, isFalse);
      expect(imageA.debugDisposed, isTrue,
          reason: 'imageSource の切り替えで差し替えられた旧 before は dispose される');
      expect(requestedSizes, [16, 16]);
    });

    testWidgets(
        'imageSource・sampleSize が同じままなら、無関係な更新（strength）は'
        '再読み込みしない（before の再利用）', (tester) async {
      late ui.Image stub;
      await tester.runAsync(() async {
        stub = await BeforeAfterView.generateSampleImage(4);
      });
      var callCount = 0;
      previewSourceImageLoader = (source, size) {
        callCount++;
        return Future.value(stub);
      };

      Widget build(double strength) => localized(BeforeAfterView(
            filter: null,
            filterId: null,
            strength: strength,
            sampleSize: 16,
            imageSource: const SamplePreviewImageSource('chart'),
          ));

      await tester.pumpWidget(build(1.0));
      await tester.pump();
      await tester.pump();
      expect(callCount, 1);

      await tester.pumpWidget(build(0.5));
      await tester.pump();
      await tester.pump();

      expect(callCount, 1, reason: 'imageSource が同じなら before は再利用されるべき');
      expect(stub.debugDisposed, isFalse);
    });

    testWidgets('imageSource が null（legacy）なら previewSourceImageLoader は呼ばれない',
        (tester) async {
      var called = false;
      previewSourceImageLoader = (source, size) {
        called = true;
        return BeforeAfterView.loadPreviewSourceImage(source, size);
      };

      await tester.pumpWidget(localized(const BeforeAfterView(
        filter: null,
        filterId: null,
        strength: 1.0,
        sampleSize: 16,
      )));
      await tester.pump();
      await tester.pump();

      expect(called, isFalse,
          reason: 'imageSource==null の legacy パスは sampleImageGenerator のまま');
    });
  });
}
