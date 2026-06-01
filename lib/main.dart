import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io' show Platform;

import 'services/filter_service.dart';
import 'services/loupe_window_controller.dart';
import 'services/settings_service.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme/app_theme.dart';

/// ルーペ窓の挙動 (#14) を集約したコントローラ。
/// 最小サイズ・状態遷移(normal/maximized/fullscreen)・枠ポリシー・
/// 透過/最前面/クリックスルーの責務を持つ (詳細は docs/ARCHITECTURE.md)。
final LoupeWindowController loupeWindow = LoupeWindowController();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Restore persisted settings (theme mode / last filter / intensity) before
  // building the app so the first frame already reflects the user's choices
  // (#17, settings_service.dart).
  final settings = SettingsService();
  await settings.load();

  // Initialize window manager for desktop platforms
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();

    // ルーペ窓の起動オプション。サイズ・最小サイズ・透過の既定は
    // LoupeWindowPolicy に集約 (testable な純粋ロジック)。
    // - backgroundColor: 透過。枠の外は透け、枠の中だけフィルタ描画する
    //   (既定方針: 透明背景 ON / 最前面 ON / クリックスルーは切替式で初期 OFF)。
    // マルチモニタ: 第1弾はメインモニタのみ対象 (docs/ARCHITECTURE.md 参照)。
    // backgroundColor は透過が既定 (LoupeWindowPolicy.defaultTransparent)。
    // window_manager の backgroundColor は非 null の Color のため、
    // 透過 ON のとき transparent、OFF のとき不透明黒を渡す。
    //
    // TODO(#14/#16): 起動既定を「設定モード (通常ウィンドウ・透明/最前面 OFF)」に
    // するモード切替を将来導入する。今は起動から透明・最前面を常時適用しているため、
    // フィルタ選択 UI (#16) 操作時に最前面・透明で操作しづらい。設定モードと
    // ルーペモードの切替は #14 スコープ外なので、本 PR では起動既定 (透明・最前面 ON)
    // を現状維持する。詳細は loupe_window_controller.dart の TODO と
    // docs/ARCHITECTURE.md「フォロー事項: アプリモード切替」を参照。
    const windowOptions = WindowOptions(
      size: LoupeWindowPolicy.defaultSize,
      minimumSize: LoupeWindowPolicy.minimumSize,
      center: true,
      backgroundColor: LoupeWindowPolicy.defaultTransparent
          ? Colors.transparent
          : Colors.black,
      skipTaskbar: false,
      title: 'Universal Experience',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      // 最小サイズ・最前面・枠ポリシーを適用 (#14)。
      await loupeWindow.initialize();
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(UniversalExperienceApp(settings: settings));
}

class UniversalExperienceApp extends StatelessWidget {
  const UniversalExperienceApp({super.key, required this.settings});

  /// Pre-loaded settings service (theme mode / last filter / intensity).
  final SettingsService settings;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // SettingsService is created+loaded in main() so the first frame uses
        // restored values; provide the existing instance (not a fresh one).
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        // FilterService is seeded from the restored settings so the previously
        // selected filter + intensity are reflected on startup.
        ChangeNotifierProvider<FilterService>(
          create: (_) => FilterService()
            ..applyFilter(settings.filterType, intensity: settings.intensity),
        ),
      ],
      // Rebuild MaterialApp when the persisted theme mode changes.
      child: Consumer<SettingsService>(
        builder: (context, settings, _) {
          return MaterialApp(
            title: 'Universal Experience',
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: settings.themeMode,
            home: const HomeScreen(),
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}
