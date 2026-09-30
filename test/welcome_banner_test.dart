// WelcomeBanner（#78: 初回の空状態の案内）のテスト。
//
// 表示条件（welcomeBannerDismissed）、閉じるボタンでの永続的な非表示、
// 「ほかの見え方を選ぶ」アクションでの dismiss + フォーカス移動（#78 レビュー
// S8）を検証する。「自分の画像で試す」アクション（pickAndLoadUserImage 経由）
// の decode 経路自体は test/image_source_picker_test.dart が検証済みなので、
// ここではピッカーの結果（成功/キャンセル）に応じて dismiss するかどうかの
// 分岐（#78 レビュー Q3）だけを確認する（pickImageFile をフェイクに差し替え、
// 実デコードは避ける）。

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/services/image_source_state.dart';
import 'package:universal_experience/services/settings_service.dart';
import 'package:universal_experience/ui/widgets/image_source_picker.dart'
    show pickImageFile;
import 'package:universal_experience/ui/widgets/welcome_banner.dart';

import 'support/sample_image_generator.dart';

Future<Uint8List> _validPngBytes() async {
  final image = await generateSampleImage(8);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget localized(SettingsService settings) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        // pickAndLoadUserImage の成功経路（loadUserImageFile）が
        // ImageSourceState.setUserImage を呼ぶため要る。
        ChangeNotifierProvider<ImageSourceState>(
          create: (_) => ImageSourceState(),
        ),
      ],
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
    pickImageFile = () async => null;
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

  testWidgets(
      '「ほかの見え方を選ぶ」は onChooseOtherView を呼んでから dismiss する'
      '（#78 レビュー S8）。実際に検索欄へフォーカスを移す側の契約は '
      'test/filter_browser_test.dart（FilterBrowserController.focusSearch）と '
      'test/home_screen_layout_test.dart のバナー経由の確認が担う（#78 レビュー nit、#72）',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.load();
    final en = lookupAppLocalizations(const Locale('en'));
    var chooseOtherCalled = false;

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsService>.value(
        value: settings,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: WelcomeBanner(
              onChooseOtherView: () => chooseOtherCalled = true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(chooseOtherCalled, isFalse);

    await tester.tap(find.text(en.welcomeBannerChooseOtherAction));
    await tester.pump();

    expect(chooseOtherCalled, isTrue);
    expect(settings.welcomeBannerDismissed, isTrue);
    expect(find.text(en.welcomeBannerTitle), findsNothing);
  });

  testWidgets(
      '「自分の画像で試す」はピッカーがキャンセルされたら dismiss しない'
      '（#78 レビュー Q3）', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.load();
    final en = lookupAppLocalizations(const Locale('en'));
    var pickerCalled = false;
    pickImageFile = () async {
      pickerCalled = true;
      return null; // キャンセル相当。
    };

    await tester.pumpWidget(localized(settings));
    await tester.pump();

    await tester.tap(find.text(en.welcomeBannerTryPhotoAction));
    await tester.pumpAndSettle();

    expect(pickerCalled, isTrue);
    expect(settings.welcomeBannerDismissed, isFalse,
        reason: 'キャンセルではバナーを閉じない（#78 レビュー Q3）');
    expect(find.text(en.welcomeBannerTitle), findsOneWidget);
  });

  testWidgets('「自分の画像で試す」は読み込みに成功したら dismiss する',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.load();
    final en = lookupAppLocalizations(const Locale('en'));

    // decodeUserImageBytes が成功する必要があるので、実デコード可能な PNG
    // バイト列を事前に（runAsync の中で）用意しておく。
    late Uint8List bytes;
    await tester.runAsync(() async {
      bytes = await _validPngBytes();
    });
    pickImageFile = () async =>
        XFile.fromData(bytes, name: 'photo.png', length: bytes.length);

    await tester.pumpWidget(localized(settings));
    await tester.pump();

    await tester.tap(find.text(en.welcomeBannerTryPhotoAction));
    // タップ〜pickAndLoadUserImage〜decodeUserImageBytes は実エンジンの
    // 非同期処理を挟むため、待機ループごと runAsync の中で行う
    // （test/image_source_picker_test.dart の drop テストと同じ理由）。
    await tester.runAsync(() async {
      for (var i = 0; i < 50; i++) {
        if (settings.welcomeBannerDismissed) return;
        await tester.pump(const Duration(milliseconds: 20));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();

    expect(settings.welcomeBannerDismissed, isTrue);
    expect(find.text(en.welcomeBannerTitle), findsNothing);
  });
}
