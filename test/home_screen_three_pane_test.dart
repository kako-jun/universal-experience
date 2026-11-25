// 主画面の 3 ペイン構成（#197 / #198 / #199）を、境界と組み合わせで確かめる widget test。
//
// home_screen_layout_test.dart は 1280x800（広幅）と 800x700（縦並び）の代表値で見ている。
// ここでは次を見る:
// - 幅の閾値（`kWideLayoutBreakpoint` = 1000dp）のちょうど前後での切り替え（#198）
// - 起動時のウィンドウサイズ（`LoupeWindowPolicy.initialSizeFor`）が返す大きさで、主画面が
//   例外なく描画でき、幅に応じた並びになる（#197）
// - 縦並びの順（選択 → プレビュー → 調整）と、その先頭に体験プリセットがあること（#198/#199）
// - 主画面の中で、体験プリセットをポインタ / キーボードで選んだあとのフォーカス（#199）

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/services/loupe_window_controller.dart';
import 'package:universal_experience/ui/screens/home_screen.dart'
    show kWideLayoutBreakpoint;
import 'package:universal_experience/ui/widgets/adjust_panel.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';
import 'package:universal_experience/ui/widgets/experience_presets.dart';
import 'package:universal_experience/ui/widgets/filter_browser.dart';

import 'support/experience_preset_select.dart';
import 'support/home_screen_harness.dart';
import 'support/narrow_scroll.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installHomeScreenFixtures);
  tearDown(resetHomeScreenFixtures);

  Rect browserRect(WidgetTester tester) =>
      tester.getRect(find.byType(FilterBrowser, skipOffstage: false));
  Rect previewRect(WidgetTester tester) =>
      tester.getRect(find.byType(BeforeAfterView, skipOffstage: false));
  Rect adjustRect(WidgetTester tester) =>
      tester.getRect(find.byType(AdjustPanel, skipOffstage: false));

  /// 3 カラム（左=選択・中央=プレビュー・右=調整）で横に並んでいる。
  void expectThreeColumns(WidgetTester tester, {String? reason}) {
    final browser = browserRect(tester);
    final preview = previewRect(tester);
    final adjust = adjustRect(tester);
    expect(browser.right, lessThanOrEqualTo(preview.left), reason: reason);
    expect(preview.right, lessThanOrEqualTo(adjust.left), reason: reason);
  }

  /// 縦並び（上から 選択 → プレビュー → 調整）になっている。
  void expectStacked(WidgetTester tester, {String? reason}) {
    final browser = browserRect(tester);
    final preview = previewRect(tester);
    final adjust = adjustRect(tester);
    expect(browser.bottom, lessThanOrEqualTo(preview.top), reason: reason);
    expect(preview.bottom, lessThanOrEqualTo(adjust.top), reason: reason);
    // 横には並んでいない（プレビュー・調整は選択の右隣に無い）。
    expect(preview.left, lessThan(browser.right), reason: reason);
    expect(adjust.left, lessThan(browser.right), reason: reason);
  }

  group('幅の閾値（kWideLayoutBreakpoint）での切り替え（#198）', () {
    test('閾値は 1000dp', () {
      expect(kWideLayoutBreakpoint, 1000);
    });

    testWidgets('ちょうど 1000dp は 3 カラム', (tester) async {
      await pumpHomeScreen(tester, size: const Size(1000, 800));
      expectThreeColumns(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('999dp は縦並び（選択 → プレビュー → 調整）', (tester) async {
      await pumpHomeScreen(tester, size: const Size(999, 800));
      expectStacked(tester);
      expect(tester.takeException(), isNull);
    });

    for (final width in [1001.0, 1100.0, 1280.0, 1920.0]) {
      testWidgets('$width dp は 3 カラム', (tester) async {
        await pumpHomeScreen(tester, size: Size(width, 800));
        expectThreeColumns(tester);
        expect(tester.takeException(), isNull);
      });
    }

    for (final width in [998.0, 900.0, 800.0, 640.0]) {
      testWidgets('$width dp は縦並び', (tester) async {
        await pumpHomeScreen(tester, size: Size(width, 800));
        expectStacked(tester);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('ウィンドウの幅を 1000dp の前後で変えると、その場で並びが切り替わり、選択は保たれる',
        (tester) async {
      final h = await pumpHomeScreen(tester, size: const Size(1280, 800));
      await selectExperiencePreset(tester, 'bppv');
      expectThreeColumns(tester);

      tester.view.physicalSize = const Size(999, 800);
      await tester.pump();
      expectStacked(tester, reason: '999dp へ縮めた');
      expect(h.visionState.selectedPresetId, 'bppv');
      expect(experiencePresetDropdownText('良性発作性頭位めまい症'), findsOneWidget);

      tester.view.physicalSize = const Size(1000, 800);
      await tester.pump();
      expectThreeColumns(tester, reason: '1000dp へ戻した');
      expect(h.visionState.selectedPresetId, 'bppv');
      expect(experiencePresetDropdownText('良性発作性頭位めまい症'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('起動時のウィンドウサイズで主画面が出る（#197）', () {
    // 画面（論理ピクセル）→ 期待する並び。
    for (final (label, display, wide) in const <(String, Size?, bool)>[
      ('画面の大きさが取れない', null, true),
      ('大きい画面 1920x1080', Size(1920, 1080), true),
      ('1366x768（高さだけ縮む）', Size(1366, 768), true),
      ('1280x720', Size(1280, 720), true),
      ('1024x768', Size(1024, 768), true),
      ('1000x700（幅がちょうど閾値）', Size(1000, 700), true),
      ('999x700（閾値を切る）', Size(999, 700), false),
      ('800x600', Size(800, 600), false),
      ('縦置き 768x1024', Size(768, 1024), false),
    ]) {
      testWidgets('$label: 例外なく描画され、${wide ? '3 カラム' : '縦並び'}になる',
          (tester) async {
        final size = LoupeWindowPolicy.initialSizeFor(display);
        if (display != null) {
          expect(size.width, lessThanOrEqualTo(display.width));
          expect(size.height, lessThanOrEqualTo(display.height));
        }
        expect(size.width >= kWideLayoutBreakpoint, wide,
            reason: '前提: 起動時の幅 ${size.width}');

        await pumpHomeScreen(tester, size: size);

        expect(tester.takeException(), isNull, reason: '$size で overflow しない');
        if (wide) {
          expectThreeColumns(tester);
          // 3 ペインとも最初の画面に出ている（スクロールしなくても見える）。
          expect(browserRect(tester).top, lessThan(size.height));
          expect(previewRect(tester).top, lessThan(size.height));
          expect(adjustRect(tester).top, lessThan(size.height));
        } else {
          expectStacked(tester);
        }
        // どちらでも、体験プリセットは最初の画面にあって、そのまま選べる。
        expect(experiencePresetDropdown().hitTestable(), findsOneWidget);
      });
    }

    testWidgets('既定の 1280x800 では、3 ペインの中身が最初の画面に収まる（プレビューは下端まで）',
        (tester) async {
      const size = LoupeWindowPolicy.defaultSize;
      await pumpHomeScreen(tester, size: size);

      expectThreeColumns(tester);
      expect(previewRect(tester).bottom, lessThanOrEqualTo(size.height));
      expect(browserRect(tester).bottom, lessThanOrEqualTo(size.height));
      expect(tester.takeException(), isNull);
    });
  });

  group('縦並びの順（選択 → プレビュー → 調整、#198）', () {
    const narrow = Size(800, 700);

    testWidgets('最初の画面の一番上は体験プリセット、続いて見出し・検索欄・一覧', (tester) async {
      await pumpHomeScreen(tester, size: narrow);

      final dropdown = tester.getRect(experiencePresetDropdown());
      final browser = browserRect(tester);
      expect(dropdown.top, greaterThanOrEqualTo(browser.top));
      expect(dropdown.bottom, lessThanOrEqualTo(narrow.height),
          reason: '体験プリセットは最初の画面にある');
      expect(dropdown.bottom,
          lessThanOrEqualTo(tester.getRect(find.text('見え方を選ぶ')).top));
      expect(tester.getRect(find.byType(TextField)).bottom,
          lessThanOrEqualTo(narrow.height),
          reason: '検索欄も最初の画面にある');
      // プレビューと調整は、体験プリセットより下。
      expect(dropdown.bottom, lessThanOrEqualTo(previewRect(tester).top));
      expect(dropdown.bottom, lessThanOrEqualTo(adjustRect(tester).top));
    });

    testWidgets('フィルタを選んでも順は変わらない（調整の中身が増えても 選択 → プレビュー → 調整）', (tester) async {
      await pumpHomeScreen(tester, size: narrow);
      await selectExperiencePreset(tester, 'vestibular_neuritis');
      expectStacked(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('画面のスクロールでプレビュー・調整の順に届き、調整の下端が画面の末尾', (tester) async {
      await pumpHomeScreen(tester, size: narrow);
      await selectExperiencePreset(tester, 'bppv');

      await scrollPreviewIntoView(tester);
      final preview = tester.getRect(find.byType(BeforeAfterView));
      expect(preview.top, greaterThanOrEqualTo(0));
      expect(preview.bottom, lessThanOrEqualTo(narrow.height),
          reason: 'プレビューまでスクロールすると画像が 1 画面に収まる');

      // 画面のスクロール（一番外側）を末尾まで動かすと、調整パネルの下端が見える。
      final page = tester.state<ScrollableState>(find
          .ancestor(
            of: find.byType(AdjustPanel),
            matching: find.byType(Scrollable),
          )
          .last);
      page.position.jumpTo(page.position.maxScrollExtent);
      await tester.pump();
      final adjust = tester.getRect(find.byType(AdjustPanel));
      expect(adjust.bottom, lessThanOrEqualTo(narrow.height));
      expect(adjust.bottom, greaterThan(preview.top),
          reason: '調整はプレビューより下（末尾）');
      // 末尾までスクロールしたとき、選択（一覧）は画面の上へ出ている。
      expect(browserRect(tester).top, lessThan(0));
    });

    testWidgets('Tab の順も 選択 → プレビュー → 調整（選択の区画の最初は体験プリセット、調整へはプレビューのあとで届く）',
        (tester) async {
      // 調整に操作部品（強さのスライダー）を出すため、プリセットを選んでおく。
      final h = await pumpHomeScreen(tester, size: narrow);
      h.visionState.selectPreset('bppv', 'bppv_rotation');
      await tester.pump();

      // 0=選択 1=プレビュー 2=調整。フォーカス中の要素がどの区画の中にあるかで判定する。
      int? sectionOfFocus() {
        final context = tester.binding.focusManager.primaryFocus?.context;
        if (context == null) return null;
        if (context.findAncestorWidgetOfExactType<FilterBrowser>() != null) {
          return 0;
        }
        if (context.findAncestorWidgetOfExactType<AdjustPanel>() != null) {
          return 2;
        }
        // プレビューのカード（BeforeAfterView と、同じカードの画像の選択欄）。
        final box = context.findRenderObject();
        if (box is! RenderBox || !box.attached) return null;
        final center = box.localToGlobal(box.size.center(Offset.zero));
        final browser = browserRect(tester);
        final adjust = adjustRect(tester);
        if (center.dy >= browser.bottom && center.dy <= adjust.top) return 1;
        return null;
      }

      // 選択の区画に入って最初に止まるのは体験プリセット（区画の一番上、#199）。
      for (var i = 0; i < 40 && sectionOfFocus() != 0; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(sectionOfFocus(), 0, reason: 'Tab で選択の区画に届く');
      expect(
        tester.binding.focusManager.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<ExperiencePresetPicker>(),
        isNotNull,
        reason: '選択の区画で最初に止まるのは体験プリセット',
      );

      final visited = <int>[];
      for (var i = 0; i < 200; i++) {
        final section = sectionOfFocus();
        if (section != null && (visited.isEmpty || visited.last != section)) {
          visited.add(section);
        }
        if (section == 2) break;
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(visited, [0, 1, 2], reason: '選択 → プレビュー → 調整 の順に 1 度ずつ通る');
    });
  });

  group('主画面で体験プリセットを選んだあとのフォーカス（#199）', () {
    for (final (label, size) in const [
      ('広幅 1280x800', Size(1280, 800)),
      ('縦並び 800x700', Size(800, 700)),
      ('低い広幅 1280x480', Size(1280, 480)),
    ]) {
      testWidgets(
          '$label: ポインタで選ぶとショートカット受け口へフォーカスが戻り、続く ← で強度が動いて「プリセットなし」へ戻る',
          (tester) async {
        final h = await pumpHomeScreen(tester, size: size);

        await selectExperiencePreset(tester, 'bppv');

        expect(h.visionState.selectedPresetId, 'bppv');
        expect(tester.binding.focusManager.primaryFocus?.debugLabel,
            'homeShortcuts');
        final before = h.visionState.strength;
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(h.visionState.strength, lessThan(before));
        // 強度を手で変えたら、フィルタは残したままプリセットの表示だけ外れる（#60 の仕様）。
        expect(h.visionState.selectedPresetId, isNull);
        expect(h.visionState.layers.map((l) => l.id), ['bppv_rotation']);
        expect(experiencePresetDropdownText('プリセットなし'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('キーボードで選ぶと、フォーカスはドロップダウンに残り、次の Tab は検索欄へ進む', (tester) async {
      final h = await pumpHomeScreen(tester, size: const Size(1280, 800));
      bool focusInPicker() =>
          tester.binding.focusManager.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<ExperiencePresetPicker>() !=
          null;
      for (var i = 0; i < 40 && !focusInPicker(); i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(focusInPicker(), isTrue, reason: 'Tab で体験プリセットに届く');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(experienceCardKey('meniere')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(h.visionState.selectedPresetId, isNotNull);
      expect(find.byKey(experienceCardKey('meniere')), findsNothing);
      expect(tester.binding.focusManager.primaryFocus?.debugLabel,
          isNot('homeShortcuts'),
          reason: 'キーボードで選んだときはショートカット受け口へ飛ばさない');
      expect(focusInPicker(), isTrue, reason: 'フォーカスはドロップダウンに残る');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        tester.binding.focusManager.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<TextField>(),
        isNotNull,
        reason: '次の Tab は検索欄（先頭からやり直しにならない）',
      );
    });
  });
}
