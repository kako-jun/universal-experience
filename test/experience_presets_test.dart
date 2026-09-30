// 体験プリセット (#19) の widget test。#72 で「プリセット欄のカード」から
// 「統合フィルタ一覧の最上段の行 + 右カラムの調整パネル」へ移った。
//
// 検証:
// 1. 4 プリセットが i18n 名で一覧に描画される。
// 2. タップで VisionFilterState.selectedId が対応 catalog id・selectedPresetId が
//    experience id になる（meniere→vertigo / bppv→bppv_rotation）。色覚
//    FilterService は変更しない（#60: deactivate() は呼ばない）。
// 3. 選んだあと右カラムに、urgency=emergency（vestibular_neuritis）で緊急受診、
//    earlyConsultation（meniere）で早期受診メッセージ、none（bppv）では受診喚起が
//    出ない。選ぶまでは何も出ない。
// 4. hearing を含む体験（meniere/labyrinthitis）で「聴覚も含む」注記が右カラムに出る。
// 5. meniere と labyrinthitis はどちらもカタログ id vertigo に写るが、
//    selectedPresetId による比較で選んだ方だけが点灯する（#60）。
// 6. escalation は Experience.vision（visionFilterUrgencyEscalationProvider）
//    から取得し、ConsultNoticeBlock（FilterParamPanel・export と共有）で
//    表示する（#76 レビュー S3）。
// 7. 免責文・根拠 URL は喚起があるときだけ、右カラムの強度の下に 1 回出る。
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
import 'package:universal_experience/services/vision_filter_metadata.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/widgets/adjust_panel.dart';
import 'package:universal_experience/ui/widgets/experience_presets.dart';
import 'package:universal_experience/ui/widgets/filter_browser.dart';

import 'support/vision_filter_metadata_fixture.dart';

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
  late FilterBrowserController browser;

  setUp(() {
    browser = FilterBrowserController();
    experiencesProvider = _fixtureExperiences;
    installVisionFilterMetadataFixture();
    visionState = VisionFilterState();
    filterService = FilterService();
  });
  tearDown(() {
    browser.dispose();
    experiencesProvider = experiences;
    resetVisionFilterMetadataProviders();
  });

  Future<void> pumpPresets(WidgetTester tester, Locale locale) async {
    // 左の一覧・右の調整パネルが両方収まる十分大きなビューポートにする。
    tester.view.physicalSize = const Size(1200, 2000);
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
          home: Scaffold(
            body: Row(
              children: [
                SizedBox(width: 380, child: FilterBrowser(controller: browser)),
                const Expanded(
                  child: SingleChildScrollView(child: AdjustPanel()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// 体験プリセットの行の中にあるテキスト。advanced カタログにも同名の行
  /// （例: Vestibular neuritis）があるため、プリセットの行の中だけを探す。
  Finder inPresetRow(String experienceId, String text) => find.descendant(
        of: find.byKey(experienceCardKey(experienceId)),
        matching: find.text(text),
      );

  testWidgets('4 プリセットが i18n 名で描画される', (tester) async {
    await pumpPresets(tester, const Locale('en'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(inPresetRow('meniere', en.experienceMeniere), findsOneWidget);
    expect(inPresetRow('bppv', en.experienceBppv), findsOneWidget);
    expect(inPresetRow('vestibular_neuritis', en.experienceVestibularNeuritis),
        findsOneWidget);
    expect(inPresetRow('labyrinthitis', en.experienceLabyrinthitis),
        findsOneWidget);
  });

  testWidgets('ja でも日本語の体験名が出る', (tester) async {
    await pumpPresets(tester, const Locale('ja'));
    final ja = lookupAppLocalizations(const Locale('ja'));
    expect(inPresetRow('meniere', ja.experienceMeniere), findsOneWidget);
    expect(inPresetRow('vestibular_neuritis', ja.experienceVestibularNeuritis),
        findsOneWidget);
  });

  testWidgets(
      'meniere タップで vision=vertigo・selectedPresetId=meniere を選択する'
      '（色覚 FilterService は変更しない、#60）', (tester) async {
    await pumpPresets(tester, const Locale('en'));

    // 事前に色覚フィルタを有効化しておく。プリセット適用で解除されないことを
    // 確認する（#60: FilterService.deactivate() は呼ばない）。
    filterService.applyFilter(ColorVisionType.protanopia);
    expect(filterService.currentFilter, ColorVisionType.protanopia);

    await tester.tap(find.byKey(experienceCardKey('meniere')));
    await tester.pump();

    expect(visionState.selectedId, 'vertigo');
    expect(visionState.selectedPresetId, 'meniere');
    expect(visionState.isColorQuickSelection, isFalse);
    expect(filterService.currentFilter, ColorVisionType.protanopia,
        reason: 'プリセット適用は色覚クイック選択の状態に干渉しない');
  });

  testWidgets('bppv タップで vision=bppv_rotation・selectedPresetId=bppv を選択する',
      (tester) async {
    await pumpPresets(tester, const Locale('en'));

    await tester.tap(find.byKey(experienceCardKey('bppv')));
    await tester.pump();

    expect(visionState.selectedId, 'bppv_rotation');
    expect(visionState.selectedPresetId, 'bppv');
  });

  testWidgets(
      'meniere と labyrinthitis は同じ catalog id (vertigo) だが、選んだ方だけが '
      '点灯する（#60: 2 行同時点灯バグの修正）', (tester) async {
    await pumpPresets(tester, const Locale('en'));

    // 何も選んでいない間はどの行にもチェックが付かない。
    expect(find.byIcon(Icons.check), findsNothing);

    await tester.tap(find.byKey(experienceCardKey('meniere')));
    await tester.pump();

    expect(visionState.selectedPresetId, 'meniere');
    // meniere の行だけにチェックマークが付き、labyrinthitis には付かない。
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(experienceCardKey('meniere')),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(experienceCardKey('labyrinthitis')));
    await tester.pump();

    expect(visionState.selectedId, 'vertigo');
    expect(visionState.selectedPresetId, 'labyrinthitis');
    expect(find.byIcon(Icons.check), findsOneWidget,
        reason: '切り替え後も点灯するのは 1 行だけであるべき');
    expect(
      find.descendant(
        of: find.byKey(experienceCardKey('labyrinthitis')),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
  });

  testWidgets('選ぶまでは受診喚起も聴覚注記も出さない（一覧の行には出さない）', (tester) async {
    await pumpPresets(tester, const Locale('en'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(find.text(en.consultEmergency), findsNothing);
    expect(find.text(en.consultEarly), findsNothing);
    expect(find.text(en.consultDisclaimer), findsNothing);
    expect(find.text(en.experienceIncludesHearingNote), findsNothing);
    expect(find.text(en.selectionEmptyTitle), findsOneWidget);
  });

  testWidgets('vestibular_neuritis を選ぶと右カラムに緊急受診メッセージが出る', (tester) async {
    await pumpPresets(tester, const Locale('en'));
    final en = lookupAppLocalizations(const Locale('en'));

    await tester.tap(find.byKey(experienceCardKey('vestibular_neuritis')));
    await tester.pump();

    expect(find.text(en.consultEmergency), findsOneWidget);
    expect(find.text(en.consultEarly), findsNothing);
  });

  testWidgets('meniere を選ぶと早期受診メッセージが出る', (tester) async {
    await pumpPresets(tester, const Locale('en'));
    final en = lookupAppLocalizations(const Locale('en'));

    await tester.tap(find.byKey(experienceCardKey('meniere')));
    await tester.pump();

    expect(find.text(en.consultEarly), findsOneWidget);
    expect(find.text(en.consultEmergency), findsNothing);
  });

  testWidgets('bppv（urgency none）は受診喚起を出さない', (tester) async {
    await pumpPresets(tester, const Locale('en'));
    final en = lookupAppLocalizations(const Locale('en'));

    await tester.tap(find.byKey(experienceCardKey('bppv')));
    await tester.pump();

    expect(find.text(en.consultEarly), findsNothing);
    expect(find.text(en.consultEmergency), findsNothing);
  });

  testWidgets('聴覚を含む体験（meniere/labyrinthitis）を選ぶと聴覚注記が出る', (tester) async {
    await pumpPresets(tester, const Locale('en'));
    final en = lookupAppLocalizations(const Locale('en'));

    await tester.tap(find.byKey(experienceCardKey('meniere')));
    await tester.pump();
    expect(find.text(en.experienceIncludesHearingNote), findsOneWidget);

    await tester.tap(find.byKey(experienceCardKey('labyrinthitis')));
    await tester.pump();
    expect(find.text(en.experienceIncludesHearingNote), findsOneWidget);
  });

  testWidgets('聴覚を含まない体験（bppv）を選んでも聴覚注記は出ない', (tester) async {
    await pumpPresets(tester, const Locale('en'));
    final en = lookupAppLocalizations(const Locale('en'));

    await tester.tap(find.byKey(experienceCardKey('bppv')));
    await tester.pump();

    expect(find.text(en.experienceIncludesHearingNote), findsNothing);
  });

  testWidgets(
      '体験の説明文は選んだあと右カラムに出る（一覧の行には出ない）', (tester) async {
    await pumpPresets(tester, const Locale('en'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(find.text(en.experienceBppvDesc), findsNothing);

    await tester.tap(find.byKey(experienceCardKey('bppv')));
    await tester.pump();

    expect(find.text(en.experienceBppvDesc), findsOneWidget);
  });

  testWidgets(
      'escalation は Experience.vision から取得し、ConsultNoticeBlock で表示する'
      '（#76 レビュー S3）', (tester) async {
    // urgency=none の bppv でも、Experience.vision（bppvRotation）に対する
    // escalation フィクスチャがあれば ConsultNoticeBlock の escalation ブロックが
    // 出ることを確認する（喚起文そのものは urgency=none のため出ない）。
    visionFilterUrgencyEscalationProvider = (filter) =>
        filter == const VisionFilter.bppvRotation()
            ? const [
                UrgencyEscalation(
                  urgency: Urgency.earlyConsultation,
                  condition: 'recurrent or severe episodes',
                ),
              ]
            : const [];
    experiencesProvider = () => const [
          Experience(
            id: 'bppv',
            vision: VisionFilter.bppvRotation(),
            urgency: Urgency.none,
          ),
        ];
    await pumpPresets(tester, const Locale('en'));
    final en = lookupAppLocalizations(const Locale('en'));

    await tester.tap(find.byKey(experienceCardKey('bppv')));
    await tester.pump();

    expect(find.text(en.consultEarly), findsNothing);
    expect(find.text(en.escalationHeaderEarly), findsOneWidget);
    expect(
      find.textContaining(en.escalationConditionBppvRecurrentSevere),
      findsOneWidget,
    );
  });

  testWidgets(
      '免責文・根拠 URL は喚起があるときだけ、右カラムの強度の下に 1 回出る'
      '（#76 再レビュー nit、#72）', (tester) async {
    await pumpPresets(tester, const Locale('en'));
    final en = lookupAppLocalizations(const Locale('en'));

    await tester.tap(find.byKey(experienceCardKey('vestibular_neuritis')));
    await tester.pump();

    expect(find.text(en.consultDisclaimer), findsOneWidget);
    expect(find.textContaining('sensus/blob/main/docs/overview.md'),
        findsOneWidget);
    expect(find.text(en.consultEmergency), findsOneWidget);
  });

  testWidgets('喚起が無い体験だけなら免責文も出ない（#76 再レビュー nit）', (tester) async {
    experiencesProvider = () => const [
          Experience(
            id: 'bppv',
            vision: VisionFilter.bppvRotation(),
            urgency: Urgency.none,
          ),
        ];
    await pumpPresets(tester, const Locale('en'));
    final en = lookupAppLocalizations(const Locale('en'));

    await tester.tap(find.byKey(experienceCardKey('bppv')));
    await tester.pump();

    expect(find.text(en.consultDisclaimer), findsNothing);
  });
}
