import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/services/settings_service.dart';

/// SettingsService の永続化（shared_preferences）テスト。
///
/// SharedPreferences.setMockInitialValues でディスクをモックし、保存（set*）と
/// 復元（load）の往復が正しいことを検証する（#17）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsService 初期状態 / load', () {
    test('保存値が無いときは既定（system / none / 1.0）を保つ', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.load();

      expect(settings.themeMode, ThemeMode.system);
      expect(settings.filterType, ColorVisionType.none);
      expect(settings.intensity, 1.0);
    });

    test('保存済みの値を復元する', () async {
      SharedPreferences.setMockInitialValues({
        SettingsService.keyThemeMode: ThemeMode.dark.name,
        SettingsService.keyFilterType: ColorVisionType.protanopia.name,
        SettingsService.keyIntensity: 0.4,
      });
      final settings = SettingsService();
      await settings.load();

      expect(settings.themeMode, ThemeMode.dark);
      expect(settings.filterType, ColorVisionType.protanopia);
      expect(settings.intensity, 0.4);
    });

    test('未知の文字列は既定にフォールバックする', () async {
      SharedPreferences.setMockInitialValues({
        SettingsService.keyThemeMode: 'bogus',
        SettingsService.keyFilterType: 'not_a_filter',
      });
      final settings = SettingsService();
      await settings.load();

      expect(settings.themeMode, ThemeMode.system);
      expect(settings.filterType, ColorVisionType.none);
    });

    test('範囲外の intensity は 0..1 に clamp して復元する', () async {
      SharedPreferences.setMockInitialValues({
        SettingsService.keyIntensity: 5.0,
      });
      final settings = SettingsService();
      await settings.load();
      expect(settings.intensity, 1.0);
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

    test('setFilterType / setIntensity が往復する', () async {
      SharedPreferences.setMockInitialValues({});
      final a = SettingsService();
      await a.load();

      await a.setFilterType(ColorVisionType.deuteranomaly);
      await a.setIntensity(0.25);

      final b = SettingsService();
      await b.load();
      expect(b.filterType, ColorVisionType.deuteranomaly);
      expect(b.intensity, 0.25);
    });

    test('同じ値の再設定では notify しない', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.load();
      var notified = 0;
      settings.addListener(() => notified++);

      await settings.setThemeMode(ThemeMode.system); // 既定と同じ
      await settings.setIntensity(1.0); // 既定と同じ
      await settings.setFilterType(ColorVisionType.none); // 既定と同じ
      expect(notified, 0);
    });

    test('setIntensity は clamp してから保存する', () async {
      SharedPreferences.setMockInitialValues({});
      final a = SettingsService();
      await a.load();
      await a.setIntensity(-3.0);
      expect(a.intensity, 0.0);

      final b = SettingsService();
      await b.load();
      expect(b.intensity, 0.0);
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

    test('全 ColorVisionType が name 経由で往復する', () async {
      for (final type in ColorVisionType.values) {
        SharedPreferences.setMockInitialValues({});
        final a = SettingsService();
        await a.load();
        await a.setFilterType(type);
        final b = SettingsService();
        await b.load();
        expect(b.filterType, type, reason: '$type');
      }
    });
  });
}
