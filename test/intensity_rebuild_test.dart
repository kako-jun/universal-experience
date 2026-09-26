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
import 'package:universal_experience/services/settings_service.dart';

void main() {
  testWidgets(
      'スライダーをドラッグしている間、SettingsService は notifyListeners されない（MaterialApp 再構築なし、#57）',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = SettingsService();
    await settings.load();

    // スライダーを操作可能にするため、フィルタを選択しておく（IntensitySlider は
    // currentFilter == none の間 onChanged が null で操作不能）。main() では
    // buildRootApp() が filterService と settings.filterType を同じ値に揃えて
    // 起動するので、ここでもテスト対象外の初期同期として揃えておく（揃えないと、
    // 最初の 1 回だけ HomeScreen._persistFilterState の setFilterType が
    // 「none → protanopia」の実変更として notify してしまい、これから見たい
    // 「intensity だけを動かしたとき」の挙動と混ざってしまう）。
    filterService.applyFilter(ColorVisionType.protanopia);
    await settings.setFilterType(ColorVisionType.protanopia);

    await tester.pumpWidget(UniversalExperienceApp(settings: settings));
    await tester.pump();

    // HomeScreen は縦に長い ListView（複数カード）。強度スライダーのカードは
    // デフォルトのテストビューポートだとスクロール外で Element 化されておらず、
    // かつ厳密に画面内に収まってもいない（hit test できない）ため、
    // scrollUntilVisible で「見つかる かつ 実際に見える」ところまで動かす。
    // ExperiencePresets カードのような、より下の（flutter_rust_bridge 初期化を
    // 要求する）カードまでは踏み込まない範囲で止まる。
    final sliderFinder = find.byType(Slider);
    await tester.scrollUntilVisible(sliderFinder, 80);
    // scrollUntilVisible が仕込むスクロールはアニメーションのため、実際に位置が
    // 収まるまで数フレーム進める（進めないと直後の drag が off-screen 判定になる）。
    await tester.pump(const Duration(milliseconds: 300));
    expect(sliderFinder, findsOneWidget);

    // ここから先（実際に強度を動かす区間）だけを計測する。
    var settingsNotified = 0;
    settings.addListener(() => settingsNotified++);

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

    expect(
      settingsNotified,
      0,
      reason: 'intensity の変更は FilterService 側だけで完結し、SettingsService '
          '（延いては MaterialApp の Consumer）へは伝播しないはず',
    );
  });
}
