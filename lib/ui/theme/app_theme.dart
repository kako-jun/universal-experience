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
  ///
  /// 色の例外（DESIGN.md）: カラートークン（colorScheme）の生成元そのもの。
  static const Color seedColor = Color(0xFF00897B);

  /// ハイコントラスト時に使う `ColorScheme.fromSeed` の contrastLevel
  /// （-1.0..1.0。1.0 が最大）。プラットフォームのアクセシビリティ設定
  /// （MediaQuery.highContrast）が有効なときだけ使う。
  static const double highContrastLevel = 1.0;

  static ThemeData get lightTheme => _build(Brightness.light);

  static ThemeData get darkTheme => _build(Brightness.dark);

  /// `MaterialApp.highContrastTheme` 用。既定テーマと同じ生成ロジックで
  /// contrastLevel だけを最大にする（二重実装しない）。
  static ThemeData get highContrastTheme =>
      _build(Brightness.light, contrastLevel: highContrastLevel);

  /// `MaterialApp.highContrastDarkTheme` 用。
  static ThemeData get highContrastDarkTheme =>
      _build(Brightness.dark, contrastLevel: highContrastLevel);

  static ThemeData _build(Brightness brightness, {double contrastLevel = 0.0}) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
      contrastLevel: contrastLevel,
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
