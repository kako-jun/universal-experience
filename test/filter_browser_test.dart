// FilterBrowser（統合フィルタ一覧、#72）の widget test。
//
// インクリメンタル検索（日本語・英語）・カテゴリ切替・該当なし表示・行の選択と
// 書き込み入口・体験プリセットの並び・検索欄へのフォーカス移動を確認する。
// 選択の正本は VisionFilterState のまま（一覧は表示と入口だけを持つ）。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/models/vision_filter_catalog.dart';
import 'package:universal_experience/services/filter_list_selection.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/ui/widgets/experience_presets.dart';
import 'package:universal_experience/ui/widgets/filter_browser.dart';

import 'support/home_screen_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installHomeScreenFixtures);
  tearDown(resetHomeScreenFixtures);

  late FilterBrowserController controller;
  late VisionFilterState state;
  var activated = 0;

  Future<void> pumpBrowser(WidgetTester tester, {String locale = 'ja'}) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    controller = FilterBrowserController();
    addTearDown(controller.dispose);
    state = VisionFilterState();
    activated = 0;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<VisionFilterState>.value(value: state),
        ],
        child: MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              height: 880,
              child: FilterBrowser(
                controller: controller,
                onActivated: () => activated++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder tileOf(String key) => find.byKey(ValueKey('filter_tile_$key'));

  testWidgets('初期状態は体験プリセット 4 件と一覧の行が並ぶ', (tester) async {
    await pumpBrowser(tester);
    for (final id in [
      'meniere',
      'bppv',
      'vestibular_neuritis',
      'labyrinthitis'
    ]) {
      expect(find.byKey(experienceCardKey(id)), findsOneWidget, reason: id);
    }
    // 体験プリセットは一覧の最上段（色覚の行より上）。
    expect(
      tester.getRect(find.byKey(experienceCardKey('meniere'))).top,
      lessThan(tester.getRect(tileOf('cv:protanopia')).top),
    );
    expect(find.text('見え方を選ぶ'), findsOneWidget);
  });

  group('検索', () {
    testWidgets('英語名で絞り込める', (tester) async {
      await pumpBrowser(tester);
      await tester.enterText(find.byType(TextField), 'protanopia');
      await tester.pump();

      expect(tileOf('cv:protanopia'), findsOneWidget);
      expect(tileOf('cv:deuteranopia'), findsNothing);
      // 体験プリセットも検索語で絞られる。
      expect(find.byKey(experienceCardKey('meniere')), findsNothing);
    });

    testWidgets('日本語名で絞り込める', (tester) async {
      await pumpBrowser(tester);
      await tester.enterText(find.byType(TextField), 'メニエール');
      await tester.pump();

      expect(find.byKey(experienceCardKey('meniere')), findsOneWidget);
      expect(find.byKey(experienceCardKey('bppv')), findsNothing);
      expect(tileOf('cv:protanopia'), findsNothing);
    });

    testWidgets('英語ロケールでも日本語名で当たる（ja/en どちらでも検索できる）', (tester) async {
      await pumpBrowser(tester, locale: 'en');
      await tester.enterText(find.byType(TextField), '1型2色覚');
      await tester.pump();

      expect(tileOf('cv:protanopia'), findsOneWidget);
    });

    testWidgets('該当なしは案内文を出す', (tester) async {
      await pumpBrowser(tester);
      await tester.enterText(find.byType(TextField), 'zzzzzzzz');
      await tester.pump();

      expect(find.text('一致する見え方がありません。'), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('クリアボタンで検索語が消え、一覧が戻る', (tester) async {
      await pumpBrowser(tester);
      await tester.enterText(find.byType(TextField), 'zzzzzzzz');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();

      expect(controller.search.text, isEmpty);
      expect(find.text('一致する見え方がありません。'), findsNothing);
      expect(tileOf('cv:protanopia'), findsOneWidget);
    });

    testWidgets('検索語があるあいだはカテゴリを無視して全体から探す', (tester) async {
      await pumpBrowser(tester);
      final category = kFilterListEntries
          .firstWhere((e) => e.key == 'catalog:starbursts')
          .category;
      final other =
          VisionFilterCategory.values.firstWhere((c) => c != category);
      controller.setCategory(other);
      controller.search.text = 'starbursts';
      await tester.pump();

      expect(tileOf('catalog:starbursts'), findsOneWidget);
    });
  });

  group('カテゴリ切替', () {
    testWidgets('カテゴリを選ぶとそのカテゴリの行だけになり、「すべて」で戻る', (tester) async {
      await pumpBrowser(tester);
      final category = kFilterListEntries
          .firstWhere((e) => e.key == 'catalog:starbursts')
          .category;
      final inCategory =
          kFilterListEntries.where((e) => e.category == category).toList();
      final outside =
          kFilterListEntries.firstWhere((e) => e.category != category);

      controller.setCategory(category);
      await tester.pump();
      expect(controller.category, category);
      expect(tileOf('catalog:starbursts'), findsOneWidget);
      expect(find.byKey(filterListTileKey(outside)), findsNothing);
      expect(controller.visibleEntries, inCategory);
      // カテゴリを絞ると体験プリセットは出ない（一覧の最上段はカテゴリ「すべて」のときだけ）。
      expect(find.byKey(experienceCardKey('meniere')), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'すべて'));
      await tester.pump();
      expect(controller.category, isNull);
      expect(find.byKey(experienceCardKey('meniere')), findsOneWidget);
    });

    testWidgets('ChoiceChip をタップして切り替えられ、選択中はチェックで示す', (tester) async {
      await pumpBrowser(tester);
      final chips = find.byType(ChoiceChip);
      expect(chips, findsNWidgets(VisionFilterCategory.values.length + 1));

      await tester.tap(chips.at(1));
      await tester.pump();
      expect(controller.category, VisionFilterCategory.values.first);
      expect(tester.widget<ChoiceChip>(chips.at(1)).selected, isTrue);
      expect(tester.widget<ChoiceChip>(chips.at(0)).selected, isFalse);
    });

    testWidgets('カテゴリを切り替えると検索語は空に戻る', (tester) async {
      await pumpBrowser(tester);
      await tester.enterText(find.byType(TextField), 'star');
      await tester.pump();

      await tester.tap(find.byType(ChoiceChip).at(1));
      await tester.pump();
      expect(controller.search.text, isEmpty);
    });
  });

  group('行の選択', () {
    testWidgets('色覚の行は色覚の層（variantId 無し）になり、onActivated が呼ばれる', (tester) async {
      await pumpBrowser(tester);
      await tester.tap(tileOf('cv:protanopia'));
      await tester.pump();

      expect(state.selectedId, 'protanopia');
      expect(state.focusedVariantId, isNull);
      expect(
        find.descendant(
            of: tileOf('cv:protanopia'),
            matching: find.byIcon(Icons.radio_button_checked)),
        findsOneWidget,
      );
      expect(activated, 1);
    });

    testWidgets('advanced だけの行は VisionFilterState.toggle で選ばれる',
        (tester) async {
      await pumpBrowser(tester);
      final tile = tileOf('catalog:starbursts');
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pump();

      expect(state.selectedId, 'starbursts');
      expect(state.focusedVariantId, isNull);
      expect(activated, 1);
    });

    testWidgets('体験プリセットの行は selectPreset で選ばれ、その行だけが点灯する', (tester) async {
      await pumpBrowser(tester);
      await tester.tap(find.byKey(experienceCardKey('meniere')));
      await tester.pump();

      expect(state.selectedPresetId, 'meniere');
      expect(
        find.descendant(
          of: find.byKey(experienceCardKey('meniere')),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
      // meniere と labyrinthitis は同じカタログ id に写るが、点灯は片方だけ。
      expect(
        find.descendant(
          of: find.byKey(experienceCardKey('labyrinthitis')),
          matching: find.byIcon(Icons.check),
        ),
        findsNothing,
      );
      expect(activated, 1);
    });
  });

  testWidgets('focusSearch は検索欄にフォーカスを移し、入力済みの文字を全選択する', (tester) async {
    await pumpBrowser(tester);
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump();
    tester.binding.focusManager.primaryFocus?.unfocus();
    await tester.pump();
    expect(controller.searchFocus.hasFocus, isFalse);

    controller.focusSearch();
    await tester.pump();

    expect(controller.searchFocus.hasFocus, isTrue);
    expect(controller.search.selection,
        const TextSelection(baseOffset: 0, extentOffset: 3));
  });
}
