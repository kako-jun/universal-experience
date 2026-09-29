// HomeScreen のスクリーンショット出力（#72）。
//
// 実ディスプレイのない環境でも UI を目視レビューできるよう、HomeScreen を
// 実際の Provider 構成で描画して PNG に書き出す。回帰テストではない（比較は
// しない）。DESIGN.md「検証方法」の手順:
//
//   UE_SCREENSHOTS=1 UE_SCREENSHOT_DIR=/path/to/out \
//     flutter test test/ui_screenshots/home_screenshots_test.dart
//
// `UE_SCREENSHOTS=1` でないとき（通常の `flutter test`・CI）は全ケースが
// skip される。出力ファイル名:
//   {wide|narrow}-{light|dark}-{ja|en}.png        — ウィンドウ 1 枚ぶん
//                                                    （wide=1280x800、narrow=800x700）
//   {wide|narrow}-{light|dark}-{ja|en}-full.png   — 縦に十分長い画面で全体を撮ったもの
//                                                    （スクロール量の確認用）
//
// 注意: after ペインは実ブリッジ（sensus の CPU `apply()`）を呼べないため、
// レイアウト確認用の簡易フェイク（輝度への単純なブレンド）に差し替えている。
// 色覚シミュレーションの正しさを示す画像ではない。

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/main.dart' show WindowModeUiContext;
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/models/sample_catalog.dart';
import 'package:universal_experience/rendering/cpu_vision_renderer.dart';
import 'package:universal_experience/services/color_vision_selection.dart';
import 'package:universal_experience/services/filter_service.dart';
import 'package:universal_experience/services/hotkey_service.dart';
import 'package:universal_experience/services/image_source_state.dart';
import 'package:universal_experience/services/loupe_window_controller.dart';
import 'package:universal_experience/services/settings_service.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/screens/home_screen.dart';
import 'package:universal_experience/ui/theme/app_theme.dart';
import 'package:universal_experience/ui/widgets/experience_presets.dart';

import '../support/screenshot_harness.dart';
import '../support/vision_filter_metadata_fixture.dart';

/// sensus の experiences() と同じ id / vision / hearing / urgency の 4 体験
/// （実ブリッジは native lib が要るため fixture で代替。experience_presets_test と同じ）。
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

/// レイアウト確認専用の after フェイク。BT.709 輝度と元画像を strength で混ぜる
/// だけ（色覚のアルゴリズムではない）。
Future<ui.Image> _layoutOnlyApplier(
  ui.Image source,
  VisionFilter filter,
  double strength,
) async {
  final data = await source.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();
  final out = Uint8List.fromList(bytes);
  final s = strength.clamp(0.0, 1.0);
  for (var i = 0; i + 3 < out.length; i += 4) {
    final y = 0.2126 * out[i] + 0.7152 * out[i + 1] + 0.0722 * out[i + 2];
    for (var c = 0; c < 3; c++) {
      out[i + c] = (out[i + c] * (1 - s) + y * s).round().clamp(0, 255);
    }
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    out,
    source.width,
    source.height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // (幅ラベル, 幅px, 高さpx) — 高さは「ウィンドウ 1 枚ぶん」。
  const sizes = <(String, double, double)>[
    ('wide', 1280, 800),
    ('narrow', 800, 700),
  ];
  // 組み合わせ: 広幅 × {light,dark} × {ja,en} + 狭幅 × light × ja。
  final combos = <(String, bool, String)>[
    ('wide', false, 'ja'),
    ('wide', false, 'en'),
    ('wide', true, 'ja'),
    ('wide', true, 'en'),
    ('narrow', false, 'ja'),
  ];

  setUpAll(() async {
    if (!screenshotsEnabled) return;
    await loadScreenshotFonts();
  });

  setUp(() {
    experiencesProvider = _fixtureExperiences;
    installVisionFilterMetadataFixture();
    CpuVisionRenderer.applier = _layoutOnlyApplier;
  });
  tearDown(() {
    experiencesProvider = experiences;
    resetVisionFilterMetadataProviders();
    CpuVisionRenderer.applier = CpuVisionRenderer.apply;
  });

  ThemeData themed(ThemeData base) => base.copyWith(
        textTheme: base.textTheme.apply(
          fontFamilyFallback: screenshotFontFallback,
        ),
      );

  Future<void> shoot(
    WidgetTester tester, {
    required String widthLabel,
    required double width,
    required double height,
    required bool dark,
    required String locale,
    required String suffix,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = SettingsService();
    await settings.load();
    final filterService = FilterService();
    final visionState = VisionFilterState();
    final imageSourceState = ImageSourceState();
    // 初回起動と同じ状態: 2型3色覚（deuteranomaly）を推奨サンプルで選択。
    selectColorVision(
      filterService,
      visionState,
      ColorVisionType.deuteranomaly,
    );
    imageSourceState.followRecommendedSample(
      recommendedSampleIdForFilter(visionState.selectedId),
    );

    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MultiProvider(
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
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: Locale(locale),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            theme: themed(AppTheme.lightTheme),
            darkTheme: themed(AppTheme.darkTheme),
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            home: const HomeScreen(),
          ),
        ),
      ),
    );

    // サンプル画像のデコード・after 描画は実時間の非同期。落ち着くまで待つ。
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }

    final path = await writeScreenshot(
      tester,
      boundaryKey,
      '$widthLabel-${dark ? 'dark' : 'light'}-$locale$suffix',
    );
    // ignore: avoid_print
    print('[ui_screenshots] wrote $path');
  }

  for (final (widthLabel, dark, locale) in combos) {
    final size = sizes.firstWhere((s) => s.$1 == widthLabel);
    final tag = '$widthLabel/${dark ? 'dark' : 'light'}/$locale';

    testWidgets(
      'screenshot $tag',
      (tester) => shoot(
        tester,
        widthLabel: widthLabel,
        width: size.$2,
        height: size.$3,
        dark: dark,
        locale: locale,
        suffix: '',
      ),
      skip: !screenshotsEnabled,
    );

    testWidgets(
      'screenshot $tag (full length)',
      (tester) => shoot(
        tester,
        widthLabel: widthLabel,
        width: size.$2,
        height: 4200,
        dark: dark,
        locale: locale,
        suffix: '-full',
      ),
      skip: !screenshotsEnabled,
    );
  }
}
