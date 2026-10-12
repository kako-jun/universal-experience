// 「このアプリについて」の版は pubspec.yaml の version を実行時に読む（#158）。
// ハードコードに戻ると、リリースで版を上げても表示が古いまま残る。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'support/home_screen_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installHomeScreenFixtures();
    PackageInfo.setMockInitialValues(
      appName: 'universal_experience',
      packageName: 'universal_experience',
      version: '9.8.7',
      buildNumber: '42',
      buildSignature: '',
    );
  });
  tearDown(resetHomeScreenFixtures);

  testWidgets('About ダイアログは PackageInfo の版を build 番号なしで出す', (tester) async {
    await pumpHomeScreen(tester, size: const Size(1280, 800));

    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();

    expect(find.byType(AboutDialog), findsOneWidget);
    expect(find.text('9.8.7'), findsOneWidget);
    expect(find.textContaining('0.1.0'), findsNothing);
    expect(find.textContaining('42'), findsNothing);
  });
}
