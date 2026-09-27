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
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/services/filter_service.dart';
import 'package:universal_experience/services/settings_service.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/screens/home_screen.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';
import 'package:universal_experience/ui/widgets/experience_presets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ExperiencePresets は実 FRB ブリッジ（experiences()）を要求し、プレーンな
  // `flutter test` では呼べない。widget test 用の fixture に差し替える
  // （i18n_test.dart / home_screen_preview_intensity_test.dart と同じ手法）。
  setUp(() => experiencesProvider = () => const []);
  tearDown(() => experiencesProvider = experiences);

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
    //    （#57 のタイプ別記憶）。
    filterService.applyFilter(ColorVisionType.protanomaly);
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
    filterService.applyFilter(ColorVisionType.deuteranomaly);
    await tester.pump();
    expect(visionState.isColorQuickSelection, isTrue);
    expect(currentPreview().filterId, 'deuteranopia');
    expect(currentPreview().strength, filterService.intensity);
    // deuteranomaly は初めて選んだので recommendedStrength（anomaly 既定値）。
    expect(currentPreview().strength, kAnomalyDefaultSeverity);

    // 4. protanomaly に戻ると、advanced を経由しても 0.25 の記憶は壊れていない。
    filterService.applyFilter(ColorVisionType.protanomaly);
    await tester.pump();
    expect(currentPreview().strength, 0.25);

    await filterService.flush();
  });
}
