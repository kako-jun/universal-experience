import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/locale_resolution.dart';

/// Persists and restores user preferences via [SharedPreferences].
///
/// Owns two persisted settings plus the welcome-banner flag:
/// - [themeMode]   ([ThemeMode], light/dark/system)
/// - [locale]      (the chosen UI language; null = follow the system locale)
///
/// The selected filter (layers, strengths, payloads) is **not** stored here.
/// `VisionFilterState` is the single selection model and `VisionFilterStore`
/// persists it (`settings.visionFilter`, #117/#124); the old `settings.filterType`
/// key this service used to own is folded into that state once at startup
/// (`VisionFilterStore.migrateLegacySettings`) and then deleted. Keeping
/// filter changes out of this service also means a slider tick never reaches
/// [notifyListeners], which the [MaterialApp] Consumer (main.dart) — there to
/// react to theme/locale — rebuilds on.
///
/// The service is a [ChangeNotifier] so widgets (e.g. the [MaterialApp] theme
/// and locale) rebuild when settings change. Call [load] once at startup before
/// runApp to hydrate the in-memory state from disk.
class SettingsService extends ChangeNotifier {
  SettingsService({SharedPreferences? prefs}) : _prefs = prefs;

  // Persistence keys.
  static const String keyThemeMode = 'settings.themeMode';
  static const String keyLocale = 'settings.locale';
  /// #78: whether the first-run welcome banner has been dismissed.
  static const String keyWelcomeBannerDismissed =
      'settings.welcomeBannerDismissed';

  SharedPreferences? _prefs;

  ThemeMode _themeMode = ThemeMode.system;
  Locale? _locale;
  bool _welcomeBannerDismissed = false;

  ThemeMode get themeMode => _themeMode;

  /// Whether the first-run welcome banner (#78) has been dismissed. Starts
  /// `false` and never resets — [dismissWelcomeBanner] is a one-way switch.
  bool get welcomeBannerDismissed => _welcomeBannerDismissed;

  /// The chosen UI language, or null to follow the system locale (#18).
  ///
  /// Chosen in the app bar's language dialog (`LanguageDialog`, #82) and applied
  /// through [setLocale]. Stored as the bare language code (e.g. `ja`); a stored
  /// code the app does not support is discarded on [load], so the dialog's
  /// "auto" state always matches what the app actually resolves.
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

    final localeCode = prefs.getString(keyLocale);
    if (localeCode != null && localeCode.isNotEmpty) {
      final saved = Locale(localeCode);
      // 未対応の言語コード（対応言語が減った・手で書き換えた等）は捨てる。
      if (isSupportedLanguage(saved)) _locale = saved;
    }

    _welcomeBannerDismissed =
        prefs.getBool(keyWelcomeBannerDismissed) ?? false;

    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setString(keyThemeMode, mode.name);
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

  /// Permanently dismisses the first-run welcome banner (#78). No-op (and no
  /// write) if already dismissed.
  Future<void> dismissWelcomeBanner() async {
    if (_welcomeBannerDismissed) return;
    _welcomeBannerDismissed = true;
    notifyListeners();
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setBool(keyWelcomeBannerDismissed, true);
  }

  static ThemeMode _themeModeFromName(String name) {
    return ThemeMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => ThemeMode.system,
    );
  }
}
