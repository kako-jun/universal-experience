import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

/// 設定の locale（null = システム追従）を、サポート対象の言語に解決する。
///
/// 解決の順序は「選んだ言語 → OS の言語リスト → 英語」:
/// 1. [preferred] の言語コードが [AppLocalizations.supportedLocales] にあればそれ。
/// 2. なければ OS の優先言語リストを、Flutter 既定の [basicLocaleListResolution]
///    で先頭から順に照合する（`[fr-FR, ja-JP]` なら fr は未対応なので ja）。
/// 3. どれも対応外なら [AppLocalizations.supportedLocales] の先頭（en）。
///
/// 結果は言語コードだけの [Locale] に正規化する（`ja-JP` → `ja`）。
///
/// `MaterialApp`（`locale` と `localeListResolutionCallback`）・起動時のエラー画面・
/// トレイ（`BuildContext` を持てない）が**同じこの関数**を通すので、画面とトレイの
/// 言語はずれない。[systemLocales] は `localeListResolutionCallback` が受け取った
/// リストを渡す用で、省略すると `platformDispatcher.locales` を読む。
///
/// `WidgetsBinding.instance.platformDispatcher` 経由で読む（`PlatformDispatcher.instance`
/// を直接参照しない）。本番ではどちらも同じ実プラットフォームディスパッチャを指すため
/// 挙動は変わらないが、`flutter_test` 下では `TestWidgetsFlutterBinding` の
/// `platformDispatcher`（`localesTestValue` で差し替え可能な偽物）と一致するため、
/// テストからロケールをオーバーライドできる。
Locale resolveSupportedLocale(
  Locale? preferred, {
  List<Locale>? systemLocales,
}) {
  if (preferred != null && isSupportedLanguage(preferred)) {
    return Locale(preferred.languageCode);
  }

  final locales =
      systemLocales ?? WidgetsBinding.instance.platformDispatcher.locales;
  final resolved = basicLocaleListResolution(
    locales,
    AppLocalizations.supportedLocales,
  );
  return Locale(resolved.languageCode);
}

/// [locale] の言語コードが、対応言語（ARB のある言語）に含まれるか。
bool isSupportedLanguage(Locale locale) => AppLocalizations.supportedLocales
    .any((s) => s.languageCode == locale.languageCode);
