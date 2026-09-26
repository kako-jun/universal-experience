import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/l10n/l10n_extensions.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/services/filter_service.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';

/// BeforeAfterView の before/after 生成ロジックと描画カバレッジのテスト（#17）。
///
/// 静的ヘルパ（generateSampleImage / renderAfter / canRender）を直接検証する。
/// protanopia は ShaderFilter 経由で実描画でき、他フィルタは未描画
/// （null = プレースホルダ表示）であることを確認する。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('canRender 描画カバレッジ', () {
    test('protanopia / protanomaly / none は描画可能', () {
      expect(BeforeAfterView.canRender(ColorVisionType.none), isTrue);
      expect(BeforeAfterView.canRender(ColorVisionType.protanopia), isTrue);
      expect(BeforeAfterView.canRender(ColorVisionType.protanomaly), isTrue);
    });

    test('未実装フィルタは描画不可（プレースホルダ）', () {
      expect(BeforeAfterView.canRender(ColorVisionType.deuteranopia), isFalse);
      expect(BeforeAfterView.canRender(ColorVisionType.tritanopia), isFalse);
      expect(BeforeAfterView.canRender(ColorVisionType.achromatopsia), isFalse);
      expect(BeforeAfterView.canRender(ColorVisionType.deuteranomaly), isFalse);
      expect(BeforeAfterView.canRender(ColorVisionType.tritanomaly), isFalse);
    });
  });

  group('generateSampleImage', () {
    test('指定サイズの正方形画像を生成し PNG 化できる', () async {
      final img = await BeforeAfterView.generateSampleImage(64);
      expect(img.width, 64);
      expect(img.height, 64);
      final png = await encodeImagePng(img);
      expect(png, isNotNull);
      expect(png!.isNotEmpty, isTrue);
      img.dispose();
    });
  });

  group('renderAfter', () {
    late ui.Image src;

    setUp(() async {
      src = await BeforeAfterView.generateSampleImage(64);
    });

    tearDown(() {
      src.dispose();
    });

    test('none は元画像をそのまま返す', () async {
      final out = await BeforeAfterView.renderAfter(
        src,
        ColorVisionType.none,
        1.0,
      );
      expect(identical(out, src), isTrue);
    });

    test('protanopia は GPU 実描画で after 画像を生成する', () async {
      final out = await BeforeAfterView.renderAfter(
        src,
        ColorVisionType.protanopia,
        1.0,
      );
      expect(out, isNotNull);
      expect(out!.width, 64);
      expect(out.height, 64);

      // after が原画と異なる（実際にフィルタが効いている）ことを確認。
      final beforePng = await encodeImagePng(src);
      final afterPng = await encodeImagePng(out);
      expect(beforePng, isNotNull);
      expect(afterPng, isNotNull);
      expect(afterPng, isNot(equals(beforePng)));
      out.dispose();
    });

    test('protanomaly も protanopia 経路で描画できる', () async {
      final out = await BeforeAfterView.renderAfter(
        src,
        ColorVisionType.protanomaly,
        0.6,
      );
      expect(out, isNotNull);
      out!.dispose();
    });

    test(
        'protanomaly は推奨強度（0.6）で描画すると protanopia（1.0）と出力が異なる '
        '（#57: 以前は両方とも intensity 1.0 で描画され同一の見た目になっていた）', () async {
      final protanopiaOut = await BeforeAfterView.renderAfter(
        src,
        ColorVisionType.protanopia,
        recommendedStrength(ColorVisionType.protanopia),
      );
      final protanomalyOut = await BeforeAfterView.renderAfter(
        src,
        ColorVisionType.protanomaly,
        recommendedStrength(ColorVisionType.protanomaly),
      );
      expect(protanopiaOut, isNotNull);
      expect(protanomalyOut, isNotNull);

      final protanopiaPng = await encodeImagePng(protanopiaOut!);
      final protanomalyPng = await encodeImagePng(protanomalyOut!);
      expect(protanopiaPng, isNotNull);
      expect(protanomalyPng, isNotNull);
      expect(protanomalyPng, isNot(equals(protanopiaPng)));

      protanopiaOut.dispose();
      protanomalyOut.dispose();
    });

    test('未実装フィルタは null（プレースホルダ）を返す', () async {
      for (final type in [
        ColorVisionType.deuteranopia,
        ColorVisionType.tritanopia,
        ColorVisionType.achromatopsia,
        ColorVisionType.deuteranomaly,
        ColorVisionType.tritanomaly,
      ]) {
        final out = await BeforeAfterView.renderAfter(src, type, 1.0);
        expect(out, isNull, reason: '$type');
      }
    });
  });

  group('BeforeAfterView ウィジェット', () {
    // 画像生成 / GPU 描画は実 microtask 上で走るため runAsync 内でポンプし、
    // 目的テキストが現れるまで待つヘルパ。pumpAndSettle はロード/描画の
    // 非同期完了を待てない（かつアニメーションで収束しない）ため使わない。
    Future<void> pumpUntilText(WidgetTester tester, String text) async {
      await tester.runAsync(() async {
        for (var i = 0; i < 50; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          if (find.text(text).evaluate().isNotEmpty) return;
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump();
    }

    // BeforeAfterView は AppLocalizations.of(context) を読むため、テストでも
    // ローカライズ済みの MaterialApp（en 固定）に乗せる。期待文字列は en ARB を
    // lookup して取り、ハードコードしない (#18)。
    const enLocale = Locale('en');
    final en = lookupAppLocalizations(enLocale);

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

    testWidgets('protanopia で原画ラベルとフィルタ名ラベルの両ペインを出す', (tester) async {
      await tester.pumpWidget(
        localized(
          const BeforeAfterView(
            filterType: ColorVisionType.protanopia,
            intensity: 1.0,
            sampleSize: 32,
          ),
        ),
      );
      final protoName = colorVisionTypeName(en, ColorVisionType.protanopia);
      await pumpUntilText(tester, protoName);

      expect(find.text(en.previewPaneOriginal), findsOneWidget);
      expect(find.text(protoName), findsOneWidget);
    });

    testWidgets('未実装フィルタでは coming soon プレースホルダを出す', (tester) async {
      await tester.pumpWidget(
        localized(
          const BeforeAfterView(
            filterType: ColorVisionType.deuteranopia,
            intensity: 1.0,
            sampleSize: 32,
          ),
        ),
      );
      await pumpUntilText(tester, en.previewComingSoon);

      expect(find.text(en.previewComingSoon), findsOneWidget);
    });

    // #58: プレビューが GPU 画像をリークする／古い結果で上書きされる／Retina で
    // ぼける、の3点を再現・固定するリグレッションテスト。
    //
    // `sampleImageGenerator` / `afterImageRenderer`（`before_after_view.dart` が
    // 公開する widget test 用 seam）をフェイクに差し替え、応答の順序・タイミング・
    // 内容をテスト側で完全に制御する。dispose 検知は `ui.Image.debugDisposed` を使う
    // （実 GPU/toImage() が必要な画像生成そのものは `tester.runAsync` の中で1回だけ
    // 行い、以降はフェイクが `Future.value(...)` で即返すことで FakeAsync ゾーンの
    // 中でも安全に awaiter できるようにする）。
    group('生成の世代管理とリソース破棄 (#58)', () {
      tearDown(() {
        sampleImageGenerator = BeforeAfterView.generateSampleImage;
        afterImageRenderer = BeforeAfterView.renderAfter;
      });

      testWidgets('連続更新では最新の結果だけが残り、追い越された結果は dispose される', (tester) async {
        late ui.Image before1;
        late ui.Image afterOld, afterMid, afterNew;
        await tester.runAsync(() async {
          before1 = await BeforeAfterView.generateSampleImage(4);
          afterOld = await BeforeAfterView.generateSampleImage(4);
          afterMid = await BeforeAfterView.generateSampleImage(4);
          afterNew = await BeforeAfterView.generateSampleImage(4);
        });
        sampleImageGenerator = (size) => Future.value(before1);

        final completers = <Completer<ui.Image?>>[];
        afterImageRenderer = (source, type, strength) {
          final c = Completer<ui.Image?>();
          completers.add(c);
          return c.future;
        };

        Widget build(double intensity) => localized(
              BeforeAfterView(
                filterType: ColorVisionType.protanopia,
                intensity: intensity,
                sampleSize: 16,
              ),
            );

        // 3回連続で更新する（インテンシティのスライダー操作を想定）。まだ
        // どの要求も解決していない状態を作る。
        await tester.pumpWidget(build(0.1));
        await tester.pump();
        await tester.pumpWidget(build(0.2));
        await tester.pump();
        await tester.pumpWidget(build(0.3));
        await tester.pump();
        expect(completers.length, 3);

        // 遅い結果が後から届く状況を作る: 最新の要求を最初に解決し、
        // 最も古い要求を最後に解決する。
        completers[2].complete(afterNew);
        await tester.pump();
        completers[0].complete(afterOld);
        await tester.pump();
        completers[1].complete(afterMid);
        await tester.pump();

        expect(afterNew.debugDisposed, isFalse, reason: '最新の結果は表示されたままであるべき');
        expect(afterOld.debugDisposed, isTrue,
            reason: '追い越された古い結果は dispose されるべき');
        expect(afterMid.debugDisposed, isTrue,
            reason: '追い越された古い結果は dispose されるべき');
        expect(before1.debugDisposed, isFalse,
            reason: '_before はどの更新でも再利用され続けている');
      });

      testWidgets(
          '_after を差し替えると旧 _after は dispose される。_before と同一なら dispose されない',
          (tester) async {
        late ui.Image before1, after1, after2;
        await tester.runAsync(() async {
          before1 = await BeforeAfterView.generateSampleImage(4);
          after1 = await BeforeAfterView.generateSampleImage(4);
          after2 = await BeforeAfterView.generateSampleImage(4);
        });
        sampleImageGenerator = (size) => Future.value(before1);

        final responses = <Future<ui.Image?> Function(ui.Image)>[
          (source) =>
              Future.value(source), // phase1: none → _after は _before と同一
          (source) => Future.value(after1), // phase2: 実描画（_before とは別物）
          (source) => Future.value(after2), // phase3: 再度差し替え
        ];
        var callIndex = 0;
        afterImageRenderer = (source, type, strength) {
          final response = responses[callIndex];
          callIndex++;
          return response(source);
        };

        // phase1: filterType=none → _after は _before(before1) のエイリアス。
        await tester.pumpWidget(localized(const BeforeAfterView(
          filterType: ColorVisionType.none,
          intensity: 1.0,
          sampleSize: 16,
        )));
        await tester.pump();
        await tester.pump();

        // phase2: none → protanopia。旧 _after(=before1) は _before と同一なので
        // dispose されてはいけない（_before として使われ続けている）。
        await tester.pumpWidget(localized(const BeforeAfterView(
          filterType: ColorVisionType.protanopia,
          intensity: 1.0,
          sampleSize: 16,
        )));
        await tester.pump();
        await tester.pump();
        expect(before1.debugDisposed, isFalse,
            reason: '旧 _after が _before と同一のときは dispose してはいけない');
        expect(after1.debugDisposed, isFalse);

        // phase3: intensity だけ変更。旧 _after(after1) は _before と別物なので
        // 今度こそ dispose されるべき。
        await tester.pumpWidget(localized(const BeforeAfterView(
          filterType: ColorVisionType.protanopia,
          intensity: 0.5,
          sampleSize: 16,
        )));
        await tester.pump();
        await tester.pump();
        expect(after1.debugDisposed, isTrue,
            reason: '差し替えられた旧 _after（_before とは別物）は dispose されるべき');
        expect(after2.debugDisposed, isFalse);
        expect(before1.debugDisposed, isFalse, reason: '_before は終始再利用されている');
      });

      testWidgets('widget dispose 後に届いた結果は dispose され、setState は呼ばれない',
          (tester) async {
        late ui.Image before1, afterImg;
        await tester.runAsync(() async {
          before1 = await BeforeAfterView.generateSampleImage(4);
          afterImg = await BeforeAfterView.generateSampleImage(4);
        });
        sampleImageGenerator = (size) => Future.value(before1);

        final completer = Completer<ui.Image?>();
        afterImageRenderer = (source, type, strength) => completer.future;

        await tester.pumpWidget(localized(const BeforeAfterView(
          filterType: ColorVisionType.protanopia,
          intensity: 1.0,
          sampleSize: 16,
        )));
        await tester.pump();

        // まだ afterImageRenderer が解決していない間に widget を破棄する。
        await tester.pumpWidget(const SizedBox());

        // dispose 後に非同期結果が届く。setState が飛んで例外になったりせず、
        // 届いた画像が dispose されることを確認する。
        completer.complete(afterImg);
        await tester.pump();

        expect(afterImg.debugDisposed, isTrue);
        expect(before1.debugDisposed, isTrue);
      });
    });

    group('自動サイズ調整 (#58: Retina 対策)', () {
      tearDown(() {
        sampleImageGenerator = BeforeAfterView.generateSampleImage;
      });

      testWidgets('sampleSize 未指定時はペインの論理サイズ×devicePixelRatioで生成する',
          (tester) async {
        late ui.Image stub;
        await tester.runAsync(() async {
          stub = await BeforeAfterView.generateSampleImage(2);
        });
        final requestedSizes = <int>[];
        sampleImageGenerator = (size) {
          requestedSizes.add(size);
          return Future.value(stub);
        };

        tester.view.physicalSize = const Size(1000, 800);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(localized(const BeforeAfterView(
          filterType: ColorVisionType.none,
          intensity: 1.0,
        )));
        await tester.pump();
        await tester.pump();

        // 論理サイズ 500x400（物理1000x800 ÷ DPR2.0）、420 以上なので横並び。
        // ペイン論理幅 = (500-12)/2 = 244 → 244 * 2.0 = 488。
        expect(requestedSizes, [488]);
      });

      testWidgets('ペインが大きい場合は上限（1024）でクランプされる', (tester) async {
        late ui.Image stub;
        await tester.runAsync(() async {
          stub = await BeforeAfterView.generateSampleImage(2);
        });
        final requestedSizes = <int>[];
        sampleImageGenerator = (size) {
          requestedSizes.add(size);
          return Future.value(stub);
        };

        // 高さも十分に取り、AspectRatio(1) のペインが正方形になっても
        // オーバーフローしない（テストのレイアウト都合であり、上限判定の本質とは
        // 無関係）ようにする。
        tester.view.physicalSize = const Size(2200, 2200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(localized(const BeforeAfterView(
          filterType: ColorVisionType.none,
          intensity: 1.0,
        )));
        await tester.pump();
        await tester.pump();

        // ペイン論理幅 = (2200-12)/2 = 1094 → 上限 1024 でクランプ。
        expect(requestedSizes, [1024]);
      });

      testWidgets('ペインのリサイズはデバウンスされ、即座には再生成しない', (tester) async {
        late ui.Image stub;
        await tester.runAsync(() async {
          stub = await BeforeAfterView.generateSampleImage(2);
        });
        final requestedSizes = <int>[];
        sampleImageGenerator = (size) {
          requestedSizes.add(size);
          return Future.value(stub);
        };

        tester.view.physicalSize = const Size(1000, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(localized(const BeforeAfterView(
          filterType: ColorVisionType.none,
          intensity: 1.0,
        )));
        await tester.pump();
        await tester.pump();
        expect(requestedSizes.length, 1, reason: '初回生成');

        // ペインをリサイズする。
        tester.view.physicalSize = const Size(1400, 800);
        await tester.pump();
        expect(requestedSizes.length, 1, reason: 'デバウンス時間が経つまでは再生成しない');

        // デバウンス時間が経過すると再生成される。
        await tester.pump(const Duration(milliseconds: 301));
        expect(requestedSizes.length, 2, reason: 'デバウンス時間経過後に新しいサイズで再生成される');
      });
    });
  });
}
