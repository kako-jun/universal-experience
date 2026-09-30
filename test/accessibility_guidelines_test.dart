// 主画面・ダイアログ・HUD がスクリーンリーダー/キーボード/低視力の人にも使えることの
// 機械検証（#45、docs/accessibility.md の「headless で確認できる項目」）。
//
// Flutter 標準のアクセシビリティ・ガイドライン（タップ領域 48dp・操作要素のラベル・
// テキストのコントラスト 4.5:1 / 大きい文字 3:1）を、実際に使うテーマ
// （ライト/ダーク/ハイコントラスト）・言語（ja/en）・幅（広幅 3 カラム/狭幅の縦積み）の
// 組み合わせで主画面に当てる。スクリーンリーダーそのものの読み上げ順・トレイ操作は
// 実機でしか確かめられないため、ここでは扱わない（docs/accessibility.md の【kako-jun 実機】）。
//
// 注: flutter_test の文字は Ahem（全面が塗りつぶしのブロック）で描かれる。コントラストは
// 「前景と背景の色の組」を測るので、実フォントでも結果は変わらない。

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/services/loupe_window_controller.dart';
import 'package:universal_experience/services/vision_filter_metadata.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart'
    show Urgency;
import 'package:universal_experience/ui/widgets/loupe_hud.dart';
import 'package:universal_experience/ui/theme/app_theme.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';

import 'support/home_screen_harness.dart';
import 'support/sample_image_generator.dart';
import 'support/color_vision_select.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installHomeScreenFixtures);
  tearDown(() {
    resetHomeScreenFixtures();
    previewSourceImageLoader = BeforeAfterView.loadPreviewSourceImage;
    afterImageRenderer = BeforeAfterView.renderAfter;
  });

  late ui.Image master;

  /// 描画は実ブリッジ（native lib）を要るので、同じ画像の複製を返すフェイクに差し替える。
  Future<void> installFakes(WidgetTester tester) async {
    await tester.runAsync(() async {
      master = await generateSampleImage(64);
    });
    addTearDown(master.dispose);
    previewSourceImageLoader = (source, size) async => master.clone();
    afterImageRenderer = (source, filter, strength) async => master.clone();
  }

  /// 非同期の描画（フェイク）と、チップ等の状態遷移アニメーションが終わるまで進める。
  /// `pump()` は時計を進めないので、遷移の途中の色を測ってしまうのを避ける。
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> pumpSelected(
    WidgetTester tester, {
    required Size size,
    required ThemeData theme,
    required Locale locale,
  }) async {
    await installFakes(tester);
    await pumpHomeScreen(
      tester,
      size: size,
      theme: theme,
      locale: locale,
      select: (s) => selectColorVisionKey(s, 'protanopia'),
    );
    await settle(tester);
  }

  const wide = Size(1280, 800);
  const narrow = Size(800, 700);

  final themes = <String, ThemeData>{
    'ライト': AppTheme.lightTheme,
    'ダーク': AppTheme.darkTheme,
    'ハイコントラスト（ライト）': AppTheme.highContrastTheme,
    'ハイコントラスト（ダーク）': AppTheme.highContrastDarkTheme,
  };

  group('タップ領域とラベル（主画面）', () {
    for (final (sizeLabel, size) in [('広幅', wide), ('狭幅', narrow)]) {
      for (final locale in const [Locale('ja'), Locale('en')]) {
        testWidgets('$sizeLabel ${locale.languageCode}', (tester) async {
          final handle = tester.ensureSemantics();
          await pumpSelected(
            tester,
            size: size,
            theme: AppTheme.lightTheme,
            locale: locale,
          );
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          handle.dispose();
        });
      }
    }
  });

  group('文字のコントラスト（主画面）', () {
    for (final entry in themes.entries) {
      for (final locale in const [Locale('ja'), Locale('en')]) {
        testWidgets('${entry.key} ${locale.languageCode}', (tester) async {
          final handle = tester.ensureSemantics();
          await pumpSelected(
            tester,
            size: wide,
            theme: entry.value,
            locale: locale,
          );
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
        });
      }
    }
  });

  // 選択の種類ごとに、右カラム（調整）に出る部品が違う。スライダー・ドロップダウン・
  // シード・受診喚起・2×2 比較を順に出して、ガイドラインを当てる。
  group('選択ごとの調整パネル', () {
    final cases = <String, void Function(HomeScreenHarness h)>{
      '色覚 + 2×2 比較の切替': (h) => selectColorVisionKey(h.visionState, 'protanopia'),
      'advanced（列挙 + 小数のパラメータ）': (h) => h.visionState.replaceWith('glaucoma'),
      'advanced（整数のパラメータ）': (h) => h.visionState.replaceWith('starbursts'),
      'advanced（シード）': (h) => h.visionState.replaceWith('floaters'),
      'advanced（強度の注意つき）': (h) => h.visionState.replaceWith('tunnel_vision'),
      '体験プリセット（緊急の受診喚起）': (h) => h.visionState
          .selectPreset('vestibular_neuritis', 'vestibular_neuritis'),
      '体験プリセット（早めの受診喚起）': (h) =>
          h.visionState.selectPreset('meniere', 'vertigo'),
    };
    for (final entry in cases.entries) {
      testWidgets(entry.key, (tester) async {
        final handle = tester.ensureSemantics();
        await installFakes(tester);
        final h = await pumpHomeScreen(tester,
            size: wide, theme: AppTheme.lightTheme);
        entry.value(h);
        await settle(tester);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }

    testWidgets('色覚 + 2×2 比較を ON', (tester) async {
      final handle = tester.ensureSemantics();
      await installFakes(tester);
      final h =
          await pumpHomeScreen(tester, size: wide, theme: AppTheme.lightTheme);
      selectColorVisionKey(h.visionState, 'protanopia');
      await tester.pump();
      await tester.tap(find.byType(FilterChip));
      await settle(tester);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  });

  group('選択ごと × テーマ（文字のコントラスト）', () {
    final cases = <String, void Function(HomeScreenHarness h)>{
      '体験プリセット（緊急の受診喚起）': (h) => h.visionState
          .selectPreset('vestibular_neuritis', 'vestibular_neuritis'),
      'advanced（強度の注意つき）': (h) => h.visionState.replaceWith('tunnel_vision'),
      'advanced（列挙 + 小数のパラメータ）': (h) => h.visionState.replaceWith('glaucoma'),
    };
    for (final theme in themes.entries) {
      for (final entry in cases.entries) {
        testWidgets('${theme.key} ${entry.key}', (tester) async {
          final handle = tester.ensureSemantics();
          await installFakes(tester);
          final h =
              await pumpHomeScreen(tester, size: wide, theme: theme.value);
          entry.value(h);
          await settle(tester);
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
        });
      }
    }
  });

  group('ダイアログ', () {
    for (final (label, tooltip) in [('言語', '言語'), ('起動モード', '起動モード')]) {
      testWidgets('$label ダイアログ', (tester) async {
        final handle = tester.ensureSemantics();
        await installFakes(tester);
        await pumpHomeScreen(tester, size: wide, theme: AppTheme.lightTheme);
        await tester.tap(find.byTooltip(tooltip));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  });

  group('ルーペ HUD（受診喚起のボタンつき）', () {
    Future<void> pumpHud(
      WidgetTester tester,
      ThemeData theme,
      Urgency urgency,
    ) async {
      visionFilterUrgencyProvider = (_) => urgency;
      visionFilterUrgencyEscalationProvider = (_) => const [];
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final visionState = VisionFilterState()..replaceWith('photophobia');
      final loupe = LoupeWindowController();
      await tester.runAsync(() => loupe.setAppMode(AppMode.loupe));
      tester.view.physicalSize = const Size(900, 300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<VisionFilterState>.value(value: visionState),
            ChangeNotifierProvider<LoupeWindowController>.value(value: loupe),
          ],
          child: MaterialApp(
            theme: theme,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: LoupeHud()),
          ),
        ),
      );
      await settle(tester);
    }

    for (final entry in themes.entries) {
      for (final (urgencyLabel, urgency) in [
        ('緊急', Urgency.emergency),
        ('早めの受診', Urgency.earlyConsultation),
      ]) {
        testWidgets('${entry.key} $urgencyLabel', (tester) async {
          final handle = tester.ensureSemantics();
          await pumpHud(tester, entry.value, urgency);
          expect(find.byType(IconButton), findsNWidgets(2),
              reason: '受診喚起と設定のボタンが出ている');
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
        });
      }
    }

    testWidgets('受診喚起のダイアログ', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpHud(tester, AppTheme.lightTheme, Urgency.emergency);
      await tester.tap(find.byIcon(Icons.warning_amber_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  });
}
