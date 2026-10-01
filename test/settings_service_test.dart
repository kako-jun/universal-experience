import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/services/settings_service.dart';
import 'package:universal_experience/services/vision_filter_store.dart';

/// SettingsService の永続化（shared_preferences）テスト。
///
/// SharedPreferences.setMockInitialValues でディスクをモックし、保存（set*）と
/// 復元（load）の往復が正しいことを検証する（#17）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsService 初期状態 / load', () {
    test('保存値が無いときは既定（system / 言語は端末追従 / バナー未消去）を保つ', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.load();

      expect(settings.themeMode, ThemeMode.system);
      expect(settings.locale, isNull);
      expect(settings.welcomeBannerDismissed, isFalse);
    });

    test('保存済みの値を復元する', () async {
      SharedPreferences.setMockInitialValues({
        SettingsService.keyThemeMode: ThemeMode.dark.name,
        SettingsService.keyLocale: 'ja',
        SettingsService.keyWelcomeBannerDismissed: true,
      });
      final settings = SettingsService();
      await settings.load();

      expect(settings.themeMode, ThemeMode.dark);
      expect(settings.locale, const Locale('ja'));
      expect(settings.welcomeBannerDismissed, isTrue);
    });

    test('未知の文字列・未対応の言語コードは既定にフォールバックする', () async {
      SharedPreferences.setMockInitialValues({
        SettingsService.keyThemeMode: 'bogus',
        SettingsService.keyLocale: 'xx',
      });
      final settings = SettingsService();
      await settings.load();

      expect(settings.themeMode, ThemeMode.system);
      expect(settings.locale, isNull);
    });

    test('旧 settings.filterType が残っていても SettingsService は読まず・消さない', () async {
      // 旧キーの取り込みと削除は VisionFilterStore.migrateLegacySettings の責務。
      SharedPreferences.setMockInitialValues({
        VisionFilterStore.keyLegacyFilterType: 'protanopia',
      });
      final settings = SettingsService();
      await settings.load();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(VisionFilterStore.keyLegacyFilterType), 'protanopia');
    });
  });

  group('SettingsService 保存 + 永続化往復', () {
    test('setThemeMode は notify し別インスタンスの load で復元される', () async {
      SharedPreferences.setMockInitialValues({});
      final a = SettingsService();
      await a.load();
      var notified = 0;
      a.addListener(() => notified++);

      await a.setThemeMode(ThemeMode.light);
      expect(a.themeMode, ThemeMode.light);
      expect(notified, 1);

      // 同じモック store を読む新インスタンスで永続化を確認。
      final b = SettingsService();
      await b.load();
      expect(b.themeMode, ThemeMode.light);
    });

    test('setLocale は notify し別インスタンスの load で復元され、null で消える', () async {
      SharedPreferences.setMockInitialValues({});
      final a = SettingsService();
      await a.load();
      var notified = 0;
      a.addListener(() => notified++);

      await a.setLocale(const Locale('ja'));
      expect(a.locale, const Locale('ja'));
      expect(notified, 1);

      final b = SettingsService();
      await b.load();
      expect(b.locale, const Locale('ja'));

      await a.setLocale(null);
      final c = SettingsService();
      await c.load();
      expect(c.locale, isNull, reason: 'null は保存値を消して端末追従に戻す');
    });

    test('同じ値の再設定では notify しない', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.load();
      var notified = 0;
      settings.addListener(() => notified++);

      await settings.setThemeMode(ThemeMode.system); // 既定と同じ
      await settings.setLocale(null); // 既定と同じ
      expect(notified, 0);
    });

    test('全 ThemeMode が name 経由で往復する', () async {
      for (final mode in ThemeMode.values) {
        SharedPreferences.setMockInitialValues({});
        final a = SettingsService();
        await a.load();
        await a.setThemeMode(mode);
        final b = SettingsService();
        await b.load();
        expect(b.themeMode, mode, reason: '$mode');
      }
    });
  });

  group('welcomeBannerDismissed / dismissWelcomeBanner (#78)', () {
    test('既定は false', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.load();
      expect(settings.welcomeBannerDismissed, isFalse);
    });

    test('dismissWelcomeBanner は notify し、別インスタンスの load で永続化が復元される',
        () async {
      SharedPreferences.setMockInitialValues({});
      final a = SettingsService();
      await a.load();
      var notified = 0;
      a.addListener(() => notified++);

      await a.dismissWelcomeBanner();
      expect(a.welcomeBannerDismissed, isTrue);
      expect(notified, 1);

      final b = SettingsService();
      await b.load();
      expect(b.welcomeBannerDismissed, isTrue);
    });

    test('既に dismissed なら再度呼んでも notify も書き込みもしない', () async {
      SharedPreferences.setMockInitialValues({
        SettingsService.keyWelcomeBannerDismissed: true,
      });
      final settings = SettingsService();
      await settings.load();
      var notified = 0;
      settings.addListener(() => notified++);

      await settings.dismissWelcomeBanner();
      expect(notified, 0, reason: '既に true なので no-op であるべき');
    });
  });
}
