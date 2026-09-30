// WindowModePanel（#63）の widget test。
//
// クリックスルーは常に ON にできる（復帰経路はフォーカス復帰＋最初のキー入力 +
// アプリ内 Esc が常時有効なベースライン）ことを受けて、クリックスルーのスイッチは
// settings モードでない限り常に有効であること、および復帰手段のヒントが常に
// 表示されることを検証する。

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/main.dart';
import 'package:universal_experience/services/hotkey_service.dart';
import 'package:universal_experience/services/loupe_window_controller.dart';
import 'package:universal_experience/services/settings_service.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/widgets/experience_presets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => experiencesProvider = () => const []);
  tearDown(() async {
    experiencesProvider = experiences;
    // トップレベル共有シングルトンをテスト間で汚染しない（#63）。
    await loupeWindow.setClickThrough(false);
    await loupeWindow.setAlwaysOnTop(false);
    await loupeWindow.setAppMode(AppMode.settings);
  });

  Future<SettingsService> preparedSettings() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = SettingsService();
    await settings.load();
    await settings.setLocale(const Locale('en'));
    return settings;
  }

  // 起動モードは主役より後ろ（AppBar のボタンから開くダイアログ、#72）。
  Future<Finder> openWindowModeDialog(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Startup Mode'));
    await tester.pumpAndSettle();
    return find.byType(AlertDialog);
  }

  testWidgets(
      'トレイもホットキーも無い既定状態でもクリックスルーを ON にでき、'
      'フォーカス復帰・Esc の復帰手段ヒントが常に表示される (#63)', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final settings = await preparedSettings();
    // クリックスルーは settings モード中は ON にできない
    // (setClickThrough 自身のガード、#63)。loupe モードへ切り替えておく。
    await tester.runAsync(() => loupeWindow.setAppMode(AppMode.loupe));

    // 引数省略 = 既定コンストラクタ（trayAvailable: false, hotkeyStatus: 空）。
    await tester.pumpWidget(UniversalExperienceApp(settings: settings));
    await tester.pump();
    final dialog = await openWindowModeDialog(tester);

    final clickThroughTile = tester.widget<SwitchListTile>(
      find.descendant(
        of: dialog,
        matching: find.widgetWithText(SwitchListTile, 'Click-through'),
      ),
    );
    expect(clickThroughTile.onChanged, isNotNull,
        reason: 'フォーカス復帰・Esc が常に使えるので、トレイ/ホットキーが無くても '
            'ON にする操作自体を塞ぐ必要は無い');

    expect(
      find.descendant(
          of: dialog,
          matching: find.text(
            'Select this window (e.g. with Alt+Tab) and press any key to turn '
            'it off',
          )),
      findsOneWidget,
      reason: 'フォーカス復帰＋最初のキー入力は常に使える復帰経路なので常時表示する',
    );
    expect(
      find.descendant(
          of: dialog,
          matching: find
              .text('You can also press Esc inside the app to turn it off')),
      findsOneWidget,
      reason: 'アプリ内 Esc は常に使える復帰経路なので常時表示する',
    );
    // トレイもホットキーも無いので、その 2 つのヒントは出ない。
    expect(
      find.descendant(
          of: dialog,
          matching: find.text('You can also turn it off from the tray menu')),
      findsNothing,
    );
  });

  testWidgets('settings モード中はクリックスルーのスイッチが無効化される (#63)',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final settings = await preparedSettings();

    await tester.pumpWidget(UniversalExperienceApp(settings: settings));
    await tester.pump();
    final dialog = await openWindowModeDialog(tester);

    final clickThroughTile = tester.widget<SwitchListTile>(
      find.descendant(
        of: dialog,
        matching: find.widgetWithText(SwitchListTile, 'Click-through'),
      ),
    );
    expect(clickThroughTile.value, isFalse);
    expect(clickThroughTile.onChanged, isNull,
        reason: '設定窓モードは UI 操作が前提のため、クリックスルーは ON にできない');
  });

  testWidgets('トレイが使える環境ではトレイの復帰手段ヒントも表示される (#63)',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final settings = await preparedSettings();
    await tester.runAsync(() => loupeWindow.setAppMode(AppMode.loupe));

    await tester.pumpWidget(UniversalExperienceApp(
      settings: settings,
      trayAvailable: true,
      hotkeyStatus: const HotkeyStatus(),
    ));
    await tester.pump();
    final dialog = await openWindowModeDialog(tester);

    expect(
      find.descendant(
          of: dialog,
          matching: find.text('You can also turn it off from the tray menu')),
      findsOneWidget,
    );
  });

  testWidgets(
      '登録されているホットキーの復帰手段ヒントが表示される（toggleClickThrough 優先） '
      '(#63)', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final settings = await preparedSettings();
    await tester.runAsync(() => loupeWindow.setAppMode(AppMode.loupe));

    await tester.pumpWidget(UniversalExperienceApp(
      settings: settings,
      trayAvailable: false,
      hotkeyStatus: const HotkeyStatus(
        registered: {AppHotkeyAction.emergencyExit},
        failed: {AppHotkeyAction.toggleClickThrough},
      ),
    ));
    await tester.pump();
    final dialog = await openWindowModeDialog(tester);

    final hotkeyText = describeHotkey(
      defaultHotkeyBindings()[AppHotkeyAction.emergencyExit]!,
      useMacSymbols: Platform.isMacOS,
    );
    expect(
      find.descendant(
          of: dialog,
          matching: find
              .text('You can also turn it off with the $hotkeyText hotkey')),
      findsOneWidget,
      reason: '実際に登録されている emergencyExit のキーを案内すべき',
    );

    final failedHotkeyText = describeHotkey(
      defaultHotkeyBindings()[AppHotkeyAction.toggleClickThrough]!,
      useMacSymbols: Platform.isMacOS,
    );
    expect(
      find.descendant(
          of: dialog,
          matching: find.text(
            'You can also turn it off with the $failedHotkeyText hotkey',
          )),
      findsNothing,
      reason: '登録に失敗した toggleClickThrough のキーをヒントに案内してはいけない',
    );
  });
}
