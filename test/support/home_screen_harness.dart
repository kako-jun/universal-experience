// HomeScreen を実際の Provider 構成で組む widget test 用の共通部品（#72）。
//
// 画面構成（3 カラム / 縦積み）・検索・選択・キー操作のテストが、同じ
// 前提（体験プリセット fixture・メタデータ fixture・Provider 一式）を
// 何度も書かずに済むようにする。`setUp` で [installHomeScreenFixtures]、
// `tearDown` で [resetHomeScreenFixtures] を呼ぶこと。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/main.dart' show WindowModeUiContext;
import 'package:universal_experience/services/filter_service.dart';
import 'package:universal_experience/services/hotkey_service.dart';
import 'package:universal_experience/services/image_source_state.dart';
import 'package:universal_experience/services/loupe_window_controller.dart';
import 'package:universal_experience/services/settings_service.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/screens/home_screen.dart';
import 'package:universal_experience/ui/widgets/experience_presets.dart';

import 'vision_filter_metadata_fixture.dart';

/// sensus の experiences() と同じ id / vision / hearing / urgency の 4 体験
/// （実ブリッジは native lib が要るため fixture で代替）。
List<Experience> fixtureExperiences() => const [
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

/// 体験プリセット・視覚フィルタのメタデータ（urgency 等）を fixture に差し替える。
void installHomeScreenFixtures() {
  experiencesProvider = fixtureExperiences;
  installVisionFilterMetadataFixture();
}

/// [installHomeScreenFixtures] を元に戻す。
void resetHomeScreenFixtures() {
  experiencesProvider = experiences;
  resetVisionFilterMetadataProviders();
}

/// [pumpHomeScreen] が組んだ状態の束。
class HomeScreenHarness {
  HomeScreenHarness({
    required this.filterService,
    required this.visionState,
    required this.loupe,
    required this.imageSource,
  });

  final FilterService filterService;
  final VisionFilterState visionState;
  final LoupeWindowController loupe;
  final ImageSourceState imageSource;
}

/// [size]（論理ピクセル）のウィンドウで [HomeScreen] を組む。何も選択していない
/// 状態から始める（[select] が指定されていればその色覚/フィルタを選んだあと描画）。
Future<HomeScreenHarness> pumpHomeScreen(
  WidgetTester tester, {
  required Size size,
  Locale locale = const Locale('ja'),
  WindowModeUiContext uiContext = const WindowModeUiContext(
    trayAvailable: false,
    hotkeyStatus: HotkeyStatus(),
  ),
  void Function(FilterService filterService, VisionFilterState state)? select,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final settings = SettingsService();
  await settings.load();
  final filterService = FilterService();
  final visionState = VisionFilterState();
  final loupe = LoupeWindowController();
  final imageSource = ImageSourceState();
  select?.call(filterService, visionState);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        ChangeNotifierProvider<FilterService>.value(value: filterService),
        ChangeNotifierProvider<VisionFilterState>.value(value: visionState),
        ChangeNotifierProvider<ImageSourceState>.value(value: imageSource),
        ChangeNotifierProvider<LoupeWindowController>.value(value: loupe),
        Provider<WindowModeUiContext>.value(value: uiContext),
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

  return HomeScreenHarness(
    filterService: filterService,
    visionState: visionState,
    loupe: loupe,
    imageSource: imageSource,
  );
}
