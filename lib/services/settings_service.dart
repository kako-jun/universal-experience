import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/disability_type.dart';

/// Persists and restores user preferences via [SharedPreferences].
///
/// Owns three persisted settings:
/// - [themeMode]   ([ThemeMode], light/dark/system)
/// - [filterType]  (the last selected [ColorVisionType])
/// - [locale]      (the chosen UI language; null = follow the system locale)
///
/// Filter *intensity* used to live here too (a single global value), but as of
/// #57 it is owned by `FilterService` instead (remembered per [ColorVisionType],
/// persisted with its own debounce). Routing every intensity change through
/// this service's [notifyListeners] meant the [MaterialApp] Consumer below
/// (main.dart) — which exists to react to theme/locale — rebuilt on every
/// slider tick too. This service only notifies for changes that the
/// [MaterialApp] actually cares about (theme, locale) plus [filterType].
///
/// The service is a [ChangeNotifier] so widgets (e.g. the [MaterialApp] theme
/// and locale) rebuild when settings change. Call [load] once at startup before
/// runApp to hydrate the in-memory state from disk.
class SettingsService extends ChangeNotifier {
  SettingsService({SharedPreferences? prefs}) : _prefs = prefs;

  // Persistence keys.
  static const String keyThemeMode = 'settings.themeMode';
  static const String keyFilterType = 'settings.filterType';
  static const String keyLocale = 'settings.locale';

  SharedPreferences? _prefs;

  ThemeMode _themeMode = ThemeMode.system;
  ColorVisionType _filterType = ColorVisionType.none;
  Locale? _locale;

  ThemeMode get themeMode => _themeMode;
  ColorVisionType get filterType => _filterType;

  /// The chosen UI language, or null to follow the system locale (#18).
  ///
  /// A language picker is out of scope for #18 (#16/#19 territory); this is the
  /// persisted backing store + [setLocale] hook so tests and a future picker can
  /// switch languages. Stored as the bare language code (e.g. `ja`).
  Locale? get locale => _locale;

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

    final localeCode = prefs.getString(keyLocale);
    if (localeCode != null && localeCode.isNotEmpty) {
      _locale = Locale(localeCode);
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

  /// Sets the UI language, or clears it (null) to follow the system locale.
  ///
  /// Persisted as the bare language code; a null locale removes the stored
  /// preference so the app falls back to the device language on next launch.
  Future<void> setLocale(Locale? locale) async {
    if (locale == _locale) return;
    _locale = locale;
    notifyListeners();
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove(keyLocale);
    } else {
      await prefs.setString(keyLocale, locale.languageCode);
    }
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
