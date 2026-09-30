import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/settings_service.dart';

/// 言語名は**その言語自身の表記**で出す（読めない言語の画面から抜け出せるように、
/// 翻訳しない。ARB には入れない）。
///
/// [AppLocalizations.supportedLocales] の各言語に 1 件ずつ必要で、足し忘れは
/// `test/language_dialog_test.dart` が検出する（言語追加の手順は
/// `docs/ADDING_A_LANGUAGE.md`）。
const Map<String, String> kLanguageEndonyms = {
  'ja': '日本語',
  'en': 'English',
};

/// 「システムに合わせる」を表す SegmentedButton の値。言語コードと衝突しない。
const String kLanguageFollowSystem = 'system';

/// AppBar の言語ボタンから開く言語ダイアログ (#82)。
///
/// OS のロケール任せにせず、アプリ内で「システムに合わせる / 日本語 / English」を
/// 選べる。選択は [SettingsService.setLocale] で永続化され、`MaterialApp.locale`
/// と（`TrayLocaleSync` 経由で）トレイの文言に即時に反映される。
Future<void> showLanguageDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const LanguageDialog(),
  );
}

class LanguageDialog extends StatelessWidget {
  const LanguageDialog({super.key});

  @override
  Widget build(BuildContext context) {
    // ダイアログを開いたまま言語を切り替えても、自身の文言が新しい言語に
    // 変わるよう、`AppLocalizations` は build のたびにこの context から引く。
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.language, color: colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(l10n.languageSectionTitle)),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const _LanguageSelector(),
              const SizedBox(height: 16),
              Text(
                l10n.languageDialogNote,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.languageCloseButton),
        ),
      ],
    );
  }
}

class _LanguageSelector extends StatelessWidget {
  const _LanguageSelector();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer<SettingsService>(
      builder: (context, settings, _) {
        return SegmentedButton<String>(
          segments: [
            ButtonSegment(
              value: kLanguageFollowSystem,
              label: Text(l10n.languageOptionSystem),
            ),
            for (final locale in AppLocalizations.supportedLocales)
              ButtonSegment(
                value: locale.languageCode,
                label: Text(
                  kLanguageEndonyms[locale.languageCode] ?? locale.languageCode,
                  // 画面の言語と違う言語の名前でも、その言語の字形で描く
                  // （日本語の画面で English、英語の画面で 日本語 を出すため）。
                  locale: Locale(locale.languageCode),
                ),
              ),
          ],
          selected: {selectedLanguageChoice(settings.locale)},
          onSelectionChanged: (selected) {
            if (selected.isEmpty) return;
            settings.setLocale(localeForLanguageChoice(selected.first));
          },
        );
      },
    );
  }
}

/// 永続化された [locale] を、ダイアログの選択値に変える。null と、サポート外の
/// 言語コードが残っていた場合は「システムに合わせる」（アプリの解決結果と同じ）。
String selectedLanguageChoice(Locale? locale) {
  if (locale == null) return kLanguageFollowSystem;
  final supported = AppLocalizations.supportedLocales
      .any((s) => s.languageCode == locale.languageCode);
  return supported ? locale.languageCode : kLanguageFollowSystem;
}

/// ダイアログの選択値を、[SettingsService.setLocale] に渡す値に変える。
Locale? localeForLanguageChoice(String choice) =>
    choice == kLanguageFollowSystem ? null : Locale(choice);
