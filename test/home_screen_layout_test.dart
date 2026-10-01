// HomeScreen の画面構成（#72 フェーズ B）の widget test。
//
// 広幅（>=1000dp）は 3 カラム「選ぶ / 見る / 調整」、狭幅は縦積み（プレビュー →
// 調整 → 選択）。プレビューが最初のビューポートに収まること、一覧の選択が右カラムに
// 反映されること、クリックスルー ON の復帰方法が主画面に常時見えること、`/` で検索欄へ
// 移ること、何も選んでいないときの空状態を確認する。
//
// 注意: ハーネスはプレビュー画像を「準備中」のプレースホルダのまま止める。
// 「最初のビューポートに収まる」は準備中と、画像が載った状態（読み込み済み）の両方で
// 測る（読み込み済みは縦が大きくなる。#130）。
// 「フィルタを選んだまま runAsync で実時間を進めても例外が出ない」テストは、
// ハーネスの契約（Rust 非依存の供給源）を守る回帰テスト（#127）。

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/main.dart' show WindowModeUiContext;
import 'package:universal_experience/services/filter_list_selection.dart';
import 'package:universal_experience/services/hotkey_service.dart';
import 'package:universal_experience/services/loupe_window_controller.dart';
import 'package:universal_experience/services/vision_filter_metadata.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/screens/home_screen.dart'
    show kMinPreviewPaneSide, previewPaneSideFor;
import 'package:universal_experience/ui/widgets/adjust_panel.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';
import 'package:universal_experience/ui/widgets/consult_notice_block.dart';
import 'package:universal_experience/ui/widgets/experience_presets.dart';
import 'package:universal_experience/ui/widgets/filter_browser.dart';
import 'package:universal_experience/ui/widgets/filter_list_tile.dart';
import 'package:universal_experience/ui/widgets/image_source_picker.dart';
import 'package:universal_experience/ui/widgets/welcome_banner.dart';
import 'package:universal_experience/ui/widgets/language_dialog.dart';
import 'package:universal_experience/ui/widgets/window_mode_panel.dart';

import 'support/home_screen_harness.dart';
import 'support/color_vision_select.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installHomeScreenFixtures);
  tearDown(resetHomeScreenFixtures);

  const wide = Size(1280, 800);
  const narrow = Size(800, 700);
  // LoupeWindowPolicy.defaultSize（起動時の既定ウィンドウ）。
  const defaultWindow = LoupeWindowPolicy.defaultSize;
  // 広幅で低い画面（ノート PC の縮めたウィンドウなど）。
  const wideLow = Size(1280, 480);

  FilterListEntry entry(String key) =>
      kFilterListEntries.firstWhere((e) => e.key == key);

  // 画像が載った状態（ハーネスの既定は「準備中」で止める）。
  void loadPreviewImages() {
    previewSourceImageLoader = (source, size) async => fixturePreviewImage();
  }

  for (final (stateLabel, loaded) in [('準備中', false), ('読み込み済み', true)]) {
    group('プレビューは最初のビューポートに収まる（$stateLabel）', () {
      for (final (label, size) in [
        ('広幅 1280x800', wide),
        ('狭幅 800x700', narrow),
        ('既定ウィンドウ 800x600', defaultWindow),
      ]) {
        testWidgets(label, (tester) async {
          if (loaded) loadPreviewImages();
          await pumpHomeScreen(tester, size: size);
          if (loaded) {
            // 画像が載っている（準備中のプレースホルダで測っていない）。
            final panes = tester.widgetList<PreviewImageView>(
              find.byType(PreviewImageView),
            );
            expect(panes.length, 2);
            expect(panes.every((p) => p.image != null), isTrue);
          }

          for (final finder in [
            find.byType(BeforeAfterView),
            find.byType(ImageSourcePicker),
          ]) {
            expect(finder, findsOneWidget);
            final rect = tester.getRect(finder);
            expect(rect.top, greaterThanOrEqualTo(0), reason: '$label $finder');
            expect(rect.bottom, lessThanOrEqualTo(size.height),
                reason: '$label $finder はビューポート内に収まる');
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(size.width));
          }
        });
      }
    });
  }

  group('previewPaneSideFor（#130）', () {
    // 画像以外の高さ 360 を引いた残りが一辺。下限は kMinPreviewPaneSide。
    test('下限 + 画像以外の高さ（520）ちょうどで下限、1 足すと 1 増える', () {
      expect(previewPaneSideFor(520), kMinPreviewPaneSide);
      expect(previewPaneSideFor(521), kMinPreviewPaneSide + 1);
      expect(previewPaneSideFor(519), kMinPreviewPaneSide);
    });

    test('小数の高さは切り捨てる', () {
      expect(previewPaneSideFor(544), 184);
      expect(previewPaneSideFor(544.9), 184);
    });

    test('負・0・極端に小さい高さは下限になる', () {
      expect(previewPaneSideFor(-100), kMinPreviewPaneSide);
      expect(previewPaneSideFor(0), kMinPreviewPaneSide);
      expect(previewPaneSideFor(1), kMinPreviewPaneSide);
    });

    test('高さが無制限（double.infinity）なら上限なし', () {
      expect(previewPaneSideFor(double.infinity), double.infinity);
    });
  });

  group('プレビュー画像の高さ配分（読み込み済み）', () {
    // 画像 1 枚（正方形）の一辺。
    double paneSide(WidgetTester tester) {
      final rect = tester.getRect(find.byType(PreviewImageView).first);
      expect(rect.width, closeTo(rect.height, 0.01), reason: '画像は正方形');
      return rect.width;
    }

    Future<double> sideAt(WidgetTester tester, Size size) async {
      loadPreviewImages();
      await pumpHomeScreen(tester, size: size);
      return paneSide(tester);
    }

    testWidgets('既定 800x600: 画像は下限より大きく、選択欄の下に余白が残る', (tester) async {
      final side = await sideAt(tester, defaultWindow);
      expect(side, greaterThan(kMinPreviewPaneSide));
      // 本体領域の高さ 544（600 - AppBar 56）から、画像以外の高さ 360 を引いた値。
      expect(side, closeTo(184, 0.01));
      final picker = tester.getRect(find.byType(ImageSourcePicker));
      expect(picker.bottom, lessThanOrEqualTo(defaultWindow.height - 8),
          reason: '選択欄の下端がウィンドウの縁に貼り付かない');
    });

    testWidgets('高さが足りなくても画像は下限（kMinPreviewPaneSide）を割らない（狭幅 800x400）',
        (tester) async {
      expect(await sideAt(tester, const Size(800, 400)),
          closeTo(kMinPreviewPaneSide, 0.01));
      expect(tester.takeException(), isNull);
    });

    testWidgets('高さが足りなくても画像は下限を割らない（低い広幅 1280x480）', (tester) async {
      expect(await sideAt(tester, wideLow), closeTo(kMinPreviewPaneSide, 0.01));
      expect(tester.takeException(), isNull);
    });

    testWidgets('余裕のある高さでは縮めない: 狭幅 800x700 は従来の 256', (tester) async {
      expect(await sideAt(tester, narrow), closeTo(256, 0.01));
    });

    testWidgets('余裕のある高さでは縮めない: 広幅 1280x800 は中央カラムの幅いっぱい（従来どおり）',
        (tester) async {
      final side = await sideAt(tester, wide);
      final preview = tester.getRect(find.byType(BeforeAfterView));
      // 画像 2 枚 + 間の 12。
      expect(side * 2 + 12, closeTo(preview.width, 0.01));
    });

    for (final (low, high) in [(560.0, 600.0), (600.0, 640.0)]) {
      testWidgets('高さに追従する: ${low.toInt()} より ${high.toInt()} の方が大きい',
          (tester) async {
        final small = await sideAt(tester, Size(800, low));
        // 同じテストの中で作り直すため、いったん外す。
        await tester.pumpWidget(const SizedBox());
        final large = await sideAt(tester, Size(800, high));
        expect(large, greaterThan(small));
      });
    }

    testWidgets('クリックスルーの案内が出ていても下限は守る（既定 800x600）', (tester) async {
      loadPreviewImages();
      const uiContext = WindowModeUiContext(
        trayAvailable: true,
        hotkeyStatus: HotkeyStatus(),
      );
      final h = await pumpHomeScreen(tester,
          size: defaultWindow, uiContext: uiContext);
      await tester.runAsync(() => h.loupe.setAppMode(AppMode.loupe));
      await tester.runAsync(() => h.loupe.setClickThrough(true));
      await tester.pump();
      expect(paneSide(tester), greaterThanOrEqualTo(kMinPreviewPaneSide));
      expect(tester.takeException(), isNull);
      await tester.runAsync(() => h.loupe.setClickThrough(false));
      await tester.runAsync(() => h.loupe.setAppMode(AppMode.settings));
    });
  });

  testWidgets('既定ウィンドウは LoupeWindowPolicy.defaultSize（800x600）',
      (tester) async {
    expect(defaultWindow, const Size(800, 600));
  });

  group('広幅で低い画面（1280x480）', () {
    Future<HomeScreenHarness> pumpLow(WidgetTester tester) async {
      const uiContext = WindowModeUiContext(
        trayAvailable: true,
        hotkeyStatus: HotkeyStatus(),
      );
      final h =
          await pumpHomeScreen(tester, size: wideLow, uiContext: uiContext);
      // クリックスルー復帰バナーを出した状態（縦の余白が最も少ない）。
      await tester.runAsync(() => h.loupe.setAppMode(AppMode.loupe));
      await tester.runAsync(() => h.loupe.setClickThrough(true));
      await tester.pump();
      return h;
    }

    testWidgets('復帰バナー表示中でも overflow せず、一覧は操作できる高さを持つ', (tester) async {
      final h = await pumpLow(tester);
      expect(find.text('クリックスルーが ON です。解除するには:'), findsOneWidget);
      // RenderFlex overflow などのレイアウト例外が出ていない。
      expect(tester.takeException(), isNull);

      final list = tester.getRect(find.descendant(
        of: find.byType(FilterBrowser),
        matching: find.byType(SingleChildScrollView),
      ));
      expect(list.height, greaterThanOrEqualTo(96),
          reason: '一覧が操作できる高さを持つ（検索欄・カテゴリが固定で食い潰さない）');
      // 検索欄は見えていて、一覧の行をタップして選べる。
      expect(
          tester.getRect(find.byType(TextField)).top, greaterThanOrEqualTo(0));
      final tile = find.byKey(filterListTileKey(entry('cv:protanopia')));
      await tester.ensureVisible(tile);
      await tester.pump();
      await tester.tap(tile);
      await tester.pump();
      expect(h.visionState.focusedId, 'protanopia');
      expect(tester.takeException(), isNull);

      await tester.runAsync(() => h.loupe.setClickThrough(false));
      await tester.runAsync(() => h.loupe.setAppMode(AppMode.settings));
    });

    testWidgets('カテゴリのチップも一覧のスクロールに含まれ、届く・押せる', (tester) async {
      final h = await pumpLow(tester);
      final chip = find.widgetWithText(ChoiceChip, '視野');
      // 見出しとカテゴリは一覧と一緒にスクロールするので、下の行を見たあとも戻れる。
      final last = find.byKey(filterListTileKey(kFilterListEntries.last));
      await tester.ensureVisible(last);
      await tester.pump();
      await tester.ensureVisible(chip.first);
      await tester.pump();
      expect(chip, findsWidgets);
      await tester.runAsync(() => h.loupe.setClickThrough(false));
      await tester.runAsync(() => h.loupe.setAppMode(AppMode.settings));
    });
  });

  testWidgets('フィルタを選んだまま実時間が進んでも、プレビューは Rust に触れず例外を出さない', (tester) async {
    // 実ブリッジ（native lib / RustLib.init()）が無い環境で、読み込み済みのプレビューに
    // 実フィルタを適用しに行くと FRB 未初期化の非同期例外が漏れる（過去に別テストへ
    // 漏れて不安定になった）。ハーネスの供給源が Rust 非依存であることを、実時間が
    // 進む `runAsync` をまたいで確かめる。
    // 画像が載った状態にする（既定のハーネスは「準備中」で止める）。フィルタ適用は
    // ハーネスの既定（Rust 非依存）のまま。
    loadPreviewImages();
    await pumpHomeScreen(
      tester,
      size: wide,
      select: (s) => selectColorVisionKey(s, 'protanopia'),
    );
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
    // 失敗扱い（再読み込みを促す UI）に落ちていない = 描画が成功した。
    expect(find.byType(PreviewErrorPlaceholder), findsNothing);
    final panes = tester.widgetList<PreviewImageView>(
      find.byType(PreviewImageView),
    );
    expect(panes.length, 2);
    expect(panes.every((p) => p.image != null), isTrue);
  });

  testWidgets('広幅は 3 カラム（左=選ぶ・中=見る・右=調整）で横に並ぶ', (tester) async {
    await pumpHomeScreen(tester, size: wide);

    final browser = tester.getRect(find.byType(FilterBrowser));
    final preview = tester.getRect(find.byType(BeforeAfterView));
    final adjust = tester.getRect(find.byType(AdjustPanel));
    expect(browser.right, lessThanOrEqualTo(preview.left));
    expect(preview.right, lessThanOrEqualTo(adjust.left));
  });

  testWidgets('Tab は 左 → 中央 → 右 の順に進み、右カラム（調整）へ届く', (tester) async {
    // 右カラムに操作要素（解除ボタン・強度スライダー）を出すため、色覚を選んでおく。
    await pumpHomeScreen(
      tester,
      size: wide,
      select: (s) => selectColorVisionKey(s, 'protanopia'),
    );
    final browser = tester.getRect(find.byType(FilterBrowser));
    final adjust = tester.getRect(find.byType(AdjustPanel));

    // 0=左 1=中央 2=右。フォーカス中の要素の矩形の位置で判定する。
    int? columnOfFocus() {
      final box =
          tester.binding.focusManager.primaryFocus?.context?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return null;
      final left = box.localToGlobal(Offset.zero).dx;
      if (left >= adjust.left) return 2;
      if (left >= browser.right) return 1;
      return 0;
    }

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(
        tester.binding.focusManager.primaryFocus?.debugLabel, 'filterSearch');

    final visited = <int>[0];
    Widget? rightFocusOwner;
    for (var i = 0; i < 200 && visited.last != 2; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final column = columnOfFocus();
      if (column == null) continue;
      expect(column, greaterThanOrEqualTo(visited.last),
          reason: 'Tab が ${visited.last} 番目のカラムから戻った（$i 回目）');
      visited.add(column);
      if (column == 2) {
        rightFocusOwner =
            tester.binding.focusManager.primaryFocus?.context?.widget;
      }
    }
    expect(visited, containsAllInOrder([0, 1, 2]),
        reason: 'Tab で 左 → 中央 → 右 の順に届く');
    expect(rightFocusOwner, isNotNull);
    // 右カラムでフォーカスが乗った要素は、確かに調整パネルの矩形の中にある。
    final focusedRect = tester.getRect(find.byWidget(rightFocusOwner!).first);
    expect(adjust.overlaps(focusedRect), isTrue);
  });

  testWidgets('狭幅は縦積み（プレビューが選択より上）', (tester) async {
    await pumpHomeScreen(tester, size: narrow);

    final preview = tester.getRect(find.byType(BeforeAfterView));
    // 狭幅の一覧は縦積みの下端にあり、スクロールしないと描画されないことがある。
    final browserFinder = find.byType(FilterBrowser, skipOffstage: false);
    final browser = tester.getRect(browserFinder);
    expect(preview.bottom, lessThanOrEqualTo(browser.top));
  });

  group('空状態', () {
    for (final (label, size) in [('広幅', wide), ('狭幅', narrow)]) {
      testWidgets('何も選んでいないと「何も選択されていません」だけを出す（$label）', (tester) async {
        await pumpHomeScreen(tester, size: size);

        expect(find.text('何も選択されていません'), findsOneWidget);
        // 強度・受診喚起・パラメータの空カードは出さない。
        expect(
            find.byType(ConsultNoticeBlock, skipOffstage: false), findsNothing);
        expect(find.byType(Slider, skipOffstage: false), findsNothing);
      });
    }

    testWidgets('選択を解除すると空状態に戻る', (tester) async {
      final h = await pumpHomeScreen(
        tester,
        size: wide,
        select: (s) => selectColorVisionKey(s, 'protanopia'),
      );
      expect(find.text('何も選択されていません'), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, 'フィルタを解除'));
      await tester.pump();

      expect(h.visionState.selectedId, isNull);
      expect(find.text('何も選択されていません'), findsOneWidget);
    });
  });

  group('一覧の選択が右カラムに反映される', () {
    testWidgets('色覚の行を選ぶと強度スライダーと選んだ症状の説明が右に出る', (tester) async {
      final h = await pumpHomeScreen(tester, size: wide);

      final tile = find.byKey(filterListTileKey(entry('cv:protanopia')));
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pump();

      expect(h.visionState.focusedId, 'protanopia');
      final adjust = find.byType(AdjustPanel);
      expect(
        find.descendant(of: adjust, matching: find.byType(Slider)),
        findsOneWidget,
      );
      expect(find.text('何も選択されていません'), findsNothing);
      // 選んだ行にはチェックが付く。
      expect(
        find.descendant(
            of: tile, matching: find.byIcon(Icons.radio_button_checked)),
        findsOneWidget,
      );
    });

    testWidgets('受診喚起のあるフィルタを選ぶと、強度の下に ConsultNoticeBlock が常時展開で出る',
        (tester) async {
      visionFilterUrgencyProvider = (_) => Urgency.emergency;
      final h = await pumpHomeScreen(tester, size: wide);

      final tile = find.byKey(filterListTileKey(entry('catalog:starbursts')));
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pump();

      expect(h.visionState.selectedId, 'starbursts');
      final adjust = find.byType(AdjustPanel);
      final notice = find.descendant(
          of: adjust, matching: find.byType(ConsultNoticeBlock));
      final slider = find.descendant(of: adjust, matching: find.byType(Slider));
      expect(notice, findsOneWidget);
      expect(slider, findsWidgets);
      // 受診喚起は強度の下（隠さない・動かさない）。
      expect(
        tester.getRect(notice).top,
        greaterThanOrEqualTo(tester.getRect(slider.first).bottom),
      );
    });

    testWidgets('体験プリセットを選ぶと右カラムに名前と説明が出る', (tester) async {
      final h = await pumpHomeScreen(tester, size: wide);

      final tile = find.byKey(experienceCardKey('bppv'));
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pump();

      expect(h.visionState.selectedPresetId, 'bppv');
      expect(find.text('何も選択されていません'), findsNothing);
      expect(
        find.descendant(
            of: find.byType(AdjustPanel), matching: find.byType(Text)),
        findsWidgets,
      );
    });
  });

  group('クリックスルー ON の復帰方法は主画面に常時見える（#63）', () {
    testWidgets('OFF の間は出ない', (tester) async {
      await pumpHomeScreen(tester, size: wide);
      expect(find.text('クリックスルーが ON です。解除するには:'), findsNothing);
    });

    testWidgets('ON にすると最上部に案内（フォーカス復帰・Esc）が出て、OFF で消える', (tester) async {
      const uiContext = WindowModeUiContext(
        trayAvailable: true,
        hotkeyStatus: HotkeyStatus(),
      );
      final h = await pumpHomeScreen(tester, size: wide, uiContext: uiContext);
      await tester.runAsync(() => h.loupe.setAppMode(AppMode.loupe));
      await tester.runAsync(() => h.loupe.setClickThrough(true));
      await tester.pump();

      expect(find.text('クリックスルーが ON です。解除するには:'), findsOneWidget);
      final lines = clickThroughRecoveryLines(
        lookupAppLocalizations(const Locale('ja')),
        uiContext,
      );
      expect(lines.length, greaterThanOrEqualTo(3),
          reason: 'フォーカス復帰・Esc・トレイの 3 本以上');
      for (final line in lines) {
        expect(find.text(line), findsOneWidget, reason: line);
      }
      // 案内は最初のビューポート内（スクロール不要）にある。
      final banner = tester.getRect(find.text('クリックスルーが ON です。解除するには:'));
      expect(banner.bottom, lessThanOrEqualTo(wide.height));
      // ダイアログを開いていなくても見える。
      expect(find.byType(AlertDialog), findsNothing);

      await tester.runAsync(() => h.loupe.setClickThrough(false));
      await tester.pump();
      expect(find.text('クリックスルーが ON です。解除するには:'), findsNothing);

      await tester.runAsync(() => h.loupe.setAppMode(AppMode.settings));
    });

    testWidgets('ON でも案内を出したままプレビューは最初のビューポートに収まる（狭幅・既定ウィンドウ 800x600）',
        (tester) async {
      final h = await pumpHomeScreen(tester, size: defaultWindow);
      await tester.runAsync(() => h.loupe.setAppMode(AppMode.loupe));
      await tester.runAsync(() => h.loupe.setClickThrough(true));
      await tester.pump();

      expect(find.text('クリックスルーが ON です。解除するには:'), findsOneWidget);
      expect(
        tester.getRect(find.byType(BeforeAfterView)).bottom,
        lessThanOrEqualTo(defaultWindow.height),
      );
      // 案内（約 115dp）の分だけ本文が低くなるため、選択欄の下端までは収まらない
      // ことがある（DESIGN.md §6.1）。画像（BeforeAfterView）が収まり、選択欄の
      // 先頭の行が見えていて、スクロールで残りへ届くことを保証する。
      expect(
        tester.getRect(find.text('プレビュー画像')).bottom,
        lessThanOrEqualTo(defaultWindow.height),
      );
      await tester.runAsync(() => h.loupe.setClickThrough(false));
      await tester.runAsync(() => h.loupe.setAppMode(AppMode.settings));
    });
  });

  group('キー操作（#63）', () {
    testWidgets('/ で検索欄にフォーカスが移り、検索欄の中の / は文字として入る', (tester) async {
      await pumpHomeScreen(tester, size: wide);

      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      await tester.pump();
      expect(
          tester.binding.focusManager.primaryFocus?.debugLabel, 'filterSearch');

      await tester.enterText(find.byType(TextField), 'a/b');
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'a/b',
      );
    });

    testWidgets('一覧の行をタップしたあとも ←→ で強度が動く（行にフォーカスを残さない）', (tester) async {
      final h = await pumpHomeScreen(tester, size: wide);
      final tile = find.byKey(filterListTileKey(entry('cv:protanopia')));
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pump();
      h.visionState.setStrength(0.5);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(h.visionState.strength, closeTo(0.55, 1e-9));
    });

    testWidgets('検索で絞ったあとの ↑↓ は、見えている行だけでフォーカスを送り、選択は変えない', (tester) async {
      final h = await pumpHomeScreen(tester, size: wide);
      await tester.enterText(find.byType(TextField), 'protan');
      await tester.pump();
      final visible = visibleFilterListEntries(query: 'protan');
      expect(visible.length, greaterThanOrEqualTo(2));

      // 行をタップして選ぶと、フォーカスはショートカットの受け口へ戻る（検索欄に残らない）。
      final first = find.byKey(filterListTileKey(visible[0]));
      await tester.ensureVisible(first);
      await tester.tap(first);
      await tester.pump();
      expect(selectedFilterListEntry(h.visionState), visible[0]);

      Key? focusedRowKey() => tester.binding.focusManager.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<FilterListTile>()
          ?.key;

      // 受け口からの ↓ は、調整中の層の行（visible[0]）の次の行に入る（先頭へは戻らない）。
      // 以降は見えている行の順に進む。
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(focusedRowKey(), filterListTileKey(visible[1]));

      // 絞り込みの外（一覧全体の次の行）へは出ない: 末尾から ↓ で先頭へ折り返す。
      for (var i = 2; i < visible.length; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(focusedRowKey(), filterListTileKey(visible[0]));

      // ↑↓ では選択（層の集合）は変わらない。Space で初めて足し引きされる。
      expect(h.visionState.layers.map((l) => l.id), ['protanopia']);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(h.visionState.layers.map((l) => l.id), ['protanopia']);
    });
  });

  group('行にフォーカスが無いときの ↑↓ は、調整中の層の行から送る（#120）', () {
    Key? focusedRowKey(WidgetTester tester) =>
        tester.binding.focusManager.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<FilterListTile>()
            ?.key;

    testWidgets('選んだ行が末尾側にあるとき、↑ は末尾ではなく直前の行に入る', (tester) async {
      final h = await pumpHomeScreen(tester, size: wide);
      await tester.enterText(find.byType(TextField), 'protan');
      await tester.pump();
      final visible = visibleFilterListEntries(query: 'protan');
      expect(visible.length, greaterThanOrEqualTo(2));

      final row = find.byKey(filterListTileKey(visible[1]));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pump();
      expect(selectedFilterListEntry(h.visionState), visible[1]);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(focusedRowKey(tester), filterListTileKey(visible[0]));
    });
  });

  group('キーボードで行を選んでもフォーカスは行に残る', () {
    FilterListTile? focusedTile(WidgetTester tester) =>
        tester.binding.focusManager.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<FilterListTile>();

    Future<void> tabUntilTile(WidgetTester tester, Key tileKey) async {
      for (var i = 0; i < 80; i++) {
        if (focusedTile(tester)?.key == tileKey) return;
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      fail('Tab で $tileKey に届かない');
    }

    testWidgets('Enter で選んだあと、フォーカスは同じ行に残り次の Tab は次の行へ進む', (tester) async {
      final h = await pumpHomeScreen(tester, size: wide);
      final first = kFilterListEntries[0];
      final second = kFilterListEntries[1];

      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tabUntilTile(tester, filterListTileKey(first));

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(selectedFilterListEntry(h.visionState), first);
      expect(focusedTile(tester)?.key, filterListTileKey(first),
          reason: 'Enter の活性化ではショートカット受け口へフォーカスを飛ばさない');
      expect(tester.binding.focusManager.primaryFocus?.debugLabel,
          isNot('homeShortcuts'));

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focusedTile(tester)?.key, filterListTileKey(second),
          reason: '次の Tab は先頭からやり直さず、隣の行へ進む');

      // 行の上の ↑ は標準のフォーカス移動（選択は Enter まで変わらない）。
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(focusedTile(tester)?.key, filterListTileKey(first));
      expect(selectedFilterListEntry(h.visionState), first);
    });

    testWidgets('Space でも同じ（フォーカスを行に残す）', (tester) async {
      final h = await pumpHomeScreen(tester, size: wide);
      final first = kFilterListEntries[0];
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tabUntilTile(tester, filterListTileKey(first));

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(selectedFilterListEntry(h.visionState), first);
      expect(focusedTile(tester)?.key, filterListTileKey(first));
    });

    testWidgets('行にフォーカスがある間の ←→ は強度を動かさず、ショートカット受け口へ固定で出る', (tester) async {
      final h = await pumpHomeScreen(tester, size: wide);
      final protan = entry('cv:protanopia');
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tabUntilTile(tester, filterListTileKey(protan));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(selectedFilterListEntry(h.visionState), protan);
      final before = h.visionState.strength;

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      expect(h.visionState.strength, before,
          reason: '行にフォーカスがある間は ←→ を奪わない（強度は動かない）');
      expect(focusedTile(tester), isNull, reason: '代わりにフォーカスは行の外へ出る');

      // 出る先は画面のショートカット受け口に固定（_ListExitToShortcutsPolicy。
      // 幾何に依らない）。挙動が変わればここで落とす。次の ←→ からは強度が動く。
      expect(tester.binding.focusManager.primaryFocus?.debugLabel,
          'homeShortcuts');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(h.visionState.strength, lessThan(before));
    });

    for (final (layoutLabel, size) in [('広幅', wide), ('狭幅', narrow)]) {
      for (final (rowLabel, rowKey) in [
        ('フィルタの行', filterListTileKey(entry('cv:protanopia'))),
        ('体験プリセットの行', experienceCardKey('bppv')),
      ]) {
        for (final (dirLabel, key) in [
          ('→', LogicalKeyboardKey.arrowRight),
          ('←', LogicalKeyboardKey.arrowLeft),
        ]) {
          testWidgets(
              '$layoutLabel: $rowLabel からの $dirLabel は強度を動かさず、ショートカット受け口へ出る',
              (tester) async {
            final h = await pumpHomeScreen(tester, size: size);
            await tester.tap(find.byType(TextField));
            await tester.pump();
            await tabUntilTile(tester, rowKey);
            final before = h.visionState.strength;

            await tester.sendKeyEvent(key);
            await tester.pump();

            expect(h.visionState.strength, before);
            expect(focusedTile(tester), isNull);
            expect(tester.binding.focusManager.primaryFocus?.debugLabel,
                'homeShortcuts');
          });
        }
      }
    }

    testWidgets('ポインタで選ぶとショートカット受け口へフォーカスが戻り ←→ が効く', (tester) async {
      await pumpHomeScreen(tester, size: wide);
      final tile = find.byKey(filterListTileKey(entry('cv:protanopia')));
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pump();

      expect(tester.binding.focusManager.primaryFocus?.debugLabel,
          'homeShortcuts');
    });
  });

  group('↑↓ で動いたフォーカス行は一覧のビューポート内に追従する（両方向・折り返し）', () {
    Rect listViewport(WidgetTester tester) => tester.getRect(find.descendant(
          of: find.byType(FilterBrowser),
          matching: find.byType(SingleChildScrollView),
        ));

    Key? focusedRowKey(WidgetTester tester) =>
        tester.binding.focusManager.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<FilterListTile>()
            ?.key;

    Finder focusedRow(WidgetTester tester) {
      final key = focusedRowKey(tester);
      expect(key, isNotNull, reason: '行にフォーカスがある');
      return find.byKey(key!);
    }

    testWidgets('↑ を連打して一覧の上方向へ進んでもフォーカス行が見える', (tester) async {
      await pumpHomeScreen(tester, size: wide);

      for (var i = 0; i < 25; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        final rect = tester.getRect(focusedRow(tester));
        final vp = listViewport(tester);
        expect(rect.top, greaterThanOrEqualTo(vp.top - 1),
            reason: '↑ ${i + 1} 回目');
        expect(rect.bottom, lessThanOrEqualTo(vp.bottom + 1),
            reason: '↑ ${i + 1} 回目');
      }
    });

    testWidgets('末尾で ↓ すると先頭へ折り返しても見える。先頭で ↑ は検索欄へ戻る', (tester) async {
      final h = await pumpHomeScreen(tester, size: wide);
      final last = kFilterListEntries.last;

      // 受け口から ↑ で末尾の行へ入る。
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(focusedRowKey(tester), filterListTileKey(last));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
          focusedRowKey(tester), filterListTileKey(kFilterListEntries.first));
      var rect = tester.getRect(focusedRow(tester));
      expect(rect.top, greaterThanOrEqualTo(listViewport(tester).top - 1),
          reason: '末尾→先頭');

      // 先頭で ↑ は末尾へ折り返さず検索欄へ戻る（#141）。
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(
          tester.binding.focusManager.primaryFocus?.debugLabel, 'filterSearch');
      expect(h.visionState.layers, isEmpty, reason: '↑↓ では選ばない');
    });
  });

  testWidgets('WelcomeBanner の「ほかの見え方を選ぶ」で検索欄にフォーカスが移る', (tester) async {
    await pumpHomeScreen(tester, size: wide);
    expect(find.byType(WelcomeBanner), findsOneWidget);

    await tester.tap(find.text('ほかの見え方を選ぶ'));
    await tester.pump();
    expect(
        tester.binding.focusManager.primaryFocus?.debugLabel, 'filterSearch');
  });

  group('クリックスルーとダイアログの Esc（#63）', () {
    const banner = 'クリックスルーが ON です。解除するには:';

    testWidgets('ダイアログのスイッチで ON にするとダイアログが自動で閉じ、Esc 1 回で解除される', (tester) async {
      final h = await pumpHomeScreen(tester, size: wide);
      await tester.runAsync(() => h.loupe.setAppMode(AppMode.loupe));
      await tester.pump();

      await tester.tap(find.byTooltip('起動モード'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(SwitchListTile, 'クリックスルー'));
        // setClickThrough の非同期処理（プラグイン呼び出しの失敗ガードなど）を待つ。
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      expect(h.loupe.clickThrough, isTrue);
      expect(find.byType(AlertDialog), findsNothing,
          reason: 'ON にした時点でダイアログは閉じ、復帰方法の案内が見える');
      expect(find.text(banner), findsOneWidget);

      await tester.runAsync(() async {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(h.loupe.clickThrough, isFalse, reason: 'Esc 1 回で解除');
      expect(find.text(banner), findsNothing);
      await tester.runAsync(() => h.loupe.setAppMode(AppMode.settings));
    });

    testWidgets('ホットキー等の別経路で ON になってもダイアログは閉じる', (tester) async {
      final h = await pumpHomeScreen(tester, size: wide);
      await tester.runAsync(() => h.loupe.setAppMode(AppMode.loupe));
      await tester.tap(find.byTooltip('起動モード'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.runAsync(() => h.loupe.setClickThrough(true));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(banner), findsOneWidget);

      await tester.runAsync(() => h.loupe.setClickThrough(false));
      await tester.runAsync(() => h.loupe.setAppMode(AppMode.settings));
    });

    testWidgets('別のダイアログが上に載っているときは、そちらを閉じずに起動モードのダイアログだけ閉じる', (tester) async {
      final h = await pumpHomeScreen(tester, size: wide);
      await tester.runAsync(() => h.loupe.setAppMode(AppMode.loupe));
      await tester.tap(find.byTooltip('起動モード'));
      await tester.pumpAndSettle();
      expect(find.byType(WindowModePanel), findsOneWidget);

      unawaited(showDialog<void>(
        context: tester.element(find.byType(WindowModePanel)),
        builder: (_) => const AlertDialog(content: Text('別のダイアログ')),
      ));
      await tester.pumpAndSettle();
      expect(find.text('別のダイアログ'), findsOneWidget);

      await tester.runAsync(() => h.loupe.setClickThrough(true));
      await tester.pumpAndSettle();

      expect(find.text('別のダイアログ'), findsOneWidget,
          reason: '最上位の別ルートを誤って pop しない');
      expect(find.byType(WindowModePanel), findsNothing,
          reason: '起動モードのダイアログ自身は閉じる');

      await tester.runAsync(() => h.loupe.setClickThrough(false));
      await tester.runAsync(() => h.loupe.setAppMode(AppMode.settings));
    });

    testWidgets('言語ダイアログを開いたままクリックスルーが ON になると、自動で閉じる（#82）', (tester) async {
      final h = await pumpHomeScreen(tester, size: wide);
      await tester.runAsync(() => h.loupe.setAppMode(AppMode.loupe));
      await tester.tap(find.byTooltip('言語'));
      await tester.pumpAndSettle();
      expect(find.byType(LanguageDialog), findsOneWidget);

      await tester.runAsync(() => h.loupe.setClickThrough(true));
      await tester.pumpAndSettle();

      expect(find.byType(LanguageDialog), findsNothing,
          reason: 'ON になるとクリックが素通りして閉じられないので自動で閉じる');
      expect(find.text(banner), findsOneWidget);

      await tester.runAsync(() => h.loupe.setClickThrough(false));
      await tester.runAsync(() => h.loupe.setAppMode(AppMode.settings));
    });

    testWidgets('ON のまま言語ダイアログを開くと、1 回目の Esc は解除・2 回目で閉じる（#82）',
        (tester) async {
      final h = await pumpHomeScreen(tester, size: wide);
      await tester.runAsync(() => h.loupe.setAppMode(AppMode.loupe));
      await tester.runAsync(() => h.loupe.setClickThrough(true));
      await tester.pump();

      await tester.tap(find.byTooltip('言語'));
      await tester.pumpAndSettle();
      expect(find.byType(LanguageDialog), findsOneWidget);

      await tester.runAsync(() async {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(h.loupe.clickThrough, isFalse);
      expect(find.byType(LanguageDialog), findsOneWidget,
          reason: '1 回目の Esc は解除に使い、ダイアログは閉じない');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(LanguageDialog), findsNothing);
      await tester.runAsync(() => h.loupe.setAppMode(AppMode.settings));
    });

    testWidgets('ON のままダイアログを開いた場合、ダイアログの中でも Esc は解除になる（閉じない）', (tester) async {
      final h = await pumpHomeScreen(tester, size: wide);
      await tester.runAsync(() => h.loupe.setAppMode(AppMode.loupe));
      await tester.runAsync(() => h.loupe.setClickThrough(true));
      await tester.pump();

      await tester.tap(find.byTooltip('起動モード'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.runAsync(() async {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(h.loupe.clickThrough, isFalse);
      expect(find.byType(AlertDialog), findsOneWidget,
          reason: '1 回目の Esc は解除に使い、ダイアログは閉じない');

      // OFF になったので、次の Esc は標準どおりダイアログを閉じる。
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.runAsync(() => h.loupe.setAppMode(AppMode.settings));
    });
  });

  testWidgets('AppBar の起動モードのボタンでダイアログが開き、閉じられる', (tester) async {
    await pumpHomeScreen(tester, size: wide);
    expect(find.byType(AlertDialog), findsNothing);

    await tester.tap(find.byTooltip('起動モード'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('閉じる'),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets('このアプリについてで「ライブ画面にはまだ適用されない」注意を読める', (tester) async {
    await pumpHomeScreen(tester, size: wide);

    await tester.tap(find.byTooltip('このアプリについて'));
    await tester.pumpAndSettle();

    expect(find.textContaining('ライブ画面への適用は'), findsOneWidget);
    expect(find.textContaining('プレビューにだけ適用されます'), findsOneWidget);
  });

  test('体験プリセットの供給源は関数ごとに 1 度だけ呼ぶ（差し替えたら取り直す）', () {
    final saved = experiencesProvider;
    addTearDown(() => experiencesProvider = saved);

    var calls = 0;
    List<Experience> counting() {
      calls++;
      return const <Experience>[];
    }

    experiencesProvider = counting;
    availableExperiences();
    availableExperiences();
    availableExperiences();
    expect(calls, 1);

    var otherCalls = 0;
    experiencesProvider = () {
      otherCalls++;
      return const <Experience>[];
    };
    availableExperiences();
    availableExperiences();
    expect(otherCalls, 1);
    expect(calls, 1);
  });
}
