// 実ブリッジ smoke test (#55)。
//
// widget test (test/experience_presets_test.dart) は experiencesProvider を
// fixture に差し替えて検証しているため、Rust ブリッジの初期化漏れ・同梱漏れを
// 検知できない（#52 の実害: 本番でプリセット欄が例外表示になった）。
// integration_test は実ネイティブライブラリをロードし、main() と同じ経路
// （RustLib.init()）で本物の `experiences()` を呼ぶ。
//
// 実行: `flutter test integration_test -d macos`

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/services/filter_service.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/src/rust/frb_generated.dart';
import 'package:universal_experience/ui/widgets/experience_presets.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await RustLib.init();
  });

  testWidgets('実ブリッジの experiences() が 4 件返る (#55)', (tester) async {
    expect(experiences(), hasLength(4));
  });

  testWidgets('プリセット欄が実ブリッジで例外なく描画される (#55)', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => VisionFilterState()),
          ChangeNotifierProvider(create: (_) => FilterService()),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(child: ExperiencePresets()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(Card), findsNWidgets(4));
  });
}
