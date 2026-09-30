// スクリーンリーダー向けの意味づけ（Semantics ツリー）の機械検証（#45）。
//
// ガイドライン系の検証は `accessibility_guidelines_test.dart`、Tab 順・Enter/Space・
// Esc は `home_screen_layout_test.dart` が持つ。ここでは「読み上げられる名前・値・役割・
// 選択状態・画像の代替テキスト」と、OS の「視差効果を減らす」への追従を確かめる。
// 実際の読み上げ（VoiceOver 等）は実機でしか確かめられない
// （docs/accessibility.md の【kako-jun 実機】）。

import 'dart:async';
import 'dart:ui' as ui;
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/services/filter_service.dart';
import 'package:universal_experience/services/loupe_window_controller.dart';
import 'package:universal_experience/services/vision_filter_metadata.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart'
    show Urgency;
import 'package:universal_experience/services/color_vision_selection.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';
import 'package:universal_experience/ui/widgets/filter_list_tile.dart';
import 'package:universal_experience/ui/widgets/image_source_picker.dart';
import 'package:universal_experience/ui/widgets/loupe_hud.dart';

import 'support/home_screen_harness.dart';
import 'support/sample_image_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installHomeScreenFixtures);
  tearDown(() {
    resetHomeScreenFixtures();
    previewSourceImageLoader = BeforeAfterView.loadPreviewSourceImage;
    afterImageRenderer = BeforeAfterView.renderAfter;
  });

  const wide = Size(1280, 800);

  Future<void> installFakes(WidgetTester tester) async {
    late ui.Image master;
    await tester.runAsync(() async {
      master = await generateSampleImage(64);
    });
    addTearDown(master.dispose);
    previewSourceImageLoader = (source, size) async => master.clone();
    afterImageRenderer = (source, filter, strength) async => master.clone();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  /// [finder] に合う唯一のノードの、読み上げ用のデータ。
  SemanticsData dataOf(WidgetTester tester, Finder finder) =>
      tester.getSemantics(finder).getSemanticsData();

  group('スライダー・ドロップダウンの名前と値', () {
    testWidgets('強度スライダーは名前「強さ」と「NN%」の値を持つ', (tester) async {
      final handle = tester.ensureSemantics();
      await installFakes(tester);
      final h = await pumpHomeScreen(tester, size: wide);
      selectColorVision(
          h.filterService, h.visionState, ColorVisionType.protanopia);
      await settle(tester);

      final slider = find.byType(Slider);
      expect(slider, findsOneWidget);
      final data = dataOf(tester, slider);
      expect(data.label, startsWith('強さ'));
      expect(data.value, matches(RegExp(r'^\d+%$')));
      expect(data.flagsCollection.isSlider, isTrue);
      handle.dispose();
    });

    testWidgets('en では名前が Intensity になる', (tester) async {
      final handle = tester.ensureSemantics();
      await installFakes(tester);
      final h =
          await pumpHomeScreen(tester, size: wide, locale: const Locale('en'));
      selectColorVision(
          h.filterService, h.visionState, ColorVisionType.protanopia);
      await settle(tester);

      expect(
          dataOf(tester, find.byType(Slider)).label, startsWith('Intensity'));
      handle.dispose();
    });

    testWidgets('advanced の強度スライダー・列挙ドロップダウンが名前を持つ', (tester) async {
      final handle = tester.ensureSemantics();
      await installFakes(tester);
      final h = await pumpHomeScreen(tester, size: wide);
      h.visionState.select('glaucoma');
      await settle(tester);

      final strength = dataOf(tester, find.byType(Slider));
      expect(strength.label, startsWith('強さ'));
      expect(strength.value, matches(RegExp(r'^\d+%$')));
      final dropdown = dataOf(tester, find.byType(DropdownButton<String>));
      expect(dropdown.label, contains('欠け方のタイプ'));
      handle.dispose();
    });

    testWidgets('小数パラメータのスライダーは名前と小数の値を読む', (tester) async {
      final handle = tester.ensureSemantics();
      await installFakes(tester);
      final h = await pumpHomeScreen(tester, size: wide);
      h.visionState.select('floaters');
      await settle(tester);

      final count = tester.widgetList<Slider>(find.byType(Slider)).length;
      expect(count, greaterThanOrEqualTo(2));
      final named = [
        for (var i = 0; i < count; i++)
          dataOf(tester, find.byType(Slider).at(i)),
      ];
      for (final data in named) {
        expect(data.label, isNotEmpty);
        expect(data.value, isNotEmpty);
      }
      expect(named.map((d) => d.value),
          contains(matches(RegExp(r'^\d+\.\d{2}$'))));
      handle.dispose();
    });

    testWidgets('整数パラメータのスライダーは整数の値を読む', (tester) async {
      final handle = tester.ensureSemantics();
      await installFakes(tester);
      final h = await pumpHomeScreen(tester, size: wide);
      h.visionState.select('starbursts');
      await settle(tester);

      final count = tester.widgetList<Slider>(find.byType(Slider)).length;
      final values = [
        for (var i = 0; i < count; i++)
          dataOf(tester, find.byType(Slider).at(i)).value,
      ];
      expect(values, contains(matches(RegExp(r'^\d+$'))));
      handle.dispose();
    });
  });

  group('見出し', () {
    testWidgets('一覧・調整の見出しは header の役割を持つ', (tester) async {
      final handle = tester.ensureSemantics();
      await installFakes(tester);
      await pumpHomeScreen(tester, size: wide);
      await settle(tester);

      for (final text in ['見え方を選ぶ', '調整']) {
        final data = dataOf(tester, find.text(text));
        expect(data.flagsCollection.isHeader, isTrue, reason: '「$text」は見出し');
      }
      handle.dispose();
    });

    testWidgets('何も選んでいない空状態の見出しも header', (tester) async {
      final handle = tester.ensureSemantics();
      await installFakes(tester);
      await pumpHomeScreen(tester, size: wide);
      await settle(tester);

      final data = dataOf(tester, find.text('何も選択されていません'));
      expect(data.flagsCollection.isHeader, isTrue);
      handle.dispose();
    });

    testWidgets('初回バナーの題は header', (tester) async {
      final handle = tester.ensureSemantics();
      await installFakes(tester);
      await pumpHomeScreen(tester, size: wide);
      await settle(tester);

      final data = dataOf(tester, find.text('はじめての方へ'));
      expect(data.flagsCollection.isHeader, isTrue);
      handle.dispose();
    });
  });

  group('選択状態（色だけで伝えない）', () {
    testWidgets('選んだ行だけが selected で、ほかの行は selected でない', (tester) async {
      final handle = tester.ensureSemantics();
      await installFakes(tester);
      final h = await pumpHomeScreen(tester, size: wide);
      h.visionState.select('glaucoma');
      await settle(tester);

      final tiles = find.byType(FilterListTile);
      final count = tester.widgetList(tiles).length;
      var selected = 0;
      for (var i = 0; i < count; i++) {
        final data = dataOf(tester, tiles.at(i));
        if (data.flagsCollection.isSelected == Tristate.isTrue) selected++;
      }
      expect(count, greaterThan(1));
      expect(selected, 1);
      handle.dispose();
    });

    testWidgets('選択行には選択済みを示すアイコンがあり、未選択行にはない', (tester) async {
      final handle = tester.ensureSemantics();
      await installFakes(tester);
      final h = await pumpHomeScreen(tester, size: wide);
      h.visionState.select('glaucoma');
      await settle(tester);

      final checks = find.descendant(
          of: find.byType(FilterListTile),
          matching: find.byIcon(Icons.check_box));
      expect(checks, findsOneWidget);
      handle.dispose();
    });
  });

  group('プレビュー画像の代替テキスト（読み上げツリーで確かめる）', () {
    // 読み上げツリー（find.bySemanticsLabel / getSemantics）で見る。ウィジェットの
    // Semantics プロパティだけを見ると、ExcludeSemantics で包んで読み上げから
    // 消えてしまっても通ってしまう。プレビューの見出し・画像は貼り付け領域の
    // ノードにまとめて読まれるので、そのまとまりの label を行ごとに見る。
    Finder previewNode() =>
        find.bySemanticsLabel(RegExp(r'ビフォー / アフター|Before / After'));

    List<String> readLines(WidgetTester tester) {
      final node = previewNode();
      expect(node, findsOneWidget);
      return dataOf(tester, node).label.split('\n');
    }

    /// 読み上げツリー全体で、[text] が読み上げに出てくる回数。
    /// まとまったノード（貼り付け領域）の中だけを数えると、画像が別ノードに分かれたときの
    /// 二重読み上げを見逃す。ほかのノードに畳み込まれたノードは、畳み込み先の label に
    /// 含まれるので数えない。
    int readoutCount(WidgetTester tester, String text) {
      var count = 0;
      void visit(SemanticsNode node) {
        if (!node.isMergedIntoParent) {
          count += text.allMatches(node.getSemanticsData().label).length;
        }
        node.visitChildren((child) {
          visit(child);
          return true;
        });
      }

      visit(tester
          .binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!);
      return count;
    }

    testWidgets('適用後の画像は「〇〇を適用した画像」と読まれる', (tester) async {
      final handle = tester.ensureSemantics();
      await installFakes(tester);
      final h = await pumpHomeScreen(tester, size: wide);
      selectColorVision(
          h.filterService, h.visionState, ColorVisionType.protanopia);
      await settle(tester);

      final lines = readLines(tester);
      expect(lines.where((l) => l.endsWith('を適用した画像')), hasLength(1));
      expect(dataOf(tester, previewNode()).flagsCollection.isImage, isTrue,
          reason: 'image の役割が読み上げに含まれる');
      handle.dispose();
    });

    testWidgets('「元の画像」は 1 回だけ読まれる（見出しと代替テキストの二重読み上げの回避）', (tester) async {
      final handle = tester.ensureSemantics();
      await installFakes(tester);
      final h = await pumpHomeScreen(tester, size: wide);
      selectColorVision(
          h.filterService, h.visionState, ColorVisionType.protanopia);
      await settle(tester);

      expect(readoutCount(tester, '元の画像'), 1,
          reason: '見出しだけが読む。画像に同じ文言の代替テキストを足すと 2 になる');
      handle.dispose();
    });

    testWidgets('en の適用後画像は Image with … applied', (tester) async {
      final handle = tester.ensureSemantics();
      await installFakes(tester);
      final h =
          await pumpHomeScreen(tester, size: wide, locale: const Locale('en'));
      selectColorVision(
          h.filterService, h.visionState, ColorVisionType.protanopia);
      await settle(tester);

      expect(
        readLines(tester)
            .where((l) => RegExp(r'^Image with .+ applied$').hasMatch(l)),
        hasLength(1),
      );
      handle.dispose();
    });

    testWidgets('何も選んでいないときは、見出し以外に画像の代替テキストを足さない', (tester) async {
      final handle = tester.ensureSemantics();
      await installFakes(tester);
      await pumpHomeScreen(tester, size: wide);
      await settle(tester);

      expect(readLines(tester).where((l) => l.endsWith('を適用した画像')), isEmpty);
      // 左右の見出しの 2 回だけ。画像の代替テキストで増えない。
      expect(readoutCount(tester, '元の画像'), 2);
      handle.dispose();
    });

    testWidgets('描画が済むまでは「準備中」だけで、適用後画像の代替テキストは読まれない', (tester) async {
      final handle = tester.ensureSemantics();
      await installFakes(tester);
      final pending = Completer<ui.Image>();
      late ui.Image rendered;
      await tester.runAsync(() async {
        rendered = await generateSampleImage(64);
      });
      addTearDown(rendered.dispose);
      afterImageRenderer = (source, filter, strength) => pending.future;
      final h = await pumpHomeScreen(tester, size: wide);
      selectColorVision(
          h.filterService, h.visionState, ColorVisionType.protanopia);
      await settle(tester);

      expect(find.text('プレビューを準備中…'), findsOneWidget);
      expect(readoutCount(tester, 'を適用した画像'), 0, reason: '準備中は画像として読まない');

      pending.complete(rendered.clone());
      await settle(tester);
      expect(
          readLines(tester).where((l) => l.endsWith('を適用した画像')), hasLength(1));
      handle.dispose();
    });

    testWidgets('準備中の表示は liveRegion として読み上げられる', (tester) async {
      final handle = tester.ensureSemantics();
      await installFakes(tester);
      // 描画が終わらないようにして、`_loading && _before == null` の準備中表示を保つ。
      afterImageRenderer =
          (source, filter, strength) => Completer<ui.Image>().future;
      await pumpHomeScreen(tester, size: wide);
      await settle(tester);

      final preparing = find.text('プレビューを準備中…');
      expect(preparing, findsOneWidget);
      expect(dataOf(tester, preparing).flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });

    testWidgets('描画に失敗したら liveRegion で伝える', (tester) async {
      final handle = tester.ensureSemantics();
      await installFakes(tester);
      afterImageRenderer =
          (source, filter, strength) async => throw StateError('render failed');
      final h = await pumpHomeScreen(tester, size: wide);
      selectColorVision(
          h.filterService, h.visionState, ColorVisionType.protanopia);
      await settle(tester);

      // 失敗は FlutterError.reportError に流れるので、ここで受け取って消費する。
      expect(tester.takeException(), isNotNull);
      final data = dataOf(tester, find.text('プレビューの描画に失敗しました'));
      expect(data.flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });

    testWidgets('描画器が null を返したら失敗として扱い、空の枠を「画像」として読まない', (tester) async {
      final handle = tester.ensureSemantics();
      await installFakes(tester);
      // 何も選んでいないとき（filter == null）は成功し、フィルタを選ぶと null を返す。
      final succeed = afterImageRenderer;
      afterImageRenderer = (source, filter, strength) async =>
          filter == null ? succeed(source, filter, strength) : null;
      final h = await pumpHomeScreen(tester, size: wide);
      await settle(tester);
      selectColorVision(
          h.filterService, h.visionState, ColorVisionType.protanopia);
      await settle(tester);

      expect(tester.takeException(), isNotNull);
      final data = dataOf(tester, find.text('プレビューの描画に失敗しました'));
      expect(data.flagsCollection.isLiveRegion, isTrue);
      expect(readoutCount(tester, 'を適用した画像'), 0,
          reason: '空の枠を「〇〇を適用した画像」と読まない');
      handle.dispose();
    });
  });

  group('視差効果を減らす設定（disableAnimations）', () {
    Future<void> setDisableAnimations(WidgetTester tester, bool value) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: value);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    }

    Duration pickerDropDuration(WidgetTester tester) {
      final container = find.descendant(
          of: find.byType(ImageSourcePicker),
          matching: find.byType(AnimatedContainer));
      expect(container, findsOneWidget);
      return tester.widget<AnimatedContainer>(container).duration;
    }

    testWidgets('ON: 画像ドロップ枠の遷移が 0', (tester) async {
      await installFakes(tester);
      await setDisableAnimations(tester, true);
      await pumpHomeScreen(tester, size: wide);
      expect(pickerDropDuration(tester), Duration.zero);
    });

    testWidgets('OFF: 画像ドロップ枠の遷移は従来どおり（0 でない）', (tester) async {
      await installFakes(tester);
      await setDisableAnimations(tester, false);
      await pumpHomeScreen(tester, size: wide);
      expect(pickerDropDuration(tester), greaterThan(Duration.zero));
    });

    /// ルーペ HUD を出して、そのフェード（AnimatedOpacity）の長さを返す。
    Future<Duration> hudFadeDuration(WidgetTester tester) async {
      visionFilterUrgencyProvider = (_) => Urgency.none;
      visionFilterUrgencyEscalationProvider = (_) => const [];
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final visionState = VisionFilterState()..select('photophobia');
      final filterService = FilterService(visionState: visionState);
      final loupe = LoupeWindowController();
      await tester.runAsync(() => loupe.setAppMode(AppMode.loupe));
      tester.view.physicalSize = const Size(900, 300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<VisionFilterState>.value(value: visionState),
            ChangeNotifierProvider<FilterService>.value(value: filterService),
            ChangeNotifierProvider<LoupeWindowController>.value(value: loupe),
          ],
          child: const MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: LoupeHud()),
          ),
        ),
      );
      await settle(tester);
      final fade = find.descendant(
          of: find.byType(LoupeHud), matching: find.byType(AnimatedOpacity));
      expect(fade, findsOneWidget);
      return tester.widget<AnimatedOpacity>(fade).duration;
    }

    testWidgets('ON: ルーペ HUD のフェードが 0', (tester) async {
      await setDisableAnimations(tester, true);
      expect(await hudFadeDuration(tester), Duration.zero);
    });

    testWidgets('OFF: ルーペ HUD のフェードは従来どおり（0 でない）', (tester) async {
      await setDisableAnimations(tester, false);
      expect(await hudFadeDuration(tester), greaterThan(Duration.zero));
    });

    /// 縦長の一覧で末尾の行を選び、選択の 20ms 後と落ち着いた後のスクロール量を返す。
    /// 瞬時なら 20ms 後にもう最終位置にいて、アニメーションならまだ途中にいる。
    Future<(double, double)> scrollAfterSelecting(WidgetTester tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      var selected = -1;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child: StatefulBuilder(
                builder: (context, setState) {
                  rebuild = setState;
                  // ListView だと画面外の行は作られず State が無いので、全行を作る。
                  return SingleChildScrollView(
                    controller: controller,
                    child: Column(
                      children: [
                        for (var i = 0; i < 30; i++)
                          FilterListTile(
                            key: ValueKey(i),
                            title: 'row $i',
                            selected: i == selected,
                            onTap: () {},
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      rebuild(() => selected = 25);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      final early = controller.offset;
      await tester.pumpAndSettle();
      return (early, controller.offset);
    }

    testWidgets('ON: 選んだ行へのスクロールが瞬時', (tester) async {
      await setDisableAnimations(tester, true);
      final (early, end) = await scrollAfterSelecting(tester);
      expect(end, greaterThan(100), reason: '末尾の行まで実際にスクロールしている');
      expect(early, closeTo(end, 0.5), reason: '20ms 後にはもう最終位置');
    });

    testWidgets('OFF: 選んだ行へのスクロールはアニメーション（20ms 後は途中）', (tester) async {
      await setDisableAnimations(tester, false);
      final (early, end) = await scrollAfterSelecting(tester);
      expect(end, greaterThan(100));
      expect(early, lessThan(end - 1), reason: '20ms 後はまだ途中');
    });
  });

  group('キーボードでダイアログを閉じる', () {
    testWidgets('言語ダイアログは Enter で開き、Esc で閉じて、フォーカスが開いたボタンに戻る', (tester) async {
      await installFakes(tester);
      await pumpHomeScreen(tester, size: wide);
      // IconButton の内側（InkResponse）の Focus。Tooltip は外側にあるので Icon から辿る。
      final icon = find.descendant(
          of: find.byTooltip('言語'), matching: find.byType(Icon));
      final focus = Focus.of(tester.element(icon));
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasPrimaryFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(focus.hasPrimaryFocus, isTrue, reason: '閉じたあと、開いたボタンから操作を続けられる');
    });
  });
}
