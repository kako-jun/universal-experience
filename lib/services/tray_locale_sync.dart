import 'dart:async';

import 'package:flutter/widgets.dart';

import '../l10n/locale_resolution.dart';
import 'settings_service.dart';

/// トレイの文言を、画面（`MaterialApp.locale`）と同じ言語に追従させる (#82)。
///
/// トレイは `BuildContext` を持てないため、`MaterialApp` の locale 変更を受け取れない。
/// 代わりに次の 2 つを購読し、**解決後の言語**（[resolveSupportedLocale]）が変わった
/// ときだけ [apply] を呼ぶ:
///
///  * [SettingsService]（言語ピッカーでの明示選択・「自動」への切替）
///  * OS のロケール変更（[WidgetsBindingObserver.didChangeLocales]。設定が
///    「自動」のときだけ実際の解決結果が変わる）
///
/// [SettingsService] はテーマ・フィルタの変更でも通知するので、解決結果が同じなら
/// 何もしない（トレイのメニューを無駄に作り直さない）。
class TrayLocaleSync with WidgetsBindingObserver {
  TrayLocaleSync({
    required this.settings,
    required this.apply,
    required Locale initial,
  }) : _applied = initial;

  final SettingsService settings;

  /// 解決済みの言語を受け取り、トレイの文言を差し替える。
  final Future<void> Function(Locale locale) apply;

  Locale _applied;
  bool _started = false;

  /// 購読を始める。二重に呼んでも 1 回分だけ購読する。
  void start() {
    if (_started) return;
    _started = true;
    settings.addListener(_onChanged);
    WidgetsBinding.instance.addObserver(this);
    // 起動から start までの間に変わっていた場合に備えて 1 回合わせる。
    _onChanged();
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    settings.removeListener(_onChanged);
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeLocales(List<Locale>? locales) => _onChanged();

  void _onChanged() {
    final resolved = resolveSupportedLocale(settings.locale);
    if (resolved == _applied) return;
    _applied = resolved;
    unawaited(apply(resolved));
  }
}
