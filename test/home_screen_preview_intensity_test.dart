// HomeScreen のプレビュー（_buildPreviewSection の Consumer2<VisionFilterState,
// FilterService> → BeforeAfterView）が、FilterService.setIntensity に追従する
// ことの回帰テスト（#57 レビュー S4）。
//
// #57 修正の要点は「intensity の通知経路を FilterService 自身に閉じ込め、
// SettingsService（延いては MaterialApp）には伝播させない」こと
// （intensity_rebuild_test.dart 参照）。その副作用で「Consumer2 を使う場所には
// 従来通り正しく伝わる」ことを別途確認しておく。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/services/color_vision_selection.dart';
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
  // （i18n_test.dart と同じ手法）。
  setUp(() => experiencesProvider = () => const []);
  tearDown(() => experiencesProvider = experiences);

  testWidgets(
      'FilterService.setIntensity のあと、プレビューの BeforeAfterView.intensity が追従する',
      (WidgetTester tester) async {
    // HomeScreen は縦に長い ListView。全セクションが一度に Element 化されるよう
    // 十分に高いビューポートにする（i18n_test.dart と同じ手法。scroll 不要）。
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = SettingsService();
    await settings.load();
    final filterService = FilterService();
    final visionState = VisionFilterState();
    // #60 M1: home_screen はもう FilterService の変化を VisionFilterState へ
    // ミラーしない。selectColorVision が両方を明示的に更新する唯一の入口。
    selectColorVision(filterService, visionState, ColorVisionType.protanopia);

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

    expect(currentPreview().strength, filterService.intensity);
    expect(currentPreview().strength, 1.0); // protanopia の recommendedStrength

    filterService.setIntensity(0.33);
    await tester.pump();

    expect(currentPreview().strength, 0.33);
    expect(currentPreview().strength, filterService.intensity);

    // setIntensity が予約したデバウンス書き込みが pending timer のまま残ると
    // テストバインディングが失敗させる。確定させておく。
    await filterService.flush();
  });
}
