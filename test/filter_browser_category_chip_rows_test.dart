// FilterBrowser のカテゴリチップ帯（#184）のテスト。
//
// 「すべて」+ 7 カテゴリを、Wrap と同じ改行位置で積み、各行の余りの幅をチップに比例配分して
// 行の左右端を揃える（layoutCategoryChips）。省略は原則しない。48dp のタップ目標、
// 行優先の Tab 順、一覧が潰れないこと、チップ余白の見積もりが実物と一致することを確かめる。

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/models/vision_filter_catalog.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/ui/theme/app_theme.dart';
import 'package:universal_experience/ui/widgets/filter_browser.dart';

import 'support/home_screen_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installHomeScreenFixtures);
  tearDown(resetHomeScreenFixtures);

  late FilterBrowserController controller;
  // 描画例外を記録する。Ahem(横に広いテスト用フォント)の極端な幅では、チップ帯と無関係の
  // 行（ExperimentalBadge など）があふれることがあるので、チップ帯（filter_browser.dart）
  // 由来のものだけを失敗にする。
  late List<String> renderErrors;
  void Function(FlutterErrorDetails)? savedOnError;

  // pumpBrowser が差し替えた FlutterError.onError を、テスト本体の終わり（expect が失敗した
  // ときも含む）で必ず戻す。戻さないと binding のアサーションでテストが止まる。
  void browserTest(
      String description, Future<void> Function(WidgetTester) body) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        if (savedOnError != null) FlutterError.onError = savedOnError;
        savedOnError = null;
      }
    });
  }

  List<String> chipBandErrors() => [
        for (final e in renderErrors)
          if (e.contains('filter_browser.dart')) e
      ];

  Future<void> pumpBrowser(
    WidgetTester tester, {
    required double width,
    required String locale,
    double textScale = 1.0,
    double height = 900,
  }) async {
    renderErrors = [];
    savedOnError = FlutterError.onError;
    FlutterError.onError = (d) => renderErrors.add(d.toString());
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    controller = FilterBrowserController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<VisionFilterState>.value(
        value: VisionFilterState(),
        child: MaterialApp(
          theme: AppTheme.lightTheme,
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

  List<Rect> chipRects(WidgetTester tester) => [
        for (final e in find.byType(ChoiceChip).evaluate())
          tester.getRect(find.byWidget(e.widget)),
      ];

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

  group('チップ余白の見積もりが実物の ChoiceChip と一致する（AppTheme・各倍率）', () {
    for (final scale in [1.0, 1.3, 1.5, 2.0]) {
      browserTest('文字倍率 $scale', (tester) async {
        Future<List<double>> measure(bool selected) async {
          await tester.pumpWidget(MaterialApp(
            theme: AppTheme.lightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: ChoiceChip(
                  label: const Text('abcd'),
                  selected: selected,
                  showCheckmark: true,
                  onSelected: (_) {},
                ),
              ),
            ),
          ));
          await tester.pumpAndSettle();
          final text = tester.getSize(find.text('abcd'));
          return [
            tester.getSize(find.byType(ChoiceChip)).width - text.width,
            text.height,
          ];
        }

        final unselected = await measure(false);
        final selected = await measure(true);
        final height = unselected[1];
        final check = categoryChipCheckWidth(height);
        // 見積もりは「実物以上」（安全側）で、等倍では一致する。
        expect(unselected[0], lessThanOrEqualTo(kCategoryChipBaseChrome + 0.5));
        expect(selected[0],
            lessThanOrEqualTo(kCategoryChipBaseChrome + check + 0.5),
            reason: '選択中の余白（チェック込み）を見積もりが下回らない');
        if (scale == 1.0) {
          expect(unselected[0], closeTo(kCategoryChipBaseChrome, 0.5));
          expect(
              selected[0],
              closeTo(
                  kCategoryChipBaseChrome + kCategoryChipCheckReserve, 0.5));
        }
      });
    }
  });

  group('layoutCategoryChips', () {
    // 実フォント(Roboto 14sp)に近いラベル幅: ja / en。
    const en = <double>[18, 78, 62, 66, 100, 136, 60, 36];
    const ja = <double>[42, 28, 28, 28, 56, 70, 56, 42];

    void expectJustified(List<CategoryChipRow> rows, double width,
        {double spacing = 8}) {
      for (final r in rows) {
        final total = r.widths.fold<double>(0, (a, b) => a + b) +
            spacing * (r.widths.length - 1);
        expect(total, closeTo(width, 0.001), reason: '各行の右端が揃う');
      }
    }

    test('en の左ペイン幅(約 300)でも全チップが省略されず、行の端が揃う', () {
      for (final w in [280.0, 300.0, 340.0]) {
        final rows = layoutCategoryChips(labelWidths: en, availableWidth: w);
        expectJustified(rows, w);
        for (final r in rows) {
          for (var k = 0; k < r.indices.length; k++) {
            expect(
                r.widths[k],
                greaterThanOrEqualTo(
                    en[r.indices[k]] + kCategoryChipBaseChrome),
                reason: '幅 $w でラベルが入る');
          }
        }
        expect(
            rows.expand((r) => r.indices).toList(), [0, 1, 2, 3, 4, 5, 6, 7]);
      }
    });

    test('行数は Wrap と同じ積み方（en 300 で 5 行以内、広いほど減る）', () {
      final narrow = layoutCategoryChips(labelWidths: en, availableWidth: 300);
      final wide = layoutCategoryChips(labelWidths: en, availableWidth: 770);
      expect(narrow.length, lessThanOrEqualTo(5));
      expect(wide.length, lessThan(narrow.length));
      expectJustified(wide, 770);
    });

    test('ja は広いほど行が減り、各行の端が揃う', () {
      for (final w in [300.0, 500.0, 770.0]) {
        expectJustified(
            layoutCategoryChips(labelWidths: ja, availableWidth: w), w);
      }
    });

    test('境界ちょうどで 1 行に収まる / 1dp 足りないと次の行へ', () {
      const labels = [10.0, 10.0, 10.0];
      const chrome = 50.0;
      const exact = 3 * 60 + 2 * 8; // 3 個ぴったり
      final fit = layoutCategoryChips(
          labelWidths: labels,
          availableWidth: exact.toDouble(),
          chrome: chrome);
      expect(fit, hasLength(1));
      final over = layoutCategoryChips(
          labelWidths: labels, availableWidth: exact - 1.0, chrome: chrome);
      expect(over, hasLength(2));
      expect(over.first.indices, [0, 1]);
    });

    test('個数が 8 でなくても動く（0・1・5・9 個）', () {
      expect(layoutCategoryChips(labelWidths: const [], availableWidth: 300),
          isEmpty);
      for (final n in [1, 5, 9]) {
        final rows = layoutCategoryChips(
            labelWidths: List.filled(n, 40), availableWidth: 300);
        expect(rows.expand((r) => r.indices), hasLength(n));
        expectJustified(rows, 300);
      }
    });

    test('幅が有限でないときは折り返さず 1 行（自然幅のまま）', () {
      final rows = layoutCategoryChips(
          labelWidths: en, availableWidth: double.infinity, chrome: 50);
      expect(rows, hasLength(1));
      expect(rows.single.widths.first, closeTo(en.first + 50, 0.001));
    });

    test('幅 0 でも例外なく、全チップが並ぶ', () {
      final rows = layoutCategoryChips(labelWidths: en, availableWidth: 0);
      expect(rows.expand((r) => r.indices), hasLength(8));
    });

    test('1 チップが幅を超える極端な狭幅では、そのチップが幅いっぱいに縮む', () {
      final rows = layoutCategoryChips(
          labelWidths: const [400, 20], availableWidth: 200);
      expect(rows.first.indices, [0]);
      expect(rows.first.widths.single, closeTo(200, 0.001));
      expectJustified(rows, 200);
    });
  });

  for (final locale in ['ja', 'en']) {
    // テストのフォント(Ahem)は実フォントより横に広いので、en は省略が出ない広めの幅で確かめる。
    for (final width in locale == 'ja'
        ? [332.0, 420.0, 800.0, 1100.0]
        : [420.0, 800.0, 1100.0]) {
      browserTest('$locale 幅$width: 各行の左右端が揃い、全チップが 48dp 以上', (tester) async {
        await pumpBrowser(tester, width: width, locale: locale);
        final rects = chipRects(tester);
        expect(rects, hasLength(8));
        final rows = rowsOf(rects);
        final left = rows.first.first.left;
        final right = rows.first.last.right;
        for (final row in rows) {
          expect(row.first.left, closeTo(left, 0.5), reason: '左端');
          expect(row.last.right, closeTo(right, 0.5), reason: '右端');
          for (final r in row) {
            expect(r.height, greaterThanOrEqualTo(48));
          }
        }
        expect(chipBandErrors(), isEmpty);
        // 省略されたチップはツールチップを持つ。ここでは全部が収まる幅なので無い。
        expect(find.byType(Tooltip), findsNothing);
      });
    }

    browserTest('$locale: 文字倍率 2.0 でも行の端が揃い、例外が出ない', (tester) async {
      await pumpBrowser(tester, width: 332, locale: locale, textScale: 2.0);
      final rows = rowsOf(chipRects(tester));
      for (final row in rows) {
        expect(row.first.left, closeTo(rows.first.first.left, 0.5));
        expect(row.last.right, closeTo(rows.first.last.right, 0.5));
      }
      expect(chipBandErrors(), isEmpty);
    });
  }

  browserTest('極端な狭幅（または大きい文字倍率）では、入らないラベルを省略してツールチップに全文を出す（読み上げは二重にしない）',
      (tester) async {
    await pumpBrowser(tester, width: 250, locale: 'en');
    final tooltips = tester.widgetList<Tooltip>(find.byType(Tooltip)).toList();
    expect(tooltips, isNotEmpty);
    for (final t in tooltips) {
      expect(t.excludeFromSemantics, isTrue);
    }
    expect(chipBandErrors(), isEmpty);
  });

  browserTest('低い画面でもチップ帯が一覧を押し潰さず、一覧がスクロールで読める', (tester) async {
    await pumpBrowser(tester, width: 332, locale: 'en', height: 480);
    expect(chipBandErrors(), isEmpty);
    // チップ帯は一覧のスクロール領域の中にある（固定されていない）。
    expect(
      find.ancestor(
        of: find.byType(ChoiceChip).first,
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
  });

  browserTest('Tab を送ると、チップを左上から右下の順（行優先）にフォーカスが進む', (tester) async {
    await pumpBrowser(tester, width: 600, locale: 'ja');
    controller.searchFocus.requestFocus();
    await tester.pump();
    final visited = <Rect>[];
    for (var i = 0; i < 8; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final ctx = FocusManager.instance.primaryFocus?.context;
      final chip = ctx?.findAncestorWidgetOfExactType<ChoiceChip>() ??
          (ctx?.widget is ChoiceChip ? ctx!.widget as ChoiceChip : null);
      expect(chip, isNotNull, reason: 'Tab ${i + 1} 回目はチップ');
      visited.add(tester.getRect(find.byWidget(chip!)));
    }
    final all = chipRects(tester);
    expect(visited, all, reason: '描画順 = 行優先 = フォーカス順');
    for (var i = 1; i < visited.length; i++) {
      final a = visited[i - 1], b = visited[i];
      expect(b.top > a.top + 1 || (b.top == a.top && b.left > a.left), isTrue);
    }
  });

  // 文字倍率が上がるとラベル左右の余白は縮み、チェックの幅は文字の高さぶん広がる。
  // どのカテゴリを選択中にしても、ラベルが省略されない（省略されるなら必ずツールチップ付き）。
  Future<void> expectNoSilentEllipsis(WidgetTester tester) async {
    for (var c = 0; c <= 7; c++) {
      controller
          .setCategory(c == 0 ? null : VisionFilterCategory.values[c - 1]);
      // チェックの出現アニメ（150ms）が終わってから測る（途中は幅がほぼ 0）。
      await tester.pumpAndSettle();
      for (final e in find.byType(ChoiceChip).evaluate()) {
        final chipFinder = find.byWidget(e.widget);
        final textFinder =
            find.descendant(of: chipFinder, matching: find.byType(Text));
        final paragraph =
            tester.renderObject<RenderParagraph>(textFinder.first);
        if (paragraph.didExceedMaxLines) {
          expect(
            find.ancestor(of: chipFinder, matching: find.byType(Tooltip)),
            findsOneWidget,
            reason: '省略されるチップにはツールチップ',
          );
        }
      }
    }
  }

  for (final scale in [1.3, 2.0]) {
    for (final locale in ['ja', 'en']) {
      for (final width in locale == 'ja' ? [332.0, 600.0] : [900.0, 1400.0]) {
        browserTest('倍率 $scale $locale 幅$width: 選択を切り替えても省略されない',
            (tester) async {
          await pumpBrowser(tester,
              width: width, locale: locale, textScale: scale);
          await expectNoSilentEllipsis(tester);
          // この幅は全チップが入る幅なので、ツールチップも出ない。
          expect(find.byType(Tooltip), findsNothing);
          expect(chipBandErrors(), isEmpty);
        });
      }
    }

    browserTest('倍率 $scale 極端な狭幅（または大きい倍率）: 省略されるチップ（選択中含む）にツールチップが付く',
        (tester) async {
      await pumpBrowser(tester, width: 300, locale: 'en', textScale: scale);
      await expectNoSilentEllipsis(tester);
      expect(chipBandErrors(), isEmpty);
    });
  }

  // ぎりぎりの幅（既定の左ペイン幅 300〜340 や広幅）で、選択を切り替えても省略が黙って
  // 起きない（省略されるチップは必ずツールチップ付き）。守っているのは「省略されたらツールチップが
  // 付く」判定（truncated を常に false にすると 1.3 en 300・1.5 en 420・2.0 en 340 が落ちる）。
  // チェック幅の見積もりそのものは、上の「チップ余白の見積もりが実物と一致する」テストが守る。
  const tight = <(String, double, double)>[
    ('ja', 1.3, 300),
    ('en', 1.3, 300),
    ('en', 1.3, 1280),
    ('ja', 1.5, 420),
    ('ja', 1.5, 600),
    ('en', 1.5, 420),
    ('en', 1.5, 600),
    ('en', 2.0, 340),
  ];
  for (final (locale, scale, width) in tight) {
    browserTest('ぎりぎり幅 倍率 $scale $locale 幅$width: 省略は必ずツールチップ付き',
        (tester) async {
      await pumpBrowser(tester, width: width, locale: locale, textScale: scale);
      await expectNoSilentEllipsis(tester);
      expect(chipBandErrors(), isEmpty);
    });
  }
}
