// 多症状のプレビュー描画経路と、推奨サンプルの追従（#119）。
//
// HomeScreen の `_previewCard` が、層が複数のときは BeforeAfterView に
// `VisionFilterState.pipelineSteps`（段順・強度 0 の層を除く）を渡し、BeforeAfterView が
// それを #118 の複数ステップ合成（`CpuVisionRenderer.pipelineApplier`）へ 1 回で渡すこと、
// 層が 1 つ以下のときは従来どおり単一フィルタの経路（`afterImageRenderer`）であることを確認する。
//
// 実ブリッジ（Rust）は `flutter test` では呼べないので、`pipelineApplier` をフェイクに
// 差し替え、「何が渡ったか」を記録して検証する。合成結果の byte-exact は #118 の Rust 側
// テストが担うため、ここでは扱わない（渡す列の順・強度・payload・除外の規則まで）。
//
// 推奨サンプルの追従（#78）は、複数層のとき `focusedId` の層に従う。フォーカスが外れたら
// 適用順で最後の層へ移り、手動で選んだサンプルとユーザー画像には追従しない。

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/models/sample_catalog.dart';
import 'package:universal_experience/rendering/cpu_vision_renderer.dart';
import 'package:universal_experience/services/preview_selection.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';

import 'support/color_vision_select.dart';
import 'support/home_screen_harness.dart';
import 'support/sample_image_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ui.Image master;

  /// pipelineApplier に渡されたステップ列（呼び出しごと）。
  final pipelineCalls = <List<VisionStep>>[];

  /// afterImageRenderer（単一フィルタ経路）に渡された (filter, strength)。
  final singleCalls = <(VisionFilter?, double)>[];

  setUp(installHomeScreenFixtures);
  tearDown(resetHomeScreenFixtures);

  Future<void> installFakes(WidgetTester tester) async {
    pipelineCalls.clear();
    singleCalls.clear();
    await tester.runAsync(() async {
      master = await generateSampleImage(64);
    });
    addTearDown(master.dispose);
    previewSourceImageLoader = (source, size) async => master.clone();
    afterImageRenderer = (source, filter, strength) async {
      singleCalls.add((filter, strength));
      return master.clone();
    };
    CpuVisionRenderer.pipelineApplier = (source, steps) async {
      pipelineCalls.add(List.of(steps));
      return master.clone();
    };
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
  }

  const wide = Size(1400, 1000);

  BeforeAfterView currentPreview(WidgetTester tester) =>
      tester.widget<BeforeAfterView>(find.byType(BeforeAfterView));

  group('描画経路', () {
    testWidgets('層が複数: steps が段順・強度つきで BeforeAfterView に渡り、合成は 1 回で呼ばれる',
        (tester) async {
      await installFakes(tester);
      final h = await pumpHomeScreen(tester, size: wide);

      // 選ぶ順は段順の逆（色覚 → 網膜 → 光学 → 運動）。
      h.visionState.toggle('protanopia');
      h.visionState.toggle('night_blindness');
      h.visionState.toggle('myopia');
      h.visionState.toggle('vertigo');
      h.visionState.setLayerStrength('myopia', 0.5);
      h.visionState.setLayerStrength('protanopia', 0.25);
      await settle(tester);

      const expected = [
        VisionStep(filter: VisionFilter.vertigo(), strength: 1.0),
        VisionStep(filter: VisionFilter.myopia(), strength: 0.5),
        VisionStep(filter: VisionFilter.nightBlindness(), strength: 1.0),
        VisionStep(filter: VisionFilter.protanopia(), strength: 0.25),
      ];
      expect(currentPreview(tester).steps, expected);
      expect(pipelineCalls, isNotEmpty);
      expect(pipelineCalls.last, expected,
          reason: '最後に描画された合成は、4 層を段順・各層の強度で 1 回に渡したもの');
      expect(singleCalls.where((c) => c.$1 != null), isEmpty,
          reason: '複数層では単一フィルタの経路を使わない');
    });

    testWidgets('payload は層ごとのものが合成に渡る', (tester) async {
      await installFakes(tester);
      final h = await pumpHomeScreen(tester, size: wide);
      h.visionState.toggle('astigmatism');
      h.visionState.toggle('protanopia');
      h.visionState.setLayerParams('astigmatism', const {'axisDeg': 30.0});
      await settle(tester);

      expect(pipelineCalls.last.first.filter,
          const VisionFilter.astigmatism(axisDeg: 30.0));
      expect(pipelineCalls.last.last.filter, const VisionFilter.protanopia());
    });

    testWidgets('強度 0 の層は合成に渡さない（層は残る）', (tester) async {
      await installFakes(tester);
      final h = await pumpHomeScreen(tester, size: wide);
      h.visionState.toggle('vertigo');
      h.visionState.toggle('myopia');
      h.visionState.toggle('night_blindness');
      h.visionState.setLayerStrength('myopia', 0.0);
      await settle(tester);

      expect(h.visionState.layers, hasLength(3));
      expect(pipelineCalls.last.map((s) => s.filter), [
        const VisionFilter.vertigo(),
        const VisionFilter.nightBlindness(),
      ]);
    });

    testWidgets('選ぶ順を入れ替えても、合成に渡る列は同じ（履歴に依存しない）', (tester) async {
      Future<List<VisionStep>> run(List<String> order) async {
        await installFakes(tester);
        final h = await pumpHomeScreen(tester, size: wide);
        for (final id in order) {
          h.visionState.toggle(id);
        }
        h.visionState.setLayerStrength('myopia', 0.6);
        await settle(tester);
        return pipelineCalls.last;
      }

      final a = await run(['vertigo', 'myopia', 'night_blindness']);
      final b = await run(['night_blindness', 'myopia', 'vertigo']);
      expect(a, b);
      expect(a, hasLength(3));
    });

    testWidgets('層が 1 つなら従来どおり単一フィルタの経路（steps は渡さない）', (tester) async {
      await installFakes(tester);
      final h = await pumpHomeScreen(tester, size: wide);
      h.visionState.toggle('myopia');
      h.visionState.setLayerStrength('myopia', 0.4);
      await settle(tester);

      expect(currentPreview(tester).steps, isNull);
      expect(pipelineCalls, isEmpty);
      expect(singleCalls.last.$1, const VisionFilter.myopia());
      expect(singleCalls.last.$2, 0.4);
    });

    testWidgets('複数層から 1 層に戻すと単一フィルタの経路へ戻る', (tester) async {
      await installFakes(tester);
      final h = await pumpHomeScreen(tester, size: wide);
      h.visionState.toggle('myopia');
      h.visionState.toggle('vertigo');
      await settle(tester);
      expect(pipelineCalls, isNotEmpty);

      h.visionState.remove('vertigo');
      await settle(tester);
      expect(currentPreview(tester).steps, isNull);
      expect(singleCalls.last.$1, const VisionFilter.myopia());
    });

    testWidgets('全層が強度 0 なら合成を呼ばず原画をそのまま見せる（空の steps）', (tester) async {
      await installFakes(tester);
      final h = await pumpHomeScreen(tester, size: wide);
      h.visionState.toggle('myopia');
      h.visionState.toggle('vertigo');
      await settle(tester);
      pipelineCalls.clear();

      h.visionState.setLayerStrength('myopia', 0.0);
      h.visionState.setLayerStrength('vertigo', 0.0);
      await settle(tester);

      expect(currentPreview(tester).steps, isEmpty);
      expect(pipelineCalls, isEmpty, reason: '空の列では描画器を呼ばない');
    });

    testWidgets('原画比較（bypass）の間は空の steps になり、解除で戻る', (tester) async {
      await installFakes(tester);
      final h = await pumpHomeScreen(tester, size: wide);
      h.visionState.toggle('myopia');
      h.visionState.toggle('vertigo');
      await settle(tester);

      final holder = Object();
      h.visionState.acquireBypass(holder);
      await settle(tester);
      expect(currentPreview(tester).steps, isEmpty);

      h.visionState.releaseBypass(holder);
      await settle(tester);
      expect(currentPreview(tester).steps, hasLength(2));
    });

    testWidgets('フォーカスが動かず steps だけ変わる更新（フォーカス外の層の強度）でも合成が再実行される',
        (tester) async {
      await installFakes(tester);
      final h = await pumpHomeScreen(tester, size: wide);
      // 色覚（protanopia）を足してから myopia を足す。フォーカスは myopia。
      selectColorVisionKey(h.visionState, 'protanopia');
      h.visionState.toggle('myopia');
      await settle(tester);
      expect(h.visionState.focusedId, 'myopia');
      final before = pipelineCalls.length;
      expect(before, greaterThan(0));
      final focusedFilter = currentPreview(tester).filter;
      final focusedStrength = currentPreview(tester).strength;

      // フォーカス外の層の強度の記憶だけを変える（フォーカス・選択は動かさない入口）。
      // フォーカス中の層（myopia）の強度・filter は変わらず、protanopia の強度だけが変わる。
      h.visionState.setStrengthForKey('protanopia', 0.3);
      await settle(tester);

      expect(h.visionState.focusedId, 'myopia');
      expect(currentPreview(tester).filter, focusedFilter);
      expect(currentPreview(tester).strength, focusedStrength);
      expect(pipelineCalls.length, before + 1,
          reason: 'steps の差だけで didUpdateWidget が再描画を起こす');
      expect(pipelineCalls.last.last,
          const VisionStep(filter: VisionFilter.protanopia(), strength: 0.3));
    });

    testWidgets('steps が変わらない再 build では合成を呼び直さない', (tester) async {
      await installFakes(tester);
      final h = await pumpHomeScreen(tester, size: wide);
      h.visionState.toggle('myopia');
      h.visionState.toggle('vertigo');
      await settle(tester);
      final before = pipelineCalls.length;

      // 同じ強度を書き直す（通知は飛ぶが steps は値として同じ）。
      h.visionState.setStrengthForKey('myopia', 1.0);
      await settle(tester);
      expect(pipelineCalls.length, before);
    });
  });

  group('合成経路の失敗と破棄（#119）', () {
    final ja = lookupAppLocalizations(const Locale('ja'));

    /// 報告された FlutterError を集める。`FlutterError.onError` を差し替えたままだと、
    /// テストの失敗（expect の失敗）もここに吸われて報告されずハングするので、戻す関数
    /// [restore] を返す。**アサーションの前に必ず [restore] を呼ぶ**（tearDown でも戻す）。
    ({List<FlutterErrorDetails> reported, void Function() restore})
        suppressReports() {
      final reported = <FlutterErrorDetails>[];
      final original = FlutterError.onError;
      FlutterError.onError = reported.add;
      void restore() => FlutterError.onError = original;
      addTearDown(restore);
      return (reported: reported, restore: restore);
    }

    testWidgets('applier が例外を投げたら失敗表示になり、次の更新で再試行できる', (tester) async {
      await installFakes(tester);
      final suppressed = suppressReports();
      final h = await pumpHomeScreen(tester, size: wide);
      CpuVisionRenderer.pipelineApplier = (source, steps) async {
        throw StateError('boom');
      };
      h.visionState.toggle('myopia');
      h.visionState.toggle('vertigo');
      await settle(tester);
      suppressed.restore();

      expect(find.text(ja.previewFailed), findsOneWidget);
      expect(suppressed.reported, isNotEmpty);

      CpuVisionRenderer.pipelineApplier = (source, steps) async {
        pipelineCalls.add(List.of(steps));
        return master.clone();
      };
      h.visionState.setLayerStrength('myopia', 0.5);
      await settle(tester);
      expect(find.text(ja.previewFailed), findsNothing);
      expect(pipelineCalls, isNotEmpty);
    });

    testWidgets('新しい合成結果に差し替わると、古い結果の画像は dispose される', (tester) async {
      await installFakes(tester);
      final outputs = <ui.Image>[];
      CpuVisionRenderer.pipelineApplier = (source, steps) async {
        pipelineCalls.add(List.of(steps));
        final out = master.clone();
        outputs.add(out);
        return out;
      };
      final h = await pumpHomeScreen(tester, size: wide);
      h.visionState.toggle('myopia');
      h.visionState.toggle('vertigo');
      await settle(tester);
      expect(outputs, hasLength(1));
      expect(outputs.first.debugDisposed, isFalse);

      h.visionState.setLayerStrength('myopia', 0.5);
      await settle(tester);
      expect(outputs, hasLength(2));
      expect(outputs.first.debugDisposed, isTrue, reason: '差し替えられた旧結果は破棄する');
      expect(outputs.last.debugDisposed, isFalse);
    });
  });

  group('previewPipelineSteps', () {
    testWidgets('bypass 中は空、通常は pipelineSteps と同じ', (tester) async {
      await installFakes(tester);
      final h = await pumpHomeScreen(tester, size: wide);
      h.visionState.toggle('myopia');
      h.visionState.toggle('vertigo');

      expect(
          previewPipelineSteps(h.visionState), h.visionState.pipelineSteps());
      h.visionState.acquireBypass(Object());
      expect(previewPipelineSteps(h.visionState), isEmpty);
    });
  });

  group('推奨サンプルの追従（#78 × #119）', () {
    String? sampleIdOf(HomeScreenHarness h) => h.imageSource.selectedSampleId;

    testWidgets('複数層では focusedId の層の推奨サンプルに追従する', (tester) async {
      await installFakes(tester);
      final h = await pumpHomeScreen(tester, size: wide);
      // 前提: 3 つの推奨サンプルが互いに違う（追従の有無が見分けられる）。
      final rec = {
        for (final id in ['myopia', 'night_blindness', 'protanopia'])
          id: recommendedSampleIdForFilter(id),
      };
      expect(rec.values.toSet(), hasLength(3));

      h.visionState.toggle('myopia');
      await tester.pump();
      expect(sampleIdOf(h), rec['myopia']);

      h.visionState.toggle('night_blindness');
      await tester.pump();
      expect(sampleIdOf(h), rec['night_blindness']);

      h.visionState.toggle('protanopia');
      await tester.pump();
      expect(sampleIdOf(h), rec['protanopia']);

      // 触れた層がフォーカスになる。
      h.visionState.setLayerStrength('myopia', 0.5);
      await tester.pump();
      expect(h.visionState.focusedId, 'myopia');
      expect(sampleIdOf(h), rec['myopia']);
    });

    testWidgets('フォーカスが外れたら適用順で最後の層の推奨サンプルへ移る', (tester) async {
      await installFakes(tester);
      final h = await pumpHomeScreen(tester, size: wide);
      h.visionState.toggle('protanopia');
      h.visionState.toggle('night_blindness');
      h.visionState.toggle(
          'myopia'); // フォーカス = myopia。適用順は myopia, night_blindness, protanopia
      await tester.pump();
      expect(sampleIdOf(h), recommendedSampleIdForFilter('myopia'));

      h.visionState.remove('myopia');
      await tester.pump();
      expect(h.visionState.focusedId, 'protanopia');
      expect(sampleIdOf(h), recommendedSampleIdForFilter('protanopia'));
    });

    testWidgets('手動で選んだサンプルには追従しない', (tester) async {
      await installFakes(tester);
      final h = await pumpHomeScreen(tester, size: wide);
      h.visionState.toggle('myopia');
      await tester.pump();

      h.imageSource.selectSample('chart');
      h.visionState.toggle('protanopia');
      await tester.pump();

      expect(sampleIdOf(h), 'chart');
      expect(h.imageSource.isFollowingRecommended, isFalse);
    });

    testWidgets('ユーザー画像には追従しない', (tester) async {
      await installFakes(tester);
      final h = await pumpHomeScreen(tester, size: wide);
      await tester.runAsync(() async {
        h.imageSource.setUserImage(await generateSampleImage(4));
      });
      await tester.pump();

      h.visionState.toggle('myopia');
      h.visionState.toggle('protanopia');
      await tester.pump();

      expect(h.imageSource.isUsingUserImage, isTrue);
    });
  });
}
