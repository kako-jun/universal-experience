// HomeScreen の画面構成（#72 フェーズ B）の widget test。
//
// 広幅（>=1000dp）は 3 カラム「選ぶ / 見る / 調整」、狭幅は縦積み（プレビュー →
// 調整 → 選択）。プレビューが最初のビューポートに収まること、一覧の選択が右カラムに
// 反映されること、クリックスルー ON の復帰方法が主画面に常時見えること、`/` で検索欄へ
// 移ること、何も選んでいないときの空状態を確認する。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/main.dart' show WindowModeUiContext;
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/services/color_vision_selection.dart';
import 'package:universal_experience/services/filter_list_selection.dart';
import 'package:universal_experience/services/hotkey_service.dart';
import 'package:universal_experience/services/vision_filter_metadata.dart';
import 'package:universal_experience/services/loupe_window_controller.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/widgets/adjust_panel.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';
import 'package:universal_experience/ui/widgets/consult_notice_block.dart';
import 'package:universal_experience/ui/widgets/experience_presets.dart';
import 'package:universal_experience/ui/widgets/filter_browser.dart';
import 'package:universal_experience/ui/widgets/filter_list_tile.dart';
import 'package:universal_experience/ui/widgets/image_source_picker.dart';
import 'package:universal_experience/ui/widgets/intensity_slider.dart';
import 'package:universal_experience/ui/widgets/welcome_banner.dart';
import 'package:universal_experience/ui/widgets/window_mode_panel.dart';

import 'support/home_screen_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installHomeScreenFixtures);
  tearDown(resetHomeScreenFixtures);

  const wide = Size(1280, 800);
  const narrow = Size(800, 700);

  FilterListEntry entry(String key) =>
      kFilterListEntries.firstWhere((e) => e.key == key);

  group('プレビューは最初のビューポートに収まる', () {
    for (final (label, size) in [
      ('広幅 1280x800', wide),
      ('狭幅 800x700', narrow)
    ]) {
      testWidgets(label, (tester) async {
        await pumpHomeScreen(tester, size: size);

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

  testWidgets('広幅は 3 カラム（左=選ぶ・中=見る・右=調整）で、Tab 順は左→中→右', (tester) async {
    await pumpHomeScreen(tester, size: wide);

    final browser = tester.getRect(find.byType(FilterBrowser));
    final preview = tester.getRect(find.byType(BeforeAfterView));
    final adjust = tester.getRect(find.byType(AdjustPanel));
    expect(browser.right, lessThanOrEqualTo(preview.left));
    expect(preview.right, lessThanOrEqualTo(adjust.left));

    // 検索欄（左）→ サンプル切替（中）→ 右カラムの順に Tab で進む。
    final search = find.byType(TextField);
    await tester.tap(search);
    await tester.pump();
    expect(
        tester.binding.focusManager.primaryFocus?.debugLabel, 'filterSearch');
    // 左カラムの中で完結する間は左のまま、最後まで進むと中央へ入る。
    var reachedCenter = false;
    for (var i = 0; i < 80 && !reachedCenter; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focused = tester.binding.focusManager.primaryFocus?.context;
      if (focused == null) continue;
      final box = focused.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        final x = box.localToGlobal(Offset.zero).dx;
        if (x >= browser.right) reachedCenter = true;
      }
    }
    expect(reachedCenter, isTrue, reason: 'Tab で左カラムを抜けて中央へ進める');
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
        expect(find.byType(IntensitySlider, skipOffstage: false), findsNothing);
        expect(
            find.byType(ConsultNoticeBlock, skipOffstage: false), findsNothing);
        expect(find.byType(Slider, skipOffstage: false), findsNothing);
      });
    }

    testWidgets('選択を解除すると空状態に戻る', (tester) async {
      final h = await pumpHomeScreen(
        tester,
        size: wide,
        select: (f, s) => selectColorVision(f, s, ColorVisionType.protanopia),
      );
      expect(find.text('何も選択されていません'), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, 'フィルタを解除'));
      await tester.pump();

      expect(h.visionState.selectedId, isNull);
      expect(find.text('何も選択されていません'), findsOneWidget);
      await h.filterService.flush();
    });
  });

  group('一覧の選択が右カラムに反映される', () {
    testWidgets('色覚の行を選ぶと強度スライダーと選んだ症状の説明が右に出る', (tester) async {
      final h = await pumpHomeScreen(tester, size: wide);

      final tile = find.byKey(filterListTileKey(entry('cv:protanopia')));
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pump();

      expect(h.visionState.colorVisionType, ColorVisionType.protanopia);
      final adjust = find.byType(AdjustPanel);
      expect(
        find.descendant(of: adjust, matching: find.byType(Slider)),
        findsOneWidget,
      );
      expect(find.text('何も選択されていません'), findsNothing);
      // 選んだ行にはチェックが付く。
      expect(
        find.descendant(of: tile, matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );
      await h.filterService.flush();
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

    testWidgets('ON でも案内を出したままプレビューは最初のビューポートに収まる（狭幅）', (tester) async {
      final h = await pumpHomeScreen(tester, size: narrow);
      await tester.runAsync(() => h.loupe.setAppMode(AppMode.loupe));
      await tester.runAsync(() => h.loupe.setClickThrough(true));
      await tester.pump();

      expect(find.text('クリックスルーが ON です。解除するには:'), findsOneWidget);
      expect(
        tester.getRect(find.byType(BeforeAfterView)).bottom,
        lessThanOrEqualTo(narrow.height),
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
      h.filterService.setIntensity(0.5);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(h.filterService.intensity, closeTo(0.55, 1e-9));
      await h.filterService.flush();
    });

    testWidgets('検索で絞ったあとの ↑↓ は、見えている行だけを順送りする', (tester) async {
      final h = await pumpHomeScreen(tester, size: wide);
      await tester.enterText(find.byType(TextField), 'protan');
      await tester.pump();
      final visible = visibleFilterListEntries(query: 'protan');
      expect(visible.length, greaterThanOrEqualTo(2));

      // 行を選ぶと、フォーカスはショートカットの受け口へ戻る（検索欄に残らない）。
      final first = find.byKey(filterListTileKey(visible[0]));
      await tester.ensureVisible(first);
      await tester.tap(first);
      await tester.pump();
      expect(selectedFilterListEntry(h.visionState), visible[0]);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(selectedFilterListEntry(h.visionState), visible[1]);

      // 絞り込みの外（一覧全体の次の行）へは出ない: 末尾から ↓ で先頭へ折り返す。
      for (var i = 2; i < visible.length; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(selectedFilterListEntry(h.visionState), visible[0]);
      await h.filterService.flush();
    });
  });

  group('キーボードで行を選んでもフォーカスは行に残る', () {
    FilterListTile? focusedTile(WidgetTester tester) => tester
        .binding.focusManager.primaryFocus?.context
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
      await h.filterService.flush();
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
      await h.filterService.flush();
    });

    testWidgets('ポインタで選ぶとショートカット受け口へフォーカスが戻り ←→ が効く', (tester) async {
      final h = await pumpHomeScreen(tester, size: wide);
      final tile = find.byKey(filterListTileKey(entry('cv:protanopia')));
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pump();

      expect(tester.binding.focusManager.primaryFocus?.debugLabel,
          'homeShortcuts');
      await h.filterService.flush();
    });
  });

  group('↑↓ で選んだ行は一覧のビューポート内に追従する（両方向・折り返し）', () {
    Rect listViewport(WidgetTester tester) => tester.getRect(find.descendant(
          of: find.byType(FilterBrowser),
          matching: find.byType(SingleChildScrollView),
        ));

    void expectSelectedVisible(
      WidgetTester tester,
      FilterListEntry selected,
      String reason,
    ) {
      final rect = tester.getRect(find.byKey(filterListTileKey(selected)));
      final vp = listViewport(tester);
      expect(rect.top, greaterThanOrEqualTo(vp.top - 1), reason: reason);
      expect(rect.bottom, lessThanOrEqualTo(vp.bottom + 1), reason: reason);
    }

    testWidgets('↑ を連打して一覧の上方向へ進んでも選択行が見える', (tester) async {
      final h = await pumpHomeScreen(tester, size: wide);
      final start = kFilterListEntries[kFilterListEntries.length - 3];
      final tile = find.byKey(filterListTileKey(start));
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();

      for (var i = 0; i < 25; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expectSelectedVisible(
          tester,
          selectedFilterListEntry(h.visionState)!,
          '↑ ${i + 1} 回目',
        );
      }
      await h.filterService.flush();
    });

    testWidgets('末尾で ↓ すると先頭へ折り返し、先頭で ↑ すると末尾へ折り返しても見える', (tester) async {
      final h = await pumpHomeScreen(tester, size: wide);
      final last = kFilterListEntries.last;
      final tile = find.byKey(filterListTileKey(last));
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(selectedFilterListEntry(h.visionState), kFilterListEntries.first);
      expectSelectedVisible(tester, kFilterListEntries.first, '末尾→先頭');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(selectedFilterListEntry(h.visionState), last);
      expectSelectedVisible(tester, last, '先頭→末尾');
      await h.filterService.flush();
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
}
