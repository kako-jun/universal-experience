// HomeScreen のプレビュー（_buildPreviewSection の Consumer<VisionFilterState>
// → BeforeAfterView）が、VisionFilterState.setStrength（強度の唯一の正本）に
// 追従することの回帰テスト（#57）。
//
// #57 の要点は「強度の通知が SettingsService（延いては MaterialApp）には伝播せず、
// Consumer を使う場所には正しく伝わる」こと（intensity_rebuild_test.dart 参照）。
// その「正しく伝わる」側を、状態 1 系統になった今も画面で確認しておく。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/main.dart' show WindowModeUiContext;
import 'package:universal_experience/services/hotkey_service.dart';
import 'package:universal_experience/services/image_source_state.dart';
import 'package:universal_experience/services/loupe_window_controller.dart';
import 'package:universal_experience/services/settings_service.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/screens/home_screen.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';
import 'package:universal_experience/ui/widgets/experience_presets.dart';

import 'support/vision_filter_metadata_fixture.dart';
import 'support/color_vision_select.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 体験プリセットの行は実 FRB ブリッジ（experiences()）を要求し、プレーンな
  // `flutter test` では呼べない。widget test 用の fixture に差し替える
  // （i18n_test.dart と同じ手法）。VisionFilterState の選択も urgency/
  // recommended_strength（#76/#77）で実ブリッジを要求するため同様に差し替える。
  setUp(() {
    experiencesProvider = () => const [];
    installVisionFilterMetadataFixture();
  });
  tearDown(() {
    experiencesProvider = experiences;
    resetVisionFilterMetadataProviders();
  });

  testWidgets(
      'VisionFilterState.setStrength のあと、プレビューの BeforeAfterView.strength が追従する',
      (WidgetTester tester) async {
    // HomeScreen は縦に長い ListView。全セクションが一度に Element 化されるよう
    // 十分に高いビューポートにする（i18n_test.dart と同じ手法。scroll 不要）。
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = SettingsService();
    await settings.load();
    final visionState = VisionFilterState();
    selectColorVisionKey(visionState, 'protanopia');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<VisionFilterState>.value(value: visionState),
          ChangeNotifierProvider<ImageSourceState>(
            create: (_) => ImageSourceState(),
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

    BeforeAfterView currentPreview() =>
        tester.widget<BeforeAfterView>(find.byType(BeforeAfterView));

    expect(currentPreview().strength, visionState.strength);
    expect(currentPreview().strength, 1.0); // protanopia の既定強度

    visionState.setStrength(0.33);
    await tester.pump();

    expect(currentPreview().strength, 0.33);
    expect(currentPreview().strength, visionState.strength);
  });

  testWidgets('強度スライダーをドラッグすると VisionFilterState.bypassed が解除される（#63）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = SettingsService();
    await settings.load();
    final visionState = VisionFilterState();
    selectColorVisionKey(visionState, 'protanopia');
    visionState.acquireBypass('test');
    expect(visionState.bypassed, isTrue);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<VisionFilterState>.value(value: visionState),
          ChangeNotifierProvider<ImageSourceState>(
            create: (_) => ImageSourceState(),
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

    // 調整パネルの強度スライダー（#120 で 1 本に統合）が唯一の Slider。
    final sliderFinder = find.byType(Slider);
    // 1200x4000 の 3 カラム（#72）では右カラム「調整」の先頭付近にあり、
    // スクロールせずに hit test できる。
    expect(sliderFinder, findsOneWidget);

    await tester.drag(sliderFinder, const Offset(60, 0));
    await tester.pump();

    expect(visionState.bypassed, isFalse);
  });
}
