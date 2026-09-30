// アプリ内の言語ピッカー（#82）の検証。
//
// AppBar の言語ボタン → ダイアログ → SegmentedButton の操作を実 UI で踏み、
// 画面の文言・sensus 由来のフィルタ名と説明・永続化・「自動」への
// 復帰が言語に追従することを確認する。トレイの追従は tray_locale_sync_test.dart /
// tray_service_test.dart が担う。

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show LocaleStringAttribute;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/l10n/l10n_extensions.dart';
import 'package:universal_experience/main.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/services/color_vision_selection.dart';
import 'package:universal_experience/services/settings_service.dart';
import 'package:universal_experience/services/tray_locale_sync.dart';
import 'package:universal_experience/ui/widgets/adjust_panel.dart';
import 'package:universal_experience/ui/widgets/language_dialog.dart';

import 'support/home_screen_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final en = lookupAppLocalizations(const Locale('en'));
  final ja = lookupAppLocalizations(const Locale('ja'));

  setUp(() {
    installHomeScreenFixtures();
    // main.dart のトップレベル共有状態を、テスト間で持ち越さない。
    deactivateColorVision(filterService, visionFilterState);
  });
  tearDown(() {
    resetHomeScreenFixtures();
    deactivateColorVision(filterService, visionFilterState);
  });

  Future<SettingsService> pumpApp(
    WidgetTester tester, {
    Locale? persisted,
    String? storedCode,
    List<Locale> system = const [Locale('en')],
  }) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // OS の優先言語リスト。複数言語を与えられるよう `locales` を正とし、
    // 単数の `locale` は先頭に揃える。
    // 一覧が空のときは単数の値に意味を持たせない（解決は一覧だけを見る）。
    tester.platformDispatcher.localeTestValue =
        system.isEmpty ? const Locale('xx') : system.first;
    tester.platformDispatcher.localesTestValue = system;
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);

    // storedCode: 設定ファイルに直接残っている言語コード（未対応コードの再現用）。
    SharedPreferences.setMockInitialValues(<String, Object>{
      if (storedCode != null) SettingsService.keyLocale: storedCode,
    });
    final settings = SettingsService();
    await settings.load();
    if (persisted != null) await settings.setLocale(persisted);

    await tester.pumpWidget(UniversalExperienceApp(settings: settings));
    await tester.pump();
    return settings;
  }

  Future<void> openDialog(WidgetTester tester, AppLocalizations l10n) async {
    await tester.tap(find.byTooltip(l10n.languageSectionTitle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(LanguageDialog), findsOneWidget);
  }

  Future<void> choose(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(
      of: find.byType(SegmentedButton<String>),
      matching: find.text(label),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Finder inAdjustPanel(String text) =>
      find.descendant(of: find.byType(AdjustPanel), matching: find.text(text));

  group('言語ダイアログの選択値', () {
    test('サポート対象の全言語に、その言語自身の表記がある（言語を足したら必須）', () {
      for (final locale in AppLocalizations.supportedLocales) {
        expect(kLanguageEndonyms[locale.languageCode], isNotEmpty,
            reason: '${locale.languageCode} の自称が kLanguageEndonyms に無い');
      }
    });

    test('永続化された locale から選択値へ。null とサポート外は「自動」', () {
      expect(selectedLanguageChoice(null), kLanguageFollowSystem);
      expect(selectedLanguageChoice(const Locale('ja')), 'ja');
      expect(selectedLanguageChoice(const Locale('en', 'US')), 'en');
      expect(selectedLanguageChoice(const Locale('fr')), kLanguageFollowSystem);
    });

    test('選択値から setLocale に渡す値へ', () {
      expect(localeForLanguageChoice(kLanguageFollowSystem), isNull);
      expect(localeForLanguageChoice('ja'), const Locale('ja'));
      expect(localeForLanguageChoice('en'), const Locale('en'));
    });
  });

  group('AppBar の言語ピッカー', () {
    testWidgets('English を選ぶと画面・フィルタ名・説明が英語になり、永続化される', (tester) async {
      final settings = await pumpApp(tester, persisted: const Locale('ja'));
      selectColorVision(
        filterService,
        visionFilterState,
        ColorVisionType.protanopia,
      );
      await tester.pump();

      // ja: 右カラムの名前（sensus のカタログ id → ARB）と説明が日本語。
      expect(find.text(ja.appTitle), findsWidgets);
      expect(inAdjustPanel(ja.filterProtanopia), findsOneWidget);
      expect(inAdjustPanel(ja.filterProtanopiaDesc), findsOneWidget);
      expect(inAdjustPanel(en.filterProtanopia), findsNothing);

      await openDialog(tester, ja);
      // 選択中の言語がひと目で分かる（日本語が選択済み）。
      final selectedBefore = tester
          .widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>))
          .selected;
      expect(selectedBefore, {'ja'});

      await choose(tester, 'English');

      expect(settings.locale, const Locale('en'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(SettingsService.keyLocale), 'en');
      // 再起動相当（別インスタンスの load）でも英語のまま。
      final restored = SettingsService();
      await restored.load();
      expect(restored.locale, const Locale('en'));

      expect(inAdjustPanel(en.filterProtanopia), findsOneWidget);
      expect(inAdjustPanel(en.filterProtanopiaDesc), findsOneWidget);
      expect(inAdjustPanel(ja.filterProtanopia), findsNothing);
      // 開いたままのダイアログ自身も新しい言語に変わる。
      expect(find.text(en.languageDialogNote), findsOneWidget);
      expect(find.text(ja.languageDialogNote), findsNothing);
      expect(
        tester
            .widget<SegmentedButton<String>>(
                find.byType(SegmentedButton<String>))
            .selected,
        {'en'},
      );
    });

    testWidgets('advanced フィルタと体験プリセットの名前も言語に追従する', (tester) async {
      await pumpApp(tester, persisted: const Locale('en'));

      visionFilterState.select('tunnel_vision');
      await tester.pump();
      expect(
          inAdjustPanel(visionFilterName(en, 'tunnel_vision')), findsOneWidget);

      await openDialog(tester, en);
      await choose(tester, '日本語');
      expect(
          inAdjustPanel(visionFilterName(ja, 'tunnel_vision')), findsOneWidget);
      expect(
          inAdjustPanel(visionFilterName(en, 'tunnel_vision')), findsNothing);

      visionFilterState.selectPreset('meniere', 'vertigo');
      await tester.pump();
      expect(inAdjustPanel(experienceName(ja, 'meniere')), findsOneWidget);
      expect(
          inAdjustPanel(experienceDescription(ja, 'meniere')), findsOneWidget);

      await choose(tester, 'English');
      expect(inAdjustPanel(experienceName(en, 'meniere')), findsOneWidget);
      expect(
          inAdjustPanel(experienceDescription(en, 'meniere')), findsOneWidget);
    });

    testWidgets('「自動」に戻すと OS の言語に従い、保存値が消える', (tester) async {
      final settings = await pumpApp(
        tester,
        persisted: const Locale('en'),
        system: const [Locale('ja')],
      );
      selectColorVision(
        filterService,
        visionFilterState,
        ColorVisionType.deuteranopia,
      );
      await tester.pump();
      expect(inAdjustPanel(en.filterDeuteranopia), findsOneWidget);

      await openDialog(tester, en);
      await choose(tester, en.languageOptionSystem);

      expect(settings.locale, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(SettingsService.keyLocale), isFalse);
      // 端末（テスト上の OS）は ja なので日本語になる。
      expect(inAdjustPanel(ja.filterDeuteranopia), findsOneWidget);
      expect(find.text(ja.languageDialogNote), findsOneWidget);
      expect(
        tester
            .widget<SegmentedButton<String>>(
                find.byType(SegmentedButton<String>))
            .selected,
        {kLanguageFollowSystem},
      );
    });

    testWidgets('言語ボタンは 48dp 以上の操作領域とツールチップを持つ', (tester) async {
      await pumpApp(tester, persisted: const Locale('en'));
      final button = find.ancestor(
        of: find.byIcon(Icons.language),
        matching: find.byType(IconButton),
      );
      expect(button, findsOneWidget);
      expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      expect(find.byTooltip(en.languageSectionTitle), findsOneWidget);
    });
  });

  group('画面とトレイの言語が一致する', () {
    // 実アプリの Localizations が解決した言語と、TrayLocaleSync が apply する言語を比べる。
    Future<({Locale screen, Locale tray})> screenAndTray(
      WidgetTester tester,
      SettingsService settings,
    ) async {
      final applied = <Locale>[];
      // 起動直後の start() で必ず 1 回 apply させるため、解決結果にならない値から始める。
      final sync = TrayLocaleSync(
        settings: settings,
        initial: const Locale('xx'),
        apply: (locale) async => applied.add(locale),
      )..start();
      addTearDown(sync.dispose);
      final screen =
          Localizations.localeOf(tester.element(find.byType(AdjustPanel)));
      return (screen: screen, tray: applied.last);
    }

    testWidgets('OS の優先言語が [fr, ja]（自動）: 画面もトレイも ja', (tester) async {
      final settings = await pumpApp(
        tester,
        system: const [Locale('fr', 'FR'), Locale('ja', 'JP')],
      );
      final r = await screenAndTray(tester, settings);
      expect(r.screen, const Locale('ja'));
      expect(r.tray, r.screen);
      expect(find.byTooltip(ja.languageSectionTitle), findsOneWidget);
    });

    testWidgets('未対応の言語コード fr が保存されていて OS が ja: 画面もトレイも ja、ダイアログは「自動」',
        (tester) async {
      final settings = await pumpApp(
        tester,
        storedCode: 'fr',
        system: const [Locale('ja', 'JP')],
      );
      expect(settings.locale, isNull, reason: '未対応の保存値は読み込み時に捨てる');
      final r = await screenAndTray(tester, settings);
      expect(r.screen, const Locale('ja'));
      expect(r.tray, r.screen);

      await openDialog(tester, ja);
      expect(
        tester
            .widget<SegmentedButton<String>>(
                find.byType(SegmentedButton<String>))
            .selected,
        {kLanguageFollowSystem},
      );
    });

    testWidgets('OS の言語リストが空（自動）: 画面もトレイも en', (tester) async {
      final settings = await pumpApp(tester, system: const []);
      final r = await screenAndTray(tester, settings);
      expect(r.screen, const Locale('en'));
      expect(r.tray, r.screen);
    });

    testWidgets('未対応の保存値 fr + OS が [fr, ja]: 画面もトレイも ja', (tester) async {
      final settings = await pumpApp(
        tester,
        storedCode: 'fr',
        system: const [Locale('fr'), Locale('ja')],
      );
      final r = await screenAndTray(tester, settings);
      expect(r.screen, const Locale('ja'));
      expect(r.tray, const Locale('ja'));
    });
  });

  group('言語名の読み上げ', () {
    testWidgets('「自動」は、端末の言語に従うことが分かる名前で読み上げられる', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, persisted: const Locale('ja'));
      await openDialog(tester, ja);
      expect(
        find.descendant(
          of: find.byType(SegmentedButton<String>),
          matching: find.bySemanticsLabel('自動（端末の言語）'),
        ),
        findsOneWidget,
      );
      // 画面に見えるのは短い「自動」のまま。
      expect(find.text('自動'), findsOneWidget);

      await tester.tap(find.text('English'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.descendant(
          of: find.byType(SegmentedButton<String>),
          matching: find.bySemanticsLabel('Auto (device language)'),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('自称名は、その言語のラベルとして読み上げられる（LocaleStringAttribute）',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, persisted: const Locale('en'));
      await openDialog(tester, en);

      final node = tester.getSemantics(find
          .descendant(
            of: find.byType(SegmentedButton<String>),
            matching: find.bySemanticsLabel('日本語'),
          )
          .first);
      // マージ境界のボタンでは、子の Semantics は getSemanticsData() で統合される。
      final data = node.getSemanticsData();
      expect(data.label, '日本語');
      final attrs = data.attributedLabel.attributes;
      expect(
        attrs.whereType<LocaleStringAttribute>().map((a) => a.locale),
        contains(const Locale('ja')),
      );
      handle.dispose();
    });
  });
}
