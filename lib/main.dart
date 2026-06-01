import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io' show Platform;

import 'services/filter_service.dart';
import 'services/loupe_window_controller.dart';
import 'services/tray_service.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme/app_theme.dart';

/// ルーペ窓の挙動 (#14) を集約したコントローラ。
/// 最小サイズ・状態遷移(normal/maximized/fullscreen)・枠ポリシー・
/// 透過/最前面/クリックスルーの責務を持つ (詳細は docs/ARCHITECTURE.md)。
final LoupeWindowController loupeWindow = LoupeWindowController();

/// トレイとウィンドウ UI で共有する FilterService。
/// トレイのクイックフィルタとウィンドウ内のドロップダウンが同じ状態を見るよう、
/// アプリ最上位で 1 つだけ生成する (#15)。
final FilterService filterService = FilterService();

/// トレイアイコンの Flutter アセットパス。`tray_manager` の `setIcon` が
/// `data/flutter_assets/` 配下のこのパスを解決する。Windows でより精細に
/// するなら `assets/tray/tray_icon.ico` を追加して分岐すればよい。
/// 詳細は docs/ARCHITECTURE.md「タスクトレイ (#15)」参照。
const String _trayIconPath = 'assets/tray/tray_icon.png';

/// タスクトレイ常駐 (#15)。トレイ非対応環境では init() が no-op になる。
///
/// ルーペ窓 (= メインウィンドウ) の表示/非表示は windowManager 経由。
/// `LoupeWindowController` (#14) は枠/モード/透過の責務で show/hide を持たないため、
/// ここで windowManager.show()/hide() を注入する。
final TrayService trayService = TrayService(
  filterService: filterService,
  iconPath: _trayIconPath,
  onShowLoupe: () async {
    await windowManager.show();
    await windowManager.focus();
  },
  onHideLoupe: () async {
    await windowManager.hide();
  },
  onOpenSettings: () async {
    // 設定 (フィルタ選択 UI) はメインウィンドウ内にあるため、ウィンドウを表示する。
    await windowManager.show();
    await windowManager.focus();
  },
  onQuit: () async {
    // トレイアイコンを破棄し、prevent-close を解除してから実際に終了する。
    await trayService.dispose();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    }
  },
);

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

    // タスクトレイ常駐 + クローズ・ポリシー (#15)。
    await _setUpTray();
  }

  runApp(const UniversalExperienceApp());
}

/// トレイを初期化し、ウィンドウのクローズ・ポリシーを適用する (#15)。
///
/// ## クローズ・ポリシー
/// メインウィンドウを閉じても**終了せず、トレイに最小化**する。これにより
/// アプリはバックグラウンドに残り、トレイメニューから復帰できる。明示的な
/// 終了はトレイの "終了" 項目のみ。
///
/// ただしトレイが立ち上がらなかった環境ではウィンドウが復帰不能になるため、
/// [resolveCloseAction] がフォールバックを表現する: トレイが無い場合は
/// クローズ = 終了。よって `setPreventClose` はトレイ初期化の成否で決める。
Future<void> _setUpTray() async {
  await trayService.init();

  final closeAction = resolveCloseAction(trayAvailable: trayService.isAvailable);
  if (closeAction == CloseAction.hideToTray) {
    await windowManager.setPreventClose(true);
    windowManager.addListener(
      _AppWindowListener(
        onClose: () async {
          // 終了ではなく非表示にする。トレイ側のトグルラベルが次回正しくなるよう
          // 表示状態を同期する。
          await windowManager.hide();
          await trayService.setLoupeVisible(false);
        },
      ),
    );
  }
}

/// window_manager のクローズイベントを close-to-tray ハンドラに橋渡しする。
class _AppWindowListener extends WindowListener {
  _AppWindowListener({required this.onClose});

  final Future<void> Function() onClose;

  @override
  void onWindowClose() {
    onClose();
  }
}

class UniversalExperienceApp extends StatelessWidget {
  const UniversalExperienceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // トレイと共有する単一の FilterService を供給する (#15)。
        ChangeNotifierProvider.value(value: filterService),
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
