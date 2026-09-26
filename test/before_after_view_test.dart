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

/// `_rebuild` は例外を `FlutterError.reportError` で報告するようになった
/// （#58 レビュー nit-1）。意図的に失敗を起こすテストがそれで落ちないよう、
/// `FlutterError.onError` を収集用に差し替えて元に戻すためのヘルパ。
///
/// `group`/`setUp` ではなく各テスト本体の中で呼ぶこと:
/// `TestWidgetsFlutterBinding` が独自の `onError`（失敗を検知してテストを落とす）
/// を仕込むタイミングが `setUp` より後（テスト本体に入ってから）なので、
/// `setUp` で差し替えても `testWidgets` 開始時に上書きされてしまい効かない。
List<FlutterErrorDetails> suppressFlutterErrorReporting() {
  final reported = <FlutterErrorDetails>[];
  final originalOnError = FlutterError.onError;
  FlutterError.onError = reported.add;
  addTearDown(() => FlutterError.onError = originalOnError);
  return reported;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('canRender 描画カバレッジ', () {
    test('全 ColorVisionType が描画可能になった（#59）', () {
      for (final type in ColorVisionType.values) {
        expect(BeforeAfterView.canRender(type), isTrue, reason: '$type');
      }
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

    test('deuteranopia / tritanopia / achromatopsia も GPU 実描画で after 画像を'
        '生成する（#59）', () async {
      for (final type in [
        ColorVisionType.deuteranopia,
        ColorVisionType.tritanopia,
        ColorVisionType.achromatopsia,
      ]) {
        final out = await BeforeAfterView.renderAfter(src, type, 1.0);
        expect(out, isNotNull, reason: '$type');
        expect(out!.width, 64, reason: '$type');
        expect(out.height, 64, reason: '$type');

        final beforePng = await encodeImagePng(src);
        final afterPng = await encodeImagePng(out);
        expect(afterPng, isNot(equals(beforePng)), reason: '$type');
        out.dispose();
      }
    });

    test(
        'deuteranomaly/tritanomaly は推奨強度で描画すると対応する -opia（1.0）と '
        '出力が異なる（#59。#57 の protanomaly と同じ不変条件を残り2型にも広げる）',
        () async {
      final pairs = <ColorVisionType, ColorVisionType>{
        ColorVisionType.deuteranomaly: ColorVisionType.deuteranopia,
        ColorVisionType.tritanomaly: ColorVisionType.tritanopia,
      };
      for (final entry in pairs.entries) {
        final anomalyType = entry.key;
        final opiaType = entry.value;

        final opiaOut = await BeforeAfterView.renderAfter(
          src,
          opiaType,
          recommendedStrength(opiaType),
        );
        final anomalyOut = await BeforeAfterView.renderAfter(
          src,
          anomalyType,
          recommendedStrength(anomalyType),
        );
        expect(opiaOut, isNotNull, reason: '$opiaType');
        expect(anomalyOut, isNotNull, reason: '$anomalyType');

        final opiaPng = await encodeImagePng(opiaOut!);
        final anomalyPng = await encodeImagePng(anomalyOut!);
        expect(anomalyPng, isNot(equals(opiaPng)), reason: '$anomalyType');

        opiaOut.dispose();
        anomalyOut.dispose();
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

    testWidgets(
        'deuteranopia でも coming soon プレースホルダは出ず、フィルタ名ラベルの'
        'ペインを出す（#59: canRender/renderAfter の対象拡大）', (tester) async {
      await tester.pumpWidget(
        localized(
          const BeforeAfterView(
            filterType: ColorVisionType.deuteranopia,
            intensity: 1.0,
            sampleSize: 32,
          ),
        ),
      );
      final deuteranopiaName =
          colorVisionTypeName(en, ColorVisionType.deuteranopia);
      await pumpUntilText(tester, deuteranopiaName);

      expect(find.text(en.previewPaneOriginal), findsOneWidget);
      expect(find.text(deuteranopiaName), findsOneWidget);
      expect(find.text(en.previewComingSoon), findsNothing);
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

      testWidgets(
          'auto モードで初回生成が完了する前に filterType が変わっても、最新の結果だけが残る '
          '(#58 レビュー M1)', (tester) async {
        late ui.Image before1, afterOld, afterNew;
        await tester.runAsync(() async {
          before1 = await BeforeAfterView.generateSampleImage(4);
          afterOld = await BeforeAfterView.generateSampleImage(4);
          afterNew = await BeforeAfterView.generateSampleImage(4);
        });
        sampleImageGenerator = (size) => Future.value(before1);

        final completers = <Completer<ui.Image?>>[];
        afterImageRenderer = (source, type, strength) {
          final c = Completer<ui.Image?>();
          completers.add(c);
          return c.future;
        };

        tester.view.physicalSize = const Size(1000, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        // sampleSize 未指定 = auto モード。初回生成の renderer がまだ解決して
        // いないうちに filterType を変える。
        await tester.pumpWidget(localized(const BeforeAfterView(
          filterType: ColorVisionType.protanopia,
          intensity: 1.0,
        )));
        await tester.pump();
        expect(completers.length, 1);

        await tester.pumpWidget(localized(const BeforeAfterView(
          filterType: ColorVisionType.deuteranopia,
          intensity: 1.0,
        )));
        await tester.pump();
        expect(completers.length, 2,
            reason: '修正前は _currentSampleSize が null のため didUpdateWidget が '
                'size=null で再生成をスキップしていた（古いフィルタの結果が残る）');

        // 遅い方（1つ目）が後から届く。
        completers[1].complete(afterNew);
        await tester.pump();
        completers[0].complete(afterOld);
        await tester.pump();

        expect(afterNew.debugDisposed, isFalse);
        expect(afterOld.debugDisposed, isTrue);
      });

      testWidgets(
          '_before を再利用するとき renderer には複製が渡され、複製は正しく dispose される '
          '(#58 レビュー S2)', (tester) async {
        late ui.Image before1, realAfter;
        await tester.runAsync(() async {
          before1 = await BeforeAfterView.generateSampleImage(4);
          realAfter = await BeforeAfterView.generateSampleImage(4);
        });
        sampleImageGenerator = (size) => Future.value(before1);

        ui.Image? capturedRendererInput;
        var callIndex = 0;
        afterImageRenderer = (source, type, strength) {
          callIndex++;
          if (callIndex == 1) {
            return Future.value(source); // none 相当: そのまま返す
          }
          capturedRendererInput = source;
          return Future.value(realAfter);
        };

        // 1回目: filterType=none で _before=_after=before1 を確定させる。
        await tester.pumpWidget(localized(const BeforeAfterView(
          filterType: ColorVisionType.none,
          intensity: 1.0,
          sampleSize: 16,
        )));
        await tester.pump();
        await tester.pump();

        // 2回目: サイズが変わらないので _before(before1) が再利用される。
        // renderer に渡されるのは before1 そのものではなく複製であるべき
        // （await 中に他の更新で _before が dispose される可能性があるため）。
        await tester.pumpWidget(localized(const BeforeAfterView(
          filterType: ColorVisionType.protanopia,
          intensity: 1.0,
          sampleSize: 16,
        )));
        await tester.pump();
        await tester.pump();

        expect(capturedRendererInput, isNotNull);
        expect(identical(capturedRendererInput, before1), isFalse,
            reason: '_before と同一オブジェクトを渡すと、await 中の dispose に対して無防備になる');
        // 複製は用済みになったら dispose される（リークしない）。realAfter とは
        // 別オブジェクトなので二重 dispose にもならない。
        expect(capturedRendererInput!.debugDisposed, isTrue);
        expect(before1.debugDisposed, isFalse,
            reason: '_before として使われ続けているので dispose されない');
        expect(realAfter.debugDisposed, isFalse);
      });

      testWidgets(
          '捨てられる経路では複製が無条件に dispose される'
          '（after が複製と同一な場合の漏れ回帰） (#58 レビュー SHOULD-2)', (tester) async {
        late ui.Image before1;
        await tester.runAsync(() async {
          before1 = await BeforeAfterView.generateSampleImage(4);
        });
        sampleImageGenerator = (size) => Future.value(before1);

        final completers = <Completer<ui.Image?>>[];
        final capturedInputs = <ui.Image>[];
        // none 相当: 渡された source（reuse 時は複製）をそのまま返すフェイク。
        afterImageRenderer = (source, type, strength) {
          capturedInputs.add(source);
          final c = Completer<ui.Image?>();
          completers.add(c);
          return c.future;
        };

        // 1回目: _before がまだ無いので複製されない。まず確定させ、以後の
        // reuse を発生させる土台を作る。
        await tester.pumpWidget(localized(const BeforeAfterView(
          filterType: ColorVisionType.none,
          intensity: 1.0,
          sampleSize: 16,
        )));
        await tester.pump();
        expect(completers.length, 1);
        completers[0].complete(capturedInputs[0]);
        await tester.pump();
        expect(before1.debugDisposed, isFalse);

        // 2回目・3回目: サイズは変わらないので _before(before1) が再利用され、
        // renderer には複製が渡る。3回目を先に解決し、2回目（追い越された方）
        // が、渡された複製をそのまま返す形であとから解決する。
        await tester.pumpWidget(localized(const BeforeAfterView(
          filterType: ColorVisionType.none,
          intensity: 0.4,
          sampleSize: 16,
        )));
        await tester.pump();
        await tester.pumpWidget(localized(const BeforeAfterView(
          filterType: ColorVisionType.none,
          intensity: 0.6,
          sampleSize: 16,
        )));
        await tester.pump();
        expect(completers.length, 3);

        final staleClone = capturedInputs[1];
        final freshClone = capturedInputs[2];
        expect(identical(staleClone, before1), isFalse);
        expect(identical(freshClone, before1), isFalse);

        completers[2].complete(freshClone); // 最新を先に確定
        await tester.pump();
        completers[1].complete(staleClone); // 追い越された方があとから、
        // 複製をそのまま返す形で解決する。
        await tester.pump();

        expect(staleClone.debugDisposed, isTrue,
            reason: '追い越された経路の複製は、after と同一でも無条件に dispose されるべき'
                '（以前は両方 false になる組み合わせで dispose 漏れが起きていた）');
        expect(before1.debugDisposed, isFalse);
        expect(freshClone.debugDisposed, isFalse);
      });
    });

    group('自動サイズ調整 (#58: Retina 対策)', () {
      tearDown(() {
        sampleImageGenerator = BeforeAfterView.generateSampleImage;
        // Q2 のテストが afterImageRenderer を「解決しない」フェイクへ差し替える
        // ため、後続テストへ漏れないよう明示的に戻す。
        afterImageRenderer = BeforeAfterView.renderAfter;
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

      testWidgets('ペインが大きい場合は上限（2048、#58レビューN5）でクランプされる', (tester) async {
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
        tester.view.physicalSize = const Size(4200, 4200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(localized(const BeforeAfterView(
          filterType: ColorVisionType.none,
          intensity: 1.0,
        )));
        await tester.pump();
        await tester.pump();

        // ペイン論理幅 = (4200-12)/2 = 2094 → 上限 2048 でクランプ。
        expect(requestedSizes, [2048]);
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

      testWidgets(
          'リサイズで _before を作り直すと旧 before は dispose され、新 before が使われる '
          '(#58 レビュー S3)', (tester) async {
        late ui.Image beforeA, beforeB;
        await tester.runAsync(() async {
          beforeA = await BeforeAfterView.generateSampleImage(4);
          beforeB = await BeforeAfterView.generateSampleImage(4);
        });
        // サイズごとに別オブジェクトを返すフェイク（本番の generateSampleImage が
        // 毎回新しいオブジェクトを返すのを模す）。
        final imagesBySize = {494: beforeA, 694: beforeB};
        final requestedSizes = <int>[];
        sampleImageGenerator = (size) {
          requestedSizes.add(size);
          return Future.value(imagesBySize[size]!);
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
        expect(requestedSizes, [494]);
        expect(beforeA.debugDisposed, isFalse);

        // ペインをリサイズし、デバウンス時間を経過させる。
        tester.view.physicalSize = const Size(1400, 800);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 301));

        expect(requestedSizes, [494, 694]);
        expect(beforeA.debugDisposed, isTrue,
            reason: '旧 before は作り直し後に dispose される');
        expect(beforeB.debugDisposed, isFalse, reason: '新しい before は使用中');
      });

      testWidgets(
          'リサイズのデバウンス中に intensity が変わっても、リサイズ先のサイズが使われる '
          '(#58 レビュー S4)', (tester) async {
        late ui.Image beforeA, beforeB;
        await tester.runAsync(() async {
          beforeA = await BeforeAfterView.generateSampleImage(4);
          beforeB = await BeforeAfterView.generateSampleImage(4);
        });
        final imagesBySize = {494: beforeA, 694: beforeB};
        final requestedSizes = <int>[];
        sampleImageGenerator = (size) {
          requestedSizes.add(size);
          return Future.value(imagesBySize[size]!);
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
        expect(requestedSizes, [494]);

        // リサイズしてデバウンスタイマーを起動するが、まだ発火させない。
        tester.view.physicalSize = const Size(1400, 800);
        await tester.pump();
        expect(requestedSizes, [494], reason: 'デバウンス中はまだ再生成されない');

        // デバウンスタイマーが発火する前に intensity を変える
        // （スライダー操作中を想定）。
        await tester.pumpWidget(localized(const BeforeAfterView(
          filterType: ColorVisionType.none,
          intensity: 0.5,
        )));
        await tester.pump();

        // #58 レビュー M1/S4: didUpdateWidget は _pendingResizeSampleSize(694) を
        // 使うべきで、古い _currentSampleSize(494) を使ってはいけない。
        expect(requestedSizes, [494, 694]);
        expect(beforeB.debugDisposed, isFalse);
      });

      testWidgets('制約が無限大のときは論理サイズ256にフォールバックする (#58 レビュー Q2)', (tester) async {
        late ui.Image stub;
        await tester.runAsync(() async {
          stub = await BeforeAfterView.generateSampleImage(2);
        });
        final requestedSizes = <int>[];
        sampleImageGenerator = (size) {
          requestedSizes.add(size);
          return Future.value(stub);
        };
        // afterImageRenderer をあえて解決しないままにして _loading を true に
        // 固定し、無限大幅では非対応の Row/Expanded 本体レイアウトまで到達
        // させない（このテストの対象はサンプル生成サイズのフォールバックのみ）。
        afterImageRenderer =
            (source, type, strength) => Completer<ui.Image?>().future;

        tester.view.physicalSize = const Size(1000, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ListView(
              scrollDirection: Axis.horizontal,
              children: const [
                SizedBox(
                  height: 400,
                  child: BeforeAfterView(
                    filterType: ColorVisionType.none,
                    intensity: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ));
        await tester.pump();
        await tester.pump();

        // 論理サイズ256（フォールバック）× DPR1.0 = 256。
        expect(requestedSizes, [256]);
      });

      testWidgets(
          'リサイズが A→B→A と元に戻ると、B 用のデバウンスタイマーは破棄され'
          '再生成されない (#58 レビュー N1)', (tester) async {
        late ui.Image stub;
        await tester.runAsync(() async {
          stub = await BeforeAfterView.generateSampleImage(2);
        });
        final requestedSizes = <int>[];
        sampleImageGenerator = (size) {
          requestedSizes.add(size);
          return Future.value(stub);
        };

        tester.view.physicalSize = const Size(1000, 800); // target A=494
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(localized(const BeforeAfterView(
          filterType: ColorVisionType.none,
          intensity: 1.0,
        )));
        await tester.pump();
        await tester.pump();
        expect(requestedSizes, [494]);

        // A→B: リサイズしてデバウンスタイマーを起動する（まだ発火させない）。
        tester.view.physicalSize = const Size(1400, 800); // target B=694
        await tester.pump();
        expect(requestedSizes, [494]);

        // B→A: タイマー発火前に元のサイズへ戻す。
        tester.view.physicalSize = const Size(1000, 800);
        await tester.pump();

        // デバウンス時間を経過させても、694 へは作り直されない。
        await tester.pump(const Duration(milliseconds: 301));
        expect(requestedSizes, [494], reason: 'A→B→A で戻ったら B 用のタイマーは破棄されるべき');
      });

      testWidgets(
          '明示サイズへ切り替えると、保留中のリサイズタイマーは意味を持たなくなる '
          '(#58 レビュー N2)', (tester) async {
        late ui.Image autoStub, explicitStub;
        await tester.runAsync(() async {
          autoStub = await BeforeAfterView.generateSampleImage(2);
          explicitStub = await BeforeAfterView.generateSampleImage(2);
        });
        final requestedSizes = <int>[];
        sampleImageGenerator = (size) {
          requestedSizes.add(size);
          return Future.value(size == 999 ? explicitStub : autoStub);
        };

        tester.view.physicalSize = const Size(1000, 800); // auto target 494
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(localized(const BeforeAfterView(
          filterType: ColorVisionType.none,
          intensity: 1.0,
        )));
        await tester.pump();
        await tester.pump();
        expect(requestedSizes, [494]);

        // リサイズしてデバウンスタイマーを起動する（まだ発火させない）。
        tester.view.physicalSize = const Size(1400, 800); // auto target 694
        await tester.pump();
        expect(requestedSizes, [494]);

        // 明示サイズへ切り替える。
        await tester.pumpWidget(localized(const BeforeAfterView(
          filterType: ColorVisionType.none,
          intensity: 1.0,
          sampleSize: 999,
        )));
        await tester.pump();
        expect(requestedSizes, [494, 999]);

        // デバウンス時間を経過させても、694 へは作り直されない
        // （保留中だった auto 用タイマーはキャンセルされ、発火時にも
        // sampleSize==null を再確認するため二重に安全）。
        await tester.pump(const Duration(milliseconds: 301));
        expect(requestedSizes, [494, 999],
            reason: '明示サイズへ切り替えたら auto 用タイマーは無効化されるべき');
      });

      testWidgets(
          '失敗直後のユーザー操作は、古い成功サイズではなく直近の失敗サイズで'
          '再試行する（ちらつき防止） (#58 レビュー nit-3)', (tester) async {
        suppressFlutterErrorReporting();

        late ui.Image goodA;
        await tester.runAsync(() async {
          goodA = await BeforeAfterView.generateSampleImage(4);
        });
        final requestedSizes = <int>[];
        sampleImageGenerator = (size) {
          requestedSizes.add(size);
          if (size == 494) return Future.value(goodA); // 初回サイズは成功。
          // リサイズ後のサイズ（694）はアセット欠落等で恒久的に失敗する。
          return Future<ui.Image>.error(StateError('boom'));
        };

        tester.view.physicalSize = const Size(1000, 800); // target 494
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(localized(const BeforeAfterView(
          filterType: ColorVisionType.none,
          intensity: 1.0,
        )));
        await tester.pump();
        await tester.pump();
        expect(requestedSizes, [494]);

        // リサイズすると新サイズ(694)での生成が失敗する
        // （_currentSampleSize=494 のまま、_failedSampleSize=694 になる）。
        tester.view.physicalSize = const Size(1400, 800); // target 694
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 301)); // デバウンス発火
        expect(requestedSizes, [494, 694]);

        // ここでユーザー操作（intensity 変更）が入る。_currentSampleSize
        // (494、もう画面のサイズに合っていない) ではなく、直近の失敗サイズ
        // (694、現在のレイアウトに合っているサイズ) で再試行するべき。494 で
        // 再試行すると、694 用の失敗表示から一瞬 494 の古い画像に戻ってまた
        // 694 に切り替わる、というちらつきが起きる。
        await tester.pumpWidget(localized(const BeforeAfterView(
          filterType: ColorVisionType.none,
          intensity: 0.5,
        )));
        await tester.pump();

        expect(requestedSizes, [494, 694, 694],
            reason: '494（古い成功サイズ）ではなく694（直近の失敗サイズ）で'
                '再試行するべき');
      });
    });

    group('例外処理と復帰 (#58 レビュー S1)', () {
      tearDown(() {
        sampleImageGenerator = BeforeAfterView.generateSampleImage;
        afterImageRenderer = BeforeAfterView.renderAfter;
      });

      testWidgets(
          'generator/renderer の例外は FlutterError.reportError で報告される '
          '(#58 レビュー nit-1)', (tester) async {
        final reportedErrors = suppressFlutterErrorReporting();
        sampleImageGenerator = (size) => Future<ui.Image>.error(
              StateError('boom: generator'),
              StackTrace.current,
            );

        await tester.pumpWidget(localized(const BeforeAfterView(
          filterType: ColorVisionType.protanopia,
          intensity: 1.0,
          sampleSize: 16,
        )));
        await tester.pump();
        await tester.pump();

        expect(reportedErrors, hasLength(1));
        expect(reportedErrors.single.exception, isA<StateError>());
        expect(reportedErrors.single.library, 'before_after_view');

        // renderer 側の例外も同様に報告される。
        late ui.Image goodBefore;
        await tester.runAsync(() async {
          goodBefore = await BeforeAfterView.generateSampleImage(4);
        });
        sampleImageGenerator = (size) => Future.value(goodBefore);
        afterImageRenderer = (source, type, strength) =>
            Future<ui.Image?>.error(StateError('boom: renderer'));

        await tester.pumpWidget(localized(const BeforeAfterView(
          filterType: ColorVisionType.protanopia,
          intensity: 0.5,
          sampleSize: 16,
        )));
        await tester.pump();
        await tester.pump();

        expect(reportedErrors, hasLength(2));
        expect(reportedErrors.last.exception, isA<StateError>());
        expect(reportedErrors.last.library, 'before_after_view');
      });

      testWidgets('generator が例外を投げても loading が固着せず、次の更新で再試行できる',
          (tester) async {
        suppressFlutterErrorReporting();
        late ui.Image goodBefore, goodAfter;
        await tester.runAsync(() async {
          goodBefore = await BeforeAfterView.generateSampleImage(4);
          goodAfter = await BeforeAfterView.generateSampleImage(4);
        });
        var generatorCallCount = 0;
        sampleImageGenerator = (size) {
          generatorCallCount++;
          if (generatorCallCount == 1) {
            return Future<ui.Image>.error(StateError('boom'));
          }
          return Future.value(goodBefore);
        };
        afterImageRenderer =
            (source, type, strength) => Future.value(goodAfter);

        final en = lookupAppLocalizations(const Locale('en'));

        await tester.pumpWidget(localized(const BeforeAfterView(
          filterType: ColorVisionType.protanopia,
          intensity: 1.0,
          sampleSize: 16,
        )));
        await tester.pump();
        await tester.pump();

        // loading が固着せず、「準備中」表示のままにならない。
        expect(find.text(en.previewPreparing), findsNothing);

        // 次の更新（intensity 変更）で再試行され、今度は成功する。
        await tester.pumpWidget(localized(const BeforeAfterView(
          filterType: ColorVisionType.protanopia,
          intensity: 0.5,
          sampleSize: 16,
        )));
        await tester.pump();
        await tester.pump();

        expect(generatorCallCount, 2);
        expect(goodAfter.debugDisposed, isFalse);
      });

      testWidgets('renderer が例外を投げても新規生成した before はリークせず、次の更新で再試行できる',
          (tester) async {
        suppressFlutterErrorReporting();
        late ui.Image before1, before2, goodAfter;
        await tester.runAsync(() async {
          before1 = await BeforeAfterView.generateSampleImage(4);
          before2 = await BeforeAfterView.generateSampleImage(4);
          goodAfter = await BeforeAfterView.generateSampleImage(4);
        });
        final generatedBefores = [before1, before2];
        var generatorCallCount = 0;
        sampleImageGenerator =
            (size) => Future.value(generatedBefores[generatorCallCount++]);

        var rendererCallCount = 0;
        afterImageRenderer = (source, type, strength) {
          rendererCallCount++;
          if (rendererCallCount == 1) {
            return Future<ui.Image?>.error(StateError('boom'));
          }
          return Future.value(goodAfter);
        };

        final en = lookupAppLocalizations(const Locale('en'));

        await tester.pumpWidget(localized(const BeforeAfterView(
          filterType: ColorVisionType.protanopia,
          intensity: 1.0,
          sampleSize: 16,
        )));
        await tester.pump();
        await tester.pump();

        // renderer が失敗しても、新規生成した before（1回目）はリークせず
        // dispose される。
        expect(before1.debugDisposed, isTrue);
        expect(find.text(en.previewPreparing), findsNothing);

        await tester.pumpWidget(localized(const BeforeAfterView(
          filterType: ColorVisionType.protanopia,
          intensity: 0.5,
          sampleSize: 16,
        )));
        await tester.pump();
        await tester.pump();

        expect(rendererCallCount, 2);
        expect(goodAfter.debugDisposed, isFalse);
      });

      testWidgets(
          'auto モードで恒久的な失敗が続いても busy loop にならず、'
          'ユーザー操作（intensity 変更）で再試行して成功する '
          '(#58 レビュー MUST-1)', (tester) async {
        suppressFlutterErrorReporting();
        late ui.Image goodBefore, goodAfter;
        await tester.runAsync(() async {
          goodBefore = await BeforeAfterView.generateSampleImage(4);
          goodAfter = await BeforeAfterView.generateSampleImage(4);
        });
        var generatorCallCount = 0;
        sampleImageGenerator = (size) {
          generatorCallCount++;
          if (generatorCallCount == 1) {
            // アセットが無い/シェーダのコンパイルが失敗する、のような
            // 恒久的な失敗を模す（一時的な失敗ではなく、以後もずっと失敗する）。
            return Future<ui.Image>.error(StateError('boom'));
          }
          return Future.value(goodBefore);
        };
        afterImageRenderer =
            (source, type, strength) => Future.value(goodAfter);

        tester.view.physicalSize = const Size(1000, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(localized(const BeforeAfterView(
          filterType: ColorVisionType.protanopia,
          intensity: 1.0,
        )));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        expect(generatorCallCount, 1);

        // 何もしなくても busy loop で再試行し続けない
        // （1秒分ポンプしても呼び出し回数は変わらない）。
        await tester.pump(const Duration(seconds: 1));
        expect(generatorCallCount, 1,
            reason: '恒久的な失敗は自動では再試行しない（busy loop 回帰）');

        // ユーザー操作（intensity 変更）で再試行され、今度は成功する。
        await tester.pumpWidget(localized(const BeforeAfterView(
          filterType: ColorVisionType.protanopia,
          intensity: 0.5,
        )));
        await tester.pump();
        await tester.pump();

        expect(generatorCallCount, 2);
        expect(goodAfter.debugDisposed, isFalse);
      });

      testWidgets(
          'リサイズ後の恒久的な失敗も 300ms 周期の busy loop にならない '
          '(#58 レビュー MUST-1)', (tester) async {
        suppressFlutterErrorReporting();
        late ui.Image goodBefore;
        await tester.runAsync(() async {
          goodBefore = await BeforeAfterView.generateSampleImage(4);
        });
        var generatorCallCount = 0;
        final requestedSizes = <int>[];
        sampleImageGenerator = (size) {
          generatorCallCount++;
          requestedSizes.add(size);
          if (size == 494) {
            return Future.value(goodBefore); // 初回サイズは成功させる。
          }
          // リサイズ後のサイズ（694）はアセット欠落等で恒久的に失敗する。
          return Future<ui.Image>.error(StateError('boom'));
        };

        tester.view.physicalSize = const Size(1000, 800); // target 494
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(localized(const BeforeAfterView(
          filterType: ColorVisionType.none,
          intensity: 1.0,
        )));
        await tester.pump();
        await tester.pump();
        expect(requestedSizes, [494]);

        // リサイズすると新サイズ(694)での生成が失敗する。
        tester.view.physicalSize = const Size(1400, 800); // target 694
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 301)); // デバウンス発火
        expect(requestedSizes, [494, 694]);

        final callCountAfterFirstFailure = generatorCallCount;
        // 300ms 周期を何度分過ぎても、694 への再試行が繰り返されない
        // （busy loop 回帰）。
        await tester.pump(const Duration(seconds: 2));
        expect(generatorCallCount, callCountAfterFirstFailure,
            reason: '恒久的な失敗は300ms周期で再試行し続けない');
        expect(requestedSizes, [494, 694]);
      });
    });

    group('失敗の表示と復帰 (#58 レビュー SHOULD-1)', () {
      tearDown(() {
        sampleImageGenerator = BeforeAfterView.generateSampleImage;
        afterImageRenderer = BeforeAfterView.renderAfter;
      });

      testWidgets(
          '最新世代が失敗すると _after が null になり previewFailed 表示になる。'
          '旧 _after は dispose され、次に成功すると元に戻る', (tester) async {
        suppressFlutterErrorReporting();
        late ui.Image goodBefore, goodAfter1, goodAfter2;
        await tester.runAsync(() async {
          goodBefore = await BeforeAfterView.generateSampleImage(4);
          goodAfter1 = await BeforeAfterView.generateSampleImage(4);
          goodAfter2 = await BeforeAfterView.generateSampleImage(4);
        });
        sampleImageGenerator = (size) => Future.value(goodBefore);

        var rendererCallCount = 0;
        afterImageRenderer = (source, type, strength) {
          rendererCallCount++;
          if (rendererCallCount == 1) return Future.value(goodAfter1);
          if (rendererCallCount == 2) {
            return Future<ui.Image?>.error(StateError('boom'));
          }
          return Future.value(goodAfter2);
        };

        final en = lookupAppLocalizations(const Locale('en'));

        // 1回目: 成功して goodAfter1 が表示される。
        await tester.pumpWidget(localized(const BeforeAfterView(
          filterType: ColorVisionType.protanopia,
          intensity: 1.0,
          sampleSize: 16,
        )));
        await tester.pump();
        await tester.pump();
        expect(find.text(en.previewFailed), findsNothing);

        // 2回目: renderer が失敗する。
        await tester.pumpWidget(localized(const BeforeAfterView(
          filterType: ColorVisionType.protanopia,
          intensity: 0.5,
          sampleSize: 16,
        )));
        await tester.pump();
        await tester.pump();

        expect(find.text(en.previewFailed), findsOneWidget);
        expect(goodAfter1.debugDisposed, isTrue,
            reason: '失敗したら旧 _after は dispose される');
        expect(goodBefore.debugDisposed, isFalse);

        // 3回目: 成功して復帰する。
        await tester.pumpWidget(localized(const BeforeAfterView(
          filterType: ColorVisionType.protanopia,
          intensity: 0.6,
          sampleSize: 16,
        )));
        await tester.pump();
        await tester.pump();

        expect(find.text(en.previewFailed), findsNothing);
        expect(goodAfter2.debugDisposed, isFalse);
      });
    });
  });
}
