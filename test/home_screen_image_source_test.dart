// HomeScreen がフィルタ選択の変化に応じて ImageSourceState.selectedSampleId を
// 自動追従させることの回帰テスト（#78）。
//
// home_screen.dart の `_followRecommendedSample`（VisionFilterState への
// リスナー、`_persistFilterState` と同じ subscribe-once パターン）が、
// フィルタの選択が変わるたびに `recommendedSampleIdForFilter` の結果で
// `ImageSourceState.followRecommendedSample` を呼ぶことを確認する。
// 既存の home_screen_preview_*.dart とは別ファイルにして、それらとの
// コンフリクトを避けている。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/main.dart' show WindowModeUiContext;
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/models/sample_catalog.dart';
import 'package:universal_experience/services/color_vision_selection.dart';
import 'package:universal_experience/services/filter_service.dart';
import 'package:universal_experience/services/hotkey_service.dart';
import 'package:universal_experience/services/image_source_state.dart';
import 'package:universal_experience/services/loupe_window_controller.dart';
import 'package:universal_experience/services/settings_service.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/screens/home_screen.dart';
import 'package:universal_experience/ui/widgets/experience_presets.dart';

import 'support/sample_image_generator.dart';
import 'support/vision_filter_metadata_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    experiencesProvider = () => const [];
    installVisionFilterMetadataFixture();
  });
  tearDown(() {
    experiencesProvider = experiences;
    resetVisionFilterMetadataProviders();
  });

  Future<ImageSourceState> pumpHome(
    WidgetTester tester, {
    required FilterService filterService,
    required VisionFilterState visionState,
  }) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = SettingsService();
    await settings.load();
    final imageSourceState = ImageSourceState();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<FilterService>.value(value: filterService),
          ChangeNotifierProvider<VisionFilterState>.value(value: visionState),
          ChangeNotifierProvider<ImageSourceState>.value(
            value: imageSourceState,
          ),
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
    return imageSourceState;
  }

  testWidgets(
      '色覚クイック選択でフィルタを切り替えると selectedSampleId が推奨サンプルに追従する',
      (tester) async {
    final filterService = FilterService();
    final visionState = VisionFilterState();
    final imageSourceState = await pumpHome(
      tester,
      filterService: filterService,
      visionState: visionState,
    );

    selectColorVision(filterService, visionState, ColorVisionType.protanopia);
    await tester.pump();

    expect(imageSourceState.selectedSampleId,
        recommendedSampleIdForFilter('protanopia'));
    expect(imageSourceState.isFollowingRecommended, isTrue);

    selectColorVision(filterService, visionState, ColorVisionType.deuteranopia);
    await tester.pump();

    expect(imageSourceState.selectedSampleId,
        recommendedSampleIdForFilter('deuteranopia'));
  });

  testWidgets(
      'advanced カタログでフィルタを切り替えても selectedSampleId が追従する',
      (tester) async {
    final filterService = FilterService();
    final visionState = VisionFilterState();
    final imageSourceState = await pumpHome(
      tester,
      filterService: filterService,
      visionState: visionState,
    );

    visionState.select('night_blindness');
    await tester.pump();

    expect(imageSourceState.selectedSampleId,
        recommendedSampleIdForFilter('night_blindness'));
  });

  testWidgets(
      'ユーザー画像を選んでいる間はフィルタを切り替えても自動切り替えが働かない'
      '（#78）', (tester) async {
    final filterService = FilterService();
    final visionState = VisionFilterState();
    final imageSourceState = await pumpHome(
      tester,
      filterService: filterService,
      visionState: visionState,
    );

    await tester.runAsync(() async {
      final image = await generateSampleImage(4);
      imageSourceState.setUserImage(image);
    });
    await tester.pump();
    expect(imageSourceState.isUsingUserImage, isTrue);

    selectColorVision(filterService, visionState, ColorVisionType.protanopia);
    await tester.pump();

    // ユーザー画像を見ている間は HomeScreen 側のリスナーが
    // followRecommendedSample を呼んでも no-op になり続ける。
    expect(imageSourceState.isUsingUserImage, isTrue,
        reason: 'フィルタ変更でユーザー画像が勝手に外れてはいけない');
  });
}
