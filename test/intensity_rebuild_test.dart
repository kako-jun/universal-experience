// 強度スライダーを動かしている間、SettingsService が notifyListeners しない
// （= それを購読する MaterialApp の Consumer, main.dart, が再構築されない）ことの
// 回帰テスト（#57）。
//
// 元のバグ: HomeScreen._persistFilterState は FilterService の notifyListeners
// （スライダー 1 目盛りごとに setIntensity が発火する）のたびに
// SettingsService.setFilterType / setIntensity の両方を呼んでいた。
// setIntensity は値が変わるたび notifyListeners するため、それを購読する
// MaterialApp（main.dart の Consumer<SettingsService>）が毎回まるごと再構築
// されていた。#57 で intensity の管理・通知・永続化を FilterService 自身に
// 移し、HomeScreen からは setFilterType の呼び出しだけが残った（型が変わって
// いなければ SettingsService 側の no-op ガードで notify もされない）。
//
// UniversalExperienceApp は main.dart 側で 1 つだけ生成するトップレベル
// `filterService`（トレイと共有、#15）を Provider 経由で使うため、ここでも
// それをそのまま使う（widget_test.dart のスモークテストと同じ構成）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/main.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/services/color_vision_selection.dart';
import 'package:universal_experience/services/settings_service.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/widgets/experience_presets.dart';

import 'support/vision_filter_metadata_fixture.dart';

void main() {
  setUp(() {
    installVisionFilterMetadataFixture();
    // 統合フィルタ一覧（#72）が体験プリセットの行を組むため、実ブリッジ
    // （experiences()）を fixture に差し替える。
    experiencesProvider = () => const <Experience>[];
  });
  tearDown(() {
    experiencesProvider = experiences;
    resetVisionFilterMetadataProviders();
  });

  testWidgets(
      'スライダーをドラッグしている間、SettingsService は notifyListeners されない（MaterialApp 再構築なし、#57）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = SettingsService();
    await settings.load();

    // スライダーを操作可能にするため、フィルタを選択しておく（IntensitySlider は
    // VisionFilterState.isColorQuickSelection が false の間 onChanged が null で
    // 操作不能、#60）。main() では buildRootApp() が selectColorVision
    // （FilterService と VisionFilterState の両方を更新する唯一の
    // 入口、#60）で filterService/visionFilterState と settings.filterType を
    // 揃えて起動するので、ここでもテスト対象外の初期同期として揃えておく
    // （揃えないと、最初の 1 回だけ HomeScreen._persistFilterState の
    // setFilterType が「none → protanopia」の実変更として notify してしまい、
    // これから見たい「intensity だけを動かしたとき」の挙動と混ざってしまう）。
    selectColorVision(filterService, visionFilterState, ColorVisionType.protanopia);
    await settings.setFilterType(ColorVisionType.protanopia);

    await tester.pumpWidget(UniversalExperienceApp(settings: settings));
    await tester.pump();

    // 幅 1200 の 3 カラム（#72）では、強度スライダーは右カラム「調整」の先頭付近に
    // あり、スクロールせずに hit test できる。色覚クイック選択由来のときは
    // FilterParamPanel が strength スライダーを出さない（showsAdvancedStrengthSlider、
    // #60）ため、Slider は IntensitySlider の 1 本だけ。
    final sliderFinder = find.byType(Slider);
    expect(sliderFinder, findsOneWidget);

    // ここから先（実際に強度を動かす区間）だけを計測する。
    var settingsNotified = 0;
    settings.addListener(() => settingsNotified++);

    final intensityBefore = filterService.intensity;
    // ドラッグ前後で MaterialApp の Element/Widget インスタンスが同一のままか
    // （= 作り直されていないか）を確認する。単に見た目が変わらないだけでは
    // 「再構築されていない」ことの証明にならないため、インスタンス同一性
    // （identical）で見る。
    final materialAppBefore =
        tester.widget<MaterialApp>(find.byType(MaterialApp));

    // 複数回「動かす」= 複数目盛りぶんドラッグする。
    await tester.drag(sliderFinder, const Offset(60, 0));
    await tester.pump();
    await tester.drag(sliderFinder, const Offset(-120, 0));
    await tester.pump();
    await tester.drag(sliderFinder, const Offset(40, 0));
    await tester.pump();

    // FilterService 自身の intensity 永続化はデバウンスされる（既定 300ms）。
    // そのデバウンス Timer が発火してもなお SettingsService には波及しない
    // ことまで確認する。
    await tester.pump(const Duration(milliseconds: 400));

    // ドラッグが実際に intensity を動かしたこと自体を確認する（動かせていない
    // 操作なら、notify が 0 であることに意味がない）。
    final intensityAfter = filterService.intensity;
    expect(
      intensityAfter,
      isNot(equals(intensityBefore)),
      reason: 'ドラッグ操作そのものが intensity を実際に変えていることの前提確認',
    );

    expect(
      settingsNotified,
      0,
      reason: 'intensity の変更は FilterService 側だけで完結し、SettingsService '
          '（延いては MaterialApp の Consumer）へは伝播しないはず',
    );

    final materialAppAfter =
        tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(
      identical(materialAppAfter, materialAppBefore),
      isTrue,
      reason: 'MaterialApp の Consumer<SettingsService> が再構築されていれば、'
          '新しい MaterialApp インスタンスに差し替わっているはず',
    );
  });
}
