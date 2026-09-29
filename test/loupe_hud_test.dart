// LoupeHud（#79）の widget test。
//
// ルーペ窓モード（AppMode.loupe）のときだけ HUD が出ること、症状名・強度
// （色覚 -omaly を含む）の表示、受診喚起アイコンの条件付き表示とダイアログ、
// 原画比較ボタンの押す/離す/キャンセル/領域外での bypass 切替、設定ボタンでの
// モード復帰、全画面での自動非表示とホバーでの再表示、Semantics ラベルを検証する。
//
// urgency/urgency_escalation/recommended_strength は sensus ブリッジの provider
// seam（`vision_filter_metadata.dart`）経由なので、他の widget test と同じく
// `test/support/vision_filter_metadata_fixture.dart` のフィクスチャに差し替える。

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/services/color_vision_selection.dart';
import 'package:universal_experience/services/filter_service.dart';
import 'package:universal_experience/services/loupe_window_controller.dart';
import 'package:universal_experience/services/vision_filter_metadata.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/widgets/loupe_hud.dart';

import 'support/vision_filter_metadata_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VisionFilterState visionState;
  late FilterService filterService;
  late LoupeWindowController loupeWindow;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    installVisionFilterMetadataFixture();
    visionState = VisionFilterState();
    filterService = FilterService();
    loupeWindow = LoupeWindowController();
  });

  tearDown(resetVisionFilterMetadataProviders);

  Future<void> pumpHud(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<VisionFilterState>.value(value: visionState),
          ChangeNotifierProvider<FilterService>.value(value: filterService),
          ChangeNotifierProvider<LoupeWindowController>.value(
            value: loupeWindow,
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
          home: Scaffold(body: LoupeHud()),
        ),
      ),
    );
    await tester.pump();
  }

  group('ルーペ窓モードのときだけ表示する', () {
    testWidgets('設定窓モードでは何も描画しない', (tester) async {
      await pumpHud(tester);

      expect(find.byIcon(Icons.settings_outlined), findsNothing);
      expect(find.byIcon(Icons.visibility_outlined), findsNothing);
    });

    testWidgets('ルーペ窓モードでは HUD を描画する', (tester) async {
      await tester.runAsync(() => loupeWindow.setAppMode(AppMode.loupe));
      await pumpHud(tester);

      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });
  });

  group('症状名・強度の表示', () {
    testWidgets('advanced カタログ選択の症状名と強度を表示する', (tester) async {
      await tester.runAsync(() => loupeWindow.setAppMode(AppMode.loupe));
      visionState.select('protanopia');

      await pumpHud(tester);

      expect(find.text('Protanopia'), findsOneWidget);
      expect(find.text('Strength: 100%'), findsOneWidget);
    });

    testWidgets('色覚クイック選択は -omaly の名前を表示する', (tester) async {
      await tester.runAsync(() => loupeWindow.setAppMode(AppMode.loupe));
      selectColorVision(
          filterService, visionState, ColorVisionType.protanomaly);

      await pumpHud(tester);

      // protanomaly はカタログでは protanopia (id) に写るが、HUD の見出しは
      // colorVisionType を優先するので -omaly の名前が出る（#60 と同じ規約）。
      expect(find.text('Protanomaly'), findsOneWidget);
      // FilterService の recommendedStrength(protanomaly) は
      // kAnomalyDefaultSeverity = 0.6（60%）。
      expect(find.text('Strength: 60%'), findsOneWidget);
    });
  });

  group('受診喚起アイコン', () {
    testWidgets('喚起が無ければアイコンを出さない', (tester) async {
      await tester.runAsync(() => loupeWindow.setAppMode(AppMode.loupe));
      visionState.select('protanopia'); // urgency=none フィクスチャのまま

      await pumpHud(tester);

      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
      expect(find.byIcon(Icons.medical_information_outlined), findsNothing);
    });

    testWidgets('喚起があればアイコンを出し、押すと全文をダイアログ表示する', (tester) async {
      visionFilterUrgencyProvider = (_) => Urgency.emergency;
      visionFilterUrgencyEscalationProvider = (_) => const [];
      await tester.runAsync(() => loupeWindow.setAppMode(AppMode.loupe));
      visionState.select('photophobia');

      await pumpHud(tester);

      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.warning_amber_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Medical guidance'), findsOneWidget);
      // 喚起文（emergency）と免責文の両方が全文表示されること。
      expect(
        find.text(
          'If these symptoms appear suddenly, seek medical care right away.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
            'This is general guidance, not a medical diagnosis'),
        findsOneWidget,
      );
    });
  });

  group('原画比較ボタン', () {
    testWidgets('押している間だけ bypass が ON、離すと OFF', (tester) async {
      await tester.runAsync(() => loupeWindow.setAppMode(AppMode.loupe));
      visionState.select('protanopia');
      await pumpHud(tester);

      expect(visionState.bypassed, isFalse);

      final center = tester.getCenter(find.byIcon(Icons.visibility_outlined));
      final gesture = await tester.startGesture(center);
      await tester.pump();
      expect(visionState.bypassed, isTrue);

      await gesture.up();
      await tester.pump();
      expect(visionState.bypassed, isFalse);
    });

    testWidgets('キャンセルされたら OFF に戻る', (tester) async {
      await tester.runAsync(() => loupeWindow.setAppMode(AppMode.loupe));
      visionState.select('protanopia');
      await pumpHud(tester);

      final center = tester.getCenter(find.byIcon(Icons.visibility_outlined));
      final gesture = await tester.startGesture(center);
      await tester.pump();
      expect(visionState.bypassed, isTrue);

      await gesture.cancel();
      await tester.pump();
      expect(visionState.bypassed, isFalse);
    });

    testWidgets('押したまま領域外に出たら OFF に戻る', (tester) async {
      await tester.runAsync(() => loupeWindow.setAppMode(AppMode.loupe));
      visionState.select('protanopia');
      await pumpHud(tester);

      final center = tester.getCenter(find.byIcon(Icons.visibility_outlined));
      final gesture = await tester.startGesture(
        center,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(visionState.bypassed, isTrue);

      // ボタンの外（十分離れた座標）まで押したまま移動する。
      await gesture.moveTo(center + const Offset(500, 500));
      await tester.pump();
      expect(visionState.bypassed, isFalse);

      await gesture.up();
      await tester.pump();
    });
  });

  group('設定ボタン', () {
    testWidgets('押すと設定窓モードに戻る', (tester) async {
      await tester.runAsync(() => loupeWindow.setAppMode(AppMode.loupe));
      await pumpHud(tester);
      expect(loupeWindow.appMode, AppMode.loupe);

      await tester.runAsync(
        () => tester.tap(find.byIcon(Icons.settings_outlined)),
      );
      await tester.pump();

      expect(loupeWindow.appMode, AppMode.settings);
    });
  });

  group('全画面での自動非表示・ホバーでの再表示', () {
    testWidgets('全画面では隠れ、縁へのホバーで表示される', (tester) async {
      await tester.runAsync(() => loupeWindow.setAppMode(AppMode.loupe));
      await tester.runAsync(
        () => loupeWindow.applyAction(LoupeWindowAction.toggleFullscreen),
      );
      expect(loupeWindow.mode, LoupeWindowMode.fullscreen);

      await pumpHud(tester);

      // 不透明度 0 で操作不能（IgnorePointer）だが、ウィジェット自体はまだ
      // ツリーに存在する。
      final opacityFinder = find.byType(AnimatedOpacity);
      expect(
        tester.widget<AnimatedOpacity>(opacityFinder).opacity,
        0.0,
      );

      // MouseRegion の領域（HUD と同じ位置）へポインタを進めるとホバー扱いになる。
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await gesture.addPointer(location: tester.getCenter(opacityFinder));
      addTearDown(gesture.removePointer);
      await tester.pump();

      expect(
        tester.widget<AnimatedOpacity>(opacityFinder).opacity,
        1.0,
      );
    });
  });

  group('Semantics', () {
    testWidgets('原画比較・設定ボタンに Semantics ラベルが付いている', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.runAsync(() => loupeWindow.setAppMode(AppMode.loupe));
      await pumpHud(tester);

      expect(
        find.bySemanticsLabel('Press and hold to compare with the original'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Open settings'), findsOneWidget);

      handle.dispose();
    });
  });
}
