// 強度スライダーを動かしている間、SettingsService が notifyListeners しない
// （= それを購読する MaterialApp の Consumer, main.dart, が再構築されない）ことの
// 回帰テスト（#57）。
//
// 元のバグ: スライダー 1 目盛りごとに発火する強度の変更が、SettingsService の
// 書き込みと notifyListeners まで波及し、それを購読する MaterialApp
// （main.dart の Consumer<SettingsService>）が毎回まるごと再構築されていた。
// 強度の正本は VisionFilterState のキーごとの記憶で、永続化は VisionFilterStore
// （#65, #124）が担うため、SettingsService（テーマ・言語・バナーだけ）へは
// 一切届かない。
//
// UniversalExperienceApp は main.dart 側で 1 つだけ生成するトップレベルの
// `visionFilterState`（トレイと共有、#15）を Provider 経由で使うため、ここでも
// それをそのまま使う（widget_test.dart のスモークテストと同じ構成）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/main.dart';
import 'package:universal_experience/services/settings_service.dart';

import 'support/color_vision_select.dart';
import 'support/home_screen_harness.dart';

void main() {
  // 統合フィルタ一覧（#72）が体験プリセットの行を組み、フィルタ選択はメタデータを
  // 引き、プレビューは読み込み・適用を行う。いずれも実ブリッジ（native lib）が要る
  // ため、ハーネスの fixture（Rust 非依存、#127/#131）に差し替える。
  setUp(installHomeScreenFixtures);
  tearDown(resetHomeScreenFixtures);

  testWidgets(
      'スライダーをドラッグしている間、SettingsService は notifyListeners されない（MaterialApp 再構築なし、#57）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = SettingsService();
    await settings.load();

    // スライダーを操作可能にするため、フィルタを選択しておく（何も選んでいないと
    // 調整パネルにスライダーが出ない）。
    selectColorVisionKey(visionFilterState, 'protanopia');

    await tester.pumpWidget(UniversalExperienceApp(settings: settings));
    await tester.pump();

    // 幅 1200 の 3 カラム（#72）では、強度スライダーは右カラム「調整」の先頭付近に
    // あり、スクロールせずに hit test できる。強度スライダーは層の由来によらず
    // FilterParamPanel の 1 本だけ（#120）。
    final sliderFinder = find.byType(Slider);
    expect(sliderFinder, findsOneWidget);

    // ここから先（実際に強度を動かす区間）だけを計測する。
    var settingsNotified = 0;
    settings.addListener(() => settingsNotified++);

    final strengthBefore = visionFilterState.strength;
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

    // VisionFilterStore 側の永続化はデバウンスされる（既定 300ms）。
    // そのデバウンス Timer が発火してもなお SettingsService には波及しない
    // ことまで確認する。
    await tester.pump(const Duration(milliseconds: 400));

    // ドラッグが実際に強度を動かしたこと自体を確認する（動かせていない
    // 操作なら、notify が 0 であることに意味がない）。
    final strengthAfter = visionFilterState.strength;
    expect(
      strengthAfter,
      isNot(equals(strengthBefore)),
      reason: 'ドラッグ操作そのものが強度を実際に変えていることの前提確認',
    );

    expect(
      settingsNotified,
      0,
      reason: '強度の変更は VisionFilterState 側だけで完結し、SettingsService '
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
