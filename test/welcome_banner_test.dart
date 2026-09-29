// WelcomeBanner（#78: 初回の空状態の案内）のテスト。
//
// 表示条件（welcomeBannerDismissed）、閉じるボタンでの永続的な非表示、
// 「ほかの見え方を選ぶ」アクションでの dismiss を検証する。
// 「自分の画像で試す」アクション（pickAndLoadUserImage 経由）の decode 経路
// 自体は test/image_source_picker_test.dart が検証済みなので、ここでは
// ボタンの存在とタップ後に dismiss されることだけを確認する
// （pickImageBytes をキャンセル相当の null フェイクにして実デコードを避ける）。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/services/settings_service.dart';
import 'package:universal_experience/ui/widgets/image_source_picker.dart'
    show pickImageBytes;
import 'package:universal_experience/ui/widgets/welcome_banner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget localized(SettingsService settings) {
    return ChangeNotifierProvider<SettingsService>.value(
      value: settings,
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: WelcomeBanner()),
      ),
    );
  }

  tearDown(() {
    pickImageBytes = () async => null;
  });

  testWidgets('welcomeBannerDismissed が false ならバナーが表示される', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.load();
    final en = lookupAppLocalizations(const Locale('en'));

    await tester.pumpWidget(localized(settings));
    await tester.pump();

    expect(find.text(en.welcomeBannerTitle), findsOneWidget);
    expect(find.text(en.welcomeBannerBody), findsOneWidget);
    expect(find.text(en.welcomeBannerChooseOtherAction), findsOneWidget);
    expect(find.text(en.welcomeBannerTryPhotoAction), findsOneWidget);
  });

  testWidgets('welcomeBannerDismissed が true なら何も表示されない', (tester) async {
    SharedPreferences.setMockInitialValues({
      SettingsService.keyWelcomeBannerDismissed: true,
    });
    final settings = SettingsService();
    await settings.load();
    final en = lookupAppLocalizations(const Locale('en'));

    await tester.pumpWidget(localized(settings));
    await tester.pump();

    expect(find.text(en.welcomeBannerTitle), findsNothing);
  });

  testWidgets('閉じるボタンで dismissWelcomeBanner が呼ばれ、二度と表示されない',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.load();
    final en = lookupAppLocalizations(const Locale('en'));

    await tester.pumpWidget(localized(settings));
    await tester.pump();
    expect(find.text(en.welcomeBannerTitle), findsOneWidget);

    await tester.tap(find.byTooltip(en.welcomeBannerDismiss));
    await tester.pump();

    expect(settings.welcomeBannerDismissed, isTrue);
    expect(find.text(en.welcomeBannerTitle), findsNothing);

    // 別インスタンスで load しても復元されたままであること（永続化、#78）。
    final reloaded = SettingsService();
    await reloaded.load();
    expect(reloaded.welcomeBannerDismissed, isTrue);
  });

  testWidgets('「ほかの見え方を選ぶ」は dismiss するだけ', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.load();
    final en = lookupAppLocalizations(const Locale('en'));

    await tester.pumpWidget(localized(settings));
    await tester.pump();

    await tester.tap(find.text(en.welcomeBannerChooseOtherAction));
    await tester.pump();

    expect(settings.welcomeBannerDismissed, isTrue);
    expect(find.text(en.welcomeBannerTitle), findsNothing);
  });

  testWidgets('「自分の画像で試す」はピッカーを起動し、その後 dismiss する',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.load();
    final en = lookupAppLocalizations(const Locale('en'));
    var pickerCalled = false;
    pickImageBytes = () async {
      pickerCalled = true;
      return null; // キャンセル相当（実デコードを避ける）。
    };

    await tester.pumpWidget(localized(settings));
    await tester.pump();

    await tester.tap(find.text(en.welcomeBannerTryPhotoAction));
    await tester.pumpAndSettle();

    expect(pickerCalled, isTrue);
    expect(settings.welcomeBannerDismissed, isTrue);
    expect(find.text(en.welcomeBannerTitle), findsNothing);
  });
}
