// トレイの文言が画面の言語へ追従する配線（TrayLocaleSync、#82）の検証。
//
// トレイは BuildContext を持てず MaterialApp.locale の変更を受け取れない。
// 言語ピッカー（SettingsService.setLocale）と OS のロケール変更の両方で、
// 解決後の言語が変わったときだけ 1 回 apply が呼ばれることを確認する。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/l10n/l10n_extensions.dart';
import 'package:universal_experience/l10n/locale_resolution.dart';
import 'package:universal_experience/services/settings_service.dart';
import 'package:universal_experience/services/tray_locale_sync.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsService settings;
  late List<Locale> applied;
  late TrayLocaleSync sync;

  Future<void> start(WidgetTester tester,
      {Locale system = const Locale('en')}) async {
    tester.platformDispatcher.localeTestValue = system;
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    settings = SettingsService();
    await settings.load();
    applied = [];
    sync = TrayLocaleSync(
      settings: settings,
      initial: resolveSupportedLocale(settings.locale),
      apply: (locale) async => applied.add(locale),
    )..start();
    addTearDown(sync.dispose);
  }

  group('resolveSupportedLocale', () {
    testWidgets('設定があればそれ、無ければシステム、非対応なら先頭（en）', (tester) async {
      tester.platformDispatcher.localeTestValue = const Locale('ja', 'JP');
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      expect(resolveSupportedLocale(null), const Locale('ja'));
      expect(resolveSupportedLocale(const Locale('en')), const Locale('en'));

      tester.platformDispatcher.localeTestValue = const Locale('fr');
      expect(resolveSupportedLocale(null),
          AppLocalizations.supportedLocales.first);
      // 保存値が非対応言語なら（古い設定など）システム追従と同じ扱い。
      expect(resolveSupportedLocale(const Locale('de')),
          AppLocalizations.supportedLocales.first);
    });
  });

  group('TrayLocaleSync', () {
    testWidgets('言語ピッカーで明示選択すると、その言語で 1 回だけ apply される', (tester) async {
      await start(tester); // システム = en
      expect(applied, isEmpty, reason: '起動直後は解決結果が変わっていない');

      await settings.setLocale(const Locale('ja'));
      expect(applied, [const Locale('ja')]);

      await settings.setLocale(const Locale('en'));
      expect(applied, [const Locale('ja'), const Locale('en')]);
    });

    testWidgets('テーマなど言語と無関係な設定変更ではトレイを作り直さない', (tester) async {
      await start(tester);
      await settings.setLocale(const Locale('ja'));
      applied.clear();

      await settings.setThemeMode(ThemeMode.dark);
      await settings.dismissWelcomeBanner();

      expect(applied, isEmpty);
    });

    testWidgets('「システムに合わせる」(null) に戻すと、OS の言語で apply される', (tester) async {
      await start(tester, system: const Locale('en'));
      await settings.setLocale(const Locale('ja'));
      applied.clear();

      await settings.setLocale(null);

      expect(applied, [const Locale('en')]);
    });

    testWidgets('明示選択と解決結果が同じなら apply しない', (tester) async {
      await start(tester, system: const Locale('ja'));
      // システムが ja なので、null → ja の明示選択は画面の言語が変わらない。
      await settings.setLocale(const Locale('ja'));

      expect(applied, isEmpty);
    });

    testWidgets('システム追従のとき、OS のロケール変更で apply される', (tester) async {
      await start(tester, system: const Locale('en'));

      tester.platformDispatcher.localeTestValue = const Locale('ja');
      await tester.pump();

      expect(applied, [const Locale('ja')]);
    });

    testWidgets('明示選択中は、OS のロケール変更で apply されない', (tester) async {
      await start(tester, system: const Locale('en'));
      await settings.setLocale(const Locale('en'));
      applied.clear();

      tester.platformDispatcher.localeTestValue = const Locale('ja');
      await tester.pump();

      expect(applied, isEmpty);
    });

    testWidgets('dispose 後は設定が変わっても apply しない', (tester) async {
      await start(tester);
      sync.dispose();

      await settings.setLocale(const Locale('ja'));

      expect(applied, isEmpty);
    });

    testWidgets('apply された言語から作るトレイ文言は、その言語の ARB 文言になる', (tester) async {
      await start(tester);
      await settings.setLocale(const Locale('ja'));

      final l10n = lookupAppLocalizations(applied.single);
      final labels = trayMenuLabelsFrom(l10n);
      expect(labels.quit, '終了');
      expect(l10n.trayTooltip, isNotEmpty);
      expect(labels.quit,
          isNot(lookupAppLocalizations(const Locale('en')).trayQuit));
    });
  });
}
