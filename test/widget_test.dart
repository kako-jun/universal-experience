// アプリ本体ウィジェット（UniversalExperienceApp）の軽量スモークテスト。
//
// 旧 placeholder は Flutter の counter テンプレートのまま残っており、存在しない
// `MyApp` を参照して `flutter analyze` をエラーにしていた（#30）。
//
// 本アプリの `main()` は async で `windowManager.ensureInitialized()` /
// `TrayService.init()` 等のデスクトップ初期化を行うため、`main()` 自体を
// testWidgets で踏むのは重く headless では不安定。一方、画面を構築する本体
// ウィジェット `UniversalExperienceApp` はデスクトップ初期化に依存せず、
// `SettingsService` だけを引数に取る（windowManager/トレイ配線は main() 側に
// 閉じている）。よってここでは本体ウィジェットだけを pump してスモークする。
//
// SharedPreferences はモックし、ディスク I/O やプラットフォームチャネルを踏まない。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/main.dart';
import 'package:universal_experience/services/settings_service.dart';
import 'package:universal_experience/ui/screens/home_screen.dart';

void main() {
  testWidgets('UniversalExperienceApp が例外なく起動し HomeScreen を表示する',
      (WidgetTester tester) async {
    // 永続化レイヤをモックして実ディスクを触らない（main() の settings.load()
    // 相当を、デスクトップ初期化なしで再現する）。
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = SettingsService();
    await settings.load();

    // main() は windowManager/トレイ初期化のあとに runApp(UniversalExperienceApp)
    // を呼ぶ。本テストはその UI 部分（本体ウィジェット）だけを構築する。
    await tester.pumpWidget(UniversalExperienceApp(settings: settings));

    // アニメーション完走を待つと無限再描画で固まりうるため pumpAndSettle は使わず、
    // 初回フレームが描けたこと（= 起動が例外なく成立したこと）だけを確認する。
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
