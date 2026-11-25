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
import 'package:universal_experience/ui/widgets/filter_list_tile.dart';

import 'support/home_screen_harness.dart';
import 'support/experience_preset_select.dart';

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

  testWidgets('初期状態は一番上に体験プリセットのドロップダウン、その下に見出し・検索欄・一覧の行が並ぶ（#199）',
      (tester) async {
    await pumpBrowser(tester);
    // 体験プリセットは左カラムの一番上（見出し・検索欄・色覚の行より上）のドロップダウン。
    final dropdown = tester.getRect(experiencePresetDropdown());
    expect(dropdown.bottom,
        lessThanOrEqualTo(tester.getRect(find.text('見え方を選ぶ')).top));
    expect(dropdown.bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(TextField)).top));
    expect(dropdown.top, lessThan(tester.getRect(tileOf('cv:protanopia')).top));
    // 何の欄か（ラベル）と、選ぶと下の設定がまとめて切り替わること（説明）が出ている。
    expect(find.text('体験プリセット'), findsOneWidget);
    expect(find.text('下の設定をまとめて切り替えます。'), findsOneWidget);
    // 何も選んでいない間は「プリセットなし」。
    expect(experiencePresetDropdownText('プリセットなし'), findsOneWidget);
    // 閉じている間はメニューの項目は無い。開くと供給源の 4 件が全部出る（件数は固定しない）。
    expect(find.byKey(experienceCardKey('meniere')), findsNothing);
    await openExperiencePresetMenu(tester);
    for (final id in [
      'meniere',
      'bppv',
      'vestibular_neuritis',
      'labyrinthitis'
    ]) {
      expect(find.byKey(experienceCardKey(id)), findsOneWidget, reason: id);
    }
  });

  group('検索', () {
    testWidgets('英語名で絞り込める', (tester) async {
      await pumpBrowser(tester);
      await tester.enterText(find.byType(TextField), 'protanopia');
      await tester.pump();

      expect(tileOf('cv:protanopia'), findsOneWidget);
      expect(tileOf('cv:deuteranopia'), findsNothing);
      // 体験プリセットのドロップダウンは検索語と無関係に出たまま。
      expect(experiencePresetDropdown(), findsOneWidget);
    });

    testWidgets('日本語名で絞り込める', (tester) async {
      await pumpBrowser(tester);
      await tester.enterText(find.byType(TextField), '緑内障');
      await tester.pump();

      expect(tileOf('catalog:glaucoma'), findsOneWidget);
      expect(tileOf('catalog:myopia'), findsNothing);
      expect(tileOf('cv:protanopia'), findsNothing);
    });

    testWidgets('体験プリセットの名前で検索すると、行は無いが「上の体験プリセットから選べます」の案内が出る（#199）',
        (tester) async {
      await pumpBrowser(tester);
      await tester.enterText(find.byType(TextField), 'メニエール');
      await tester.pump();

      // 体験プリセットは一覧の行ではない。行は 0 件だが、「見つかりません」ではなく案内を出す。
      expect(find.byType(FilterListTile), findsNothing);
      expect(find.byKey(filterListPresetHintKey), findsOneWidget);
      expect(find.text('「メニエール病」は、上の「体験プリセット」から選べます。'), findsOneWidget);
      expect(find.text('一致する見え方がありません。'), findsNothing);
      expect(experiencePresetDropdown(), findsOneWidget);
    });

    testWidgets('プリセットの id・英語名でも案内が出る。複数当たれば全部の名前を並べる', (tester) async {
      await pumpBrowser(tester);
      await tester.enterText(find.byType(TextField), 'bppv');
      await tester.pump();
      expect(find.text('「良性発作性頭位めまい症」は、上の「体験プリセット」から選べます。'),
          findsOneWidget);

      // 「炎」は 前庭神経炎・迷路炎 の 2 つのプリセットに当たる。
      await tester.enterText(find.byType(TextField), '炎');
      await tester.pump();
      expect(find.text('「前庭神経炎」「迷路炎」は、上の「体験プリセット」から選べます。'), findsOneWidget);
    });

    testWidgets('プリセット名と行の両方に当たる検索語では、案内と行の両方が出る', (tester) async {
      await pumpBrowser(tester);
      // 「前庭神経炎」は体験プリセットにも advanced のフィルタにもある。
      await tester.enterText(find.byType(TextField), '前庭神経炎');
      await tester.pump();

      expect(find.byKey(filterListPresetHintKey), findsOneWidget);
      expect(tileOf('catalog:vestibular_neuritis'), findsOneWidget);
      expect(
        tester.getRect(find.byKey(filterListPresetHintKey)).bottom,
        lessThanOrEqualTo(
            tester.getRect(tileOf('catalog:vestibular_neuritis')).top),
        reason: '案内は行より上',
      );
    });

    testWidgets('どれにも当たらない検索語では案内は出ず、「一致する見え方がありません」だけ', (tester) async {
      await pumpBrowser(tester);
      await tester.enterText(find.byType(TextField), 'zzzzzzzz');
      await tester.pump();

      expect(find.byKey(filterListPresetHintKey), findsNothing);
      expect(find.text('一致する見え方がありません。'), findsOneWidget);
    });

    testWidgets('検索していない間（カテゴリで絞っているだけ）は案内を出さない', (tester) async {
      await pumpBrowser(tester);
      expect(find.byKey(filterListPresetHintKey), findsNothing);
      controller.setCategory(VisionFilterCategory.colorVision);
      await tester.pump();
      expect(find.byKey(filterListPresetHintKey), findsNothing);
    });

    testWidgets('英語ロケールの案内は英語（プリセット名・ラベルとも）', (tester) async {
      await pumpBrowser(tester, locale: 'en');
      await tester.enterText(find.byType(TextField), 'meniere');
      await tester.pump();
      expect(
        find.text(
            'Ménière\'s disease — choose it from “Experience Presets” above.'),
        findsOneWidget,
      );
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
      // カテゴリを絞っても体験プリセットのドロップダウンは出たまま（#199）。
      expect(experiencePresetDropdown(), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'すべて'));
      await tester.pump();
      expect(controller.category, isNull);
      expect(experiencePresetDropdown(), findsOneWidget);
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

    testWidgets('体験プリセットはドロップダウンから selectPreset で選ばれ、選んだ名前が表示される',
        (tester) async {
      await pumpBrowser(tester);
      await selectExperiencePreset(tester, 'meniere');

      expect(state.selectedPresetId, 'meniere');
      expect(experiencePresetDropdownText('メニエール病'), findsOneWidget);
      // meniere と labyrinthitis は同じカタログ id に写るが、表示は選んだ方だけ。
      expect(experiencePresetDropdownText('迷路炎'), findsNothing);
      // 選んだ結果は下の一覧に反映される（プリセットのフィルタの行にチェック）。
      expect(
        tester.widget<FilterListTile>(tileOf('catalog:vertigo')).selected,
        isTrue,
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
