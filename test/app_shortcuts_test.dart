// アプリ内キー操作（Shortcuts/Actions、#63）の widget test。
//
// `/`・↑↓・←→ が home_screen.dart の Shortcuts/Actions 経由で
// preview_selection.dart のロジックへ正しく配線されていることを検証する。
// UniversalExperienceApp はトップレベル共有の filterService/visionFilterState/
// loupeWindow シングルトンを使うため（main.dart 参照）、各テストの前後で
// 状態をリセットする。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/main.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/models/vision_filter_catalog.dart';
import 'package:universal_experience/services/color_vision_selection.dart';
import 'package:universal_experience/services/settings_service.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/widgets/experience_presets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => experiencesProvider = () => const []);
  tearDown(() async {
    experiencesProvider = experiences;
    // トップレベル共有シングルトンをテスト間で汚染しない（#63）。clear() は
    // strength をリセットしない既存仕様のため、明示的に既定へ戻す。
    visionFilterState.clear();
    visionFilterState.setStrength(1.0);
    filterService.deactivate();
    await filterService.flush();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = SettingsService();
    await settings.load();

    await tester.pumpWidget(UniversalExperienceApp(settings: settings));
    await tester.pump();
  }

  testWidgets('/ で advanced カタログの FocusNode にフォーカスが移る',
      (WidgetTester tester) async {
    await pumpApp(tester);

    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      isNot('filterCatalog'),
      reason: '起動直後は Scaffold 側 (autofocus) にフォーカスがあるはず',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.pump();

    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      'filterCatalog',
    );
  });

  testWidgets('↓ で VisionFilterState.selectedId がカタログ順に進む（先頭から）',
      (WidgetTester tester) async {
    await pumpApp(tester);
    expect(visionFilterState.selectedId, isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(visionFilterState.selectedId, kVisionFilterCatalog[0].id);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(visionFilterState.selectedId, kVisionFilterCatalog[1].id);
  });

  testWidgets('↑ で VisionFilterState.selectedId がカタログ順に戻る',
      (WidgetTester tester) async {
    await pumpApp(tester);
    visionFilterState.select(kVisionFilterCatalog[2].id);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(visionFilterState.selectedId, kVisionFilterCatalog[1].id);
  });

  testWidgets('← → で advanced 選択中は VisionFilterState.strength が ±5% 動く',
      (WidgetTester tester) async {
    await pumpApp(tester);
    visionFilterState.select('cataract');
    visionFilterState.setStrength(0.5);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(visionFilterState.strength, closeTo(0.55, 1e-9));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(visionFilterState.strength, closeTo(0.45, 1e-9));
  });

  testWidgets('← → で色覚クイック選択中は FilterService.intensity が ±5% 動く',
      (WidgetTester tester) async {
    await pumpApp(tester);
    selectColorVision(
        filterService, visionFilterState, ColorVisionType.protanopia);
    filterService.setIntensity(0.5);
    await tester.pump();
    // VisionFilterState.clear() は strength をリセットしない（既存仕様）ため、
    // 他テストの残留値と比較しないよう、操作前の値を基準にする。
    final strengthBefore = visionFilterState.strength;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(filterService.intensity, closeTo(0.55, 1e-9));
    // 色覚クイック選択では VisionFilterState.strength は使われないので不変。
    expect(visionFilterState.strength, strengthBefore);

    // setIntensity が予約したデバウンス書き込みが pending timer のまま残ると
    // テストバインディングが失敗させる。確定させておく。
    await filterService.flush();
  });
}
