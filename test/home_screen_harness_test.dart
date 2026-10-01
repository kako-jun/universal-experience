// installHomeScreenFixtures（test/support/home_screen_harness.dart）の契約テスト（#127, #131）。
//
// ハーネスは、プレビューの読み込み・フィルタ適用・複数層の合成を Rust 非依存のフェイクに固定する。
// `flutter test` には native lib も RustLib.init() も無いので、実ローダ/実レンダラが
// 残ると、フィルタを選んだ状態で実時間が進む（`tester.runAsync`）タイミングに
// 「FRB 未初期化」の非同期例外が走行中のテストへ漏れる。ここでは
//
// - 差し替えと復元そのもの（install / reset。読み込み・適用・複数層の合成・体験）
// - アプリ本体（UniversalExperienceApp）経路でも、フィルタ選択・強度変更・画像読み込み完了を
//   `runAsync` で実時間を進めながら行っても（単一層は afterImageRenderer、2 層以上は
//   pipelineApplier の経路）、実レンダラに届かず例外が出ないこと
//
// を確かめる。画面構成（HomeScreen 単体）側の同種の回帰は home_screen_layout_test.dart。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/main.dart';
import 'package:universal_experience/models/preview_image_source.dart';
import 'package:universal_experience/models/sample_catalog.dart';
import 'package:universal_experience/rendering/cpu_vision_renderer.dart';
import 'package:universal_experience/services/settings_service.dart';
import 'package:universal_experience/services/vision_filter_snapshot.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';
import 'package:universal_experience/ui/widgets/experience_presets.dart';

import 'support/color_vision_select.dart';
import 'support/home_screen_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installHomeScreenFixtures);
  tearDown(() {
    resetHomeScreenFixtures();
    // UniversalExperienceApp が読む共有 singleton を、他のテストへ残さない。clear() は
    // 強度の記憶を消さないので、空の snapshot で記憶ごと初期状態へ戻す。
    visionFilterState.restore(const VisionFilterSnapshot());
    imageSourceState.resetToRecommended(kDefaultSampleId);
  });

  test('install は実ローダ・実レンダラ・実合成・実ブリッジを fixture に差し替え、reset で戻す', () async {
    // 外れたことを同一性で決定論的に確かめる（実時間に頼らない）。以降の runAsync を
    // 使う回帰テストは、ここで差し替えが効いていることを前提にしている。
    expect(previewSourceImageLoader,
        isNot(BeforeAfterView.loadPreviewSourceImage));
    expect(afterImageRenderer, isNot(BeforeAfterView.renderAfter));
    expect(CpuVisionRenderer.pipelineApplier,
        isNot(CpuVisionRenderer.applyPipeline));
    expect(experiencesProvider, isNot(experiences));
    expect(experiencesProvider().map((e) => e.id),
        ['meniere', 'bppv', 'vestibular_neuritis', 'labyrinthitis']);

    // 既定の読み込みは完了しない（プレビューは「準備中」で止まる）。
    var loaded = false;
    previewSourceImageLoader(const SamplePreviewImageSource('x'), 100)
        .then((_) => loaded = true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(loaded, isFalse);

    // 既定の適用は Rust に触れず、入力の複製を返す（元画像とは別の ui.Image）。
    final source = fixturePreviewImage();
    addTearDown(source.dispose);
    final out =
        await afterImageRenderer(source, const VisionFilter.protanopia(), 1.0);
    expect(out, isNotNull);
    addTearDown(out!.dispose);
    expect(identical(out, source), isFalse);
    expect(out.width, source.width);
    expect(out.height, source.height);

    // 複数層の合成も同様に、Rust に触れず入力の複製を返す。
    final pipelined = await CpuVisionRenderer.pipelineApplier(source, const [
      VisionStep(filter: VisionFilter.protanopia(), strength: 1.0),
      VisionStep(filter: VisionFilter.vertigo(), strength: 0.5),
    ]);
    addTearDown(pipelined.dispose);
    expect(identical(pipelined, source), isFalse);
    expect(pipelined.width, source.width);
    expect(pipelined.height, source.height);

    resetHomeScreenFixtures();
    expect(CpuVisionRenderer.pipelineApplier, CpuVisionRenderer.applyPipeline);
    expect(previewSourceImageLoader, BeforeAfterView.loadPreviewSourceImage);
    expect(afterImageRenderer, BeforeAfterView.renderAfter);
    expect(experiencesProvider, experiences);
  });

  group('UniversalExperienceApp 経路', () {
    Future<void> pumpApp(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final settings = SettingsService();
      await settings.load();
      await tester.pumpWidget(UniversalExperienceApp(settings: settings));
      await tester.pump();
    }

    Future<void> advanceRealTime(WidgetTester tester) async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
    }

    testWidgets('画像が読み込み済みでも、フィルタ選択と強度変更のあと runAsync で実時間を進めて例外が出ない',
        (tester) async {
      // 画像が載った状態にする。適用はハーネスの既定（Rust 非依存）を、呼び出しを
      // 数えるラッパーで包む（フィルタ適用の経路が実際に走ったことを示す）。
      final rendered = <(VisionFilter?, double)>[];
      previewSourceImageLoader = (source, size) async => fixturePreviewImage();
      final fakeRenderer = afterImageRenderer;
      afterImageRenderer = (source, filter, strength) {
        rendered.add((filter, strength));
        return fakeRenderer(source, filter, strength);
      };

      await pumpApp(tester);
      selectColorVisionKey(visionFilterState, 'protanopia');
      await tester.pump();
      await advanceRealTime(tester);
      visionFilterState.setStrength(0.4);
      await tester.pump();
      await advanceRealTime(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(PreviewErrorPlaceholder), findsNothing);
      expect(rendered, isNotEmpty, reason: 'フィルタ適用の経路を通っていなければ、この回帰テストは何も守れない');
      expect(rendered.last.$2, 0.4, reason: '強度の変更がレンダラへ届く');
      final panes =
          tester.widgetList<PreviewImageView>(find.byType(PreviewImageView));
      expect(panes.length, 2);
      expect(panes.every((p) => p.image != null), isTrue);
    });

    testWidgets('2 層を選び、画像が読み込み済みでも、runAsync で実時間を進めて例外が出ない（複数層の合成）',
        (tester) async {
      // 2 層以上は afterImageRenderer ではなく CpuVisionRenderer.pipelineApplier を通る。
      // ハーネスの既定（Rust 非依存）を、呼び出しを数えるラッパーで包む。
      final pipelined = <List<VisionStep>>[];
      previewSourceImageLoader = (source, size) async => fixturePreviewImage();
      final fakePipeline = CpuVisionRenderer.pipelineApplier;
      CpuVisionRenderer.pipelineApplier = (source, steps) {
        pipelined.add(List.of(steps));
        return fakePipeline(source, steps);
      };

      await pumpApp(tester);
      visionFilterState.toggle('protanopia');
      visionFilterState.toggle('cataract');
      await tester.pump();
      await advanceRealTime(tester);
      visionFilterState.setStrength(0.4);
      await tester.pump();
      await advanceRealTime(tester);

      expect(visionFilterState.layers, hasLength(2));
      expect(tester.takeException(), isNull);
      expect(find.byType(PreviewErrorPlaceholder), findsNothing);
      expect(pipelined, isNotEmpty,
          reason: '複数層の合成の経路を通っていなければ、この回帰テストは何も守れない');
      expect(pipelined.last, hasLength(2));
      expect(pipelined.last.any((s) => s.strength == 0.4), isTrue,
          reason: '強度の変更が合成のステップへ届く');
      final panes =
          tester.widgetList<PreviewImageView>(find.byType(PreviewImageView));
      expect(panes.length, 2);
      expect(panes.every((p) => p.image != null), isTrue);
    });
  });
}
