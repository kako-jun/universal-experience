// NativeBridgeErrorApp（lib/main.dart、#55）の widget テスト。
//
// Rust ブリッジ初期化失敗時 (initNativeBridge() が false) に main() が表示する
// エラー画面。`locale` を注入できるようにした (#55) ので、実際に
// システムロケールに依存せず ja/en それぞれの文言が出ることと、未対応ロケール
// でのフォールバックを widget test レベルで検証する。
//
// `resolveSupportedLocale` が `WidgetsBinding.instance.platformDispatcher.locales`
// 経由で読むので、`tester.platformDispatcher` への `localesTestValue` 差し替えが実際に効く。下の「サポート対象ロケールへの
// 差し替えが効く」テストは、この配線が壊れて元の `PlatformDispatcher.instance`
// を直接読むようになった場合に en (実フォールバック) が出て落ちる mutation-testing
// 用の証拠テスト。

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
    // resolveSupportedLocale は supportedLocales.first (en) にフォールバックする。
    tester.platformDispatcher.localeTestValue = const Locale('fr');
    tester.platformDispatcher.localesTestValue = const [Locale('fr')];
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(const NativeBridgeErrorApp());
    await tester.pumpAndSettle();

    final fallback =
        lookupAppLocalizations(AppLocalizations.supportedLocales.first);
    expect(find.text(fallback.nativeBridgeInitFailed), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'locale 未指定 + サポート対象システムロケール(ja)への localeTestValue 差し替えが効く',
      (WidgetTester tester) async {
    // fr のテストはフォールバック先 (en) と実システムロケールが偶然一致しうるため、
    // それだけでは localeTestValue が本当に読まれているか証明できない。ここでは
    // フォールバックと衝突しないサポート対象ロケール ja を指定し、実際に ja の
    // 文言が出ることを確認する。もし resolveSupportedLocale が
    // WidgetsBinding.instance.platformDispatcher ではなく実 PlatformDispatcher.instance
    // を直接読むよう退行すれば、ここは ja ではなく実フォールバック (en) になり失敗する。
    tester.platformDispatcher.localeTestValue = const Locale('ja');
    tester.platformDispatcher.localesTestValue = const [Locale('ja')];
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(const NativeBridgeErrorApp());
    await tester.pumpAndSettle();

    final ja = lookupAppLocalizations(const Locale('ja'));
    expect(find.text(ja.nativeBridgeInitFailed), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('表示中に OS の言語が変わると、エラー画面の文言も追従する',
      (WidgetTester tester) async {
    tester.platformDispatcher.localeTestValue = const Locale('ja');
    tester.platformDispatcher.localesTestValue = const [Locale('ja')];
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(const NativeBridgeErrorApp());
    await tester.pumpAndSettle();
    final ja = lookupAppLocalizations(const Locale('ja'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(find.text(ja.nativeBridgeInitFailed), findsOneWidget);

    // [fr, en]: fr は未対応なので、次の候補 en になる。
    tester.platformDispatcher.localeTestValue = const Locale('fr');
    tester.platformDispatcher.localesTestValue = const [
      Locale('fr'),
      Locale('en'),
    ];
    await tester.pumpAndSettle();
    expect(find.text(en.nativeBridgeInitFailed), findsOneWidget);
    expect(find.text(ja.nativeBridgeInitFailed), findsNothing);
  });

  testWidgets('OS の言語リストが空なら en になる', (WidgetTester tester) async {
    tester.platformDispatcher.localeTestValue = const Locale('xx');
    tester.platformDispatcher.localesTestValue = const [];
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(const NativeBridgeErrorApp());
    await tester.pumpAndSettle();
    final en = lookupAppLocalizations(const Locale('en'));
    expect(find.text(en.nativeBridgeInitFailed), findsOneWidget);
  });
}
