// FilterBrowser の多選択（チェック式の一覧、#120）の widget test。
//
// 行のチェックで層が足される/外れる・適用順の番号バッジ・色覚グループの排他（ラジオ式）・
// 上限での無効化と理由・体験プリセットの置き換えと点灯条件・FilterService の同期を確認する。
// 選択の正本は VisionFilterState のまま（一覧は表示と入口だけを持つ）。

import 'dart:ui' show CheckedState, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/models/vision_filter_catalog.dart';
import 'package:universal_experience/services/filter_service.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/ui/widgets/experience_presets.dart';
import 'package:universal_experience/ui/widgets/filter_browser.dart';
import 'package:universal_experience/ui/widgets/filter_list_tile.dart';

import 'support/home_screen_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installHomeScreenFixtures);
  tearDown(resetHomeScreenFixtures);

  late FilterBrowserController controller;
  late FilterService filterService;
  late VisionFilterState state;

  Future<void> pumpBrowser(WidgetTester tester, {String locale = 'ja'}) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    controller = FilterBrowserController();
    addTearDown(controller.dispose);
    state = VisionFilterState();
    filterService = FilterService(visionState: state);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<FilterService>.value(value: filterService),
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
              child: FilterBrowser(controller: controller),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder tileOf(String key) => find.byKey(ValueKey('filter_tile_$key'));

  Future<void> tapRow(WidgetTester tester, String key) async {
    await tester.ensureVisible(tileOf(key));
    await tester.tap(tileOf(key));
    await tester.pump();
  }

  /// 行（[tileOf]）の読み上げ用のデータ。
  SemanticsData semanticsOf(WidgetTester tester, String key) =>
      tester.getSemantics(tileOf(key)).getSemanticsData();

  Finder badgeOf(String key, String number) =>
      find.descendant(of: tileOf(key), matching: find.text(number));

  bool isDisabled(WidgetTester tester, String key) => !tester
      .widget<ListTile>(find.descendant(
        of: tileOf(key),
        matching: find.byType(ListTile),
      ))
      .enabled;

  List<String> layerIds() => [for (final l in state.layers) l.id];

  group('チェックで層が足され外れる', () {
    testWidgets('行を選ぶと層が足され、もう一度選ぶと外れる', (tester) async {
      await pumpBrowser(tester);

      await tapRow(tester, 'catalog:glaucoma');
      await tapRow(tester, 'catalog:myopia');
      expect(layerIds(), ['myopia', 'glaucoma'], reason: '段順に並ぶ');
      expect(
        find.descendant(
            of: tileOf('catalog:glaucoma'),
            matching: find.byIcon(Icons.check_box)),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: tileOf('catalog:floaters'),
            matching: find.byIcon(Icons.check_box_outline_blank)),
        findsOneWidget,
      );

      await tapRow(tester, 'catalog:glaucoma');
      expect(layerIds(), ['myopia']);
      expect(
        find.descendant(
            of: tileOf('catalog:glaucoma'),
            matching: find.byIcon(Icons.check_box_outline_blank)),
        findsOneWidget,
      );
    });

    testWidgets('選んだ行がフォーカス層になる', (tester) async {
      await pumpBrowser(tester);
      await tapRow(tester, 'catalog:myopia');
      await tapRow(tester, 'catalog:glaucoma');
      expect(state.focusedId, 'glaucoma');
    });
  });

  group('適用順の番号バッジ', () {
    testWidgets('番号は選んだ順でなく段順（チップ帯・層の並びと同じ）に付く', (tester) async {
      await pumpBrowser(tester);

      // 選んだ順: 視野 → 色覚 → 光学。段順は 光学 → 視野 → 色覚。
      await tapRow(tester, 'catalog:glaucoma');
      await tapRow(tester, 'cv:protanopia');
      await tapRow(tester, 'catalog:myopia');

      expect(layerIds(), ['myopia', 'glaucoma', 'protanopia']);
      expect(badgeOf('catalog:myopia', '1'), findsOneWidget);
      expect(badgeOf('catalog:glaucoma', '2'), findsOneWidget);
      expect(badgeOf('cv:protanopia', '3'), findsOneWidget);
      // 未選択の行には番号がない。
      expect(
        find.descendant(
            of: tileOf('catalog:floaters'), matching: find.text('1')),
        findsNothing,
      );
    });

    testWidgets('外すと残りの番号が詰まる', (tester) async {
      await pumpBrowser(tester);
      await tapRow(tester, 'catalog:myopia');
      await tapRow(tester, 'catalog:glaucoma');
      await tapRow(tester, 'cv:protanopia');

      await tapRow(tester, 'catalog:myopia');
      expect(badgeOf('catalog:glaucoma', '1'), findsOneWidget);
      expect(badgeOf('cv:protanopia', '2'), findsOneWidget);
    });

    testWidgets('番号は読み上げでも「適用順 N 番目」と伝わる', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpBrowser(tester);
      await tapRow(tester, 'catalog:myopia');

      // 選択済みの行の読み上げ（行の label は子の文字・バッジの意味づけを束ねる）に
      // 「適用順 1 番目」が入り、未選択の行には入らない。
      final selected = semanticsOf(tester, 'catalog:myopia');
      expect(selected.label, contains('適用順 1 番目'));
      expect(semanticsOf(tester, 'catalog:glaucoma').label,
          isNot(contains('適用順')));
      handle.dispose();
    });
  });

  group('読み上げ（Semantics）', () {
    testWidgets('行の checked は選択と一致し、色覚行はラジオ式の排他グループになる', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpBrowser(tester);
      await tapRow(tester, 'catalog:myopia');
      await tapRow(tester, 'cv:protanopia');

      final checked = semanticsOf(tester, 'catalog:myopia');
      expect(checked.flagsCollection.isChecked, CheckedState.isTrue);
      expect(checked.flagsCollection.isInMutuallyExclusiveGroup, isFalse);

      final unchecked = semanticsOf(tester, 'catalog:glaucoma');
      expect(unchecked.flagsCollection.isChecked, CheckedState.isFalse);

      final radioOn = semanticsOf(tester, 'cv:protanopia');
      expect(radioOn.flagsCollection.isChecked, CheckedState.isTrue);
      expect(radioOn.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
      final radioOff = semanticsOf(tester, 'cv:deuteranopia');
      expect(radioOff.flagsCollection.isChecked, CheckedState.isFalse);
      expect(radioOff.flagsCollection.isInMutuallyExclusiveGroup, isTrue);

      // 外すと checked も外れる。
      await tapRow(tester, 'catalog:myopia');
      expect(semanticsOf(tester, 'catalog:myopia').flagsCollection.isChecked,
          CheckedState.isFalse);
      handle.dispose();
    });

    testWidgets('上限で無効の行は isEnabled=false で、理由が label に入る', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpBrowser(tester);
      for (final key in [
        'catalog:myopia',
        'catalog:cataract',
        'catalog:floaters',
        'catalog:glaucoma',
        'catalog:teichopsia',
      ]) {
        await tapRow(tester, key);
      }

      await tester.ensureVisible(tileOf('catalog:hyperopia'));
      final disabled = semanticsOf(tester, 'catalog:hyperopia');
      expect(disabled.flagsCollection.isEnabled, Tristate.isFalse);
      expect(disabled.label, contains('上限の 5 件に達しています'));

      final enabled = semanticsOf(tester, 'catalog:myopia');
      expect(enabled.flagsCollection.isEnabled, Tristate.isTrue);
      expect(enabled.label, isNot(contains('上限')));
      handle.dispose();
    });
  });

  group('色覚グループは排他（ラジオ式）', () {
    testWidgets('色覚カテゴリの見出しに「いずれか 1 つ」が付き、行はラジオ式', (tester) async {
      await pumpBrowser(tester);
      expect(find.textContaining('いずれか 1 つ'), findsOneWidget);
      expect(
        find.descendant(
            of: tileOf('cv:protanopia'),
            matching: find.byIcon(Icons.radio_button_unchecked)),
        findsOneWidget,
      );
    });

    testWidgets('別の色覚を選ぶと置き換わり、他のフィルタの層は残る', (tester) async {
      await pumpBrowser(tester);
      await tapRow(tester, 'catalog:myopia');
      await tapRow(tester, 'cv:protanopia');
      await tapRow(tester, 'cv:deuteranomaly');

      expect(layerIds(), ['myopia', 'deuteranopia']);
      expect(state.layers.last.variantId, 'deuteranomaly');
      expect(
        find.descendant(
            of: tileOf('cv:protanopia'),
            matching: find.byIcon(Icons.radio_button_checked)),
        findsNothing,
      );
      expect(
        find.descendant(
            of: tileOf('cv:deuteranomaly'),
            matching: find.byIcon(Icons.radio_button_checked)),
        findsOneWidget,
      );
      expect(badgeOf('cv:deuteranomaly', '2'), findsOneWidget);
    });

    testWidgets('色覚を選ぶと FilterService の色覚型も同期し、外すと none に戻る', (tester) async {
      await pumpBrowser(tester);
      await tapRow(tester, 'catalog:myopia');
      expect(filterService.currentFilter, ColorVisionType.none);

      await tapRow(tester, 'cv:tritanomaly');
      expect(filterService.currentFilter, ColorVisionType.tritanomaly);
      // 色覚の強度スライダーが読む値も、層の強度と同じ記憶を指す。
      state.setLayerStrength('tritanopia', 0.35);
      expect(filterService.intensity, closeTo(0.35, 1e-9));

      await tapRow(tester, 'cv:tritanomaly');
      expect(filterService.currentFilter, ColorVisionType.none);
      expect(layerIds(), ['myopia']);
    });

    testWidgets(
        'カタログ側の色覚グループの行（tetrachromacy）が色覚層を置き換えると FilterService は none に戻る',
        (tester) async {
      await pumpBrowser(tester);
      await tapRow(tester, 'cv:protanopia');
      expect(filterService.currentFilter, ColorVisionType.protanopia);

      await tapRow(tester, 'catalog:tetrachromacy');
      expect(layerIds(), ['tetrachromacy']);
      expect(filterService.currentFilter, ColorVisionType.none);
    });
  });

  group('上限（5 層）', () {
    const five = [
      'catalog:myopia',
      'catalog:cataract',
      'catalog:floaters',
      'catalog:glaucoma',
      'catalog:teichopsia',
    ];

    testWidgets('上限に達すると未選択の行は無効になり、理由が文字で出る', (tester) async {
      await pumpBrowser(tester);
      for (final key in five) {
        await tapRow(tester, key);
      }
      expect(state.layers.length, 5);

      // 未選択の行（advanced・色覚）は選べない。
      for (final key in [
        'catalog:hyperopia',
        'cv:protanopia',
        'cv:deuteranomaly'
      ]) {
        await tester.ensureVisible(tileOf(key));
        expect(isDisabled(tester, key), isTrue, reason: key);
        expect(
          find.descendant(
            of: tileOf(key),
            matching: find.text('上限の 5 件に達しています。ほかを外すと選べます'),
          ),
          findsOneWidget,
          reason: key,
        );
      }
      // 選択済みの行は有効（外せる）で、理由は出ない。
      expect(isDisabled(tester, 'catalog:myopia'), isFalse);
      expect(
        find.descendant(
          of: tileOf('catalog:myopia'),
          matching: find.textContaining('上限'),
        ),
        findsNothing,
      );

      // 無効な行をタップしても何も変わらない。
      await tester.tap(tileOf('catalog:hyperopia'), warnIfMissed: false);
      await tester.pump();
      expect(state.layers.length, 5);
      expect(layerIds(), isNot(contains('hyperopia')));
    });

    testWidgets('外すと無効が解ける', (tester) async {
      await pumpBrowser(tester);
      for (final key in five) {
        await tapRow(tester, key);
      }
      await tapRow(tester, 'catalog:myopia');
      await tester.ensureVisible(tileOf('catalog:hyperopia'));
      expect(isDisabled(tester, 'catalog:hyperopia'), isFalse);
      expect(find.textContaining('上限の'), findsNothing);
    });

    testWidgets('色覚の層があるときは、上限でも色覚の行が選べる（置き換え）', (tester) async {
      await pumpBrowser(tester);
      for (final key in [
        'catalog:myopia',
        'catalog:cataract',
        'catalog:floaters',
        'catalog:glaucoma',
        'cv:protanopia',
      ]) {
        await tapRow(tester, key);
      }
      expect(state.layers.length, 5);
      expect(isDisabled(tester, 'cv:deuteranopia'), isFalse);
      expect(isDisabled(tester, 'cv:tritanomaly'), isFalse);
      expect(isDisabled(tester, 'catalog:hyperopia'), isTrue);

      await tapRow(tester, 'cv:deuteranopia');
      expect(state.layers.length, 5);
      expect(layerIds().last, 'deuteranopia');
    });

    testWidgets('体験プリセットは上限でも選べ、層をそのフィルタ 1 つに置き換える', (tester) async {
      await pumpBrowser(tester);
      for (final key in five) {
        await tapRow(tester, key);
      }
      await tester.ensureVisible(find.byKey(experienceCardKey('meniere')));
      await tester.tap(find.byKey(experienceCardKey('meniere')));
      await tester.pump();

      expect(state.layers.length, 1);
      expect(state.selectedPresetId, 'meniere');
      // 置き換えで上限が解けるので、一覧の行はまた選べる。
      expect(isDisabled(tester, 'catalog:hyperopia'), isFalse);
    });
  });

  group('体験プリセット', () {
    Finder presetCheck(String id) => find.descendant(
          of: find.byKey(experienceCardKey(id)),
          matching: find.byIcon(Icons.check),
        );

    testWidgets('プリセットを選ぶと層が置き換わり、その行だけが点灯する', (tester) async {
      await pumpBrowser(tester);
      await tapRow(tester, 'catalog:myopia');
      await tapRow(tester, 'catalog:glaucoma');

      await tester.ensureVisible(find.byKey(experienceCardKey('meniere')));
      await tester.tap(find.byKey(experienceCardKey('meniere')));
      await tester.pump();
      expect(state.layers.length, 1);
      expect(presetCheck('meniere'), findsOneWidget);
      expect(presetCheck('bppv'), findsNothing);
    });

    testWidgets('層の集合がそのフィルタ 1 つでなくなると点灯は消え、戻っても点かない', (tester) async {
      await pumpBrowser(tester);
      await tester.ensureVisible(find.byKey(experienceCardKey('meniere')));
      await tester.tap(find.byKey(experienceCardKey('meniere')));
      await tester.pump();
      expect(presetCheck('meniere'), findsOneWidget);

      await tapRow(tester, 'cv:protanopia');
      expect(state.layers.length, 2);
      expect(presetCheck('meniere'), findsNothing);

      await tapRow(tester, 'cv:protanopia');
      expect(state.layers.length, 1);
      expect(presetCheck('meniere'), findsNothing,
          reason: '層が 1 つに戻ってもプリセットの点灯は復活しない');
    });
  });

  testWidgets('カテゴリを色覚に絞っても「いずれか 1 つ」が出る。検索中は出さない', (tester) async {
    await pumpBrowser(tester);
    controller.setCategory(VisionFilterCategory.colorVision);
    await tester.pump();
    expect(find.textContaining('いずれか 1 つ'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'protan');
    await tester.pump();
    expect(find.textContaining('いずれか 1 つ'), findsNothing);
  });

  testWidgets('英語ロケールの見出しと上限の理由', (tester) async {
    await pumpBrowser(tester, locale: 'en');
    expect(find.text('Color vision (pick one)'), findsOneWidget);
    for (final key in [
      'catalog:myopia',
      'catalog:cataract',
      'catalog:floaters',
      'catalog:glaucoma',
      'catalog:teichopsia',
    ]) {
      await tapRow(tester, key);
    }
    await tester.ensureVisible(tileOf('catalog:hyperopia'));
    expect(
      find.descendant(
        of: tileOf('catalog:hyperopia'),
        matching: find.text('Limit of 5 reached. Uncheck one to pick this.'),
      ),
      findsOneWidget,
    );
    // 行の型（チェック式）はプリセットの行と別。
    expect(find.byType(FilterListTile), findsWidgets);
  });
}
