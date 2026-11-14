// FilterBrowser のカテゴリチップの等幅グリッド（#184）のテスト。
//
// 「すべて」+ 7 カテゴリを、幅ごとに列数を決めて端数行なしで並べる。各行の左端・右端が揃い、
// チップは同幅で、48dp 以上のタップ領域を持ち、ラベルが入らないときはツールチップを出す。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/ui/widgets/filter_browser.dart';

import 'support/home_screen_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installHomeScreenFixtures);
  tearDown(resetHomeScreenFixtures);

  Future<void> pumpBrowser(
    WidgetTester tester, {
    required double width,
    required String locale,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final controller = FilterBrowserController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<VisionFilterState>.value(
        value: VisionFilterState(),
        child: MaterialApp(
          locale: Locale(locale),
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
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: FilterBrowser(controller: controller, onActivated: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// チップの描画矩形（タップ領域ではなく Material の見た目）を上→下・左→右の順で返す。
  List<Rect> chipRects(WidgetTester tester) {
    final rects = [
      for (final e in find.byType(ChoiceChip).evaluate())
        tester.getRect(find.byWidget(e.widget)),
    ];
    return rects;
  }

  /// 同じ上端（行）ごとにまとめる。
  List<List<Rect>> rowsOf(List<Rect> rects) {
    final rows = <List<Rect>>[];
    for (final r in rects) {
      if (rows.isNotEmpty && (rows.last.first.top - r.top).abs() < 1) {
        rows.last.add(r);
      } else {
        rows.add([r]);
      }
    }
    return rows;
  }

  void expectAligned(WidgetTester tester, {required int columns}) {
    final rects = chipRects(tester);
    expect(rects, hasLength(8));
    final rows = rowsOf(rects);
    expect(rows, hasLength(8 ~/ columns), reason: '端数行を作らない');
    final width = rects.first.width;
    final left = rows.first.first.left;
    final right = rows.first.last.right;
    for (final row in rows) {
      expect(row, hasLength(columns));
      expect(row.first.left, closeTo(left, 0.5), reason: '各行の左端が揃う');
      expect(row.last.right, closeTo(right, 0.5), reason: '各行の右端が揃う');
      for (final r in row) {
        expect(r.width, closeTo(width, 0.5), reason: '全チップ同幅');
        expect(r.height, greaterThanOrEqualTo(48), reason: '48dp のタップ目標');
      }
    }
  }

  group('categoryChipColumns', () {
    test('8 個は 4 / 2 / 1 列のいずれかになり、収まる最大の列を選ぶ', () {
      int cols(double w, double label) =>
          categoryChipColumns(availableWidth: w, widestLabel: label, count: 8);
      expect(cols(800, 80), 4);
      expect(cols(300, 80), 2);
      expect(cols(300, 150), 2, reason: '入らなくても 2 列まで（省略 + ツールチップ）');
      expect(cols(200, 150), 1);
    });
  });

  for (final locale in ['ja', 'en']) {
    // 既定ウィンドウ(800)の縦積み。英語は最長ラベルが 4 列に入らないので 2 列。
    testWidgets('$locale: 既定ウィンドウ幅(800)で行が揃う', (tester) async {
      await pumpBrowser(tester, width: 800, locale: locale);
      expectAligned(tester, columns: locale == 'ja' ? 4 : 2);
    });

    // テストのフォント(Ahem)は実フォントより横に広いので、英語の 4 列は広めの幅で確かめる。
    testWidgets('$locale: 十分に広いと 4 列で行が揃う', (tester) async {
      await pumpBrowser(tester,
          width: locale == 'ja' ? 960 : 1700, locale: locale);
      expectAligned(tester, columns: 4);
    });

    testWidgets('$locale: 左ペイン幅(約 300)では 2 列で行が揃う', (tester) async {
      await pumpBrowser(tester, width: 332, locale: locale);
      expectAligned(tester, columns: 2);
    });

    testWidgets('$locale: 最小の左ペイン(280)でも行が揃い、例外が出ない', (tester) async {
      await pumpBrowser(tester, width: 312, locale: locale);
      expectAligned(tester, columns: 2);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('en: 最長ラベルが入らない幅では省略し、ツールチップに全文を出す', (tester) async {
    await pumpBrowser(tester, width: 332, locale: 'en');
    final chip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Vestibular & dizziness'));
    expect(chip.tooltip, 'Vestibular & dizziness');
    final short =
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Other'));
    expect(short.tooltip, isNull);
  });

  testWidgets('文字を大きくしても行が揃って崩れない', (tester) async {
    await pumpBrowser(tester, width: 332, locale: 'ja', textScale: 2.0);
    final rects = chipRects(tester);
    final rows = rowsOf(rects);
    for (final row in rows) {
      expect(row.first.left, closeTo(rows.first.first.left, 0.5));
      expect(row.last.right, closeTo(rows.first.last.right, 0.5));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('フォーカス順は左上から右下（DOM 順 = 行優先）', (tester) async {
    await pumpBrowser(tester, width: 960, locale: 'ja');
    final rects = chipRects(tester);
    for (var i = 1; i < rects.length; i++) {
      final a = rects[i - 1], b = rects[i];
      expect(b.top > a.top + 1 || (b.top == a.top && b.left > a.left), isTrue);
    }
  });
}
