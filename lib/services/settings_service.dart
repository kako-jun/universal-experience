import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/disability_type.dart';

/// Persists and restores user preferences via [SharedPreferences].
///
/// Owns three persisted settings:
/// - [themeMode]   ([ThemeMode], light/dark/system)
/// - [filterType]  (the last selected [ColorVisionType])
/// - [intensity]   (the last filter intensity, 0.0..1.0)
///
/// The service is a [ChangeNotifier] so widgets (e.g. the [MaterialApp] theme)
/// rebuild when settings change. Call [load] once at startup before runApp to
/// hydrate the in-memory state from disk.
class SettingsService extends ChangeNotifier {
  SettingsService({SharedPreferences? prefs}) : _prefs = prefs;

  // Persistence keys.
  static const String keyThemeMode = 'settings.themeMode';
  static const String keyFilterType = 'settings.filterType';
  static const String keyIntensity = 'settings.intensity';

  SharedPreferences? _prefs;

  ThemeMode _themeMode = ThemeMode.system;
  ColorVisionType _filterType = ColorVisionType.none;
  double _intensity = 1.0;

  ThemeMode get themeMode => _themeMode;
  ColorVisionType get filterType => _filterType;
  double get intensity => _intensity;

  /// Loads persisted settings from disk into memory.
  ///
  /// Safe to call when nothing has been saved yet: defaults are kept.
  Future<void> load() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();

    final themeName = prefs.getString(keyThemeMode);
    if (themeName != null) {
      _themeMode = _themeModeFromName(themeName);
    }

    final filterName = prefs.getString(keyFilterType);
    if (filterName != null) {
      _filterType = _filterTypeFromName(filterName);
    }

    final storedIntensity = prefs.getDouble(keyIntensity);
    if (storedIntensity != null) {
      _intensity = storedIntensity.clamp(0.0, 1.0);
    }

    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setString(keyThemeMode, mode.name);
  }

  Future<void> setFilterType(ColorVisionType type) async {
    if (type == _filterType) return;
    _filterType = type;
    notifyListeners();
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setString(keyFilterType, type.name);
  }

  Future<void> setIntensity(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    if (clamped == _intensity) return;
    _intensity = clamped;
    notifyListeners();
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setDouble(keyIntensity, clamped);
  }

  static ThemeMode _themeModeFromName(String name) {
    return ThemeMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => ThemeMode.system,
    );
  }

  static ColorVisionType _filterTypeFromName(String name) {
    return ColorVisionType.values.firstWhere(
      (t) => t.name == name,
      orElse: () => ColorVisionType.none,
    );
  }
}
