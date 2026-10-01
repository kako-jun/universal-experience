// FilterBrowser のカテゴリチップと検索語の表示の食い違い（#143）のテスト。
//
// 検索語があるあいだ一覧はカテゴリを無視して全体から探すので、チップは全て
// 非選択表示（selected: false・チェック・選択色なし。通常の非選択チップと同じ見た目）に見せる。内部のカテゴリ
// （FilterBrowserController.category）は変えず、検索語を消すと元の選択表示に戻る。
// チップを押すと従来どおり検索語が消えてそのカテゴリが選ばれる。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/models/vision_filter_catalog.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/ui/theme/app_theme.dart';
import 'package:universal_experience/ui/widgets/filter_browser.dart';

import 'support/home_screen_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installHomeScreenFixtures);
  tearDown(resetHomeScreenFixtures);

  late FilterBrowserController controller;

  Future<void> pumpBrowser(
    WidgetTester tester, {
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    controller = FilterBrowserController();
    addTearDown(controller.dispose);
    final state = VisionFilterState();

    await tester.pumpWidget(
      ChangeNotifierProvider<VisionFilterState>.value(
        value: state,
        child: MaterialApp(
          theme: theme,
          locale: const Locale('ja'),
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
              child: FilterBrowser(controller: controller, onActivated: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder chips() => find.byType(ChoiceChip);

  List<bool> selectedFlags(WidgetTester tester) => [
        for (final chip in tester.widgetList<ChoiceChip>(chips()))
          chip.selected,
      ];

  Finder chipLabeled(String label) => find.widgetWithText(ChoiceChip, label);

  Future<void> typeSearch(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
  }

  testWidgets('検索語が無いときは従来どおり「すべて」だけが選択表示', (tester) async {
    await pumpBrowser(tester);
    expect(chips(), findsNWidgets(1 + VisionFilterCategory.values.length));
    final flags = selectedFlags(tester);
    expect(flags.first, isTrue);
    expect(flags.skip(1), everyElement(isFalse));
  });

  testWidgets('検索語を入れると全チップが非選択になり、消すと元に戻る（カテゴリ未選択）', (tester) async {
    await pumpBrowser(tester);
    await typeSearch(tester, 'myo');
    expect(selectedFlags(tester), everyElement(isFalse));
    expect(controller.category, isNull, reason: '内部のカテゴリは変えない');

    await typeSearch(tester, '');
    final flags = selectedFlags(tester);
    expect(flags.first, isTrue);
    expect(flags.skip(1), everyElement(isFalse));
  });

  testWidgets('カテゴリ選択中に検索すると全チップ非選択、消すとそのカテゴリの選択に戻る', (tester) async {
    await pumpBrowser(tester);
    await tester.tap(chipLabeled('色覚'));
    await tester.pump();
    expect(controller.category, VisionFilterCategory.colorVision);
    expect(
      tester.widget<ChoiceChip>(chipLabeled('色覚')).selected,
      isTrue,
    );

    await typeSearch(tester, 'myo');
    expect(selectedFlags(tester), everyElement(isFalse));
    expect(controller.category, VisionFilterCategory.colorVision,
        reason: '検索中も内部のカテゴリは保たれる');

    await typeSearch(tester, '');
    expect(
      tester.widget<ChoiceChip>(chipLabeled('色覚')).selected,
      isTrue,
      reason: '検索語を消すと元のカテゴリ選択に戻る',
    );
    expect(tester.widget<ChoiceChip>(chipLabeled('すべて')).selected, isFalse);
  });

  testWidgets('空白だけの検索語は検索扱いにしない（チップは選択表示のまま）', (tester) async {
    await pumpBrowser(tester);
    await typeSearch(tester, '   ');
    expect(controller.isSearching, isFalse);
    expect(selectedFlags(tester).first, isTrue);
  });

  testWidgets('検索中にチップを押すと検索語が消えてそのカテゴリが選ばれる', (tester) async {
    await pumpBrowser(tester);
    await typeSearch(tester, 'myo');
    expect(selectedFlags(tester), everyElement(isFalse));

    await tester.tap(chipLabeled('色覚'));
    await tester.pump();

    expect(controller.search.text, isEmpty);
    expect(controller.category, VisionFilterCategory.colorVision);
    expect(tester.widget<ChoiceChip>(chipLabeled('色覚')).selected, isTrue);
    expect(tester.widget<ChoiceChip>(chipLabeled('すべて')).selected, isFalse);
  });

  testWidgets('検索中に「すべて」を押しても検索語が消えて「すべて」が選ばれる', (tester) async {
    await pumpBrowser(tester);
    await tester.tap(chipLabeled('色覚'));
    await tester.pump();
    await typeSearch(tester, 'myo');

    await tester.tap(chipLabeled('すべて'));
    await tester.pump();

    expect(controller.search.text, isEmpty);
    expect(controller.category, isNull);
    expect(tester.widget<ChoiceChip>(chipLabeled('すべて')).selected, isTrue);
  });

  testWidgets('検索中のチップは、検索していない時の非選択チップと同じ見た目（文字色を上書きしない）',
      (tester) async {
    Color? labelColor(String label) => tester
        .widget<RichText>(find.descendant(
            of: chipLabeled(label), matching: find.byType(RichText)))
        .text
        .style
        ?.color;

    await pumpBrowser(tester);
    // 検索していない時の非選択チップ（「すべて」が選択中なので「色覚」を基準にする）。
    expect(tester.widget<ChoiceChip>(chipLabeled('色覚')).selected, isFalse);
    final plainUnselected = labelColor('色覚');

    await typeSearch(tester, 'myo');
    for (final chip in tester.widgetList<ChoiceChip>(chips())) {
      expect(chip.selected, isFalse, reason: 'チェック・選択色が出ない');
      expect(chip.labelStyle, isNull, reason: '文字色の上書きはしない');
    }
    expect(labelColor('色覚'), plainUnselected);
    expect(labelColor('すべて'), plainUnselected,
        reason: '選択中だった「すべて」も通常の非選択と同じ文字色');
  });

  // 検索中の文字（通常の非選択チップと同じ）が 4 テーマで読めること（DESIGN.md の
  // コントラスト 4.5:1 / 大きい文字 3:1）。
  group('検索中のチップの文字コントラスト', () {
    final themes = <String, ThemeData>{
      'ライト': AppTheme.lightTheme,
      'ダーク': AppTheme.darkTheme,
      'ハイコントラスト（ライト）': AppTheme.highContrastTheme,
      'ハイコントラスト（ダーク）': AppTheme.highContrastDarkTheme,
    };
    for (final entry in themes.entries) {
      testWidgets(entry.key, (tester) async {
        final handle = tester.ensureSemantics();
        await pumpBrowser(tester, theme: entry.value);
        await typeSearch(tester, 'myo');
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }
        expect(selectedFlags(tester), everyElement(isFalse));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  });
}
