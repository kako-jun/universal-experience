// i18n 基盤（#18）の配線を自動検証する。
//
// 1. `lib/l10n/app_*.arb` を glob し、全 ARB のキー集合・プレースホルダが基準言語（en）と
//    一致し、ARB の言語が AppLocalizations.supportedLocales と一致する（訳漏れの早期検出。
//    言語を足してもこのテストの改修は要らない）。
// 2. AppLocalizations が対応言語すべてで lookup でき、代表キーが空でない。
// 3. SettingsService.setLocale が往復・永続化し、null でシステム追従に戻る。未対応の
//    言語コードが保存されていたら読み込み時に捨てる（#82）。
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
import 'package:universal_experience/main.dart' show WindowModeUiContext;
import 'package:universal_experience/models/sample_catalog.dart';
import 'package:universal_experience/models/vision_filter_catalog.dart';
import 'package:universal_experience/services/filter_service.dart';
import 'package:universal_experience/services/hotkey_service.dart';
import 'package:universal_experience/services/image_source_state.dart';
import 'package:universal_experience/services/loupe_window_controller.dart';
import 'package:universal_experience/services/settings_service.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/services/vision_filter_metadata.dart';
import 'package:universal_experience/ui/screens/home_screen.dart';
import 'package:universal_experience/ui/widgets/experience_presets.dart';

import 'support/vision_filter_metadata_fixture.dart';

Map<String, dynamic> _readArb(String name) {
  final file = File('lib/l10n/$name');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

/// ARB の翻訳キー（@meta と @@locale を除く）。
Set<String> _messageKeys(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

/// `lib/l10n/app_<言語コード>.arb` を全部読む（言語コード → 中身）。言語を足したとき
/// このテストの改修なしに検査対象へ入るよう、ファイルを glob する。
Map<String, Map<String, dynamic>> _readAllArbs() {
  final result = <String, Map<String, dynamic>>{};
  final pattern = RegExp(r'^app_(.+)\.arb$');
  final files = Directory('lib/l10n')
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where(pattern.hasMatch)
      .toList()
    ..sort();
  for (final name in files) {
    result[pattern.firstMatch(name)!.group(1)!] = _readArb(name);
  }
  return result;
}

/// メッセージ中のプレースホルダ名（`{name}`）。
Set<String> _placeholders(String message) =>
    RegExp(r'\{(\w+)\}').allMatches(message).map((m) => m.group(1)!).toSet();

/// 対応言語すべての AppLocalizations（`AppLocalizations.supportedLocales`）。
List<AppLocalizations> _allLocalizations() => [
      for (final locale in AppLocalizations.supportedLocales)
        lookupAppLocalizations(locale),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ARB 整合性', () {
    // 基準言語は l10n.yaml の template-arb-file（app_en.arb）。
    const templateCode = 'en';

    test('ARB ファイルの言語と AppLocalizations.supportedLocales が一致する', () {
      final arbs = _readAllArbs();
      expect(arbs, contains(templateCode));
      final supported =
          AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet();
      expect(arbs.keys.toSet(), supported,
          reason: 'ARB の言語 = 対応言語（supportedLocales は ARB から生成される）');
      for (final entry in arbs.entries) {
        expect(entry.value['@@locale'], entry.key,
            reason: 'app_${entry.key}.arb の @@locale がファイル名と違う');
      }
    });

    test('全 ARB のキー集合が基準言語（en）と一致する', () {
      final arbs = _readAllArbs();
      final template = _messageKeys(arbs[templateCode]!);
      for (final entry in arbs.entries) {
        if (entry.key == templateCode) continue;
        final keys = _messageKeys(entry.value);
        expect(keys.difference(template), isEmpty,
            reason: '${entry.key} にしかないキー');
        expect(template.difference(keys), isEmpty,
            reason: '${entry.key} の訳漏れ（キーの欠落）');
      }
    });

    test('全 ARB の全メッセージが非空文字列', () {
      for (final entry in _readAllArbs().entries) {
        for (final key in _messageKeys(entry.value)) {
          expect(entry.value[key], isA<String>(), reason: '${entry.key}.$key');
          expect((entry.value[key] as String).trim(), isNotEmpty,
              reason: '${entry.key}.$key');
        }
      }
    });

    test('全 ARB で、基準言語と同じプレースホルダを持つ', () {
      final arbs = _readAllArbs();
      final template = arbs[templateCode]!;
      for (final entry in arbs.entries) {
        if (entry.key == templateCode) continue;
        for (final key in _messageKeys(template)) {
          final translated = entry.value[key];
          if (translated is! String) continue; // 欠落は上のテストが報告する
          expect(
              _placeholders(translated), _placeholders(template[key] as String),
              reason: '${entry.key}.$key のプレースホルダが en と違う');
        }
      }
    });
  });

  group('AppLocalizations lookup', () {
    test('対応言語すべてで代表キーが解決でき空でない', () {
      for (final l10n in _allLocalizations()) {
        expect(l10n.appTitle, isNotEmpty);
        expect(l10n.filterListHeading, isNotEmpty);
        expect(l10n.consultEarly, isNotEmpty);
        expect(l10n.consultEmergency, isNotEmpty);
        expect(l10n.trayQuit, isNotEmpty);
      }
    });

    test('全 catalog id が対応言語すべてでフォールバックなしで名前解決できる', () {
      // フォールバックは id をそのまま返すので、id と異なれば解決済み。これが検出するのは
      // 「id に対応する ARB キーの引き当て漏れ」で、訳が英語のままコピーされている
      // ケースは検出できない（それは翻訳の確認で見る。docs/ADDING_A_LANGUAGE.md）。
      for (final l10n in _allLocalizations()) {
        for (final entry in kVisionFilterCatalog) {
          expect(visionFilterName(l10n, entry.id), isNot(entry.id),
              reason: '${l10n.localeName}.${entry.id}');
        }
      }
    });

    test('全サンプル id が対応言語すべてでフォールバックなしで名前解決できる（#78）', () {
      for (final l10n in _allLocalizations()) {
        for (final entry in kSampleCatalog) {
          // フォールバックは id をそのまま返すので、id と異なれば解決済み。
          expect(sampleImageName(l10n, entry.id), isNot(entry.id),
              reason: '${l10n.localeName}.${entry.id}');
        }
      }
    });

    test(
        '全 catalog param.labelKey / option.labelKey が対応言語すべてでフォールバックなしで'
        '名前解決できる', () {
      // visionParamLabel() のフォールバックは labelKey をそのまま返すので、
      // labelKey と異なれば実翻訳が解決できている（未訳のまま raw key が UI に
      // 出てしまう回帰を検出する）。
      for (final l10n in _allLocalizations()) {
        final lang = l10n.localeName;
        for (final entry in kVisionFilterCatalog) {
          for (final param in entry.parameters) {
            expect(
              visionParamLabel(l10n, param.labelKey),
              isNot(param.labelKey),
              reason: '${entry.id}.${param.name} ($lang)',
            );
            for (final option in param.options) {
              expect(
                visionParamLabel(l10n, option.labelKey),
                isNot(option.labelKey),
                reason: '${entry.id}.${param.name}.${option.value} ($lang)',
              );
            }
          }
        }
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

    test('urgency 由来の受診喚起は none 以外でのみ出る（#76: sensus の Urgency が唯一の正本）',
        () {
      final en = lookupAppLocalizations(const Locale('en'));
      expect(urgencyConsultMessage(en, Urgency.none), isNull);
      expect(urgencyConsultMessage(en, Urgency.earlyConsultation),
          en.consultEarly);
      expect(urgencyConsultMessage(en, Urgency.emergency), en.consultEmergency);
    });

    test('escalation の条件文は訳があれば日本語、なければ英語のまま（#76）', () {
      final en = lookupAppLocalizations(const Locale('en'));
      final ja = lookupAppLocalizations(const Locale('ja'));
      expect(escalationConditionText(en, 'recurrent or severe episodes'),
          en.escalationConditionBppvRecurrentSevere);
      expect(escalationConditionText(ja, 'recurrent or severe episodes'),
          ja.escalationConditionBppvRecurrentSevere);
      // 訳の対応表に無い文字列は英語のままフォールバックする。
      const unknown = 'some future sensus condition not yet translated';
      expect(escalationConditionText(ja, unknown), unknown);
    });

    test(
        'consultDisclaimerShort（PNG 用の短い免責文）は診断ではない旨・医療監修なしの旨・'
        '根拠の三つを含む', () {
      final en = lookupAppLocalizations(const Locale('en'));
      final ja = lookupAppLocalizations(const Locale('ja'));
      expect(en.consultDisclaimerShort, contains('diagnos'));
      expect(en.consultDisclaimerShort, contains('review'));
      expect(en.consultDisclaimerShort, contains('sensus'));
      expect(ja.consultDisclaimerShort, contains('診断'));
      expect(ja.consultDisclaimerShort, contains('監修'));
      expect(ja.consultDisclaimerShort, contains('sensus'));
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

    test('未対応の言語コードが保存されていたら、読み込み時に捨てて自動（null）にする（#82）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        SettingsService.keyLocale: 'xx',
      });
      final settings = SettingsService();
      await settings.load();
      expect(settings.locale, isNull);

      // 対応言語の保存値はそのまま復元される。
      SharedPreferences.setMockInitialValues(<String, Object>{
        SettingsService.keyLocale: 'ja',
      });
      final restored = SettingsService();
      await restored.load();
      expect(restored.locale, const Locale('ja'));
    });
  });

  group('HomeScreen ロケール別描画', () {
    // HomeScreen は体験プリセット集 (#19) が bridge の experiences() を呼ぶ。FFI 未
    // ロードの flutter test では native を叩けないため、fixture で seam を差し替える。
    // VisionFilterState の選択も urgency/recommended_strength（#76/#77）で実
    // ブリッジを要求するため、既定は installVisionFilterMetadataFixture()
    // （urgency=none 一律）にする。urgency を検証するテストだけ個別に上書きする。
    setUp(() {
      installVisionFilterMetadataFixture();
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
    tearDown(() {
      experiencesProvider = experiences;
      resetVisionFilterMetadataProviders();
    });

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
            ChangeNotifierProvider<ImageSourceState>(
                create: (_) => ImageSourceState()),
            ChangeNotifierProvider<LoupeWindowController>(
                create: (_) => LoupeWindowController()),
            Provider<WindowModeUiContext>.value(
              value: const WindowModeUiContext(
                trayAvailable: false,
                hotkeyStatus: HotkeyStatus(),
              ),
            ),
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

    testWidgets('ja では日本語の見出し・空状態・検索欄が出る', (tester) async {
      await pumpHome(tester, const Locale('ja'));
      final ja = lookupAppLocalizations(const Locale('ja'));
      expect(find.text(ja.filterListHeading), findsOneWidget);
      expect(find.text(ja.adjustHeading), findsOneWidget);
      expect(find.text(ja.previewSectionTitle), findsOneWidget);
      expect(find.text(ja.selectionEmptyTitle), findsOneWidget);
      expect(find.text(ja.filterSearchLabel), findsOneWidget);
      // 旧セクション見出し・英語ハードコードが残っていないこと（退行検出）。
      expect(find.text('Color Vision Simulation'), findsNothing);
      expect(find.text('Filter Intensity'), findsNothing);
    });

    testWidgets('en では英語の見出し・空状態・検索欄が出る', (tester) async {
      await pumpHome(tester, const Locale('en'));
      final en = lookupAppLocalizations(const Locale('en'));
      expect(find.text(en.filterListHeading), findsOneWidget);
      expect(find.text(en.adjustHeading), findsOneWidget);
      expect(find.text(en.previewSectionTitle), findsOneWidget);
      expect(find.text(en.selectionEmptyTitle), findsOneWidget);
      expect(find.text(en.filterSearchLabel), findsOneWidget);
      // 旧ハードコードの日本語ヒーローが残っていないこと。
      expect(find.text('すべての感覚を、すべての人に。'), findsNothing);
    });

    testWidgets('emergency urgency フィルタ選択で緊急受診メッセージが出る（#76）', (tester) async {
      // #76: urgency は sensus ブリッジ（fixture）が唯一の正本。ここでは
      // vestibular_neuritis だけ emergency を返すフィクスチャにする
      // （vestibular_neuritis は payload を持たないカタログ id なので
      //  FilterParamPanel 側の VisionFilter インスタンスとも == で一致する）。
      visionFilterUrgencyProvider = (filter) =>
          filter == const VisionFilter.vestibularNeuritis()
              ? Urgency.emergency
              : Urgency.none;

      await pumpHome(tester, const Locale('en'));
      final en = lookupAppLocalizations(const Locale('en'));

      final state =
          tester.element(find.byType(HomeScreen)).read<VisionFilterState>();
      state.select('vestibular_neuritis');
      await tester.pump();

      // 右カラム（AdjustPanel → FilterParamPanel）に緊急受診メッセージが 1 件。
      // #72 で体験プリセットは一覧の行になり、選ぶまで喚起文を出さないので、
      // 選んでいないプリセット（vestibular_neuritis の体験）の分は数えない。
      expect(find.text(en.consultEmergency), findsOneWidget);
    });
  });
}
