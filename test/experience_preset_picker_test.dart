// 体験プリセットのドロップダウン（`ExperiencePresetPicker`、#199）の widget test。
//
// experience_presets_test.dart（4 体験の選択と右カラムの注記）・filter_browser_test.dart
// （一覧との並び）が見ていない所を見る:
// - 件数を固定しない（0 件・1 件・多数。多数ではメニューがスクロールして全件に届く）
// - 表示名が未登録の id・視覚フィルタの無い体験・一覧に無い選択中 id
// - フィルタを足し引きしたあとの「プリセットなし」
// - ラベル・説明文（ja / en）
// - ポインタ / キーボードで選んだあとのフォーカス
// - 低い画面（`kFilterBrowserCompactHeight` 未満）でのスクロール

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/models/vision_filter_catalog.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/widgets/experience_presets.dart';
import 'package:universal_experience/ui/widgets/filter_browser.dart';
import 'package:universal_experience/ui/widgets/filter_list_tile.dart';

import 'support/experience_preset_select.dart';
import 'support/home_screen_harness.dart';

/// [count] 件の体験（id は `future_00`, `future_01`, …。ARB に名前が無いので id のまま出る）。
/// 視覚フィルタは 3 種を順に割り当てる。
List<Experience> _manyExperiences(int count) => [
      for (var i = 0; i < count; i++)
        Experience(
          id: 'future_${i.toString().padLeft(2, '0')}',
          vision: const [
            VisionFilter.vertigo(),
            VisionFilter.bppvRotation(),
            VisionFilter.vestibularNeuritis(),
          ][i % 3],
          urgency: Urgency.none,
        ),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installHomeScreenFixtures);
  tearDown(resetHomeScreenFixtures);

  late FilterBrowserController controller;
  late VisionFilterState state;
  var activated = 0;

  /// 幅 400・高さ [height] の箱に [FilterBrowser] を置く。
  Future<void> pumpBrowser(
    WidgetTester tester, {
    String locale = 'ja',
    double height = 880,
    double width = 400,
  }) async {
    tester.view.physicalSize = Size(width, 900);
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
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                height: height,
                child: FilterBrowser(
                  controller: controller,
                  onActivated: () => activated++,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder tileOf(String key) => find.byKey(ValueKey('filter_tile_$key'));

  /// 開いたメニューの中のスクロール（メニューは別ルートに出るので、一覧のスクロールとは別）。
  Finder menuScrollable() => find
      .ancestor(
        of: find.byWidgetPredicate((w) => w is DropdownMenuItem<String>).first,
        matching: find.byType(Scrollable),
      )
      .first;

  /// 一覧（`FilterBrowser` の中）のスクロール。
  Finder listScrollView() => find.descendant(
        of: find.byType(FilterBrowser),
        matching: find.byType(SingleChildScrollView),
      );

  bool focusIsInPicker(WidgetTester tester) =>
      tester.binding.focusManager.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<ExperiencePresetPicker>() !=
      null;

  group('件数を固定しない', () {
    testWidgets('体験が 0 件ならドロップダウンを出さず、見出し・検索欄・一覧はそのまま出る', (tester) async {
      experiencesProvider = () => const <Experience>[];
      await pumpBrowser(tester);

      expect(experiencePresetDropdown(), findsNothing);
      expect(find.text('体験プリセット'), findsNothing);
      expect(find.text('下の設定をまとめて切り替えます。'), findsNothing);
      expect(find.text('プリセットなし'), findsNothing);
      expect(find.text('見え方を選ぶ'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(tileOf('cv:protanopia'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('体験が 1 件ならメニューは 1 項目', (tester) async {
      experiencesProvider = () => const [
            Experience(
              id: 'bppv',
              vision: VisionFilter.bppvRotation(),
              urgency: Urgency.none,
            ),
          ];
      await pumpBrowser(tester);
      await openExperiencePresetMenu(tester);

      expect(find.byWidgetPredicate((w) => w is DropdownMenuItem<String>),
          findsOneWidget);
      expect(find.byKey(experienceCardKey('bppv')), findsOneWidget);
      expect(find.byKey(experienceCardKey('meniere')), findsNothing);
    });

    testWidgets('体験が 5 件に増えれば 5 件とも出る（4 件に決め打ちしていない）', (tester) async {
      experiencesProvider = () => [
            ...fixtureExperiences(),
            const Experience(
              id: 'future_new',
              vision: VisionFilter.vertigo(),
              urgency: Urgency.none,
            ),
          ];
      await pumpBrowser(tester);
      await openExperiencePresetMenu(tester);

      for (final id in [
        'meniere',
        'bppv',
        'vestibular_neuritis',
        'labyrinthitis',
        'future_new',
      ]) {
        expect(find.byKey(experienceCardKey(id)), findsOneWidget, reason: id);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('体験が多い（30 件）ときはメニューがスクロールし、全件に届いて、末尾の 1 件を選べる', (tester) async {
      final many = _manyExperiences(30);
      experiencesProvider = () => many;
      await pumpBrowser(tester);
      await openExperiencePresetMenu(tester);
      expect(tester.takeException(), isNull);

      // メニューは画面に収まり（menuMaxHeight）、最初は末尾が見えていない。
      expect(find.byKey(experienceCardKey(many.last.id)).hitTestable(),
          findsNothing,
          reason: '前提: 30 件は 1 画面に入らない');

      final seen = <String>{};
      for (final exp in many) {
        final item = find.byKey(experienceCardKey(exp.id));
        await tester.scrollUntilVisible(item, 80,
            scrollable: menuScrollable(), maxScrolls: 200);
        expect(item, findsOneWidget, reason: exp.id);
        seen.add(exp.id);
      }
      expect(seen, hasLength(30));

      final last = find.byKey(experienceCardKey(many.last.id));
      expect(last.hitTestable(), findsOneWidget);
      await tester.tap(last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(state.selectedPresetId, many.last.id);
      expect(state.layers.map((l) => l.id),
          [visionFilterCatalogId(many.last.vision!)]);
      // 名前が未登録の id は id のまま表示される。
      expect(experiencePresetDropdownText(many.last.id), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('表示名が未登録の体験（sensus に増えた直後）は id のまま出て、選べる', (tester) async {
      experiencesProvider = () => const [
            Experience(
              id: 'brand_new_condition',
              vision: VisionFilter.vertigo(),
              urgency: Urgency.none,
            ),
          ];
      await pumpBrowser(tester);
      await openExperiencePresetMenu(tester);
      expect(
        find.descendant(
          of: find.byKey(experienceCardKey('brand_new_condition')),
          matching: find.text('brand_new_condition'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(experienceCardKey('brand_new_condition')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(state.selectedPresetId, 'brand_new_condition');
      expect(state.selectedId, 'vertigo');
    });
  });

  group('選択', () {
    testWidgets('選ぶと selectPreset が呼ばれ、層はそのプリセットのフィルタ 1 つに置き換わる',
        (tester) async {
      await pumpBrowser(tester);
      state.toggle('myopia');
      state.toggle('glaucoma');
      await tester.pump();
      expect(state.layers, hasLength(2));

      await selectExperiencePreset(tester, 'vestibular_neuritis');

      expect(state.selectedPresetId, 'vestibular_neuritis');
      expect(state.layers.map((l) => l.id), ['vestibular_neuritis']);
      // メニューは閉じている。
      expect(find.byKey(experienceCardKey('meniere')), findsNothing);
      // 結果は下の一覧のチェックに出る。
      expect(
        tester
            .widget<FilterListTile>(tileOf('catalog:vestibular_neuritis'))
            .selected,
        isTrue,
      );
      expect(tester.widget<FilterListTile>(tileOf('catalog:myopia')).selected,
          isFalse);
    });

    testWidgets('メニューを開いて何も選ばずに閉じても、選択は変わらない', (tester) async {
      await pumpBrowser(tester);
      await selectExperiencePreset(tester, 'bppv');
      await openExperiencePresetMenu(tester);

      // メニューの外（バリア）をタップして閉じる。
      await tester.tapAt(const Offset(395, 895));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byKey(experienceCardKey('meniere')), findsNothing);
      expect(state.selectedPresetId, 'bppv');
      expect(experiencePresetDropdownText('良性発作性頭位めまい症'), findsOneWidget);
      expect(activated, 1, reason: '選んだ 1 回だけ');
    });

    testWidgets('視覚フィルタの無い体験は選べない（タップしても選択は変わらない）', (tester) async {
      experiencesProvider = () => const [
            Experience(
              id: 'bppv',
              vision: VisionFilter.bppvRotation(),
              urgency: Urgency.none,
            ),
            Experience(id: 'hearing_only', urgency: Urgency.none),
          ];
      await pumpBrowser(tester);
      await openExperiencePresetMenu(tester);
      final item = tester.widget<DropdownMenuItem<String>>(
        find.ancestor(
          of: find.byKey(experienceCardKey('hearing_only')),
          matching:
              find.byWidgetPredicate((w) => w is DropdownMenuItem<String>),
        ),
      );
      expect(item.enabled, isFalse);

      await tester.tap(find.byKey(experienceCardKey('hearing_only')),
          warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(state.selectedPresetId, isNull);
      expect(state.layers, isEmpty);
      expect(activated, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('選択中の id が体験の一覧に無い（古い保存値など）ときは「プリセットなし」で、例外を出さない',
        (tester) async {
      await pumpBrowser(tester);
      state.selectPreset('gone_from_sensus', 'vertigo');
      await tester.pump();

      expect(state.selectedPresetId, 'gone_from_sensus');
      expect(tester.takeException(), isNull);
      expect(experiencePresetDropdownText('プリセットなし'), findsOneWidget);
      // そのあとでも普通に選べる。
      await selectExperiencePreset(tester, 'meniere');
      expect(state.selectedPresetId, 'meniere');
      expect(experiencePresetDropdownText('メニエール病'), findsOneWidget);
    });

    testWidgets('外から選択が変わっても（トレイ・復元）、ドロップダウンの表示が追従する', (tester) async {
      await pumpBrowser(tester);
      state.selectPreset('labyrinthitis', 'vertigo');
      await tester.pump();
      expect(experiencePresetDropdownText('迷路炎'), findsOneWidget);

      state.selectPreset('bppv', 'bppv_rotation');
      await tester.pump();
      expect(experiencePresetDropdownText('迷路炎'), findsNothing);
      expect(experiencePresetDropdownText('良性発作性頭位めまい症'), findsOneWidget);
    });
  });

  group('フィルタを変えたあとは「プリセットなし」へ戻る', () {
    testWidgets('一覧の行をタップしてフィルタを足す', (tester) async {
      await pumpBrowser(tester);
      await selectExperiencePreset(tester, 'meniere');
      expect(experiencePresetDropdownText('メニエール病'), findsOneWidget);

      await tester.ensureVisible(tileOf('catalog:myopia'));
      await tester.pump();
      await tester.tap(tileOf('catalog:myopia'));
      await tester.pump();

      expect(state.selectedPresetId, isNull);
      expect(state.layers.map((l) => l.id), containsAll(['vertigo', 'myopia']));
      expect(experiencePresetDropdownText('プリセットなし'), findsOneWidget);
      expect(experiencePresetDropdownText('メニエール病'), findsNothing);
    });

    testWidgets('足したフィルタを外して元の 1 つに戻しても、プリセットは付き直さない', (tester) async {
      await pumpBrowser(tester);
      await selectExperiencePreset(tester, 'meniere');
      await tester.ensureVisible(tileOf('catalog:myopia'));
      await tester.pump();
      await tester.tap(tileOf('catalog:myopia'));
      await tester.pump();
      await tester.tap(tileOf('catalog:myopia'));
      await tester.pump();

      expect(state.layers.map((l) => l.id), ['vertigo']);
      expect(state.selectedPresetId, isNull);
      expect(experiencePresetDropdownText('プリセットなし'), findsOneWidget);
    });

    testWidgets('プリセットのフィルタの行をタップして外す（層が空になる）', (tester) async {
      await pumpBrowser(tester);
      await selectExperiencePreset(tester, 'bppv');
      await tester.ensureVisible(tileOf('catalog:bppv_rotation'));
      await tester.pump();
      await tester.tap(tileOf('catalog:bppv_rotation'));
      await tester.pump();

      expect(state.layers, isEmpty);
      expect(state.selectedPresetId, isNull);
      expect(experiencePresetDropdownText('プリセットなし'), findsOneWidget);
    });

    testWidgets('色覚の行を選ぶ', (tester) async {
      await pumpBrowser(tester);
      await selectExperiencePreset(tester, 'bppv');
      await tester.ensureVisible(tileOf('cv:protanopia'));
      await tester.pump();
      await tester.tap(tileOf('cv:protanopia'));
      await tester.pump();

      expect(state.selectedPresetId, isNull);
      expect(experiencePresetDropdownText('プリセットなし'), findsOneWidget);
    });

    testWidgets('「プリセットなし」へ戻ったあと、同じプリセットをもう一度選べる', (tester) async {
      await pumpBrowser(tester);
      await selectExperiencePreset(tester, 'meniere');
      state.toggle('myopia');
      await tester.pump();
      expect(experiencePresetDropdownText('プリセットなし'), findsOneWidget);

      await selectExperiencePreset(tester, 'meniere');

      expect(state.selectedPresetId, 'meniere');
      expect(state.layers.map((l) => l.id), ['vertigo']);
      expect(experiencePresetDropdownText('メニエール病'), findsOneWidget);
    });
  });

  group('ラベルと説明文', () {
    for (final locale in ['ja', 'en']) {
      testWidgets('$locale: ラベル・説明文・「プリセットなし」が ARB の文言で出る', (tester) async {
        await pumpBrowser(tester, locale: locale);
        final l10n = lookupAppLocalizations(Locale(locale));

        expect(
          find.descendant(
            of: find.byType(ExperiencePresetPicker),
            matching: find.text(l10n.experienceSectionTitle),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(ExperiencePresetPicker),
            matching: find.text(l10n.experiencePresetHelper),
          ),
          findsOneWidget,
        );
        expect(experiencePresetDropdownText(l10n.experiencePresetNone),
            findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('$locale: プリセットを選んだあとも説明文は出たまま', (tester) async {
        await pumpBrowser(tester, locale: locale);
        final l10n = lookupAppLocalizations(Locale(locale));
        await selectExperiencePreset(tester, 'vestibular_neuritis');

        expect(find.text(l10n.experiencePresetHelper), findsOneWidget);
        expect(experiencePresetDropdownText(l10n.experienceVestibularNeuritis),
            findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    test('ja と en で文言が別（ja に英語のまま残していない）', () {
      final ja = lookupAppLocalizations(const Locale('ja'));
      final en = lookupAppLocalizations(const Locale('en'));
      expect(ja.experiencePresetHelper, isNot(en.experiencePresetHelper));
      expect(ja.experiencePresetNone, isNot(en.experiencePresetNone));
      expect(ja.experiencePresetHelper, isNotEmpty);
      expect(ja.experiencePresetNone, isNotEmpty);
      expect(
          RegExp(r'[A-Za-z]{3,}').hasMatch(ja.experiencePresetHelper), isFalse);
      expect(
          RegExp(r'[A-Za-z]{3,}').hasMatch(ja.experiencePresetNone), isFalse);
    });

    testWidgets('幅が狭くても（256dp）長い英語名で overflow しない', (tester) async {
      await pumpBrowser(tester, locale: 'en', width: 256);
      await selectExperiencePreset(tester, 'vestibular_neuritis');
      expect(tester.takeException(), isNull);
      await openExperiencePresetMenu(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('選んだあとのフォーカス', () {
    testWidgets('ポインタで選ぶと onActivated が 1 回呼ばれる', (tester) async {
      await pumpBrowser(tester);
      await selectExperiencePreset(tester, 'bppv');
      expect(activated, 1);
      await selectExperiencePreset(tester, 'meniere');
      expect(activated, 2);
    });

    testWidgets(
        'キーボード（Tab → Enter で開く → Enter で選ぶ）では onActivated を呼ばず、フォーカスはドロップダウンに残る',
        (tester) async {
      await pumpBrowser(tester);
      // 体験プリセットはカラムの一番上なので、最初の Tab で届く。
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focusIsInPicker(tester), isTrue,
          reason: '最初の Tab でドロップダウンにフォーカスが入る');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(experienceCardKey('meniere')), findsOneWidget,
          reason: 'Enter でメニューが開く');

      // メニューの中の先頭の項目へ移して選ぶ。
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(state.selectedPresetId, isNotNull, reason: 'キーボードだけで選べる');
      expect(find.byKey(experienceCardKey('meniere')), findsNothing,
          reason: 'メニューは閉じている');
      expect(activated, 0, reason: 'キーボードで選んだときは受け口へ戻さない');
      expect(focusIsInPicker(tester), isTrue,
          reason: 'フォーカスはドロップダウンに残る（次の Tab が先頭からやり直しにならない）');

      // 次の Tab は検索欄へ進む（先頭からやり直しにならない）。
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(controller.isSearchFocused, isTrue);
    });

    testWidgets('キーボードで選んだあとにポインタで選ぶと、onActivated が呼ばれる（直近の入力で決まる）',
        (tester) async {
      await pumpBrowser(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(activated, 0);

      await selectExperiencePreset(tester, 'labyrinthitis');
      expect(state.selectedPresetId, 'labyrinthitis');
      expect(activated, 1);
    });
  });

  group('選んだ入力の種類は、メニューの項目を確定した入力で決まる（#199）', () {
    testWidgets('マウスで開いて ↑↓ Enter で選ぶ → キーボード扱い（onActivated を呼ばず、フォーカスはドロップダウン）',
        (tester) async {
      await pumpBrowser(tester);
      await openExperiencePresetMenu(tester);
      expect(find.byKey(experienceCardKey('meniere')), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(state.selectedPresetId, isNotNull, reason: '↑↓ Enter で選べる');
      expect(find.byKey(experienceCardKey('meniere')), findsNothing,
          reason: 'メニューは閉じている');
      expect(activated, 0, reason: '確定したのはキーボード');
      expect(focusIsInPicker(tester), isTrue);
    });

    testWidgets('Enter で開いてクリックで選ぶ → ポインタ扱い（onActivated を呼ぶ）', (tester) async {
      await pumpBrowser(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(experienceCardKey('bppv')), findsOneWidget,
          reason: 'Enter でメニューが開く');

      await tester.tap(find.byKey(experienceCardKey('bppv')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(state.selectedPresetId, 'bppv');
      expect(activated, 1, reason: '確定したのはポインタ');
    });

    testWidgets('メニューの中でキーを押したあとでも、クリックで確定すればポインタ扱い', (tester) async {
      await pumpBrowser(tester);
      await openExperiencePresetMenu(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      await tester.tap(find.byKey(experienceCardKey('labyrinthitis')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(state.selectedPresetId, 'labyrinthitis');
      expect(activated, 1);
    });
  });

  group('高さの境界（kFilterBrowserCompactHeight）をまたいでも状態が落ちない（#199）', () {
    Future<void> resize(WidgetTester tester, double height) async {
      tester.view.physicalSize = Size(400, height + 100);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<VisionFilterState>.value(value: state),
          ],
          child: MaterialApp(
            locale: const Locale('ja'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  height: height,
                  child: FilterBrowser(
                    controller: controller,
                    onActivated: () => activated++,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    for (final (label, from, to) in [
      ('固定 → 全体スクロール', 600.0, 300.0),
      ('全体スクロール → 固定', 300.0, 600.0),
    ]) {
      testWidgets('$label: 検索欄のフォーカスと入力中の文字が残る', (tester) async {
        await pumpBrowser(tester, height: from);
        await tester.tap(find.byType(TextField));
        await tester.pump();
        await tester.enterText(find.byType(TextField), 'prot');
        await tester.pump();
        expect(controller.isSearchFocused, isTrue);

        await resize(tester, to);

        expect(controller.isSearchFocused, isTrue, reason: 'フォーカスが落ちない');
        expect(controller.search.text, 'prot');
        expect(tester.takeException(), isNull);
      });

      testWidgets('$label: ドロップダウンのフォーカスが残る', (tester) async {
        await pumpBrowser(tester, height: from);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(focusIsInPicker(tester), isTrue);

        await resize(tester, to);

        expect(focusIsInPicker(tester), isTrue, reason: 'フォーカスが落ちない');
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('低い画面（高さが kFilterBrowserCompactHeight 未満）', () {
    testWidgets('閾値以上では体験プリセット・見出し・検索欄は固定で、一覧だけがスクロールする', (tester) async {
      await pumpBrowser(tester, height: kFilterBrowserCompactHeight);

      expect(
        find.descendant(
            of: listScrollView(), matching: experiencePresetDropdown()),
        findsNothing,
        reason: 'ドロップダウンは一覧のスクロールの外',
      );
      expect(
        find.descendant(of: listScrollView(), matching: find.byType(TextField)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      // 一覧を末尾までスクロールしても、ドロップダウンは動かない。
      final before = tester.getRect(experiencePresetDropdown());
      final list = tester.state<ScrollableState>(find
          .descendant(of: listScrollView(), matching: find.byType(Scrollable))
          .first);
      list.position.jumpTo(list.position.maxScrollExtent);
      await tester.pump();
      expect(tester.getRect(experiencePresetDropdown()), before);
      expect(experiencePresetDropdown().hitTestable(), findsOneWidget);
    });

    for (final height in [
      kFilterBrowserCompactHeight - 1,
      300.0,
      200.0,
      120.0,
    ]) {
      testWidgets('高さ $height: overflow せず、一番上は体験プリセットで、全体が 1 つのスクロールになる',
          (tester) async {
        await pumpBrowser(tester, height: height);
        expect(tester.takeException(), isNull);

        // ドロップダウン・検索欄・一覧の行が同じスクロールの中にある。
        expect(listScrollView(), findsOneWidget);
        expect(
          find.descendant(
              of: listScrollView(), matching: experiencePresetDropdown()),
          findsOneWidget,
        );
        expect(
          find.descendant(
              of: listScrollView(), matching: find.byType(TextField)),
          findsOneWidget,
        );
        expect(
          find.descendant(
              of: listScrollView(), matching: tileOf('cv:protanopia')),
          findsOneWidget,
        );
        // 並び順は同じ（体験プリセット → 見出し → 検索欄 → 行）。
        final dropdown = tester.getRect(experiencePresetDropdown());
        expect(dropdown.bottom,
            lessThanOrEqualTo(tester.getRect(find.text('見え方を選ぶ')).top));
        expect(dropdown.bottom,
            lessThanOrEqualTo(tester.getRect(find.byType(TextField)).top));
        expect(tester.getRect(find.byType(TextField)).bottom,
            lessThanOrEqualTo(tester.getRect(tileOf('cv:protanopia')).top));

        // 末尾の行までスクロールで届き、そこから体験プリセットへ戻って選べる。
        final list = tester.state<ScrollableState>(find
            .descendant(of: listScrollView(), matching: find.byType(Scrollable))
            .first);
        expect(list.position.maxScrollExtent, greaterThan(0));
        list.position.jumpTo(list.position.maxScrollExtent);
        await tester.pump();
        expect(experiencePresetDropdown().hitTestable(), findsNothing,
            reason: '末尾までスクロールすると体験プリセットは画面の外');

        await selectExperiencePreset(tester, 'bppv');

        expect(state.selectedPresetId, 'bppv');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('低い画面でも、検索で一覧が 0 件になっても体験プリセットは出たまま', (tester) async {
      await pumpBrowser(tester, height: 300);
      await tester.enterText(find.byType(TextField), 'zzzzzzzz');
      await tester.pump();

      expect(find.byType(FilterListTile), findsNothing);
      expect(experiencePresetDropdown(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('低い画面でプリセットを選んだあとも、検索欄の文字とカテゴリは保たれる', (tester) async {
      await pumpBrowser(tester, height: 300);
      await tester.enterText(find.byType(TextField), 'protanopia');
      await tester.pump();

      await selectExperiencePreset(tester, 'meniere');

      expect(controller.search.text, 'protanopia');
      expect(tileOf('cv:protanopia'), findsOneWidget);
      expect(state.selectedPresetId, 'meniere');
    });
  });
}
