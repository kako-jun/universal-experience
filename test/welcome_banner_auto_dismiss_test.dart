// ウェルカムバナー（#78）の自動 dismiss（#143）のテスト。
//
// フィルタ選択か原画がユーザー操作で変わったら、バナー（「推奨の既定で始めています」の案内）を
// 自動で閉じる（dismissWelcomeBannerOnUserChange）。閉じる入口は
// 一覧の行・体験プリセット・LayerChipStrip の ✕/すべて解除・サンプル切替・自分の画像チップ・
// 写真の読み込み/貼り付け/閉じる・おすすめに戻す。一方、起動時の復元・初期選択
// （seedInitialLayers）・推奨サンプルへの自動追従・プログラムからの状態変更・
// バナー自身の「写真ピッカーのキャンセル」では閉じない。
// SettingsService を提供しない分離ウィジェットテストではタップしても例外にならない。
// トレイ/ホットキー経由の変更では閉じない（既知の制約、docs 記載）。

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/main.dart';
import 'package:universal_experience/models/sample_catalog.dart';
import 'package:universal_experience/services/clipboard_image_reader.dart';
import 'package:universal_experience/services/image_source_state.dart';
import 'package:universal_experience/services/settings_service.dart';
import 'package:universal_experience/services/vision_filter_snapshot.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/services/vision_filter_store.dart';
import 'package:universal_experience/ui/widgets/experience_presets.dart';
import 'package:universal_experience/ui/widgets/filter_browser.dart';
import 'package:universal_experience/ui/widgets/image_source_picker.dart';
import 'package:universal_experience/ui/widgets/layer_chip_strip.dart';
import 'package:universal_experience/ui/widgets/welcome_banner.dart';

import 'support/home_screen_harness.dart';
import 'support/sample_image_generator.dart';

class _FakeClipboardImageReader implements ClipboardImageReader {
  _FakeClipboardImageReader(this.bytes);
  final Uint8List bytes;

  @override
  Future<ClipboardContent> read() async => ClipboardImageData(bytes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final ja = lookupAppLocalizations(const Locale('ja'));
  const tall = Size(1200, 4000);

  setUp(installHomeScreenFixtures);
  tearDown(() {
    resetHomeScreenFixtures();
    pickImageFile = () async => null;
    clipboardImageReader = const PasteboardClipboardImageReader();
  });

  Finder banner() => find.byType(WelcomeBanner);
  Finder bannerTitle() => find.text(ja.welcomeBannerTitle);

  Future<Uint8List> validPng(WidgetTester tester) async {
    final bytes = await tester.runAsync(() async {
      final image = await generateSampleImage(8);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    });
    return bytes!;
  }

  /// バナーが出ていて、永続にも dismiss が無い（初期状態）ことを確かめる。
  void expectBannerUp(HomeScreenHarness h) {
    expect(h.settings.welcomeBannerDismissed, isFalse);
    expect(bannerTitle(), findsOneWidget);
  }

  /// dismiss されている: 状態・表示・永続（別インスタンスで load し直す）の 3 点。
  Future<void> expectBannerDismissed(
    WidgetTester tester,
    HomeScreenHarness h,
  ) async {
    await tester.pump();
    expect(h.settings.welcomeBannerDismissed, isTrue);
    expect(bannerTitle(), findsNothing);
    final reloaded = SettingsService();
    await tester.runAsync(reloaded.load);
    expect(reloaded.welcomeBannerDismissed, isTrue, reason: '再起動しても出ない');
  }

  group('ユーザー操作で閉じる', () {
    testWidgets('一覧の行をタップ', (tester) async {
      final h = await pumpHomeScreen(tester, size: tall);
      expectBannerUp(h);
      await tester.tap(find.byKey(const ValueKey('filter_tile_cv:protanopia')));
      await tester.pump();
      expect(h.visionState.layers, isNotEmpty);
      await expectBannerDismissed(tester, h);
    });

    testWidgets('体験プリセットをタップ', (tester) async {
      final h = await pumpHomeScreen(tester, size: tall);
      expectBannerUp(h);
      await tester.tap(find.byKey(experienceCardKey('bppv')));
      await tester.pump();
      expect(h.visionState.selectedPresetId, 'bppv');
      await expectBannerDismissed(tester, h);
    });

    testWidgets('LayerChipStrip の ✕（プログラムでの 2 層化では閉じない）', (tester) async {
      final h = await pumpHomeScreen(tester, size: tall);
      h.visionState.toggle('myopia');
      h.visionState.toggle('glaucoma');
      await tester.pump();
      expectBannerUp(h);

      await tester.tap(find.byKey(const ValueKey('layer_chip_remove_myopia')));
      await tester.pump();
      expect(h.visionState.layers, hasLength(1));
      await expectBannerDismissed(tester, h);
    });

    testWidgets('LayerChipStrip の「すべて解除」', (tester) async {
      final h = await pumpHomeScreen(tester, size: tall);
      h.visionState.toggle('myopia');
      h.visionState.toggle('glaucoma');
      await tester.pump();
      expectBannerUp(h);

      await tester.tap(find.byKey(const ValueKey('layer_strip_clear_all')));
      await tester.pump();
      expect(h.visionState.layers, isEmpty);
      await expectBannerDismissed(tester, h);
    });

    testWidgets('調整パネルの「フィルタを解除」（1 層でも閉じる）', (tester) async {
      final h = await pumpHomeScreen(
        tester,
        size: tall,
        select: (s) => s.seedInitialLayers(),
      );
      await tester.pump();
      expect(h.visionState.layers, hasLength(1));
      expectBannerUp(h);

      await tester.tap(find.text(ja.clearFilter));
      await tester.pump();
      expect(h.visionState.layers, isEmpty);
      await expectBannerDismissed(tester, h);
    });

    testWidgets('サンプル画像の切替', (tester) async {
      final h = await pumpHomeScreen(tester, size: tall);
      expectBannerUp(h);
      final chips = find.descendant(
        of: find.byType(ImageSourcePicker),
        matching: find.byType(ChoiceChip),
      );
      final other =
          chips.evaluate().map((e) => e.widget as ChoiceChip).toList();
      final index = other.indexWhere((c) => !c.selected);
      expect(index, isNonNegative, reason: '選択中でないサンプルチップがある');
      await tester.tap(chips.at(index));
      await tester.pump();
      expect(h.imageSource.isFollowingRecommended, isFalse);
      await expectBannerDismissed(tester, h);
    });

    testWidgets('ファイルを選んで読み込む（画像を選ぶ…）', (tester) async {
      final h = await pumpHomeScreen(tester, size: tall);
      final bytes = await validPng(tester);
      pickImageFile = () async => XFile.fromData(bytes, name: 'a.png');
      expectBannerUp(h);

      await tester.runAsync(() async {
        await tester.tap(find.text(ja.imageSourcePickButton));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      expect(h.imageSource.isUsingUserImage, isTrue);
      await expectBannerDismissed(tester, h);
    });

    testWidgets('クリップボードから貼り付け', (tester) async {
      final h = await pumpHomeScreen(tester, size: tall);
      final bytes = await validPng(tester);
      clipboardImageReader = _FakeClipboardImageReader(bytes);
      expectBannerUp(h);

      await tester.runAsync(() async {
        await tester.tap(find.text(ja.imageSourcePasteButton));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      expect(h.imageSource.isUsingUserImage, isTrue);
      await expectBannerDismissed(tester, h);
    });

    testWidgets('読み込み済みの写真を閉じる', (tester) async {
      final h = await pumpHomeScreen(tester, size: tall);
      await tester.runAsync(() async {
        h.imageSource.setUserImage(await generateSampleImage(4));
      });
      await tester.pump();
      expectBannerUp(h);

      await tester.tap(find.byTooltip(ja.imageSourceClosePhotoTooltip));
      await tester.pump();
      expect(h.imageSource.hasUserImage, isFalse);
      await expectBannerDismissed(tester, h);
    });

    testWidgets('「自分の画像」チップで読み込み済みの写真へ戻る', (tester) async {
      final h = await pumpHomeScreen(tester, size: tall);
      await tester.runAsync(() async {
        h.imageSource.setUserImage(await generateSampleImage(4));
      });
      h.imageSource.selectSample(kDefaultSampleId); // 写真を外す（プログラム）
      await tester.pump();
      expect(h.imageSource.isUsingUserImage, isFalse);
      expectBannerUp(h);

      await tester.tap(
        find.widgetWithText(ChoiceChip, ja.imageSourceYourPhotoChipLabel),
      );
      await tester.pump();
      expect(h.imageSource.isUsingUserImage, isTrue);
      await expectBannerDismissed(tester, h);
    });

    testWidgets('「おすすめに戻す」', (tester) async {
      final h = await pumpHomeScreen(tester, size: tall);
      h.imageSource.selectSample(kDefaultSampleId); // 手動固定（プログラム）
      await tester.pump();
      expect(h.imageSource.isFollowingRecommended, isFalse);
      expectBannerUp(h);

      await tester.tap(find.text(ja.imageSourceResetToRecommended));
      await tester.pump();
      expect(h.imageSource.isFollowingRecommended, isTrue);
      await expectBannerDismissed(tester, h);
    });
  });

  group('ユーザー操作以外では閉じない', () {
    testWidgets('初期選択（seedInitialLayers）と推奨サンプルへの自動追従では残る', (tester) async {
      final h = await pumpHomeScreen(
        tester,
        size: tall,
        select: (s) => s.seedInitialLayers(),
      );
      await tester.pump();
      expect(h.visionState.layers, isNotEmpty);
      expectBannerUp(h);

      // 以後の選択変更（= _followRecommendedSample が走る）もプログラムなら閉じない。
      h.visionState.toggle('glaucoma');
      h.visionState.selectPreset('bppv', 'bppv_rotation');
      await tester.pump();
      expectBannerUp(h);
    });

    testWidgets('プログラムからの原画変更・層の変更では残る', (tester) async {
      final h = await pumpHomeScreen(tester, size: tall);
      h.visionState.toggle('myopia');
      h.visionState.toggle('glaucoma');
      h.visionState.remove('myopia');
      h.visionState.clear();
      h.imageSource.selectSample(kDefaultSampleId);
      h.imageSource.resetToRecommended(kDefaultSampleId);
      await tester.runAsync(() async {
        h.imageSource.setUserImage(await generateSampleImage(4));
      });
      h.imageSource.useLoadedUserImage();
      h.imageSource.clearUserImage(kDefaultSampleId);
      await tester.pump();
      expectBannerUp(h);
    });

    testWidgets('バナーの「自分の画像で試す」でピッカーをキャンセルすると残る', (tester) async {
      final h = await pumpHomeScreen(tester, size: tall);
      pickImageFile = () async => null;

      await tester.runAsync(() async {
        await tester.tap(
          find.widgetWithText(FilledButton, ja.welcomeBannerTryPhotoAction),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expectBannerUp(h);
      expect(banner(), findsOneWidget);
    });

    // 閉じるのは loadUserImageFile 側（バナー側の dismiss を外しても閉じる）。
    // バナー側 dismiss 自体の検証ではなく、この経路で最終的に閉じる確認。
    testWidgets('バナーの「自分の画像で試す」で読み込めたら閉じる', (tester) async {
      final h = await pumpHomeScreen(tester, size: tall);
      final bytes = await validPng(tester);
      pickImageFile = () async => XFile.fromData(bytes, name: 'a.png');

      await tester.runAsync(() async {
        await tester.tap(
          find.widgetWithText(FilledButton, ja.welcomeBannerTryPhotoAction),
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await expectBannerDismissed(tester, h);
    });

    testWidgets('バナー自身の「ほかの見え方を選ぶ」は従来どおり閉じる', (tester) async {
      final h = await pumpHomeScreen(tester, size: tall);
      await tester.tap(find.text(ja.welcomeBannerChooseOtherAction));
      await tester.pump();
      await expectBannerDismissed(tester, h);
    });

    testWidgets('起動時の復元（buildRootApp: 初回シード）では dismiss されない', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      final store = VisionFilterStore();
      addTearDown(store.dispose);
      addTearDown(() {
        visionFilterState.restore(const VisionFilterSnapshot());
        imageSourceState.resetToRecommended(kDefaultSampleId);
      });

      await tester.runAsync(
        () => buildRootApp(
          initBridge: () async => true,
          settings: settings,
          store: store,
        ),
      );

      expect(visionFilterState.layers, isNotEmpty, reason: '初回シードの層がある');
      expect(settings.welcomeBannerDismissed, isFalse);
    });
  });

  group('SettingsService を提供しない分離ウィジェット（例外にならない）', () {
    Widget isolated(
      Widget child, {
      required List<SingleChildWidget> providers,
    }) {
      return MultiProvider(
        providers: providers,
        child: MaterialApp(
          locale: const Locale('ja'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      );
    }

    testWidgets('FilterBrowser の行・プリセットのタップ', (tester) async {
      tester.view.physicalSize = const Size(400, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller = FilterBrowserController();
      addTearDown(controller.dispose);
      final state = VisionFilterState();

      await tester.pumpWidget(isolated(
        SizedBox(
          height: 2800,
          child: FilterBrowser(controller: controller, onActivated: () {}),
        ),
        providers: [
          ChangeNotifierProvider<VisionFilterState>.value(value: state),
        ],
      ));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('filter_tile_cv:protanopia')));
      await tester.pump();
      expect(state.layers, isNotEmpty);
      await tester.tap(find.byKey(experienceCardKey('bppv')));
      await tester.pump();
      expect(state.selectedPresetId, 'bppv');
      expect(tester.takeException(), isNull);
    });

    testWidgets('LayerChipStrip の ✕', (tester) async {
      final state = VisionFilterState()
        ..toggle('myopia')
        ..toggle('glaucoma');
      await tester.pumpWidget(isolated(
        const LayerChipStrip(),
        providers: [
          ChangeNotifierProvider<VisionFilterState>.value(value: state),
        ],
      ));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('layer_chip_remove_myopia')));
      await tester.pump();
      expect(state.layers, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('LayerChipStrip の「すべて解除」', (tester) async {
      final state = VisionFilterState()
        ..toggle('myopia')
        ..toggle('glaucoma');
      await tester.pumpWidget(isolated(
        const LayerChipStrip(),
        providers: [
          ChangeNotifierProvider<VisionFilterState>.value(value: state),
        ],
      ));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('layer_strip_clear_all')));
      await tester.pump();
      expect(state.layers, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ImageSourcePicker のサンプル切替・おすすめに戻す', (tester) async {
      final source = ImageSourceState();
      await tester.pumpWidget(isolated(
        const ImageSourcePicker(child: SizedBox(height: 10)),
        providers: [
          ChangeNotifierProvider<ImageSourceState>.value(value: source),
          ChangeNotifierProvider<VisionFilterState>(
            create: (_) => VisionFilterState(),
          ),
        ],
      ));
      await tester.pump();

      final chips = find.byType(ChoiceChip);
      final list = chips.evaluate().map((e) => e.widget as ChoiceChip).toList();
      await tester.tap(chips.at(list.indexWhere((c) => !c.selected)));
      await tester.pump();
      expect(source.isFollowingRecommended, isFalse);
      await tester.tap(find.text(ja.imageSourceResetToRecommended));
      await tester.pump();
      expect(source.isFollowingRecommended, isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}
