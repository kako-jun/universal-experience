// HomeScreen のプレビュー（_buildPreviewSection の Consumer2<VisionFilterState,
// FilterService> → BeforeAfterView）が、advanced カタログ（VisionFilterState）の
// 選択・パラメータ変更に追従することの回帰テスト（#60）。
//
// #60 修正の要点は「プレビューの描画対象を VisionFilterState の現在の選択
// （VisionFilter + payload + strength）に一本化する」こと。advanced カタログの
// 選択（FilterCatalogSelector が呼ぶ `VisionFilterState.select`）が
// BeforeAfterView.filter/filterId に反映されること、payload の変更
// （FilterParamPanel が呼ぶ `VisionFilterState.setParam`）が新しい filter
// インスタンス（payload 込みの値等価）として反映されることを確認する。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/l10n/l10n_extensions.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/main.dart' show WindowModeUiContext;
import 'package:universal_experience/services/color_vision_selection.dart';
import 'package:universal_experience/services/filter_service.dart';
import 'package:universal_experience/services/hotkey_service.dart';
import 'package:universal_experience/services/loupe_window_controller.dart';
import 'package:universal_experience/services/settings_service.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/screens/home_screen.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';
import 'package:universal_experience/ui/widgets/experience_presets.dart';
import 'package:universal_experience/ui/widgets/filter_selector.dart';

import 'support/vision_filter_metadata_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ExperiencePresets は実 FRB ブリッジ（experiences()）を要求し、プレーンな
  // `flutter test` では呼べない。widget test 用の fixture に差し替える
  // （i18n_test.dart / home_screen_preview_intensity_test.dart と同じ手法）。
  // VisionFilterState の選択も同様に urgency/recommended_strength（#76/#77）で
  // 実ブリッジを要求するため、同じフィクスチャで差し替える。
  setUp(() {
    experiencesProvider = () => const [];
    installVisionFilterMetadataFixture();
  });
  tearDown(() {
    experiencesProvider = experiences;
    resetVisionFilterMetadataProviders();
  });

  testWidgets(
      'advanced カタログでフィルタを選ぶと、プレビューの filter/filterId が追従する（#60）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = SettingsService();
    await settings.load();
    final filterService = FilterService();
    final visionState = VisionFilterState();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<FilterService>.value(value: filterService),
          ChangeNotifierProvider<VisionFilterState>.value(value: visionState),
          ChangeNotifierProvider<LoupeWindowController>.value(
            value: LoupeWindowController(),
          ),
          Provider<WindowModeUiContext>.value(
            value: const WindowModeUiContext(
              trayAvailable: false,
              hotkeyStatus: HotkeyStatus(),
            ),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(),
        ),
      ),
    );
    await tester.pump();

    BeforeAfterView currentPreview() =>
        tester.widget<BeforeAfterView>(find.byType(BeforeAfterView));

    // 初期状態: 何も選択していないので filter/filterId は null。
    expect(currentPreview().filter, isNull);
    expect(currentPreview().filterId, isNull);

    // advanced カタログから starbursts を選択する（FilterCatalogSelector の
    // onSelected と同じ呼び出し）。
    visionState.select('starbursts');
    await tester.pump();

    expect(currentPreview().filterId, 'starbursts');
    expect(currentPreview().filter, isNotNull);
    expect(currentPreview().strength, visionState.strength,
        reason: 'advanced 選択は色覚クイック選択ではないので、strength は '
            'VisionFilterState.strength を使うべき（previewStrength の判定）');

    final filterBeforeParamChange = currentPreview().filter;

    // starbursts の numRays パラメータを変える → payload 込みで新しい
    // VisionFilter インスタンス（値は異なるが == で比較可能）になり、
    // BeforeAfterView.filter も追従するべき。
    visionState.setParam('numRays', 4);
    await tester.pump();

    expect(currentPreview().filter, isNot(equals(filterBeforeParamChange)),
        reason: 'payload の変更は filter の値等価性に反映され、再描画のトリガーになるべき');
  });

  testWidgets(
      'VisionFilterState.setStrength のあと、プレビューの strength が追従する（#60）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = SettingsService();
    await settings.load();
    final filterService = FilterService();
    final visionState = VisionFilterState()..select('cataract');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<FilterService>.value(value: filterService),
          ChangeNotifierProvider<VisionFilterState>.value(value: visionState),
          ChangeNotifierProvider<LoupeWindowController>.value(
            value: LoupeWindowController(),
          ),
          Provider<WindowModeUiContext>.value(
            value: const WindowModeUiContext(
              trayAvailable: false,
              hotkeyStatus: HotkeyStatus(),
            ),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(),
        ),
      ),
    );
    await tester.pump();

    BeforeAfterView currentPreview() =>
        tester.widget<BeforeAfterView>(find.byType(BeforeAfterView));

    expect(currentPreview().strength, 1.0);

    visionState.setStrength(0.42);
    await tester.pump();

    expect(currentPreview().strength, 0.42);
  });

  testWidgets(
      '色覚クイック選択 → advanced → 別の色覚クイック選択、と切り替えても '
      '#57 のタイプ別強度記憶は壊れない（#60）', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = SettingsService();
    await settings.load();
    final filterService = FilterService();
    final visionState = VisionFilterState();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<FilterService>.value(value: filterService),
          ChangeNotifierProvider<VisionFilterState>.value(value: visionState),
          ChangeNotifierProvider<LoupeWindowController>.value(
            value: LoupeWindowController(),
          ),
          Provider<WindowModeUiContext>.value(
            value: const WindowModeUiContext(
              trayAvailable: false,
              hotkeyStatus: HotkeyStatus(),
            ),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(),
        ),
      ),
    );
    await tester.pump();

    BeforeAfterView currentPreview() =>
        tester.widget<BeforeAfterView>(find.byType(BeforeAfterView));

    // 1. protanomaly を色覚クイック選択で選び、強度を独自の値に変える
    //    （#57 のタイプ別記憶）。selectColorVision は FilterSelector・トレイ
    //    共通の入口（#60）。
    selectColorVision(filterService, visionState, ColorVisionType.protanomaly);
    await tester.pump();
    expect(visionState.isColorQuickSelection, isTrue);
    expect(currentPreview().strength, filterService.intensity);
    filterService.setIntensity(0.25);
    await tester.pump();
    expect(currentPreview().strength, 0.25);

    // 2. advanced（starbursts）へ切り替える。色覚クイック選択の記憶
    //    （FilterService 側）には触れない。
    visionState.select('starbursts');
    await tester.pump();
    expect(visionState.isColorQuickSelection, isFalse);
    expect(currentPreview().filterId, 'starbursts');
    expect(currentPreview().strength, visionState.strength);

    // 3. 別の色覚クイック選択（deuteranomaly）に切り替える。プレビューは
    //    deuteranomaly の色覚フィルタに戻り、protanomaly で覚えた強度
    //    （0.25）はそのまま残っている（#57 の記憶がここで巻き戻らない）はず。
    selectColorVision(filterService, visionState, ColorVisionType.deuteranomaly);
    await tester.pump();
    expect(visionState.isColorQuickSelection, isTrue);
    expect(currentPreview().filterId, 'deuteranopia');
    expect(currentPreview().strength, filterService.intensity);
    // deuteranomaly は初めて選んだので recommendedStrength（anomaly 既定値）。
    expect(currentPreview().strength, kAnomalyDefaultSeverity);

    // 4. protanomaly に戻ると、advanced を経由しても 0.25 の記憶は壊れていない。
    selectColorVision(filterService, visionState, ColorVisionType.protanomaly);
    await tester.pump();
    expect(currentPreview().strength, 0.25);

    await filterService.flush();
  });

  testWidgets(
      'protanopia → プリセット → protanopia に戻すと、プレビューに反映されチップも正しく点灯する '
      '（#60 回帰テスト）', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // meniere（vision=vertigo）を含む fixture に差し替える（実ブリッジ不要）。
    experiencesProvider = () => const [
          Experience(
            id: 'meniere',
            vision: VisionFilter.vertigo(),
            urgency: Urgency.earlyConsultation,
          ),
        ];

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = SettingsService();
    await settings.load();
    final filterService = FilterService();
    final visionState = VisionFilterState();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<FilterService>.value(value: filterService),
          ChangeNotifierProvider<VisionFilterState>.value(value: visionState),
          ChangeNotifierProvider<LoupeWindowController>.value(
            value: LoupeWindowController(),
          ),
          Provider<WindowModeUiContext>.value(
            value: const WindowModeUiContext(
              trayAvailable: false,
              hotkeyStatus: HotkeyStatus(),
            ),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(),
        ),
      ),
    );
    await tester.pump();

    final en = lookupAppLocalizations(const Locale('en'));
    BeforeAfterView currentPreview() =>
        tester.widget<BeforeAfterView>(find.byType(BeforeAfterView));
    // advanced カタログ（FilterCatalogSelector）にも "Protanopia" チップが
    // あるため、FilterSelector（色覚クイック選択）の中だけに絞って探す。
    Finder protanopiaChip() => find.descendant(
          of: find.byType(FilterSelector),
          matching: find.text(colorVisionTypeName(en, ColorVisionType.protanopia)),
        );
    bool protanopiaChipSelected() =>
        tester.widget<FilterChip>(find.ancestor(
          of: protanopiaChip(),
          matching: find.byType(FilterChip),
        )).selected;

    // 1. protanopia チップをタップする。
    await tester.tap(protanopiaChip());
    await tester.pump();

    expect(currentPreview().filterId, 'protanopia');
    expect(protanopiaChipSelected(), isTrue);

    // 2. プリセット（meniere）をタップする。色覚クイック選択の記憶は
    //    FilterService 側に残るが、プレビュー・チップの点灯は advanced/
    //    プリセット側に切り替わる（#60: isColorQuickSelection から導く）。
    await tester.tap(find.text(en.experienceMeniere));
    await tester.pump();

    expect(currentPreview().filterId, 'vertigo');
    expect(visionState.isColorQuickSelection, isFalse);
    expect(protanopiaChipSelected(), isFalse,
        reason: 'advanced/プリセットを見ている間は色覚チップを点灯させない（#60）');

    // 3. protanopia チップに戻す。以前の実装（listener ミラー + 直前の型との
    //    差分検知）は、FilterService.currentFilter がプリセット遷移中も
    //    ずっと protanopia のままだったため、この再タップに反応せず
    //    VisionFilterState が更新されなかった（#60）。
    //    selectColorVision はタップの都度、無条件に両方のサービスを更新する
    //    ため、この再タップでも正しく反映される。
    await tester.tap(protanopiaChip());
    await tester.pump();

    expect(currentPreview().filterId, 'protanopia');
    expect(visionState.isColorQuickSelection, isTrue);
    expect(protanopiaChipSelected(), isTrue);
  });

  testWidgets(
      'VisionFilterState.bypassed が true の間、プレビューに「原画表示中」バッジが出る (#63)',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = SettingsService();
    await settings.load();
    final filterService = FilterService();
    final visionState = VisionFilterState();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<FilterService>.value(value: filterService),
          ChangeNotifierProvider<VisionFilterState>.value(value: visionState),
          ChangeNotifierProvider<LoupeWindowController>.value(
            value: LoupeWindowController(),
          ),
          Provider<WindowModeUiContext>.value(
            value: const WindowModeUiContext(
              trayAvailable: false,
              hotkeyStatus: HotkeyStatus(),
            ),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Showing original'), findsNothing);

    visionState.acquireBypass('test');
    await tester.pump();
    expect(find.text('Showing original'), findsOneWidget);

    visionState.releaseBypass('test');
    await tester.pump();
    expect(find.text('Showing original'), findsNothing);
  });
}
