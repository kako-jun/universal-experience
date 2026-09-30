// スクリーンリーダー向けの意味づけ（Semantics ツリー）の機械検証（#45）。
//
// ガイドライン系の検証は `accessibility_guidelines_test.dart`、Tab 順・Enter/Space・
// Esc は `home_screen_layout_test.dart` が持つ。ここでは「読み上げられる名前・値・役割・
// 選択状態・画像の代替テキスト」と、OS の「視差効果を減らす」への追従を確かめる。
// 実際の読み上げ（VoiceOver 等）は実機でしか確かめられない
// （docs/accessibility.md の【kako-jun 実機】）。

import 'dart:ui' as ui;
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/services/color_vision_selection.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';
import 'package:universal_experience/ui/widgets/filter_list_tile.dart';
import 'package:universal_experience/ui/widgets/image_source_picker.dart';

import 'support/home_screen_harness.dart';
import 'support/sample_image_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installHomeScreenFixtures);
  tearDown(() {
    resetHomeScreenFixtures();
    previewSourceImageLoader = BeforeAfterView.loadPreviewSourceImage;
    afterImageRenderer = BeforeAfterView.renderAfter;
  });

  const wide = Size(1280, 800);

  Future<void> installFakes(WidgetTester tester) async {
    late ui.Image master;
    await tester.runAsync(() async {
      master = await generateSampleImage(64);
    });
    addTearDown(master.dispose);
    previewSourceImageLoader = (source, size) async => master.clone();
    afterImageRenderer = (source, filter, strength) async => master.clone();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  /// [matcher] に合う唯一のノードの、読み上げ用のデータ。
  SemanticsData dataOf(WidgetTester tester, Finder finder) =>
      tester.getSemantics(finder).getSemanticsData();

  group('スライダー・ドロップダウンの名前と値', () {
    testWidgets('強度スライダーは名前「強さ」と「NN%」の値を持つ', (tester) async {
      final handle = tester.ensureSemantics();
      await installFakes(tester);
      final h = await pumpHomeScreen(tester, size: wide);
      selectColorVision(
          h.filterService, h.visionState, ColorVisionType.protanopia);
      await settle(tester);

      final slider = find.byType(Slider);
      expect(slider, findsOneWidget);
      final data = dataOf(tester, slider);
      expect(data.label, startsWith('強さ'));
      expect(data.value, matches(RegExp(r'^\d+%$')));
      expect(data.flagsCollection.isSlider, isTrue);
      await h.filterService.flush();
      handle.dispose();
    });

    testWidgets('en では名前が Intensity になる', (tester) async {
      final handle = tester.ensureSemantics();
      await installFakes(tester);
      final h =
          await pumpHomeScreen(tester, size: wide, locale: const Locale('en'));
      selectColorVision(
          h.filterService, h.visionState, ColorVisionType.protanopia);
      await settle(tester);

      expect(
          dataOf(tester, find.byType(Slider)).label, startsWith('Intensity'));
      await h.filterService.flush();
      handle.dispose();
    });

    testWidgets('advanced の強度スライダー・列挙ドロップダウンが名前を持つ', (tester) async {
      final handle = tester.ensureSemantics();
      await installFakes(tester);
      final h = await pumpHomeScreen(tester, size: wide);
      h.visionState.select('glaucoma');
      await settle(tester);

      final strength = dataOf(tester, find.byType(Slider));
      expect(strength.label, startsWith('強さ'));
      expect(strength.value, matches(RegExp(r'^\d+%$')));
      final dropdown = dataOf(tester, find.byType(DropdownButton<String>));
      expect(dropdown.label, contains('欠け方のタイプ'));
      await h.filterService.flush();
      handle.dispose();
    });

    testWidgets('小数パラメータのスライダーは名前と小数の値を読む', (tester) async {
      final handle = tester.ensureSemantics();
      await installFakes(tester);
      final h = await pumpHomeScreen(tester, size: wide);
      h.visionState.select('floaters');
      await settle(tester);

      final count = tester.widgetList<Slider>(find.byType(Slider)).length;
      expect(count, greaterThanOrEqualTo(2));
      final named = [
        for (var i = 0; i < count; i++)
          dataOf(tester, find.byType(Slider).at(i)),
      ];
      for (final data in named) {
        expect(data.label, isNotEmpty);
        expect(data.value, isNotEmpty);
      }
      expect(named.map((d) => d.value),
          contains(matches(RegExp(r'^\d+\.\d{2}$'))));
      await h.filterService.flush();
      handle.dispose();
    });

    testWidgets('整数パラメータのスライダーは整数の値を読む', (tester) async {
      final handle = tester.ensureSemantics();
      await installFakes(tester);
      final h = await pumpHomeScreen(tester, size: wide);
      h.visionState.select('starbursts');
      await settle(tester);

      final count = tester.widgetList<Slider>(find.byType(Slider)).length;
      final values = [
        for (var i = 0; i < count; i++)
          dataOf(tester, find.byType(Slider).at(i)).value,
      ];
      expect(values, contains(matches(RegExp(r'^\d+$'))));
      await h.filterService.flush();
      handle.dispose();
    });
  });

  group('見出し', () {
    testWidgets('一覧・調整の見出しは header の役割を持つ', (tester) async {
      final handle = tester.ensureSemantics();
      await installFakes(tester);
      await pumpHomeScreen(tester, size: wide);
      await settle(tester);

      for (final text in ['見え方を選ぶ', '調整']) {
        final data = dataOf(tester, find.text(text));
        expect(data.flagsCollection.isHeader, isTrue, reason: '「$text」は見出し');
      }
      handle.dispose();
    });

    testWidgets('何も選んでいない空状態の見出しも header', (tester) async {
      final handle = tester.ensureSemantics();
      await installFakes(tester);
      await pumpHomeScreen(tester, size: wide);
      await settle(tester);

      final data = dataOf(tester, find.text('何も選択されていません'));
      expect(data.flagsCollection.isHeader, isTrue);
      handle.dispose();
    });

    testWidgets('初回バナーの題は header', (tester) async {
      final handle = tester.ensureSemantics();
      await installFakes(tester);
      await pumpHomeScreen(tester, size: wide);
      await settle(tester);

      final data = dataOf(tester, find.text('はじめての方へ'));
      expect(data.flagsCollection.isHeader, isTrue);
      handle.dispose();
    });
  });

  group('選択状態（色だけで伝えない）', () {
    testWidgets('選んだ行だけが selected で、ほかの行は selected でない', (tester) async {
      final handle = tester.ensureSemantics();
      await installFakes(tester);
      final h = await pumpHomeScreen(tester, size: wide);
      h.visionState.select('glaucoma');
      await settle(tester);

      final tiles = find.byType(FilterListTile);
      final count = tester.widgetList(tiles).length;
      var selected = 0;
      for (var i = 0; i < count; i++) {
        final data = dataOf(tester, tiles.at(i));
        if (data.flagsCollection.isSelected == Tristate.isTrue) selected++;
      }
      expect(count, greaterThan(1));
      expect(selected, 1);
      await h.filterService.flush();
      handle.dispose();
    });

    testWidgets('選択行には選択済みを示すアイコンがあり、未選択行にはない', (tester) async {
      final handle = tester.ensureSemantics();
      await installFakes(tester);
      final h = await pumpHomeScreen(tester, size: wide);
      h.visionState.select('glaucoma');
      await settle(tester);

      final checks = find.descendant(
          of: find.byType(FilterListTile), matching: find.byIcon(Icons.check));
      expect(checks, findsOneWidget);
      await h.filterService.flush();
      handle.dispose();
    });
  });

  group('プレビュー画像の代替テキスト', () {
    testWidgets('画像の読み込み前後で、元・適用後の画像に名前がつく', (tester) async {
      final handle = tester.ensureSemantics();
      await installFakes(tester);
      final h = await pumpHomeScreen(tester, size: wide);
      selectColorVision(
          h.filterService, h.visionState, ColorVisionType.protanopia);
      await settle(tester);

      final labels = [
        for (final e in tester.widgetList<Semantics>(find.descendant(
            of: find.byType(PreviewImageView),
            matching: find.byType(Semantics))))
          if (e.properties.image == true) e.properties.label,
      ];
      expect(labels, hasLength(2));
      expect(labels.first, '元の画像');
      expect(labels.last, endsWith('を適用した画像'));
      await h.filterService.flush();
      handle.dispose();
    });

    testWidgets('en の適用後画像の名前は Image with … applied', (tester) async {
      final handle = tester.ensureSemantics();
      await installFakes(tester);
      final h =
          await pumpHomeScreen(tester, size: wide, locale: const Locale('en'));
      selectColorVision(
          h.filterService, h.visionState, ColorVisionType.protanopia);
      await settle(tester);

      final labels = [
        for (final e in tester.widgetList<Semantics>(find.descendant(
            of: find.byType(PreviewImageView),
            matching: find.byType(Semantics))))
          if (e.properties.image == true) e.properties.label,
      ];
      expect(labels.first, 'Original');
      expect(labels.last, matches(RegExp(r'^Image with .+ applied$')));
      await h.filterService.flush();
      handle.dispose();
    });

    testWidgets('描画に失敗したら liveRegion で伝える', (tester) async {
      final handle = tester.ensureSemantics();
      await installFakes(tester);
      afterImageRenderer =
          (source, filter, strength) async => throw StateError('render failed');
      final h = await pumpHomeScreen(tester, size: wide);
      selectColorVision(
          h.filterService, h.visionState, ColorVisionType.protanopia);
      await settle(tester);

      // 失敗は FlutterError.reportError に流れるので、ここで受け取って消費する。
      expect(tester.takeException(), isNotNull);
      final data = dataOf(tester, find.text('プレビューの描画に失敗しました'));
      expect(data.flagsCollection.isLiveRegion, isTrue);
      await h.filterService.flush();
      handle.dispose();
    });
  });

  group('視差効果を減らす設定（disableAnimations）', () {
    Future<void> setDisableAnimations(WidgetTester tester, bool value) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: value);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    }

    Duration pickerDropDuration(WidgetTester tester) {
      final container = find.descendant(
          of: find.byType(ImageSourcePicker),
          matching: find.byType(AnimatedContainer));
      expect(container, findsOneWidget);
      return tester.widget<AnimatedContainer>(container).duration;
    }

    testWidgets('ON: 画像ドロップ枠の遷移が 0', (tester) async {
      await installFakes(tester);
      await setDisableAnimations(tester, true);
      await pumpHomeScreen(tester, size: wide);
      expect(pickerDropDuration(tester), Duration.zero);
    });

    testWidgets('OFF: 画像ドロップ枠の遷移は従来どおり（0 でない）', (tester) async {
      await installFakes(tester);
      await setDisableAnimations(tester, false);
      await pumpHomeScreen(tester, size: wide);
      expect(pickerDropDuration(tester), greaterThan(Duration.zero));
    });
  });

  group('キーボードでダイアログを閉じる', () {
    testWidgets('言語ダイアログは Enter で開き、Esc で閉じて、フォーカスが開いたボタンに戻る', (tester) async {
      await installFakes(tester);
      await pumpHomeScreen(tester, size: wide);
      // IconButton の内側（InkResponse）の Focus。Tooltip は外側にあるので Icon から辿る。
      final icon = find.descendant(
          of: find.byTooltip('言語'), matching: find.byType(Icon));
      final focus = Focus.of(tester.element(icon));
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasPrimaryFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(focus.hasPrimaryFocus, isTrue, reason: '閉じたあと、開いたボタンから操作を続けられる');
    });
  });
}
