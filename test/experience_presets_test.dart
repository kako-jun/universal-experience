// 体験プリセット集 (#19) の widget test。
//
// 検証:
// 1. 4 プリセットが i18n 名で描画される。
// 2. タップで VisionFilterState.selectedId が対応 catalog id になる
//    （meniere→vertigo / bppv→bppv_rotation）。色覚 FilterService は none に戻る。
// 3. urgency=emergency（vestibular_neuritis）で緊急受診、earlyConsultation（meniere）
//    で早期受診メッセージ、none（bppv）では受診喚起が出ない。
// 4. hearing を含む体験（meniere/labyrinthitis）で「聴覚も含む」注記が出る。
//
// bridge の experiences() は native lib（FFI）を要求し flutter test では呼べないため、
// experiencesProvider seam を fixture で差し替える（音声再生は #19 非スコープ）。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/services/filter_service.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/widgets/experience_presets.dart';

/// テスト用の 4 体験 fixture（sensus の experiences() と同じ id / vision / hearing /
/// urgency）。実 bridge は native を要求するため fixture で代替する。
List<Experience> _fixtureExperiences() => const [
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

void main() {
  late VisionFilterState visionState;
  late FilterService filterService;

  setUp(() {
    experiencesProvider = _fixtureExperiences;
    visionState = VisionFilterState();
    filterService = FilterService();
  });
  tearDown(() => experiencesProvider = experiences);

  Future<void> pumpPresets(WidgetTester tester, Locale locale) async {
    // ListView 内の全カードが lazy build されるよう十分高いビューポートにする。
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<VisionFilterState>.value(value: visionState),
          ChangeNotifierProvider<FilterService>.value(value: filterService),
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
          home: const Scaffold(
            body: SingleChildScrollView(child: ExperiencePresets()),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('4 プリセットが i18n 名で描画される', (tester) async {
    await pumpPresets(tester, const Locale('en'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(find.text(en.experienceMeniere), findsOneWidget);
    expect(find.text(en.experienceBppv), findsOneWidget);
    expect(find.text(en.experienceVestibularNeuritis), findsOneWidget);
    expect(find.text(en.experienceLabyrinthitis), findsOneWidget);
  });

  testWidgets('ja でも日本語の体験名が出る', (tester) async {
    await pumpPresets(tester, const Locale('ja'));
    final ja = lookupAppLocalizations(const Locale('ja'));
    expect(find.text(ja.experienceMeniere), findsOneWidget); // メニエール病
    expect(find.text(ja.experienceVestibularNeuritis), findsOneWidget); // 前庭神経炎
  });

  testWidgets('meniere タップで vision=vertigo を選択し色覚は none に戻る', (tester) async {
    await pumpPresets(tester, const Locale('en'));
    final en = lookupAppLocalizations(const Locale('en'));

    // 事前に色覚フィルタを有効化しておき、適用で解除されることを確認する。
    filterService.applyFilter(ColorVisionType.protanopia);
    expect(filterService.currentFilter, ColorVisionType.protanopia);

    await tester.tap(find.text(en.experienceMeniere));
    await tester.pump();

    expect(visionState.selectedId, 'vertigo');
    expect(filterService.currentFilter, ColorVisionType.none);
  });

  testWidgets('bppv タップで vision=bppv_rotation を選択する', (tester) async {
    await pumpPresets(tester, const Locale('en'));
    final en = lookupAppLocalizations(const Locale('en'));

    await tester.tap(find.text(en.experienceBppv));
    await tester.pump();

    expect(visionState.selectedId, 'bppv_rotation');
  });

  testWidgets('vestibular_neuritis は緊急受診メッセージを出す', (tester) async {
    await pumpPresets(tester, const Locale('en'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(find.text(en.consultEmergency), findsOneWidget);
  });

  testWidgets('meniere は早期受診メッセージを出す', (tester) async {
    await pumpPresets(tester, const Locale('en'));
    final en = lookupAppLocalizations(const Locale('en'));
    // meniere / labyrinthitis の 2 体験が earlyConsultation。
    expect(find.text(en.consultEarly), findsNWidgets(2));
  });

  testWidgets('bppv（urgency none）は受診喚起を出さない', (tester) async {
    // bppv だけを供給し、受診喚起が一切出ないことを確認する。
    experiencesProvider = () => const [
          Experience(
            id: 'bppv',
            vision: VisionFilter.bppvRotation(),
            urgency: Urgency.none,
          ),
        ];
    await pumpPresets(tester, const Locale('en'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(find.text(en.consultEarly), findsNothing);
    expect(find.text(en.consultEmergency), findsNothing);
  });

  testWidgets('聴覚を含む体験（meniere/labyrinthitis）で聴覚注記が出る', (tester) async {
    await pumpPresets(tester, const Locale('en'));
    final en = lookupAppLocalizations(const Locale('en'));
    // meniere と labyrinthitis の 2 体験が hearing を持つ → 注記 2 件。
    expect(find.text(en.experienceIncludesHearingNote), findsNWidgets(2));
  });

  testWidgets('聴覚を含まない体験（bppv 単独）では聴覚注記が出ない', (tester) async {
    experiencesProvider = () => const [
          Experience(
            id: 'bppv',
            vision: VisionFilter.bppvRotation(),
            urgency: Urgency.none,
          ),
        ];
    await pumpPresets(tester, const Locale('en'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(find.text(en.experienceIncludesHearingNote), findsNothing);
  });
}
