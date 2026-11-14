// 「原画表示中」のバッジ（#63、#183）: liveRegion（出た瞬間に 1 回読み上げ）と、狭いときのアイコン形。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/ui/widgets/bypass_badge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester tester, double width) => tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                height: 200,
                child: BypassBadge.overlaid(
                  const SizedBox.expand(),
                  show: true,
                ),
              ),
            ),
          ),
        ),
      );

  final liveRegion = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.liveRegion == true);

  testWidgets('読み上げツリーで liveRegion になっている（文字つき）', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, 400);
    expect(find.text('Showing original'), findsOneWidget);
    final data = tester.getSemantics(liveRegion).getSemanticsData();
    expect(data.flagsCollection.isLiveRegion, isTrue);
    expect(data.label, contains('Showing original'));
    handle.dispose();
  });

  testWidgets('狭いと文字を縮めずアイコンだけの形になり、liveRegion とラベルは保つ', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, 80);
    expect(find.text('Showing original'), findsNothing);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    final data = tester.getSemantics(liveRegion).getSemanticsData();
    expect(data.flagsCollection.isLiveRegion, isTrue);
    expect(data.label, 'Showing original');
    handle.dispose();
  });

  testWidgets('文字倍率を打ち消さない（縮小して文字を小さくしない）', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester, 160);
    // 160 には文字つき ×2 が収まらない → アイコン形。文字つきを縮小して置かない。
    expect(find.byType(FittedBox), findsNothing);
    expect(
        tester.getSize(find.byType(BypassBadge)).height, lessThanOrEqualTo(48));
  });
}
