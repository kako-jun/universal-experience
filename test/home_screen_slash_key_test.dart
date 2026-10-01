// `/` ショートカット（FocusFilterSearchIntent）のガード（#141）。
//
// `/` はテキスト入力以外に固有の意味を持たないので、ボタン・チップ等に
// フォーカスが残っていても検索欄へ移る（TextInputAwareCallbackAction）。
// テキスト入力中だけ奪わない。↑↓・←→ のガード（isFocusOnInteractiveControl）は
// 変えていないことも合わせて固定する。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/services/app_shortcuts.dart';
import 'package:universal_experience/services/filter_list_selection.dart';
import 'package:universal_experience/ui/widgets/filter_browser.dart';
import 'package:universal_experience/ui/widgets/filter_list_tile.dart';

import 'support/color_vision_select.dart';
import 'support/home_screen_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installHomeScreenFixtures);
  tearDown(resetHomeScreenFixtures);

  const wide = Size(1280, 800);

  TextField searchField(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField));

  FocusNode? primary(WidgetTester tester) =>
      tester.binding.focusManager.primaryFocus;

  bool isSearchFocused(WidgetTester tester) =>
      primary(tester)?.debugLabel == 'filterSearch';

  /// [target]（のサブツリー）の中のフォーカス可能なノードへ確実にフォーカスを置く
  /// （タップでフォーカスが移るかはプラットフォーム次第なので明示的に要求する）。
  Future<void> focusInside(WidgetTester tester, Finder target) async {
    final root = tester.element(target.first);
    bool inside(BuildContext? context) {
      if (context == null) return false;
      if (identical(context, root)) return true;
      var found = false;
      context.visitAncestorElements((element) {
        if (identical(element, root)) {
          found = true;
          return false;
        }
        return true;
      });
      return found;
    }

    FocusManager.instance.rootScope.descendants
        .firstWhere((node) => node.canRequestFocus && inside(node.context))
        .requestFocus();
    await tester.pump();
    expect(inside(primary(tester)?.context), isTrue,
        reason: 'フォーカスは対象の部品の中にある');
  }

  /// 検索欄に [text] を入れる（検索欄にフォーカスがあり、キャレットは末尾）。
  Future<void> typeSearch(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
  }

  Future<void> pressSlash(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.pump();
  }

  void expectSearchFocusedAndAllSelected(WidgetTester tester, String text) {
    expect(isSearchFocused(tester), isTrue, reason: '/ で検索欄にフォーカスが移る');
    expect(
      searchField(tester).controller!.selection,
      TextSelection(baseOffset: 0, extentOffset: text.length),
      reason: '入力済みの文字が全選択される',
    );
  }

  group('ボタン・チップにフォーカスが残っていても / が効く（#141）', () {
    testWidgets('カテゴリの ChoiceChip にフォーカスがある状態で / → 検索欄へ移り全選択', (tester) async {
      await pumpHomeScreen(tester, size: wide);
      await typeSearch(tester, 'myo');

      final chip = find.widgetWithText(ChoiceChip, '色覚');
      expect(chip, findsOneWidget);
      await focusInside(tester, chip);
      expect(isFocusOnInteractiveControl(), isTrue);
      expect(isFocusOnTextInput(), isFalse);
      expect(isSearchFocused(tester), isFalse);

      await pressSlash(tester);

      expectSearchFocusedAndAllSelected(tester, 'myo');
    });

    testWidgets('FilledButton（ウェルカムバナー）にフォーカスがある状態で / → 同上', (tester) async {
      await pumpHomeScreen(tester, size: wide);
      await typeSearch(tester, 'abc');

      final button = find.byType(FilledButton);
      expect(button, findsWidgets, reason: '初回起動はウェルカムバナーに FilledButton が出る');
      await focusInside(tester, button);
      expect(isFocusOnInteractiveControl(), isTrue);
      expect(isFocusOnTextInput(), isFalse);

      await pressSlash(tester);

      expectSearchFocusedAndAllSelected(tester, 'abc');
    });

    testWidgets('OutlinedButton（貼り付け）にフォーカスがある状態で / → 同上', (tester) async {
      await pumpHomeScreen(tester, size: wide);
      await typeSearch(tester, 'abc');

      final button = find.byType(OutlinedButton);
      expect(button, findsWidgets);
      await focusInside(tester, button);
      expect(isFocusOnInteractiveControl(), isTrue);

      await pressSlash(tester);

      expectSearchFocusedAndAllSelected(tester, 'abc');
    });

    testWidgets('Slider にフォーカスがある状態で / → 同上', (tester) async {
      final h = await pumpHomeScreen(
        tester,
        size: wide,
        select: (s) => selectColorVisionKey(s, 'protanopia'),
      );
      await typeSearch(tester, 'abc');
      final before = h.visionState.strength;

      final slider = find.byType(Slider);
      expect(slider, findsOneWidget);
      await focusInside(tester, slider);
      expect(isFocusOnInteractiveControl(), isTrue);

      await pressSlash(tester);

      expectSearchFocusedAndAllSelected(tester, 'abc');
      expect(h.visionState.strength, before, reason: '/ は強度に触れない');
    });
  });

  group('テキスト入力中は / を奪わない（#141）', () {
    testWidgets('検索欄にフォーカスがある間の / は、フォーカス移動も全選択も起こさない', (tester) async {
      await pumpHomeScreen(tester, size: wide);
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();
      expect(isSearchFocused(tester), isTrue);
      expect(isFocusOnTextInput(), isTrue);
      const caret = TextSelection.collapsed(offset: 3);
      expect(searchField(tester).controller!.selection, caret);

      await pressSlash(tester);

      expect(isSearchFocused(tester), isTrue);
      expect(searchField(tester).controller!.selection, caret,
          reason: '再フォーカス・全選択（focusSearch）は走らない');
    });

    testWidgets('検索欄の途中を選んでいても / で選択範囲が全選択に変わらない', (tester) async {
      await pumpHomeScreen(tester, size: wide);
      await tester.enterText(find.byType(TextField), 'abcdef');
      await tester.pump();
      const partial = TextSelection(baseOffset: 1, extentOffset: 3);
      searchField(tester).controller!.selection = partial;
      await tester.pump();

      await pressSlash(tester);

      expect(searchField(tester).controller!.selection, partial);
    });

    testWidgets('検索欄に文字として入力した / は検索語に入る', (tester) async {
      await pumpHomeScreen(tester, size: wide);
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'a/b');
      await tester.pump();

      expect(searchField(tester).controller!.text, 'a/b');
      expect(isSearchFocused(tester), isTrue);
    });
  });

  group('↑↓・←→ のガードは変わっていない（#141 回帰）', () {
    testWidgets('チップにフォーカスがある間の ← → は強度を動かさない', (tester) async {
      final h = await pumpHomeScreen(
        tester,
        size: wide,
        select: (s) => selectColorVisionKey(s, 'protanopia'),
      );
      final before = h.visionState.strength;
      final chip = find.widgetWithText(ChoiceChip, '色覚');
      await focusInside(tester, chip);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();

      expect(h.visionState.strength, before,
          reason: 'ボタン・チップ上の ←→ はショートカットに奪われない');
    });

    testWidgets('スライダー上の → は強度ショートカットでなく Slider 自身の操作（二重に動かない）',
        (tester) async {
      final h = await pumpHomeScreen(
        tester,
        size: wide,
        select: (s) => selectColorVisionKey(s, 'protanopia'),
      );
      final before = h.visionState.strength;

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      // Slider 自身の 1 ステップ（5%）だけ動く。ショートカットが奪うと二重に足されて 10%。
      expect((h.visionState.strength - before).abs(), lessThan(0.0501),
          reason: 'ショートカットと Slider 自身の二重加算になっていない');
    });

    testWidgets('チップにフォーカスがある間の ↓ は、調整中の層の次の行へフォーカスを送るショートカットにならない',
        (tester) async {
      final h = await pumpHomeScreen(
        tester,
        size: wide,
        select: (s) => selectColorVisionKey(s, 'protanopia'),
      );
      expect(h.visionState.focusedId, 'protanopia');
      final protanopiaIndex =
          kFilterListEntries.indexWhere((e) => e.key == 'cv:protanopia');
      final nextRow =
          filterListTileKey(kFilterListEntries[protanopiaIndex + 1]);

      await focusInside(tester, find.widgetWithText(ChoiceChip, '色覚'));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      final focusedRow = primary(tester)
          ?.context
          ?.findAncestorWidgetOfExactType<FilterListTile>()
          ?.key;
      expect(focusedRow, isNot(nextRow),
          reason: 'CycleFilterIntent（調整中の層の次の行へ）には奪われない');
    });
  });
}
