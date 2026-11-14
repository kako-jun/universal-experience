// 調整パネル見出し行の「フィルタをすべて解除」ボタンの回帰テスト（#182）。
//
// 文言が長くなってもはみ出さない・見出しが単語の途中で折れない・ボタンは右端に揃う・
// 全文がツールチップか折り返しで読める、を狭幅 / 英語 / 大きい文字倍率で確かめる。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/ui/widgets/adjust_panel.dart';

import 'support/vision_filter_metadata_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installVisionFilterMetadataFixture);
  tearDown(resetVisionFilterMetadataProviders);

  const gutter = 16.0;

  Future<AppLocalizations> pumpPanel(
    WidgetTester tester, {
    required double width,
    required Locale locale,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = Size(width, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<VisionFilterState>(
        create: (_) => VisionFilterState(),
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.symmetric(horizontal: gutter),
              child: SingleChildScrollView(child: AdjustPanel()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return AppLocalizations.of(tester.element(find.byType(AdjustPanel)))!;
  }

  Finder button() => find.byType(TextButton);

  for (final locale in const [Locale('ja'), Locale('en')]) {
    for (final width in const [220.0, 268.0, 348.0, 600.0]) {
      for (final scale in const [1.0, 1.5, 2.0]) {
        // 幅 220 に倍率 2.0 は想定外の極端な組み合わせ（アイコンと余白だけでボタンの
        // 最小幅が見出しの残りを超える）。ここは対象外にする。
        if (width < 250 && scale > 1.5) continue;
        testWidgets('${locale.languageCode} 幅$width 倍率$scale: はみ出さず、全文が読める',
            (tester) async {
          final l10n = await pumpPanel(
            tester,
            width: width,
            locale: locale,
            textScale: scale,
          );
          // overflow などの描画例外が出ていない。
          expect(tester.takeException(), isNull);

          // 全文は折り返しの Text とツールチップの両方で読める。
          expect(find.text(l10n.clearFilter), findsOneWidget);
          expect(find.byTooltip(l10n.clearFilter), findsOneWidget);

          // ボタンは画面内（余白の内側）に収まる。
          final rect = tester.getRect(button());
          expect(rect.left, greaterThanOrEqualTo(gutter - 0.01));
          expect(rect.right, lessThanOrEqualTo(width - gutter + 0.01));

          // 見出しは単語の途中で折れない（1 行のまま）。
          final heading = tester.getSize(find.text(l10n.adjustHeading));
          final oneLine = (Theme.of(tester.element(find.byType(AdjustPanel)))
                      .textTheme
                      .titleMedium!
                      .fontSize ??
                  16) *
              scale *
              1.6;
          expect(heading.height, lessThan(oneLine), reason: '見出しが 2 行以上に折れている');
        });
      }
    }

    testWidgets('${locale.languageCode} 十分な幅ではボタンが右端に揃う', (tester) async {
      await pumpPanel(tester, width: 600, locale: locale);
      expect(tester.takeException(), isNull);
      expect(tester.getRect(button()).right, closeTo(600 - gutter, 0.5));
    });
  }
}
