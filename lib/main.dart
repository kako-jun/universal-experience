import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io' show Platform;

import 'services/filter_service.dart';
import 'services/loupe_window_controller.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme/app_theme.dart';

/// ルーペ窓の挙動 (#14) を集約したコントローラ。
/// 最小サイズ・状態遷移(normal/maximized/fullscreen)・枠ポリシー・
/// 透過/最前面/クリックスルーの責務を持つ (詳細は docs/ARCHITECTURE.md)。
final LoupeWindowController loupeWindow = LoupeWindowController();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
    final windowOptions = WindowOptions(
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

  runApp(const UniversalExperienceApp());
}

class UniversalExperienceApp extends StatelessWidget {
  const UniversalExperienceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => FilterService()),
      ],
      child: MaterialApp(
        title: 'Universal Experience',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: const HomeScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
