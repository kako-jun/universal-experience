// 主要な操作要素がデスクトップでも 48dp 以上のタップ領域を持つことの検証（#45, #72）。
//
// Flutter の既定は、デスクトップ（macOS / Windows / Linux）では
// `MaterialTapTargetSize.shrinkWrap` + 密な `visualDensity` で、ChoiceChip や
// TextButton が 48dp を割る。`AppTheme` が padded を保つことを、プラットフォームを
// macOS にして確かめる（テスト後の override の復帰は variant が行う）。

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/ui/theme/app_theme.dart';
import 'package:universal_experience/ui/widgets/filter_browser.dart';
import 'package:universal_experience/ui/widgets/image_source_picker.dart';
import 'package:universal_experience/ui/widgets/language_dialog.dart';

import 'support/home_screen_harness.dart';
import 'support/color_vision_select.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installHomeScreenFixtures);
  tearDown(resetHomeScreenFixtures);

  test('AppTheme は padded なタップ領域と標準の密度を指定している', () {
    for (final theme in [
      AppTheme.lightTheme,
      AppTheme.darkTheme,
      AppTheme.highContrastTheme,
      AppTheme.highContrastDarkTheme,
    ]) {
      expect(theme.materialTapTargetSize, MaterialTapTargetSize.padded);
      expect(theme.visualDensity, VisualDensity.standard);
    }
  });

  testWidgets(
    'macOS でも主要な操作要素は 48dp 以上（チップ・解除・クリア・AppBar・行・比較の切替・スライダー）',
    (tester) async {
      expect(defaultTargetPlatform, TargetPlatform.macOS);
      await pumpHomeScreen(
        tester,
        size: const Size(1280, 800),
        theme: AppTheme.lightTheme,
        select: (s) => selectColorVisionKey(s, 'protanopia'),
      );
      await tester.enterText(find.byType(TextField), 'a');
      await tester.pump();

      void expectAtLeast48(Finder finder, String label) {
        expect(finder, findsWidgets, reason: label);
        for (final element in finder.evaluate()) {
          final size = (element.renderObject! as RenderBox).size;
          expect(size.width, greaterThanOrEqualTo(48),
              reason: '$label の幅 $size');
          expect(size.height, greaterThanOrEqualTo(48),
              reason: '$label の高さ $size');
        }
      }

      expectAtLeast48(find.byType(ChoiceChip), 'カテゴリの ChoiceChip');
      expectAtLeast48(
        find.widgetWithText(TextButton, 'フィルタを解除'),
        '選択解除の TextButton',
      );
      expectAtLeast48(
        find.descendant(
            of: find.byType(FilterBrowser), matching: find.byType(IconButton)),
        '検索のクリア IconButton',
      );
      expectAtLeast48(
        find.descendant(
            of: find.byType(AppBar), matching: find.byType(IconButton)),
        'AppBar の IconButton',
      );
      expectAtLeast48(find.byType(ListTile), '一覧の行（ListTile）');
      expectAtLeast48(
        find.widgetWithText(FilterChip, '2×2 で比較'),
        '色覚の 2×2 比較の切替（FilterChip）',
      );
      for (final (type, label) in [
        (ChoiceChip, 'サンプル切替の ChoiceChip'),
        (OutlinedButton, '画像を選ぶ OutlinedButton'),
      ]) {
        expectAtLeast48(
          find.descendant(
              of: find.byType(ImageSourcePicker), matching: find.byType(type)),
          label,
        );
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('言語ダイアログの各セグメントと閉じるボタンも macOS で 48dp 以上（#82）', (tester) async {
    expect(defaultTargetPlatform, TargetPlatform.macOS);
    await pumpHomeScreen(
      tester,
      size: const Size(1280, 800),
      theme: AppTheme.lightTheme,
    );
    await tester.tap(find.byTooltip('言語'));
    await tester.pumpAndSettle();
    expect(find.byType(LanguageDialog), findsOneWidget);

    final segments = find.descendant(
      of: find.byType(SegmentedButton<String>),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    // 自動 / 日本語 / English の 3 つ。
    expect(segments, findsNWidgets(3));
    final targets = [
      ...segments.evaluate(),
      ...find
          .descendant(
              of: find.byType(LanguageDialog),
              matching: find.widgetWithText(TextButton, '閉じる'))
          .evaluate(),
    ];
    for (final element in targets) {
      final size = (element.renderObject! as RenderBox).size;
      expect(size.width, greaterThanOrEqualTo(48), reason: '幅 $size');
      expect(size.height, greaterThanOrEqualTo(48), reason: '高さ $size');
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
