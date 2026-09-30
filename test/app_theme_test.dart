// AppTheme のハイコントラスト対応の検証（#72）。
//
// - highContrastTheme / highContrastDarkTheme は既定テーマと同じシード・明暗で、
//   contrastLevel だけが違う（同じ生成ロジックを流用している）。
// - MaterialApp に配線され、MediaQuery.highContrast が true のときだけ切り替わる。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/ui/theme/app_theme.dart';

/// WCAG のコントラスト比。
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('ハイコントラストのテーマは明暗を保ったまま前景/背景の対比が上がる', () {
    for (final (normal, high, brightness)
        in <(ThemeData, ThemeData, Brightness)>[
      (AppTheme.lightTheme, AppTheme.highContrastTheme, Brightness.light),
      (AppTheme.darkTheme, AppTheme.highContrastDarkTheme, Brightness.dark),
    ]) {
      expect(high.colorScheme.brightness, brightness);
      expect(
        _contrast(high.colorScheme.primary, high.colorScheme.surface),
        greaterThan(
            _contrast(normal.colorScheme.primary, normal.colorScheme.surface)),
      );
      expect(
        _contrast(high.colorScheme.onSurfaceVariant, high.colorScheme.surface),
        greaterThanOrEqualTo(
          _contrast(
              normal.colorScheme.onSurfaceVariant, normal.colorScheme.surface),
        ),
      );
      // cardTheme など colorScheme 由来の設定が引き継がれている。
      expect(high.cardTheme.color, high.colorScheme.surfaceContainerHighest);
    }
  });

  Future<ThemeData> pumpAndReadTheme(
    WidgetTester tester, {
    required bool highContrast,
    required ThemeMode mode,
  }) async {
    late ThemeData seen;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(highContrast: highContrast),
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          highContrastTheme: AppTheme.highContrastTheme,
          highContrastDarkTheme: AppTheme.highContrastDarkTheme,
          themeMode: mode,
          home: Builder(builder: (context) {
            seen = Theme.of(context);
            return const SizedBox();
          }),
        ),
      ),
    );
    // テーマ切り替えはアニメーションで補間されるため、落ち着かせてから読む。
    await tester.pumpAndSettle();
    return seen;
  }

  testWidgets('MediaQuery.highContrast が true のときだけハイコントラストへ切り替わる',
      (tester) async {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      final high =
          await pumpAndReadTheme(tester, highContrast: true, mode: mode);
      final expected = mode == ThemeMode.light
          ? AppTheme.highContrastTheme
          : AppTheme.highContrastDarkTheme;
      expect(high.colorScheme.primary, expected.colorScheme.primary);
    }

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      final normal =
          await pumpAndReadTheme(tester, highContrast: false, mode: mode);
      final expected =
          mode == ThemeMode.light ? AppTheme.lightTheme : AppTheme.darkTheme;
      expect(normal.colorScheme.primary, expected.colorScheme.primary);
    }
  });
}
