// WindowModePanel（#63）の widget test。
//
// 受け入れ条件「トレイもホットキーもない場合は、クリックスルーを ON にできない
// こと」を、`UniversalExperienceApp` の既定コンストラクタ（trayAvailable: false,
// hotkeyStatus: 空、= もっとも安全側の既定）で検証する。

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

  testWidgets(
      'トレイもホットキーも無い既定状態ではクリックスルーを ON にできない (#63)',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final settings = await preparedSettings();

    // 引数省略 = 既定コンストラクタ（trayAvailable: false, hotkeyStatus: 空）。
    await tester.pumpWidget(UniversalExperienceApp(settings: settings));
    await tester.pump();

    final clickThroughTile = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Click-through'),
    );
    expect(clickThroughTile.value, isFalse);
    expect(clickThroughTile.onChanged, isNull,
        reason: '復帰手段（トレイ/ホットキー）が無いので ON にする操作自体を塞ぐべき');

    // タップしても実際に状態が変わらないことも確認する（保険）。
    await tester.tap(find.widgetWithText(SwitchListTile, 'Click-through'));
    await tester.pump();
    expect(loupeWindow.clickThrough, isFalse);

    expect(find.text('Click-through is disabled because neither the tray '
        'nor a hotkey is available to undo it'), findsOneWidget);
  });

  testWidgets('トレイが使える環境ではクリックスルーを ON にできる (#63)',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final settings = await preparedSettings();
    // クリックスルーは settings モード中は ON にできない
    // (setClickThrough 自身のガード、#63)。スイッチ自体も settings モードでは
    // 無効化されるため、このテストの前提（トレイがあれば ON にできる）を
    // 成立させるには loupe モードへ切り替えておく必要がある。
    //
    // tester.runAsync 経由で呼ぶ必要がある: testWidgets は FakeAsync ゾーンで
    // 動くため、window_manager のプラットフォームチャンネル呼び出し
    // （未登録ハンドラで最終的に MissingPluginException になる）の解決が
    // 実イベントループを必要とし、pump() 無しに直接 await すると
    // テストがハングする（setAppMode 自体は本番では問題ない — この待避は
    // テスト環境固有）。
    await tester.runAsync(() => loupeWindow.setAppMode(AppMode.loupe));

    await tester.pumpWidget(UniversalExperienceApp(
      settings: settings,
      trayAvailable: true,
      hotkeyStatus: const HotkeyStatus(),
    ));
    await tester.pump();

    final clickThroughTile = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Click-through'),
    );
    expect(clickThroughTile.onChanged, isNotNull);
  });

  testWidgets(
      'toggleClickThrough が失敗し emergencyExit だけ登録された環境では '
      'ヒントに emergencyExit のキーを表示する (#63)',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final settings = await preparedSettings();

    // トレイは無し。toggleClickThrough は登録失敗、emergencyExit だけ登録成功
    // = canEnableClickThrough は true（emergencyExit 経由）だが、ヒントが
    // 決め打ちの toggleClickThrough キーを案内してしまうと実際には戻れない。
    await tester.pumpWidget(UniversalExperienceApp(
      settings: settings,
      trayAvailable: false,
      hotkeyStatus: const HotkeyStatus(
        registered: {AppHotkeyAction.emergencyExit},
        failed: {AppHotkeyAction.toggleClickThrough},
      ),
    ));
    await tester.pump();

    expect(
      find.text(
        'Use this hotkey to get back: '
        '${describeHotkey(AppHotkeyAction.emergencyExit)}',
      ),
      findsOneWidget,
      reason: '実際に登録されている emergencyExit のキーを案内すべき',
    );
    // 下部のホットキー一覧セクションには全アクションの既定キーが登録状況に
    // 関わらず並ぶため、ヒント文言そのもの（登録失敗の toggleClickThrough の
    // キーを案内していないこと）をピンポイントで確認する。
    expect(
      find.text(
        'Use this hotkey to get back: '
        '${describeHotkey(AppHotkeyAction.toggleClickThrough)}',
      ),
      findsNothing,
      reason: '登録に失敗した toggleClickThrough のキーをヒントに案内してはいけない',
    );
  });
}
