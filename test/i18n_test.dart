// i18n 基盤（#18）の配線を自動検証する。
//
// 1. ARB の en/ja でキー集合が一致する（訳漏れの早期検出）。
// 2. AppLocalizations が en/ja の両方で lookup でき、代表キーが空でない。
// 3. SettingsService.setLocale が往復・永続化し、null でシステム追従に戻る。
// 4. HomeScreen を ja / en で pump し、ロケールごとに正しい文言が出る
//    （受診喚起メッセージ含む）。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/l10n/l10n_extensions.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/models/vision_filter_catalog.dart';
import 'package:universal_experience/services/filter_service.dart';
import 'package:universal_experience/services/settings_service.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/screens/home_screen.dart';
import 'package:universal_experience/ui/widgets/experience_presets.dart';

Map<String, dynamic> _readArb(String name) {
  final file = File('lib/l10n/$name');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

/// ARB の翻訳キー（@meta と @@locale を除く）。
Set<String> _messageKeys(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ARB 整合性', () {
    test('en と ja のキー集合が一致する', () {
      final en = _messageKeys(_readArb('app_en.arb'));
      final ja = _messageKeys(_readArb('app_ja.arb'));
      expect(ja.difference(en), isEmpty, reason: 'ja にしかないキー');
      expect(en.difference(ja), isEmpty, reason: 'en にしかないキー（ja 訳漏れ）');
    });

    test('ja の全メッセージが非空文字列', () {
      final ja = _readArb('app_ja.arb');
      for (final key in _messageKeys(ja)) {
        expect(ja[key], isA<String>(), reason: key);
        expect((ja[key] as String).trim(), isNotEmpty, reason: key);
      }
    });
  });

  group('AppLocalizations lookup', () {
    test('en/ja とも代表キーが解決でき空でない', () {
      for (final l10n in [
        lookupAppLocalizations(const Locale('en')),
        lookupAppLocalizations(const Locale('ja')),
      ]) {
        expect(l10n.appTitle, isNotEmpty);
        expect(l10n.colorVisionSectionTitle, isNotEmpty);
        expect(l10n.consultEarly, isNotEmpty);
        expect(l10n.consultEmergency, isNotEmpty);
        expect(l10n.trayQuit, isNotEmpty);
      }
    });

    test('全 catalog id がフォールバックなしで名前解決できる', () {
      final en = lookupAppLocalizations(const Locale('en'));
      for (final entry in kVisionFilterCatalog) {
        // フォールバックは id をそのまま返すので、id と異なれば解決済み。
        expect(visionFilterName(en, entry.id), isNot(entry.id),
            reason: entry.id);
      }
    });

    test('全 ColorVisionType の有病率が i18n 解決でき、ja に英語が混入しない', () {
      final en = lookupAppLocalizations(const Locale('en'));
      final ja = lookupAppLocalizations(const Locale('ja'));
      for (final type in ColorVisionType.values) {
        final enText = colorVisionTypePrevalence(en, type);
        final jaText = colorVisionTypePrevalence(ja, type);
        expect(enText.trim(), isNotEmpty, reason: '$type (en)');
        expect(jaText.trim(), isNotEmpty, reason: '$type (ja)');
        // ja の有病率行に英語の "of males/females" が混入していないこと（退行検出）。
        expect(jaText.toLowerCase(), isNot(contains('of males')),
            reason: '$type の ja に英語が混入');
        expect(jaText.toLowerCase(), isNot(contains('of females')),
            reason: '$type の ja に英語が混入');
      }
      // 代表ケース: deuteranomaly の ja 訳が日本語であること。
      expect(colorVisionTypePrevalence(ja, ColorVisionType.deuteranomaly),
          contains('男性'));
    });

    test('urgency 由来の受診喚起は medium/high のみ出る', () {
      final en = lookupAppLocalizations(const Locale('en'));
      expect(consultMessageForUrgency(en, VisionFilterUrgency.none), isNull);
      expect(consultMessageForUrgency(en, VisionFilterUrgency.low), isNull);
      expect(consultMessageForUrgency(en, VisionFilterUrgency.medium),
          en.consultEarly);
      expect(consultMessageForUrgency(en, VisionFilterUrgency.high),
          en.consultEmergency);
    });
  });

  group('SettingsService.locale', () {
    test('setLocale が往復・永続化し、null でクリアする', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final a = SettingsService();
      await a.load();
      expect(a.locale, isNull, reason: '既定はシステム追従(null)');

      await a.setLocale(const Locale('ja'));
      expect(a.locale, const Locale('ja'));

      // 別インスタンスで復元されること。
      final b = SettingsService();
      await b.load();
      expect(b.locale, const Locale('ja'));

      await b.setLocale(null);
      expect(b.locale, isNull);
      final c = SettingsService();
      await c.load();
      expect(c.locale, isNull);
    });
  });

  group('HomeScreen ロケール別描画', () {
    // HomeScreen は体験プリセット集 (#19) が bridge の experiences() を呼ぶ。FFI 未
    // ロードの flutter test では native を叩けないため、fixture で seam を差し替える。
    setUp(() {
      experiencesProvider = () => const [
            Experience(
              id: 'meniere',
              vision: VisionFilter.vertigo(),
              hearing: HearingFilter.meniere(),
              urgency: Urgency.earlyConsultation,
            ),
            Experience(
              id: 'bppv',
              vision: VisionFilter.bppvRotation(),
              urgency: Urgency.none,
            ),
            Experience(
              id: 'vestibular_neuritis',
              vision: VisionFilter.vestibularNeuritis(),
              urgency: Urgency.emergency,
            ),
            Experience(
              id: 'labyrinthitis',
              vision: VisionFilter.vertigo(),
              hearing: HearingFilter.labyrinthitis(),
              urgency: Urgency.earlyConsultation,
            ),
          ];
    });
    tearDown(() => experiencesProvider = experiences);

    Future<void> pumpHome(WidgetTester tester, Locale locale) async {
      // HomeScreen は ListView で縦に長いため、全セクションが lazy build されるよう
      // 十分に高いビューポートにする（小さいと下のセクションが未生成で見つからない）。
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final settings = SettingsService();
      await settings.load();
      await settings.setLocale(locale);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsService>.value(value: settings),
            ChangeNotifierProvider<FilterService>(
                create: (_) => FilterService()),
            ChangeNotifierProvider<VisionFilterState>(
                create: (_) => VisionFilterState()),
          ],
          child: MaterialApp(
            locale: locale,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('ja では日本語のセクション見出しが出る', (tester) async {
      await pumpHome(tester, const Locale('ja'));
      final ja = lookupAppLocalizations(const Locale('ja'));
      expect(find.text(ja.colorVisionSectionTitle), findsOneWidget);
      expect(find.text(ja.intensitySectionTitle), findsOneWidget);
      // 既存の英語ハードコードが残っていないこと（退行検出）。
      expect(find.text('Color Vision Simulation'), findsNothing);
      expect(find.text('Filter Intensity'), findsNothing);
    });

    testWidgets('en では英語のセクション見出しが出る', (tester) async {
      await pumpHome(tester, const Locale('en'));
      final en = lookupAppLocalizations(const Locale('en'));
      expect(find.text(en.colorVisionSectionTitle), findsOneWidget);
      expect(find.text(en.intensitySectionTitle), findsOneWidget);
      // 旧ハードコードの日本語ヒーローが残っていないこと。
      expect(find.text('すべての感覚を、すべての人に。'), findsNothing);
    });

    testWidgets('high urgency フィルタ選択で緊急受診メッセージが出る', (tester) async {
      await pumpHome(tester, const Locale('en'));
      final en = lookupAppLocalizations(const Locale('en'));

      // glaucoma は urgency.high。Advanced カタログから選択する。
      final state =
          tester.element(find.byType(HomeScreen)).read<VisionFilterState>();
      state.select('glaucoma');
      await tester.pump();

      // glaucoma 選択で param panel に緊急受診メッセージが 1 件。加えて体験プリセット
      // 集 (#19) の vestibular_neuritis（emergency）が常時同じメッセージを表示するため
      // 厳密に計 2 件。プリセットが落ちたら 1 件になり検出できる（exact count）。
      expect(find.text(en.consultEmergency), findsNWidgets(2));
    });
  });
}
