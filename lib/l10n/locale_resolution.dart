import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

/// 設定の locale（null = システム追従）を、サポート対象 locale に解決する。
///
/// `lookupAppLocalizations` はサポート外 locale で投げるため、システム locale が
/// 非対応のときは [AppLocalizations.supportedLocales] の先頭（en）へフォールバック
/// する。`MaterialApp` の locale 解決（`locale: null` のとき）も同じく先頭へ
/// フォールバックするので、画面とトレイ（`BuildContext` を持てない）が同じ言語に
/// なる。
///
/// `WidgetsBinding.instance.platformDispatcher` 経由で読む（`PlatformDispatcher.instance`
/// を直接参照しない）。本番ではどちらも同じ実プラットフォームディスパッチャを指すため
/// 挙動は変わらないが、`flutter_test` 下では `WidgetsBinding.instance` が
/// `TestWidgetsFlutterBinding` になり、その `platformDispatcher` が
/// `tester.platformDispatcher`（`localeTestValue` で差し替え可能な偽物）と一致する
/// ため、テストからロケールをオーバーライドできる。
Locale resolveSupportedLocale(Locale? preferred) {
  bool isSupported(Locale l) => AppLocalizations.supportedLocales
      .any((s) => s.languageCode == l.languageCode);

  if (preferred != null && isSupported(preferred)) {
    return Locale(preferred.languageCode);
  }

  final system = WidgetsBinding.instance.platformDispatcher.locale;
  if (isSupported(system)) return Locale(system.languageCode);

  return AppLocalizations.supportedLocales.first;
}
