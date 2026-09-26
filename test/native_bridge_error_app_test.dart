// NativeBridgeErrorApp（lib/main.dart、#55）の widget テスト。
//
// Rust ブリッジ初期化失敗時 (initNativeBridge() が false) に main() が表示する
// エラー画面。`locale` を注入できるようにした (#55 レビュー S1) ので、実際に
// システムロケールに依存せず ja/en それぞれの文言が出ることと、未対応ロケール
// でのフォールバックを widget test レベルで検証する。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/main.dart';
import 'package:universal_experience/ui/screens/home_screen.dart';

void main() {
  testWidgets('locale: en を渡すと英語の nativeBridgeInitFailed が表示される',
      (WidgetTester tester) async {
    await tester.pumpWidget(const NativeBridgeErrorApp(locale: Locale('en')));
    await tester.pumpAndSettle();

    final en = lookupAppLocalizations(const Locale('en'));
    expect(find.text(en.nativeBridgeInitFailed), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('locale: ja を渡すと日本語の nativeBridgeInitFailed が表示される',
      (WidgetTester tester) async {
    await tester.pumpWidget(const NativeBridgeErrorApp(locale: Locale('ja')));
    await tester.pumpAndSettle();

    final ja = lookupAppLocalizations(const Locale('ja'));
    expect(find.text(ja.nativeBridgeInitFailed), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('locale 未指定 + 未対応システムロケールは先頭のサポート対象言語にフォールバックする',
      (WidgetTester tester) async {
    // fr は AppLocalizations.supportedLocales に無いので、
    // _resolveStartupLocale() は supportedLocales.first (en) にフォールバックする。
    tester.platformDispatcher.localeTestValue = const Locale('fr');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);

    await tester.pumpWidget(const NativeBridgeErrorApp());
    await tester.pumpAndSettle();

    final fallback =
        lookupAppLocalizations(AppLocalizations.supportedLocales.first);
    expect(find.text(fallback.nativeBridgeInitFailed), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
