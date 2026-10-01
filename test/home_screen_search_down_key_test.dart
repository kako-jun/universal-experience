// 検索欄の ↓ で先頭の行へ、先頭の行の ↑ で検索欄へ戻る（#141 項目 2）。
//
// 検索欄（EditableText）にフォーカスがある間の ↓ だけを CycleFilterIntent が奪い、
// 今見えていてフォーカスできる先頭の行へ移す。選択（層）は変えない。先頭の行の ↑ は
// 末尾へ折り返さず検索欄へ戻る（全選択せずキャレット維持）。IME 未確定（composing）中は
// 奪わない。検索欄の ↑・←→・Home/End・文字入力・`/`・Cmd/Ctrl+V・行/ボタン/スライダー上の
// 既存規則は変えない。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey, TextRange;
import 'package:flutter_test/flutter_test.dart';
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
  const narrow = Size(420, 800);

  TextField searchField(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField));

  TextEditingController searchController(WidgetTester tester) =>
      searchField(tester).controller!;

  FocusNode? primary(WidgetTester tester) =>
      tester.binding.focusManager.primaryFocus;

  bool isSearchFocused(WidgetTester tester) =>
      primary(tester)?.debugLabel == 'filterSearch';

  Key? focusedRowKey(WidgetTester tester) => primary(tester)
      ?.context
      ?.findAncestorWidgetOfExactType<FilterListTile>()
      ?.key;

  /// 検索欄に明示的にフォーカスを置く（タップでフォーカスが移るかはプラットフォーム次第）。
  Future<void> focusSearch(WidgetTester tester) async {
    searchField(tester).focusNode!.requestFocus();
    await tester.pump();
    expect(isSearchFocused(tester), isTrue);
  }

  /// 検索欄に [text] を入れる（フォーカスあり、キャレットは末尾）。
  Future<void> typeSearch(WidgetTester tester, String text) async {
    await focusSearch(tester);
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    expect(isSearchFocused(tester), isTrue);
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
  }

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
  }

  final firstEntry = kFilterListEntries.first;
  final lastEntry = kFilterListEntries.last;

  group('検索欄の ↓ で先頭の行へ（#141）', () {
    testWidgets('検索欄が空でも ↓ → 先頭の可視行へ移り、層・検索語は変わらない', (tester) async {
      final h = await pumpHomeScreen(tester, size: wide);
      await focusSearch(tester);
      expect(searchController(tester).text, isEmpty);

      await press(tester, LogicalKeyboardKey.arrowDown);

      expect(focusedRowKey(tester), filterListTileKey(firstEntry));
      expect(isSearchFocused(tester), isFalse);
      expect(h.visionState.layers, isEmpty, reason: '↓ は選ばない');
      expect(searchController(tester).text, isEmpty);
    });

    testWidgets('検索語で絞った先頭行へ移る（調整中の層の行ではない）', (tester) async {
      final h = await pumpHomeScreen(
        tester,
        size: wide,
        select: (s) => selectColorVisionKey(s, 'protanopia'),
      );
      await typeSearch(tester, 'myopia');
      final visible = visibleFilterListEntries(query: 'myopia');
      expect(visible, isNotEmpty);
      final layersBefore = h.visionState.layers.map((l) => l.id).toList();

      await press(tester, LogicalKeyboardKey.arrowDown);

      expect(focusedRowKey(tester), filterListTileKey(visible.first));
      expect(h.visionState.layers.map((l) => l.id).toList(), layersBefore,
          reason: '選択（層）は変えない');
      expect(searchController(tester).text, 'myopia');
    });

    testWidgets('上限で先頭行が無効（フォーカス不可）なら最初のフォーカス可能行へ', (tester) async {
      final h = await pumpHomeScreen(tester, size: wide);
      // 色覚以外を 5 層（上限）選ぶ → 色覚の行はすべて無効になる。
      for (final id in [
        'myopia',
        'vertigo',
        'glaucoma',
        'cataract',
        'floaters'
      ]) {
        h.visionState.toggle(id);
      }
      await tester.pump();
      expect(h.visionState.layers, hasLength(5));
      final firstEnabled = kFilterListEntries.firstWhere(
          (e) => filterListEntryBlockReason(h.visionState, e) == null);
      expect(filterListEntryBlockReason(h.visionState, firstEntry), isNotNull,
          reason: '先頭の行は上限で無効');
      expect(firstEnabled, isNot(firstEntry));

      await focusSearch(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);

      expect(focusedRowKey(tester), filterListTileKey(firstEnabled),
          reason: '無効の先頭行へは requestFocus しない');
      expect(h.visionState.layers, hasLength(5));
    });

    testWidgets('上限で先頭行が無効でも、最初の有効行の ↑ は検索欄へ戻る', (tester) async {
      final h = await pumpHomeScreen(tester, size: wide);
      for (final id in [
        'myopia',
        'vertigo',
        'glaucoma',
        'cataract',
        'floaters'
      ]) {
        h.visionState.toggle(id);
      }
      await tester.pump();
      final firstEnabled = kFilterListEntries.firstWhere(
          (e) => filterListEntryBlockReason(h.visionState, e) == null);
      expect(firstEnabled, isNot(firstEntry), reason: '前提: 先頭の行は無効');

      await focusSearch(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedRowKey(tester), filterListTileKey(firstEnabled));

      await press(tester, LogicalKeyboardKey.arrowUp);

      expect(isSearchFocused(tester), isTrue,
          reason: '最初の有効行の ↑ は末尾へ折り返さず検索欄へ戻る');
      expect(h.visionState.layers, hasLength(5));
    });

    testWidgets('行 0 件（検索語が当たらない）では何も起きず検索欄に残る', (tester) async {
      final h = await pumpHomeScreen(tester, size: wide);
      await typeSearch(tester, 'zzzzqqqq');
      expect(visibleFilterListEntries(query: 'zzzzqqqq'), isEmpty);
      searchController(tester).selection =
          const TextSelection.collapsed(offset: 2);
      await tester.pump();

      await press(tester, LogicalKeyboardKey.arrowDown);

      expect(isSearchFocused(tester), isTrue);
      expect(searchController(tester).selection.baseOffset, 8,
          reason: '奪われず、入力欄がキャレットを末尾へ動かす');
      expect(tester.takeException(), isNull);
      expect(h.visionState.layers, isEmpty);
    });

    testWidgets('体験プリセットだけ表示されている（行は 0 件）ときも何も起きない', (tester) async {
      await pumpHomeScreen(tester, size: wide);
      await typeSearch(tester, 'meniere');
      expect(visibleFilterListEntries(query: 'meniere'), isEmpty,
          reason: '前提: 絞り込みの行は 0 件');
      expect(find.byType(FilterListTile), findsWidgets,
          reason: '前提: 体験プリセットの行は見えている');
      searchController(tester).selection =
          const TextSelection.collapsed(offset: 2);
      await tester.pump();

      await press(tester, LogicalKeyboardKey.arrowDown);

      expect(isSearchFocused(tester), isTrue,
          reason: 'プリセット行へは移さない（フォーカスは検索欄のまま）');
      expect(searchController(tester).selection.baseOffset, 7,
          reason: '奪われず、入力欄がキャレットを末尾へ動かす');
      expect(tester.takeException(), isNull);
    });

    testWidgets('狭幅（縦積み）レイアウトでも ↓ で先頭行へ移り、先頭行の ↑ で検索欄へ戻る', (tester) async {
      await pumpHomeScreen(tester, size: narrow);
      await focusSearch(tester);

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedRowKey(tester), filterListTileKey(firstEntry));

      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(isSearchFocused(tester), isTrue);
    });
  });

  group('先頭の行の ↑ は検索欄へ戻る（#141）', () {
    testWidgets('末尾へ折り返さず検索欄へ戻り、キャレットは維持され全選択されない', (tester) async {
      final h = await pumpHomeScreen(tester, size: wide);
      await typeSearch(tester, 'o');
      final text = searchController(tester).text;
      expect(text, 'o');
      final visible = visibleFilterListEntries(query: text);
      expect(visible.length, greaterThan(1));
      searchController(tester).selection =
          const TextSelection.collapsed(offset: 1);
      await tester.pump();

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedRowKey(tester), filterListTileKey(visible.first));
      await press(tester, LogicalKeyboardKey.arrowUp);

      expect(isSearchFocused(tester), isTrue);
      expect(focusedRowKey(tester), isNull);
      expect(searchController(tester).selection.isCollapsed, isTrue,
          reason: '全選択しない');
      expect(searchController(tester).selection.baseOffset, 1);
      expect(h.visionState.layers, isEmpty);
    });

    testWidgets('戻った後の文字入力は検索欄に入る', (tester) async {
      await pumpHomeScreen(tester, size: wide);
      await focusSearch(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(isSearchFocused(tester), isTrue);

      tester.testTextInput.enterText('myo');
      await tester.pump();

      expect(searchController(tester).text, 'myo');
      expect(isSearchFocused(tester), isTrue);
    });

    testWidgets('先頭以外の行の ↑ は前の行へ、末尾の ↓ は先頭へ折り返す（従来どおり）', (tester) async {
      await pumpHomeScreen(tester, size: wide);
      await focusSearch(tester);
      await press(tester, LogicalKeyboardKey.arrowDown); // 先頭
      await press(tester, LogicalKeyboardKey.arrowDown); // 2 行目
      expect(focusedRowKey(tester), filterListTileKey(kFilterListEntries[1]));

      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedRowKey(tester), filterListTileKey(firstEntry),
          reason: '2 行目の ↑ は先頭へ（検索欄ではない）');

      // 末尾の ↓ は先頭へ折り返す。
      await focusInside(tester,
          find.byKey(filterListTileKey(lastEntry), skipOffstage: false));
      await tester.pumpAndSettle();
      expect(focusedRowKey(tester), filterListTileKey(lastEntry));
      await press(tester, LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(focusedRowKey(tester), filterListTileKey(firstEntry));
    });

    testWidgets('先頭の行で Space/Enter の足し引きは従来どおり、↑ は選択を変えない', (tester) async {
      final h = await pumpHomeScreen(tester, size: wide);
      await focusSearch(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedRowKey(tester), filterListTileKey(firstEntry));

      await press(tester, LogicalKeyboardKey.space);
      expect(h.visionState.layers.map((l) => l.id), [firstEntry.catalogId]);

      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(isSearchFocused(tester), isTrue);
      expect(h.visionState.layers.map((l) => l.id), [firstEntry.catalogId],
          reason: '↑ で検索欄へ戻っても選択は変わらない');

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedRowKey(tester), filterListTileKey(firstEntry));
      await press(tester, LogicalKeyboardKey.enter);
      expect(h.visionState.layers, isEmpty, reason: 'Enter でも外れる');
    });
  });

  group('検索欄の既存の操作は奪わない（#141 回帰）', () {
    testWidgets('検索欄の ↑ は行へ移らず検索欄に残る', (tester) async {
      final h = await pumpHomeScreen(tester, size: wide);
      await typeSearch(tester, 'myo');

      await press(tester, LogicalKeyboardKey.arrowUp);

      expect(isSearchFocused(tester), isTrue);
      expect(focusedRowKey(tester), isNull);
      expect(h.visionState.layers, isEmpty);
    });

    testWidgets('検索欄の ← → Home End はキャレットを動かし、強度は動かさない', (tester) async {
      final h = await pumpHomeScreen(
        tester,
        size: wide,
        select: (s) => selectColorVisionKey(s, 'protanopia'),
      );
      h.visionState.setStrength(0.5);
      await tester.pump();
      await typeSearch(tester, 'myop');
      final strength = h.visionState.strength;
      expect(searchController(tester).selection.baseOffset, 4);

      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(searchController(tester).selection.baseOffset, 3);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(searchController(tester).selection.baseOffset, 4);
      await press(tester, LogicalKeyboardKey.home);
      expect(searchController(tester).selection.baseOffset, 0);
      await press(tester, LogicalKeyboardKey.end);
      expect(searchController(tester).selection.baseOffset, 4);

      expect(isSearchFocused(tester), isTrue);
      expect(h.visionState.strength, strength);
    });

    testWidgets('検索欄の `/` は全選択もフォーカス移動も起こさない', (tester) async {
      await pumpHomeScreen(tester, size: wide);
      await typeSearch(tester, 'myo');
      const caret = TextSelection.collapsed(offset: 3);
      expect(searchController(tester).selection, caret);

      await press(tester, LogicalKeyboardKey.slash);

      expect(isSearchFocused(tester), isTrue);
      expect(searchController(tester).selection, caret);
    });

    testWidgets('検索欄の Ctrl+V は行へフォーカスを移さない', (tester) async {
      await pumpHomeScreen(tester, size: wide);
      await typeSearch(tester, 'myo');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(isSearchFocused(tester), isTrue);
      expect(focusedRowKey(tester), isNull);
    });
  });

  group('IME 変換中（composing）の ↓（#141）', () {
    testWidgets('未確定文字がある間の ↓ は奪わず、確定後は先頭行へ移る', (tester) async {
      await pumpHomeScreen(tester, size: wide);
      await typeSearch(tester, 'myo');
      final controller = searchController(tester);
      // 「yo」が未確定（変換中）の状態。
      controller.value = const TextEditingValue(
        text: 'myo',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 1, end: 3),
      );
      await tester.pump();
      expect(controller.value.composing.isValid, isTrue);
      expect(controller.value.composing.isCollapsed, isFalse);

      await press(tester, LogicalKeyboardKey.arrowDown);

      expect(focusedRowKey(tester), isNull, reason: '変換中の ↓ は候補選択のため奪わない');
      expect(isSearchFocused(tester), isTrue);

      // 確定（composing が無効）→ 移る。
      controller.value = const TextEditingValue(
        text: 'myo',
        selection: TextSelection.collapsed(offset: 3),
      );
      await tester.pump();
      await focusSearch(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);

      expect(focusedRowKey(tester), isNotNull);
      expect(isSearchFocused(tester), isFalse);
    });
  });

  group('行・ボタン・スライダー上の ↓ は従来どおり（#141 回帰）', () {
    testWidgets('チップにフォーカスがある間の ↓ は先頭行へ送るショートカットにならない', (tester) async {
      await pumpHomeScreen(tester, size: wide);
      await focusInside(tester, find.widgetWithText(ChoiceChip, '色覚'));

      await press(tester, LogicalKeyboardKey.arrowDown);

      // ガードが壊れて moveRowFocus が走ると、調整中の層が無いので先頭行へ入る。
      expect(focusedRowKey(tester), isNull,
          reason: 'CycleFilterIntent には奪われない（行へは移らない）');
    });

    // Slider 自身の矢印 Shortcuts が先に処理するため、このガードの検出力は無い。
    // 実挙動の確認（ガードの検出力はチップ上の ↓ のテストが担う）。
    testWidgets('実挙動の確認: Slider にフォーカスがある間の ↓ は行へ移さない', (tester) async {
      final h = await pumpHomeScreen(
        tester,
        size: wide,
        select: (s) => selectColorVisionKey(s, 'protanopia'),
      );
      await focusInside(tester, find.byType(Slider));
      final layers = h.visionState.layers.map((l) => l.id).toList();

      await press(tester, LogicalKeyboardKey.arrowDown);

      expect(focusedRowKey(tester), isNull);
      expect(h.visionState.layers.map((l) => l.id).toList(), layers);
    });

    testWidgets('行にフォーカスがある間の ↓ は次の行へ（従来どおり）', (tester) async {
      await pumpHomeScreen(tester, size: wide);
      await focusSearch(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedRowKey(tester), filterListTileKey(firstEntry));

      await press(tester, LogicalKeyboardKey.arrowDown);

      expect(focusedRowKey(tester), filterListTileKey(kFilterListEntries[1]));
    });
  });
}
