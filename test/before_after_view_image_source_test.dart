// BeforeAfterView の PreviewImageSource 対応（#78）のテスト。
//
// before_after_view_test.dart の「生成の世代管理とリソース破棄 (#58)」群と
// 同じ規律を、新しい軸（imageSource の変更）について確認する。filter は
// 常に null にして afterImageRenderer の既定実装（source をそのまま返す）に
// 任せ、CpuVisionRenderer 実ブリッジを踏まずに前段（before 画像の読み込み）
// だけに集中する。

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/models/preview_image_source.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';

import 'support/sample_image_generator.dart';

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
      final source = await generateSampleImage(10);
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
        stub = await generateSampleImage(4);
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
        imageA = await generateSampleImage(4);
        imageB = await generateSampleImage(4);
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
        stub = await generateSampleImage(4);
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

    testWidgets('source を読み込み中に imageSource が A→B に切り替わっても、最終的に B が'
        '読み込まれる', (tester) async {
      // 回帰テスト: 旧実装は _rebuild の最後で
      // `_currentImageSource = widget.imageSource`（呼び出し時点の最新値）を
      // 読んでいた。A の読み込みが in-flight のまま widget.imageSource が B に
      // 進むと、A の画像を読み込んだのに `_currentImageSource` には B が
      // 記録されてしまい、その後 B への再読み込みが reuseBefore に「もう
      // 読み込み済み」と誤認されてスキップされる（実際に表示され続けるのは
      // A の画像のまま）。修正後は `_rebuild` の冒頭で捕まえた `source` だけを
      // 使うので、B は正しく再読み込みされる。
      late ui.Image imageA, imageB;
      await tester.runAsync(() async {
        imageA = await generateSampleImage(4);
        imageB = await generateSampleImage(4);
      });

      final completers = <String, Completer<ui.Image>>{
        'a': Completer<ui.Image>(),
        'b': Completer<ui.Image>(),
      };
      final requested = <String>[];
      previewSourceImageLoader = (source, size) {
        final id = (source as SamplePreviewImageSource).sampleId;
        requested.add(id);
        return completers[id]!.future;
      };

      Widget build(String sampleId) => localized(BeforeAfterView(
            filter: null,
            filterId: null,
            strength: 1.0,
            sampleSize: 16,
            imageSource: SamplePreviewImageSource(sampleId),
          ));

      // 1回目: imageSource=a。previewSourceImageLoader('a') が呼ばれるが、
      // まだ未解決のまま止める。
      await tester.pumpWidget(build('a'));
      await tester.pump();
      expect(requested, ['a']);

      // 2回目: imageSource を a→b に切り替える。1回目がまだ in-flight なので
      // _scheduleRebuild が集約するだけで、この時点ではまだ b の読み込みは
      // 始まらない。
      await tester.pumpWidget(build('b'));
      await tester.pump();
      expect(requested, ['a'], reason: '2回目は集約されているだけでまだ呼ばれていない');

      // ここで1回目（a）の読み込みを解決する。widget.imageSource は既に b に
      // 進んでいるが、_rebuild はこの呼び出しの冒頭で捕まえた a を使うべき。
      completers['a']!.complete(imageA);
      await tester.pump();
      await tester.pump();

      // 集約されていた b への要求が続けて走り始めるはず。
      expect(requested, ['a', 'b'],
          reason: '_currentImageSource が正しく a として記録されていれば、b の'
              '再読み込みが reuseBefore で誤ってスキップされない');

      completers['b']!.complete(imageB);
      await tester.pump();
      await tester.pump();

      expect(imageB.debugDisposed, isFalse);
      expect(imageA.debugDisposed, isTrue,
          reason: '最終的に b の画像に差し替わり、a は dispose される');
    });
  });
}
