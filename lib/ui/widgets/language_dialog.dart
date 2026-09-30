import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart'
    show AttributedString, LocaleStringAttribute;
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/settings_service.dart';
import 'click_through_dialog_scope.dart';

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

/// 「自動」を表す SegmentedButton の値。言語コードと衝突しない。
const String kLanguageFollowSystem = 'system';

/// AppBar の言語ボタンから開く言語ダイアログ (#82)。
///
/// OS のロケール任せにせず、アプリ内で「自動 / 日本語 / English」を
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
      // クリックスルー（#63）が ON になったら自動で閉じ、ON の間は Esc が解除に
      // なる。起動モードのダイアログと同じ共有部品。
      content: ClickThroughDialogScope(
        child: SizedBox(
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
                label: _Endonym(locale.languageCode),
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

/// 言語名を、その言語自身の表記・字形・読み上げ言語で出す。
///
/// 画面の言語と違う名前（日本語の画面で English、英語の画面で 日本語）でも、
/// 描画は `Text.locale` でその言語の字形にし、スクリーンリーダーには
/// [LocaleStringAttribute] でその言語の名前として読ませる。
class _Endonym extends StatelessWidget {
  const _Endonym(this.languageCode);

  final String languageCode;

  @override
  Widget build(BuildContext context) {
    final name = kLanguageEndonyms[languageCode] ?? languageCode;
    final locale = Locale(languageCode);
    return Semantics(
      attributedLabel: AttributedString(
        name,
        attributes: [
          LocaleStringAttribute(
            locale: locale,
            range: TextRange(start: 0, end: name.length),
          ),
        ],
      ),
      child: ExcludeSemantics(child: Text(name, locale: locale)),
    );
  }
}

/// 永続化された [locale] を、ダイアログの選択値に変える。null と、サポート外の
/// 言語コードが残っていた場合は「自動」（アプリの解決結果と同じ）。
String selectedLanguageChoice(Locale? locale) {
  if (locale == null) return kLanguageFollowSystem;
  final supported = AppLocalizations.supportedLocales
      .any((s) => s.languageCode == locale.languageCode);
  return supported ? locale.languageCode : kLanguageFollowSystem;
}

/// ダイアログの選択値を、[SettingsService.setLocale] に渡す値に変える。
Locale? localeForLanguageChoice(String choice) =>
    choice == kLanguageFollowSystem ? null : Locale(choice);
