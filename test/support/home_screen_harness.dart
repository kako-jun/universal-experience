// HomeScreen を実際の Provider 構成で組む widget test 用の共通部品（#72）。
//
// 画面構成（3 カラム / 縦積み）・検索・選択・キー操作のテストが、同じ
// 前提（体験プリセット fixture・メタデータ fixture・Provider 一式）を
// 何度も書かずに済むようにする。`setUp` で [installHomeScreenFixtures]、
// `tearDown` で [resetHomeScreenFixtures] を呼ぶこと。

import 'dart:async' show Completer;
import 'dart:ui' as ui;

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
import 'package:universal_experience/ui/widgets/before_after_view.dart';
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

/// 体験プリセット・視覚フィルタのメタデータ（urgency 等）と、プレビュー画像の
/// 供給源を fixture に差し替える。
///
/// プレビュー（[BeforeAfterView]）の読み込み・フィルタ適用は既定だと実ブリッジ
/// （native lib の CPU `apply()`）に届く。`flutter test` には native lib も
/// `RustLib.init()` も無いので、フィルタを選んだ状態で実時間が進む（`runAsync`
/// の間など）と、画像の読み込み完了のタイミング次第で「FRB 未初期化」の非同期例外が
/// 走っているテストのどれかに漏れて不安定になる（#127）。ここで Rust にも実時間にも
/// 依存しない供給源へ揃える。
///
/// - 読み込み: 完了しない（[Completer] を返すだけ）。プレビューは「準備中」のまま
///   止まる。画面構成・操作系のテストは従来もこの状態で測っていた（実画像の完了は
///   実時間次第で、`runAsync` の有無で揺れていた）。画像が載った状態を見たい
///   テストは、`setUp` のあとで [fixturePreviewImage] を返すローダに差し替える。
/// - 適用: フィルタを掛けず入力の複製を返す（Rust に触れない）。
void installHomeScreenFixtures() {
  experiencesProvider = fixtureExperiences;
  installVisionFilterMetadataFixture();
  previewSourceImageLoader = (source, size) => Completer<ui.Image>().future;
  afterImageRenderer = (source, filter, strength) async => source.clone();
}

/// [installHomeScreenFixtures] を元に戻す。
void resetHomeScreenFixtures() {
  experiencesProvider = experiences;
  resetVisionFilterMetadataProviders();
  previewSourceImageLoader = BeforeAfterView.loadPreviewSourceImage;
  afterImageRenderer = BeforeAfterView.renderAfter;
}

/// 画像のエンコード/デコードを待たずに作れる、単色の小さな [ui.Image]。
///
/// `toImageSync` は即座に返るので、`testWidgets` の fake async の中でも実時間を
/// 進めずに済む（`toImage` は `runAsync` が要る）。呼び出しごとに新しい画像を返す
/// （[BeforeAfterView] が受け取った画像を dispose するため、使い回さない）。
ui.Image fixturePreviewImage() {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 8, 8),
    Paint()..color = const Color(0xFF808080),
  );
  final picture = recorder.endRecording();
  try {
    return picture.toImageSync(8, 8);
  } finally {
    picture.dispose();
  }
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
  ThemeData? theme,
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
        theme: theme,
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
