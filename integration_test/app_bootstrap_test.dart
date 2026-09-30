// main() の実起動経路を踏む integration test (#55 レビュー M1)。
//
// integration_test/experience_presets_smoke_test.dart は自身の setUpAll で
// initNativeBridge() を呼んでから統合フィルタ一覧を自前の MaterialApp に
// 包んで pump しているだけで、main() の実際のブートストラップ（buildRootApp()）
// は一度も通らない。main() 内から initNativeBridge() の呼び出しが削除/誤配置
// されても、既存のテストは全部グリーンのままになりうる（#52 と同種の退行が
// 場所を変えて再発する）。
//
// このファイルは新しい別プロセスとして起動されるため RustLib は未初期化の
// 状態から始まる。同じファイル内で先に initNativeBridge() を呼んでしまう
// smoke test と合流させると「本当に未初期化から通しで検証できているか」が
// テスト順序に依存してしまうため、あえて別ファイルに分離している。
//
// 実行: `flutter test integration_test/app_bootstrap_test.dart -d macos`
// （CI では linux -d linux も）。experience_presets_smoke_test.dart と一緒に
// 1 回の `flutter test integration_test` へまとめて渡すと、デスクトップでは
// 2 番目に起動する側のアプリ起動待ちが失敗する既知の制約があるため、
// 別コマンドとして実行する（詳細は .github/workflows/ci.yml のコメント参照）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/main.dart';
import 'package:universal_experience/src/rust/frb_generated.dart';
import 'package:universal_experience/ui/screens/home_screen.dart';
import 'package:universal_experience/ui/widgets/experience_presets.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // SettingsService.load() が SharedPreferences を読むため、実ディスクを
    // 触らずモックする（main() の settings.load() 相当）。
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('main() 相当の buildRootApp() が実ブリッジを初期化し HomeScreen を描画する',
      (tester) async {
    // このプロセスではまだ何も RustLib.init() を呼んでいないはず（#55 の
    // 退行を検知する前提条件）。
    expect(RustLib.instance.initialized, isFalse);

    final result = await buildRootApp();
    expect(result.bridgeReady, isTrue);
    await tester.pumpWidget(result.app);
    await tester.pumpAndSettle();

    expect(RustLib.instance.initialized, isTrue);
    expect(find.byType(HomeScreen), findsOneWidget);

    // #72: 統合フィルタ一覧の最上段に、実ブリッジの experiences() 由来の体験
    // プリセット 4 行が出ていること（#52: 本番でプリセットが例外表示になった
    // 退行の検知）。一覧は遅延構築されない（SingleChildScrollView）ので、画面外でも
    // ツリー上に存在する。
    expect(find.byType(ExperiencePresetTile), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('initBridge が false を返す経路は NativeBridgeErrorApp になる',
      (tester) async {
    final result = await buildRootApp(initBridge: () async => false);
    expect(result.bridgeReady, isFalse);
    expect(result.app, isA<NativeBridgeErrorApp>());

    await tester.pumpWidget(result.app);
    await tester.pumpAndSettle();

    // NativeBridgeErrorApp はロケール未指定だとシステムロケール追従なので、
    // ここでは特定言語を決め打ちせず、サポート対象言語のどれかの文言が
    // 出ていることだけを確認する（言語固定の検証は
    // test/native_bridge_error_app_test.dart 側で行う）。
    final possibleMessages = AppLocalizations.supportedLocales
        .map((l) => lookupAppLocalizations(l).nativeBridgeInitFailed)
        .toSet();
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text && possibleMessages.contains(widget.data),
      ),
      findsOneWidget,
    );
    expect(find.byType(HomeScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
