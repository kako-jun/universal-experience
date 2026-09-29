// LoupeHud（#79）の widget test。
//
// ルーペ窓モード（AppMode.loupe）のときだけ HUD が出ること、症状名・強度
// （色覚 -omaly を含む、bypass に関わらず素の値を表示すること）、受診喚起
// アイコンの条件付き表示とダイアログ、原画比較ボタンの押す/離す/キャンセル/
// 領域外・タッチでの bypass 切替、フォーカス喪失・dispose・KeyRepeat での
// 解除、ホットキーとの多重 holder、設定ボタンでのモード復帰、全画面での
// 自動非表示と縁の検知帯でのホバー表示、Semantics を検証する。
//
// urgency/urgency_escalation/recommended_strength は sensus ブリッジの provider
// seam（`vision_filter_metadata.dart`）経由なので、他の widget test と同じく
// `test/support/vision_filter_metadata_fixture.dart` のフィクスチャに差し替える。

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/services/color_vision_selection.dart';
import 'package:universal_experience/services/filter_service.dart';
import 'package:universal_experience/services/hotkey_actions.dart';
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

  tearDown(() {
    resetVisionFilterMetadataProviders();
    isLoupeFullScreenProvider =
        (controller) => controller.mode == LoupeWindowMode.fullscreen;
  });

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

    testWidgets('原画比較中でも強度は素の値のまま表示する (#79 レビュー S1)', (tester) async {
      await tester.runAsync(() => loupeWindow.setAppMode(AppMode.loupe));
      visionState.select('protanopia');
      visionState.setStrength(0.42);

      await pumpHud(tester);
      expect(find.text('Strength: 42%'), findsOneWidget);

      // このボタン以外の入力元（例: ホットキー）が bypass を保持していても、
      // 強度表示は previewStrength（0.0 になる）ではなく selectedStrength の
      // 素の値のまま。
      visionState.acquireBypass('external');
      await tester.pump();

      expect(find.text('Strength: 42%'), findsOneWidget,
          reason: '原画比較中でも強度表示は変わらない');
      expect(find.text('Strength: 0%'), findsNothing);
    });

    testWidgets('原画比較中は原画比較ボタンのアイコン色が変わる (#79 レビュー S1)', (tester) async {
      await tester.runAsync(() => loupeWindow.setAppMode(AppMode.loupe));
      visionState.select('protanopia');
      await pumpHud(tester);

      final iconFinder = find.byIcon(Icons.visibility_outlined);
      final beforeColor = tester.widget<Icon>(iconFinder).color;

      visionState.acquireBypass('external');
      await tester.pump();

      final afterColor = tester.widget<Icon>(iconFinder).color;
      expect(afterColor, isNot(equals(beforeColor)),
          reason: '原画比較中であることをアイコンの色で示す');
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

    testWidgets('タッチ入力（hover の無い経路）でも押す/離すが機能する (#79 レビュー S5)', (tester) async {
      await tester.runAsync(() => loupeWindow.setAppMode(AppMode.loupe));
      visionState.select('protanopia');
      await pumpHud(tester);

      final center = tester.getCenter(find.byIcon(Icons.visibility_outlined));
      final gesture = await tester.startGesture(
        center,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      expect(visionState.bypassed, isTrue);

      await gesture.up();
      await tester.pump();
      expect(visionState.bypassed, isFalse);
    });

    testWidgets('タッチ入力で押したまま領域外に出たら OFF に戻る (#79 レビュー S5)', (tester) async {
      await tester.runAsync(() => loupeWindow.setAppMode(AppMode.loupe));
      visionState.select('protanopia');
      await pumpHud(tester);

      final center = tester.getCenter(find.byIcon(Icons.visibility_outlined));
      final gesture = await tester.startGesture(
        center,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      expect(visionState.bypassed, isTrue);

      await gesture.moveTo(center + const Offset(500, 500));
      await tester.pump();
      expect(visionState.bypassed, isFalse,
          reason: 'タッチには hover が無いため Listener.onPointerMove が主経路');

      await gesture.up();
      await tester.pump();
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

    testWidgets('dispose 時点で押下中なら holder を解放する (#79 レビュー M1)', (tester) async {
      await tester.runAsync(() => loupeWindow.setAppMode(AppMode.loupe));
      visionState.select('protanopia');
      await pumpHud(tester);

      final center = tester.getCenter(find.byIcon(Icons.visibility_outlined));
      final gesture = await tester.startGesture(center);
      await tester.pump();
      expect(visionState.bypassed, isTrue);

      // 押したまま設定窓モードへ切り替える → LoupeHud が SizedBox.shrink() を
      // 返し、原画比較ボタンが dispose される。
      await tester.runAsync(() => loupeWindow.setAppMode(AppMode.settings));
      await tester.pump();

      expect(visionState.bypassed, isFalse,
          reason: 'dispose 時点で holder を解放するべき');

      await gesture.up();
    });

    testWidgets('フォーカスを失ったら holder を解放する (#79 レビュー M2)', (tester) async {
      await tester.runAsync(() => loupeWindow.setAppMode(AppMode.loupe));
      visionState.select('protanopia');
      await pumpHud(tester);

      final iconFinder = find.byIcon(Icons.visibility_outlined);
      final focusNode = Focus.of(tester.element(iconFinder));

      // Enter で押下 → フォーカスを外す → 解放されていること。
      focusNode.requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(visionState.bypassed, isTrue);

      focusNode.unfocus();
      await tester.pump();

      expect(visionState.bypassed, isFalse,
          reason: 'フォーカスを失ったら押下中の holder を解放するべき');

      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    });

    testWidgets(
        'Enter/Space の押下・解放で bypass が切り替わり、KeyRepeat は無視する'
        ' (#79 レビュー M2)', (tester) async {
      await tester.runAsync(() => loupeWindow.setAppMode(AppMode.loupe));
      visionState.select('protanopia');
      await pumpHud(tester);

      final focusNode =
          Focus.of(tester.element(find.byIcon(Icons.visibility_outlined)));
      focusNode.requestFocus();
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(visionState.bypassed, isTrue);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(visionState.bypassed, isFalse);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(visionState.bypassed, isTrue);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(visionState.bypassed, isFalse);
    });
  });

  group('ホットキーとの多重 holder (#79 レビュー M3)', () {
    HotkeyActions buildHotkeyActions() {
      return HotkeyActions(
        deactivateFilters: () {},
        setClickThrough: (value) async {},
        setAlwaysOnTop: (value) async {},
        getClickThrough: () => false,
        acquireBypass: () => visionState.acquireBypass('hotkey'),
        releaseBypass: () => visionState.releaseBypass('hotkey'),
        clearBypass: visionState.clearBypass,
        showAndFocusLoupe: () async {},
        toggleLoupeVisible: () async {},
        setLoupeVisible: (value) async {},
      );
    }

    testWidgets('ホットキー押下 → HUD 押下 → HUD を離す → bypassed は true のまま',
        (tester) async {
      final hotkeyActions = buildHotkeyActions();
      await tester.runAsync(() => loupeWindow.setAppMode(AppMode.loupe));
      visionState.select('protanopia');
      await pumpHud(tester);

      hotkeyActions.holdOriginalKeyDown();
      expect(visionState.bypassed, isTrue);

      final center = tester.getCenter(find.byIcon(Icons.visibility_outlined));
      final gesture = await tester.startGesture(center);
      await tester.pump();
      expect(visionState.bypassed, isTrue);

      await gesture.up();
      await tester.pump();
      expect(visionState.bypassed, isTrue, reason: 'ホットキーがまだ保持している');

      hotkeyActions.holdOriginalKeyUp();
      expect(visionState.bypassed, isFalse);
    });

    testWidgets(
        'HUD 押下 → ホットキー押下 → ホットキーを離す → bypassed は true のまま'
        '（逆順）', (tester) async {
      final hotkeyActions = buildHotkeyActions();
      await tester.runAsync(() => loupeWindow.setAppMode(AppMode.loupe));
      visionState.select('protanopia');
      await pumpHud(tester);

      final center = tester.getCenter(find.byIcon(Icons.visibility_outlined));
      final gesture = await tester.startGesture(center);
      await tester.pump();
      expect(visionState.bypassed, isTrue);

      hotkeyActions.holdOriginalKeyDown();
      expect(visionState.bypassed, isTrue);

      hotkeyActions.holdOriginalKeyUp();
      expect(visionState.bypassed, isTrue, reason: 'HUD がまだ保持している');

      await gesture.up();
      await tester.pump();
      expect(visionState.bypassed, isFalse);
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

  group('全画面での自動非表示・縁の検知帯でのホバー表示', () {
    testWidgets('全画面でなければ常に表示される (#79 レビュー S5)', (tester) async {
      await tester.runAsync(() => loupeWindow.setAppMode(AppMode.loupe));
      await pumpHud(tester);

      expect(loupeWindow.mode, isNot(LoupeWindowMode.fullscreen));
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        1.0,
      );
    });

    testWidgets('全画面では隠れ、上端の検知帯（x=5）のホバーで表示される', (tester) async {
      await tester.runAsync(() => loupeWindow.setAppMode(AppMode.loupe));
      await tester.runAsync(
        () => loupeWindow.applyAction(LoupeWindowAction.toggleFullscreen),
      );
      expect(loupeWindow.mode, LoupeWindowMode.fullscreen);

      await pumpHud(tester);

      final opacityFinder = find.byType(AnimatedOpacity);
      expect(tester.widget<AnimatedOpacity>(opacityFinder).opacity, 0.0);

      // 上端の端（x=5）へポインタを進める。検知帯は全幅なので、バー本体の
      // 中心から離れた位置でも反応する。
      final topLeft = tester.getTopLeft(find.byType(LoupeHud));
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await gesture.addPointer(location: topLeft + const Offset(5, 5));
      addTearDown(gesture.removePointer);
      await tester.pump();

      expect(tester.widget<AnimatedOpacity>(opacityFinder).opacity, 1.0);
    });

    testWidgets('検知帯・バーから離れると、猶予後に隠れる', (tester) async {
      await tester.runAsync(() => loupeWindow.setAppMode(AppMode.loupe));
      await tester.runAsync(
        () => loupeWindow.applyAction(LoupeWindowAction.toggleFullscreen),
      );
      await pumpHud(tester);

      final opacityFinder = find.byType(AnimatedOpacity);
      final topLeft = tester.getTopLeft(find.byType(LoupeHud));
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await gesture.addPointer(location: topLeft + const Offset(5, 5));
      await tester.pump();
      expect(tester.widget<AnimatedOpacity>(opacityFinder).opacity, 1.0);

      // 画面外へ大きく離れる。
      await gesture.moveTo(topLeft + const Offset(5, 2000));
      await tester.pump();
      // 猶予（kLoupeHudHideDelay）未満ではまだ表示されたまま。
      await tester.pump(
        kLoupeHudHideDelay - const Duration(milliseconds: 100),
      );
      expect(tester.widget<AnimatedOpacity>(opacityFinder).opacity, 1.0,
          reason: '猶予中はまだ隠れない');

      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.widget<AnimatedOpacity>(opacityFinder).opacity, 0.0,
          reason: '猶予が過ぎたら隠れる');

      await gesture.removePointer();
    });

    testWidgets(
        '隠れている間は IgnorePointer と ExcludeSemantics でバーを外す'
        ' (#79 レビュー S3)', (tester) async {
      await tester.runAsync(() => loupeWindow.setAppMode(AppMode.loupe));
      await tester.runAsync(
        () => loupeWindow.applyAction(LoupeWindowAction.toggleFullscreen),
      );
      await pumpHud(tester);

      // AnimatedOpacity（縁のバー用）の直接の子で判定する — ボタン群の
      // Tooltip（excludeFromSemantics: true）も内部で ExcludeSemantics を
      // 使うため、配下を検索すると無関係な一致を拾ってしまう。
      final opacityFinder = find.byType(AnimatedOpacity);
      final opacityChild = tester.widget<AnimatedOpacity>(opacityFinder).child;
      expect(opacityChild, isA<ExcludeSemantics>());
      expect(
        (opacityChild as ExcludeSemantics).child,
        isA<IgnorePointer>(),
      );
      // 設定ボタンは実体としてツリーにあるが、操作不能。
      final settingsButton = tester.widget<IconButton>(
        find.descendant(
          of: opacityFinder,
          matching: find.byType(IconButton),
        ),
      );
      expect(
        settingsButton.onPressed,
        isNotNull,
        reason: 'ウィジェット自体は無効化されておらず、IgnorePointer が外側で操作を止める',
      );
    });

    testWidgets('検知帯の MouseRegion は opaque: false (#79 レビュー S3)',
        (tester) async {
      await tester.runAsync(() => loupeWindow.setAppMode(AppMode.loupe));
      await pumpHud(tester);

      final band = tester.widget<Positioned>(find.byType(Positioned));
      expect(band.height, 12);
      final bandRegion = band.child as MouseRegion;
      expect(bandRegion.opaque, isFalse);
    });

    testWidgets('全画面判定は isLoupeFullScreenProvider の seam 経由で行う',
        (tester) async {
      // controller.mode は fullscreen ではないが、seam を差し替えれば隠れる。
      isLoupeFullScreenProvider = (_) => true;
      await tester.runAsync(() => loupeWindow.setAppMode(AppMode.loupe));
      expect(loupeWindow.mode, isNot(LoupeWindowMode.fullscreen));

      await pumpHud(tester);

      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        0.0,
        reason: 'seam が true を返せば、実際の mode に関わらず隠れる',
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

    testWidgets('label と tooltip が同じ文言で二重に載らない (#79 レビュー nit)', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.runAsync(() => loupeWindow.setAppMode(AppMode.loupe));
      await pumpHud(tester);

      final node = tester.getSemantics(
        find.bySemanticsLabel('Open settings'),
      );
      expect(node.label, 'Open settings');
      expect(node.tooltip, isEmpty,
          reason: 'Tooltip.excludeFromSemantics で tooltip フィールドは載せない');

      handle.dispose();
    });

    testWidgets('押し続けられない場合の代替: Semantics.onTap でトグルできる (#79 レビュー S4)',
        (tester) async {
      final handle = tester.ensureSemantics();

      await tester.runAsync(() => loupeWindow.setAppMode(AppMode.loupe));
      visionState.select('protanopia');
      await pumpHud(tester);

      final semanticsFinder = find.semantics.byLabel(
        'Press and hold to compare with the original',
      );
      expect(visionState.bypassed, isFalse);

      tester.semantics.tap(semanticsFinder);
      await tester.pump();
      expect(visionState.bypassed, isTrue, reason: '1 回目のトグルで ON');

      tester.semantics.tap(semanticsFinder);
      await tester.pump();
      expect(visionState.bypassed, isFalse, reason: '2 回目のトグルで OFF');

      handle.dispose();
    });

    testWidgets('フォーカスが当たると 2px の枠が表示される (#79 レビュー S4)', (tester) async {
      await tester.runAsync(() => loupeWindow.setAppMode(AppMode.loupe));
      visionState.select('protanopia');
      await pumpHud(tester);

      final containerFinder =
          find.widgetWithIcon(Container, Icons.visibility_outlined);
      BoxDecoration decorationOf() =>
          tester.widget<Container>(containerFinder).decoration as BoxDecoration;

      expect(decorationOf().border, isNull);

      final focusNode = Focus.of(tester.element(containerFinder));
      focusNode.requestFocus();
      await tester.pump();
      await tester.pump();

      expect(decorationOf().border, isNotNull);
      expect(
        (decorationOf().border as Border).top.width,
        2,
      );

      focusNode.unfocus();
    });
  });
}
