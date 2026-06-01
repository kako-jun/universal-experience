import 'package:flutter/material.dart';

/// Application theming for universal-experience.
///
/// Material 3 themes generated from a single [seedColor] via
/// [ColorScheme.fromSeed]. Both light and dark variants share the same seed so
/// the brand identity stays consistent across modes.
class AppTheme {
  AppTheme._();

  /// Brand seed color. A calm teal/cyan that reads well for an
  /// accessibility-focused colour-vision tool.
  static const Color seedColor = Color(0xFF00897B);

  static ThemeData get lightTheme => _build(Brightness.light);

  static ThemeData get darkTheme => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: brightness,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 2,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      sliderTheme: const SliderThemeData(
        showValueIndicator: ShowValueIndicator.onDrag,
      ),
    );
  }
}
