import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/l10n/l10n_extensions.dart';
import 'package:universal_experience/rendering/cpu_vision_renderer.dart';
import 'package:universal_experience/services/export_service.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';

/// BeforeAfterView の before/after 生成ロジックと描画カバレッジのテスト（#17）。
///
/// 静的ヘルパ（generateSampleImage / renderAfter）を直接検証する。
///
/// #60: BeforeAfterView は `VisionFilterState` の選択（[VisionFilter]・payload・
/// strength）を唯一の正本にするよう配線された（home_screen.dart 側）。この
/// widget 自身はもう `ColorVisionType` を知らず、[filter]（nullable な
/// [VisionFilter]）・[filterId]（カタログ id、caption/ラベル解決用）・
/// [strength] を受け取るだけの presentational widget になった。`ColorVisionType`
/// → `VisionFilter` のマッピング契約（anomaly は base -opia と同一の
/// `VisionFilter`、等）は `test/filter_service_test.dart` が検証する
/// （`visionFilterForColorVisionType`）ので、ここでは重複させない。
///
/// `renderAfter` は実ブリッジ（`applyVisionCpuRgba8`）を必要とする
/// [CpuVisionRenderer.applier] へ委譲するため（#85）、`flutter test`（native lib
/// 未ロード）では実際の CPU 描画は呼べない。widget test 群は
/// [CpuVisionRenderer.applier] をフェイクに差し替える。実ブリッジでの実描画は
/// `integration_test/cpu_preview_all_filters_test.dart`（CI）が担う。
///
/// #85 レビュー S3/S4 で以下を変更した:
/// - CPU プレビューは固定の正準サイズ（[BeforeAfterView.canonicalSampleSize]）
///   で描画し、ペインの論理サイズ・devicePixelRatio には依存しない。旧
///   `group('自動サイズ調整 (#58: Retina 対策)', ...)`（DPR 連動・リサイズの
///   デバウンス）はこの仕様変更で丸ごと不要になったため削除した。
/// - 連続する `_rebuild` 要求は 1 本だけ実行し、後続は最新の 1 件だけ保留する
///   （[BeforeAfterView] の `_scheduleRebuild`）。これにより、旧
///   `sampleImageGenerator`/`afterImageRenderer` を使った「複数の要求が本当に
///   同時に実行中」を前提にしたテスト（追い越し・discard 経路）の一部は、
///   その状況自体がもう production コードから起こり得なくなったため、
///   直列化を確認する形に書き換えるか削除した（該当箇所にコメントで残す）。

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
    late ui.Image fakeOut;

    setUp(() async {
      src = await BeforeAfterView.generateSampleImage(4);
      fakeOut = await BeforeAfterView.generateSampleImage(4);
    });

    tearDown(() {
      src.dispose();
      if (!identical(fakeOut, src)) fakeOut.dispose();
      // #85: renderAfter は CpuVisionRenderer.applier（実ブリッジ必須）へ委譲する
      // ため、各テストで差し替えたフェイクを既定へ戻す。
      CpuVisionRenderer.applier = CpuVisionRenderer.apply;
    });

    test('filter が null なら CpuVisionRenderer を呼ばず元画像をそのまま返す', () async {
      var called = false;
      CpuVisionRenderer.applier = (source, filter, strength) async {
        called = true;
        return fakeOut;
      };

      final out = await BeforeAfterView.renderAfter(src, null, 1.0);
      expect(identical(out, src), isTrue);
      expect(called, isFalse, reason: 'filter なしなので CPU レンダラを呼ぶ必要がない');
    });

    test('filter が非 null なら source・filter・strength をそのまま CpuVisionRenderer.applier に渡す',
        () async {
      ui.Image? capturedSource;
      VisionFilter? capturedFilter;
      double? capturedStrength;
      CpuVisionRenderer.applier = (source, filter, strength) async {
        capturedSource = source;
        capturedFilter = filter;
        capturedStrength = strength;
        return fakeOut;
      };

      const filter = VisionFilter.protanopia();
      final out = await BeforeAfterView.renderAfter(src, filter, 0.75);
      expect(identical(out, fakeOut), isTrue);
      expect(identical(capturedSource, src), isTrue);
      expect(capturedFilter, filter);
      expect(capturedStrength, 0.75);
    });

    test('payload 付きフィルタもそのまま渡される（#60: マッピングはこの widget の責務ではない）',
        () async {
      VisionFilter? capturedFilter;
      CpuVisionRenderer.applier = (source, filter, strength) async {
        capturedFilter = filter;
        return fakeOut;
      };

      const filter = VisionFilter.astigmatism(axisDeg: 45.0);
      await BeforeAfterView.renderAfter(src, filter, 1.0);
      expect(capturedFilter, filter);
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

    group('ラベル表示', () {
      // #85: renderAfter の既定実装は実ブリッジ必須の CpuVisionRenderer.applier
      // へ委譲するため、`flutter test`（native lib 未ロード）ではフェイクに
      // 差し替える。ここではラベル表示（`_after` が非 null になること）だけを
      // 見たいので、フェイクは source をそのまま返すだけでよい（実描画・実ブリッジの
      // 検証は integration_test/cpu_preview_all_filters_test.dart の役割）。
      setUp(() {
        CpuVisionRenderer.applier = (source, filter, strength) async => source;
      });
      tearDown(() {
        CpuVisionRenderer.applier = CpuVisionRenderer.apply;
      });

      testWidgets('protanopia で原画ラベルとフィルタ名ラベルの両ペインを出す', (tester) async {
        await tester.pumpWidget(
          localized(
            const BeforeAfterView(
              filter: VisionFilter.protanopia(),
              filterId: 'protanopia',
              strength: 1.0,
              sampleSize: 32,
            ),
          ),
        );
        final protoName = visionFilterName(en, 'protanopia');
        await pumpUntilText(tester, protoName);

        expect(find.text(en.previewPaneOriginal), findsOneWidget);
        expect(find.text(protoName), findsOneWidget);
      });

      testWidgets(
          'deuteranopia でも原画ラベルとフィルタ名ラベルの両ペインを出す'
          '（#59: renderAfter の対象拡大）', (tester) async {
        await tester.pumpWidget(
          localized(
            const BeforeAfterView(
              filter: VisionFilter.deuteranopia(),
              filterId: 'deuteranopia',
              strength: 1.0,
              sampleSize: 32,
            ),
          ),
        );
        final deuteranopiaName = visionFilterName(en, 'deuteranopia');
        await pumpUntilText(tester, deuteranopiaName);

        expect(find.text(en.previewPaneOriginal), findsOneWidget);
        expect(find.text(deuteranopiaName), findsOneWidget);
      });

      testWidgets('filter が null なら両ペインとも原画ラベルになる（#60）', (tester) async {
        await tester.pumpWidget(
          localized(
            const BeforeAfterView(
              filter: null,
              filterId: null,
              strength: 1.0,
              sampleSize: 32,
            ),
          ),
        );
        await pumpUntilText(tester, en.previewPaneOriginal);

        expect(find.text(en.previewPaneOriginal), findsNWidgets(2));
      });
    });

    group('時間依存フィルタの注記 (#60)', () {
      setUp(() {
        CpuVisionRenderer.applier = (source, filter, strength) async => source;
      });
      tearDown(() {
        CpuVisionRenderer.applier = CpuVisionRenderer.apply;
      });

      testWidgets('vertigo（時間依存）は静止フレームの注記を出す', (tester) async {
        await tester.pumpWidget(
          localized(
            const BeforeAfterView(
              filter: VisionFilter.vertigo(),
              filterId: 'vertigo',
              strength: 1.0,
              sampleSize: 32,
            ),
          ),
        );
        await pumpUntilText(tester, en.previewStaticFrameNote);
        expect(find.text(en.previewStaticFrameNote), findsOneWidget);
      });

      testWidgets('protanopia（時間依存でない）は静止フレームの注記を出さない', (tester) async {
        await tester.pumpWidget(
          localized(
            const BeforeAfterView(
              filter: VisionFilter.protanopia(),
              filterId: 'protanopia',
              strength: 1.0,
              sampleSize: 32,
            ),
          ),
        );
        await pumpUntilText(tester, visionFilterName(en, 'protanopia'));
        expect(find.text(en.previewStaticFrameNote), findsNothing);
      });
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

      // #85 レビュー S3: `_scheduleRebuild` が実行を直列化する（同時に走る
      // ジョブは常に1本）ようになったため、以前このテストが前提にしていた
      // 「3件が本当に同時に in-flight」という状況はもう production コードから
      // 起こり得ない。2回目・3回目の要求は最新の1件だけが集約され、1回目が
      // 完了してから走る。
      testWidgets(
          '連続更新では中間の要求は集約され、最終的に最新の結果だけが残る '
          '(#85 レビュー S3)', (tester) async {
        late ui.Image before1;
        late ui.Image afterA, afterB;
        await tester.runAsync(() async {
          before1 = await BeforeAfterView.generateSampleImage(4);
          afterA = await BeforeAfterView.generateSampleImage(4);
          afterB = await BeforeAfterView.generateSampleImage(4);
        });
        sampleImageGenerator = (size) => Future.value(before1);

        final completers = <Completer<ui.Image?>>[];
        final capturedStrengths = <double>[];
        afterImageRenderer = (source, filter, strength) {
          capturedStrengths.add(strength);
          final c = Completer<ui.Image?>();
          completers.add(c);
          return c.future;
        };

        Widget build(double strength) => localized(
              BeforeAfterView(
                filter: const VisionFilter.protanopia(),
                filterId: 'protanopia',
                strength: strength,
                sampleSize: 16,
              ),
            );

        // 3回連続で更新する（インテンシティのスライダー操作を想定）。1回目の
        // 要求だけが実際に in-flight になり、2・3回目は集約されて1件だけ
        // 保留される。
        await tester.pumpWidget(build(0.1));
        await tester.pump();
        await tester.pumpWidget(build(0.2));
        await tester.pump();
        await tester.pumpWidget(build(0.3));
        await tester.pump();
        expect(completers.length, 1, reason: '2・3回目は集約され、実際にはまだ呼ばれていない');

        // 1回目（intensity=0.1）を解決する。集約された保留分（最新の
        // intensity=0.3 を使う）が続けて自動的に走り始める。
        completers[0].complete(afterA);
        await tester.pump();
        await tester.pump();
        expect(completers.length, 2, reason: '1回目の完了を受けて保留していた最新の要求が走り始める');
        expect(capturedStrengths, [0.1, 0.3],
            reason: '保留分は要求時点(0.2)ではなく実行時点の最新値(0.3)を使う');
        expect(afterA.debugDisposed, isFalse,
            reason: '2件目の解決前は1回目の結果が表示されたままになる（集約の許容する遷移）');

        // 2回目（実際には intensity=0.3 用）を解決する。
        completers[1].complete(afterB);
        await tester.pump();

        expect(afterB.debugDisposed, isFalse, reason: '最新の結果は表示されたままであるべき');
        expect(afterA.debugDisposed, isTrue,
            reason: '差し替えられた旧結果は dispose されるべき');
        expect(before1.debugDisposed, isFalse,
            reason: '_before はどの更新でも再利用され続けている');
      });

      testWidgets(
          'スライダーを連続で変化させても、同時に実行される afterImageRenderer は '
          '1本を超えない (#85 レビュー S3)', (tester) async {
        late ui.Image before1;
        final afterImages = <double, ui.Image>{};
        await tester.runAsync(() async {
          before1 = await BeforeAfterView.generateSampleImage(4);
          for (final v in [0.1, 0.2, 0.3, 0.4, 0.5]) {
            afterImages[v] = await BeforeAfterView.generateSampleImage(4);
          }
        });
        sampleImageGenerator = (size) => Future.value(before1);

        var activeCount = 0;
        var maxActiveCount = 0;
        final calledStrengths = <double>[];
        afterImageRenderer = (source, filter, strength) async {
          activeCount++;
          if (activeCount > maxActiveCount) maxActiveCount = activeCount;
          calledStrengths.add(strength);
          // 他の要求が（誤って）同時に割り込めるかどうかを検知するため、
          // 実処理っぽく一度イベントループへ制御を返す。
          await Future<void>.delayed(const Duration(milliseconds: 5));
          activeCount--;
          return afterImages[strength];
        };

        Widget build(double strength) => localized(
              BeforeAfterView(
                filter: const VisionFilter.protanopia(),
                filterId: 'protanopia',
                strength: strength,
                sampleSize: 16,
              ),
            );

        for (final v in [0.1, 0.2, 0.3, 0.4, 0.5]) {
          await tester.pumpWidget(build(v));
          await tester.pump();
        }
        // 保留中のジョブが順に流れ切るまでポンプする。
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }

        expect(maxActiveCount, lessThanOrEqualTo(1),
            reason: '同時に実行される afterImageRenderer 呼び出しは1本を超えてはいけない');
        expect(calledStrengths.last, 0.5, reason: '最終的には最新の intensity が反映される');
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
              Future.value(source), // phase1: filter=null → _after は _before と同一
          (source) => Future.value(after1), // phase2: 実描画（_before とは別物）
          (source) => Future.value(after2), // phase3: 再度差し替え
        ];
        var callIndex = 0;
        afterImageRenderer = (source, filter, strength) {
          final response = responses[callIndex];
          callIndex++;
          return response(source);
        };

        // phase1: filter=null → _after は _before(before1) のエイリアス。
        await tester.pumpWidget(localized(const BeforeAfterView(
          filter: null,
          filterId: null,
          strength: 1.0,
          sampleSize: 16,
        )));
        await tester.pump();
        await tester.pump();

        // phase2: null → protanopia。旧 _after(=before1) は _before と同一なので
        // dispose されてはいけない（_before として使われ続けている）。
        await tester.pumpWidget(localized(const BeforeAfterView(
          filter: VisionFilter.protanopia(),
          filterId: 'protanopia',
          strength: 1.0,
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
          filter: VisionFilter.protanopia(),
          filterId: 'protanopia',
          strength: 0.5,
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
        afterImageRenderer = (source, filter, strength) => completer.future;

        await tester.pumpWidget(localized(const BeforeAfterView(
          filter: VisionFilter.protanopia(),
          filterId: 'protanopia',
          strength: 1.0,
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

      // 旧 "auto モードで初回生成が完了する前に filterType が変わっても..."
      // (#58 レビュー M1) テストは削除した: M1 が守っていたのは「sampleSize
      // 未指定＝ペインのレイアウトから決まる auto モードで、初回生成が終わる
      // 前は _currentSampleSize が null のままなので didUpdateWidget が
      // 再生成をスキップしてしまう」という auto モード特有の不具合で、#85
      // レビュー S4 で auto モード自体（レイアウト依存のサイズ決定）を撤去した
      // ため前提が消滅した。「初期生成中に filter が変わっても最新の結果
      // だけが残る」という一般的な不変条件自体は、上の
      // 「連続更新では中間の要求は集約され…」(#85 レビュー S3) テストで
      // 別の切り口から検証済み。

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
        afterImageRenderer = (source, filter, strength) {
          callIndex++;
          if (callIndex == 1) {
            return Future.value(source); // filter=null 相当: そのまま返す
          }
          capturedRendererInput = source;
          return Future.value(realAfter);
        };

        // 1回目: filter=null で _before=_after=before1 を確定させる。
        await tester.pumpWidget(localized(const BeforeAfterView(
          filter: null,
          filterId: null,
          strength: 1.0,
          sampleSize: 16,
        )));
        await tester.pump();
        await tester.pump();

        // 2回目: サイズが変わらないので _before(before1) が再利用される。
        // renderer に渡されるのは before1 そのものではなく複製であるべき
        // （await 中に他の更新で _before が dispose される可能性があるため）。
        await tester.pumpWidget(localized(const BeforeAfterView(
          filter: VisionFilter.protanopia(),
          filterId: 'protanopia',
          strength: 1.0,
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

      // 旧 "捨てられる経路では複製が無条件に dispose される…" (#58 レビュー
      // SHOULD-2) テストは削除した: このテストは「2件目・3件目の要求が本当に
      // 同時に in-flight で、3件目が先に解決し2件目（追い越された方）が後から
      // 解決する」という状況を作って `_rebuild` の discard 分岐（`isLatest ==
      // false` の経路）を突く内容だった。#85 レビュー S3 で `_scheduleRebuild`
      // が実行を直列化した結果、production コードからはそもそも2本の
      // `_rebuild` が同時に in-flight になり得なくなったため、この状況を
      // widget test から再現できなくなった（`_rebuild` 内の discard 分岐自体は
      // dispose 安全性の防御として残してあるが、素通しでは踏めない）。

      testWidgets(
          '保留中の要求がある状態で dispose したら、renderer は再び呼ばれない '
          '(#85 レビュー N12)', (tester) async {
        late ui.Image before1;
        await tester.runAsync(() async {
          before1 = await BeforeAfterView.generateSampleImage(4);
        });
        sampleImageGenerator = (size) => Future.value(before1);

        var rendererCallCount = 0;
        final completer = Completer<ui.Image?>();
        afterImageRenderer = (source, filter, strength) {
          rendererCallCount++;
          return completer.future;
        };

        await tester.pumpWidget(localized(const BeforeAfterView(
          filter: VisionFilter.protanopia(),
          filterId: 'protanopia',
          strength: 1.0,
          sampleSize: 16,
        )));
        await tester.pump();
        expect(rendererCallCount, 1);

        // intensity を変える → 1回目がまだ in-flight なので集約されて
        // pending になるだけで、まだ renderer は呼ばれない。
        await tester.pumpWidget(localized(const BeforeAfterView(
          filter: VisionFilter.protanopia(),
          filterId: 'protanopia',
          strength: 0.5,
          sampleSize: 16,
        )));
        await tester.pump();
        expect(rendererCallCount, 1, reason: '2回目は集約されているだけでまだ呼ばれていない');

        // 保留が残ったまま widget を破棄する。
        await tester.pumpWidget(const SizedBox());

        // 1回目の要求をようやく解決する。_runRebuild は mounted チェックに
        // より、保留中の要求（intensity=0.5 分）を再スケジュールしないはず。
        completer.complete(before1);
        await tester.pump();
        await tester.pump();

        expect(rendererCallCount, 1,
            reason: 'dispose 後は保留中の要求があっても renderer が再度呼ばれて'
                'はいけない');
      });

      testWidgets(
          'sampleSize 未指定のとき generator は canonicalSampleSize（1024）で'
          '呼ばれる (#85 レビュー N12)', (tester) async {
        late ui.Image stub;
        await tester.runAsync(() async {
          stub = await BeforeAfterView.generateSampleImage(4);
        });
        final requestedSizes = <int>[];
        sampleImageGenerator = (size) {
          requestedSizes.add(size);
          return Future.value(stub);
        };
        afterImageRenderer = (source, filter, strength) => Future.value(source);

        await tester.pumpWidget(localized(const BeforeAfterView(
          filter: null,
          filterId: null,
          strength: 1.0,
        )));
        await tester.pump();
        await tester.pump();

        expect(requestedSizes, [BeforeAfterView.canonicalSampleSize]);
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
          filter: VisionFilter.protanopia(),
          filterId: 'protanopia',
          strength: 1.0,
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
        afterImageRenderer = (source, filter, strength) =>
            Future<ui.Image?>.error(StateError('boom: renderer'));

        await tester.pumpWidget(localized(const BeforeAfterView(
          filter: VisionFilter.protanopia(),
          filterId: 'protanopia',
          strength: 0.5,
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
            (source, filter, strength) => Future.value(goodAfter);

        final en = lookupAppLocalizations(const Locale('en'));

        await tester.pumpWidget(localized(const BeforeAfterView(
          filter: VisionFilter.protanopia(),
          filterId: 'protanopia',
          strength: 1.0,
          sampleSize: 16,
        )));
        await tester.pump();
        await tester.pump();

        // loading が固着せず、「準備中」表示のままにならない。
        expect(find.text(en.previewPreparing), findsNothing);

        // 次の更新（intensity 変更）で再試行され、今度は成功する。
        await tester.pumpWidget(localized(const BeforeAfterView(
          filter: VisionFilter.protanopia(),
          filterId: 'protanopia',
          strength: 0.5,
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
        afterImageRenderer = (source, filter, strength) {
          rendererCallCount++;
          if (rendererCallCount == 1) {
            return Future<ui.Image?>.error(StateError('boom'));
          }
          return Future.value(goodAfter);
        };

        final en = lookupAppLocalizations(const Locale('en'));

        await tester.pumpWidget(localized(const BeforeAfterView(
          filter: VisionFilter.protanopia(),
          filterId: 'protanopia',
          strength: 1.0,
          sampleSize: 16,
        )));
        await tester.pump();
        await tester.pump();

        // renderer が失敗しても、新規生成した before（1回目）はリークせず
        // dispose される。
        expect(before1.debugDisposed, isTrue);
        expect(find.text(en.previewPreparing), findsNothing);

        await tester.pumpWidget(localized(const BeforeAfterView(
          filter: VisionFilter.protanopia(),
          filterId: 'protanopia',
          strength: 0.5,
          sampleSize: 16,
        )));
        await tester.pump();
        await tester.pump();

        expect(rendererCallCount, 2);
        expect(goodAfter.debugDisposed, isFalse);
      });

      // 旧タイトルの「auto モードで」は #85 レビュー S4 で auto モード
      // （レイアウト依存のサイズ決定）自体を撤去したため取れたが、検証内容
      // （恒久的な失敗は busy loop にならず、ユーザー操作でのみ再試行される）
      // 自体は canonical サイズ描画でもそのまま成り立つ普遍的な不変条件。
      testWidgets(
          '恒久的な失敗が続いても busy loop にならず、'
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
            (source, filter, strength) => Future.value(goodAfter);

        await tester.pumpWidget(localized(const BeforeAfterView(
          filter: VisionFilter.protanopia(),
          filterId: 'protanopia',
          strength: 1.0,
          sampleSize: 16,
        )));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        expect(generatorCallCount, 1);

        // 何もしなくても busy loop で再試行し続けない
        // （1秒分ポンプしても呼び出し回数は変わらない。#85 レビュー S4 で
        // 自動リサイズのタイマー自体が無くなったため、そもそも自動で再試行
        // する経路が存在しない）。
        await tester.pump(const Duration(seconds: 1));
        expect(generatorCallCount, 1,
            reason: '恒久的な失敗は自動では再試行しない（busy loop 回帰）');

        // ユーザー操作（intensity 変更）で再試行され、今度は成功する。
        await tester.pumpWidget(localized(const BeforeAfterView(
          filter: VisionFilter.protanopia(),
          filterId: 'protanopia',
          strength: 0.5,
          sampleSize: 16,
        )));
        await tester.pump();
        await tester.pump();

        expect(generatorCallCount, 2);
        expect(goodAfter.debugDisposed, isFalse);
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
        afterImageRenderer = (source, filter, strength) {
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
          filter: VisionFilter.protanopia(),
          filterId: 'protanopia',
          strength: 1.0,
          sampleSize: 16,
        )));
        await tester.pump();
        await tester.pump();
        expect(find.text(en.previewFailed), findsNothing);

        // 2回目: renderer が失敗する。
        await tester.pumpWidget(localized(const BeforeAfterView(
          filter: VisionFilter.protanopia(),
          filterId: 'protanopia',
          strength: 0.5,
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
          filter: VisionFilter.protanopia(),
          filterId: 'protanopia',
          strength: 0.6,
          sampleSize: 16,
        )));
        await tester.pump();
        await tester.pump();

        expect(find.text(en.previewFailed), findsNothing);
        expect(goodAfter2.debugDisposed, isFalse);
      });
    });

    group('export の caption (#85 レビュー S8)', () {
      tearDown(() {
        sampleImageGenerator = BeforeAfterView.generateSampleImage;
        afterImageRenderer = BeforeAfterView.renderAfter;
        exportImageComposer = composeExportImage;
        pngSaver = savePng;
      });

      testWidgets(
          '1回目の結果を表示中に強度を変えてから export しても、caption は'
          '描画時の強度になる', (tester) async {
        late ui.Image before1, after1, composedStub;
        await tester.runAsync(() async {
          before1 = await BeforeAfterView.generateSampleImage(4);
          after1 = await BeforeAfterView.generateSampleImage(4);
          composedStub = await BeforeAfterView.generateSampleImage(4);
        });
        sampleImageGenerator = (size) => Future.value(before1);

        // 1回目（intensity=1.0）はすぐ解決する。2回目（intensity=0.5、
        // コアレス後に走る）は意図的に未解決のまま止め、「表示中の _after は
        // まだ1回目のまま」という状況を作る。
        var rendererCallCount = 0;
        final pending = Completer<ui.Image?>();
        afterImageRenderer = (source, filter, strength) {
          rendererCallCount++;
          if (rendererCallCount == 1) return Future.value(after1);
          return pending.future;
        };

        ExportCaption? capturedCaption;
        exportImageComposer = (base, caption) async {
          capturedCaption = caption;
          // 本物の composeExportImage は常に base とは別の新しい ui.Image を
          // 返す（base を下地に新しいキャンバスへ描き直すため）。_export は
          // 戻り値を dispose する責務を持つので、base（＝表示中の _after）を
          // そのまま返すと _after を誤って dispose してしまう。フェイクでも
          // 別オブジェクトを返して契約を守る。
          return composedStub;
        };
        String? savedFilename;
        pngSaver = (bytes, filename) async {
          savedFilename = filename;
          return '/fake/downloads/$filename';
        };

        final en = lookupAppLocalizations(const Locale('en'));

        // 1回目: protanopia, intensity=1.0 で描画完了させる。
        await tester.pumpWidget(localized(const BeforeAfterView(
          filter: VisionFilter.protanopia(),
          filterId: 'protanopia',
          strength: 1.0,
          sampleSize: 16,
        )));
        await tester.pump();
        await tester.pump();
        expect(rendererCallCount, 1);

        // intensity を 0.5 に変える。_scheduleRebuild は実行中でなければ
        // 即座に2回目を起動する（#85 レビュー S3）が、その2回目は上の
        // フェイクで意図的に未解決のまま止めてあるので、_after はまだ
        // 1回目（after1, strength=1.0）のままになる。
        await tester.pumpWidget(localized(const BeforeAfterView(
          filter: VisionFilter.protanopia(),
          filterId: 'protanopia',
          strength: 0.5,
          sampleSize: 16,
        )));
        await tester.pump();
        expect(rendererCallCount, 2, reason: '2回目のレンダリングは開始しているが、まだ完了していない');

        // ここで export をタップする。表示されている _after はまだ1回目の
        // 結果なので、caption も1回目の strength（100%）になるべき——
        // widget.strength の現在値（0.5 → 50%）を使ってはいけない
        // （#85 レビュー S8）。
        await tester.tap(find.byTooltip(en.exportButtonTooltip));
        // encodeImagePng は実エンジンの PNG エンコードを行う（フェイクにして
        // いない）ため、素の pump() だけでは終わらないことがある。他の
        // テスト（pumpUntilText 参照）と同じく tester.runAsync の中で実時間
        // ポンプして待つ。
        await tester.runAsync(() async {
          for (var i = 0; i < 50; i++) {
            if (savedFilename != null) return;
            await tester.pump(const Duration(milliseconds: 20));
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        });
        await tester.pump();

        expect(capturedCaption, isNotNull);
        expect(capturedCaption!.strengthLabel, en.strengthLabel(100),
            reason: '描画時（1回目、strength=1.0=100%）の値を使うべき');
        expect(
          capturedCaption!.symptomLabel,
          visionFilterName(en, 'protanopia'),
        );
        expect(savedFilename, isNotNull);
        expect(savedFilename, contains('100pct'));
        expect(savedFilename, isNot(contains('50pct')));
      });

      testWidgets('filter=null（原画）で export すると symptomLabel が previewPaneOriginal になる '
          '(#60)', (tester) async {
        late ui.Image before1, composedStub;
        await tester.runAsync(() async {
          before1 = await BeforeAfterView.generateSampleImage(4);
          composedStub = await BeforeAfterView.generateSampleImage(4);
        });
        sampleImageGenerator = (size) => Future.value(before1);
        afterImageRenderer = (source, filter, strength) =>
            Future.value(source); // filter=null: そのまま返す

        ExportCaption? capturedCaption;
        exportImageComposer = (base, caption) async {
          capturedCaption = caption;
          return composedStub;
        };
        String? savedFilename;
        pngSaver = (bytes, filename) async {
          savedFilename = filename;
          return '/fake/downloads/$filename';
        };

        final en = lookupAppLocalizations(const Locale('en'));

        await tester.pumpWidget(localized(const BeforeAfterView(
          filter: null,
          filterId: null,
          strength: 1.0,
          sampleSize: 16,
        )));
        await tester.pump();
        await tester.pump();

        await tester.tap(find.byTooltip(en.exportButtonTooltip));
        await tester.runAsync(() async {
          for (var i = 0; i < 50; i++) {
            if (savedFilename != null) return;
            await tester.pump(const Duration(milliseconds: 20));
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        });
        await tester.pump();

        expect(capturedCaption, isNotNull);
        expect(capturedCaption!.symptomLabel, en.previewPaneOriginal);
        expect(savedFilename, contains('-none-'));
      });
    });
  });
}
