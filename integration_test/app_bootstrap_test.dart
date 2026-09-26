// main() の実起動経路を踏む integration test (#55 レビュー M1)。
//
// integration_test/experience_presets_smoke_test.dart は自身の setUpAll で
// initNativeBridge() を呼んでから ExperiencePresets を自前の MaterialApp に
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
// 実行: `flutter test integration_test -d macos`（CI では linux -d linux も）

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

    final app = await buildRootApp();
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    expect(RustLib.instance.initialized, isTrue);
    expect(find.byType(HomeScreen), findsOneWidget);

    // HomeScreen の body は素の ListView（暗黙 SliverList）なので、初期ビュー
    // ポート + デフォルトの cache extent より下にあるセクションは、実際に
    // スクロールされるまでツリーに build されない。ExperiencePresets は 6
    // セクション中 5 番目で、実起動時のウィンドウでは初期表示では画面外
    // （experience_presets_smoke_test.dart は ExperiencePresets 単体を自前の
    // 小さな Scaffold+SingleChildScrollView に包んで pump するだけなので
    // この問題を踏まない）。まず ExperiencePresets をスクロールで可視化する。
    await tester.scrollUntilVisible(
      find.byType(ExperiencePresets),
      300.0,
      // このテスト時点で画面上の Scrollable はこの HomeScreen 本体の ListView
      // 1 つだけ（DropdownButton 等はメニューを開かない限り Scrollable を
      // 生成しない）なので .first で一意に解決できる。
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // HomeScreen の他 5 セクション（filter/controls/preview/advanced/info）も
    // それぞれ自前で Card を使っているため、素の find.byType(Card) はツリー
    // 全体では 4 に確定しない。ExperiencePresets の子孫だけに絞って検証する。
    expect(
      find.descendant(
        of: find.byType(ExperiencePresets),
        matching: find.byType(Card),
      ),
      findsNWidgets(4),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('initBridge が false を返す経路は NativeBridgeErrorApp になる',
      (tester) async {
    final app = await buildRootApp(initBridge: () async => false);
    expect(app, isA<NativeBridgeErrorApp>());

    await tester.pumpWidget(app);
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
