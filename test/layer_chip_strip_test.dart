// 重ねているフィルタのチップ帯（#120）の widget test。
//
// 1 層以上で出る・0 層でも同じ高さを確保する（#183）・適用順の番号・チップで「調整中」が移る・✕ で 1 層だけ外れる・
// 「すべて解除」で全部外れる・別名（-omaly）のチップが variantId の表示名になる、を確認する。

import 'dart:math' as math;
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/l10n/l10n_extensions.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/ui/theme/app_theme.dart';
import 'package:universal_experience/ui/widgets/layer_chip_strip.dart';

import 'support/home_screen_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installHomeScreenFixtures);
  tearDown(resetHomeScreenFixtures);

  late VisionFilterState state;

  Future<void> pumpStrip(WidgetTester tester, {double width = 600}) async {
    tester.view.physicalSize = Size(width, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    state = VisionFilterState();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<VisionFilterState>.value(value: state),
        ],
        child: const MaterialApp(
          locale: Locale('ja'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: Center(child: LayerChipStrip())),
        ),
      ),
    );
  }

  Finder chip(String id) => find.byKey(ValueKey('layer_chip_$id'));
  Finder remove(String id) => find.byKey(ValueKey('layer_chip_remove_$id'));
  final clearAll = find.byKey(const ValueKey('layer_strip_clear_all'));

  group('表示条件', () {
    testWidgets('0 層ではチップも「すべて解除」も出ない（領域だけ確保）', (tester) async {
      await pumpStrip(tester);
      expect(clearAll, findsNothing);
      expect(tester.getSize(find.byType(LayerChipStrip)).height, 52);
    });

    testWidgets('0 層には淡い案内文が出る', (tester) async {
      await pumpStrip(tester);
      expect(find.text('選んだフィルタがここに並びます'), findsOneWidget);
      state.toggle('myopia');
      await tester.pump();
      expect(find.text('選んだフィルタがここに並びます'), findsNothing);
    });

    testWidgets('層を足すと、調整中になったチップが見える位置へスクロールする', (tester) async {
      await pumpStrip(tester, width: 280);
      for (final id in ['myopia', 'glaucoma', 'cataract', 'floaters']) {
        state.toggle(id);
        await tester.pump();
        await tester.pump();
      }
      expect(tester.getRect(chip('floaters')).right, lessThanOrEqualTo(280));
      expect(tester.getRect(chip('floaters')).left, greaterThanOrEqualTo(0));
    });

    testWidgets('文字 x2 でも帯の高さが層数に依らない', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpStrip(tester, width: 600);
      final h0 = tester.getSize(find.byType(LayerChipStrip)).height;
      for (final id in ['myopia', 'glaucoma', 'cataract']) {
        state.toggle(id);
        await tester.pump();
        expect(tester.getSize(find.byType(LayerChipStrip)).height, h0);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('1 層でチップが出る。「すべて解除」は 2 層以上のときだけ', (tester) async {
      await pumpStrip(tester);
      state.toggle('myopia');
      await tester.pump();
      expect(chip('myopia'), findsOneWidget);
      expect(clearAll, findsNothing);
      state.toggle('glaucoma');
      await tester.pump();
      expect(clearAll, findsOneWidget);
    });

    testWidgets('0/1/2/5 層で帯の高さが同一', (tester) async {
      await pumpStrip(tester, width: 400);
      final heights = <double>[];
      final ids = ['myopia', 'glaucoma', 'cataract', 'floaters', 'hyperopia'];
      for (var n = 0; n <= 5; n++) {
        if (n > 0) state.toggle(ids[n - 1]);
        await tester.pump();
        expect(state.layers.length, n);
        if (n == 0 || n == 1 || n == 2 || n == 5) {
          heights.add(tester.getSize(find.byType(LayerChipStrip)).height);
        }
      }
      expect(heights.toSet().length, 1, reason: '$heights');
      expect(tester.takeException(), isNull);
    });

    testWidgets('0→1→2 層で帯の下のウィジェットの位置が動かない', (tester) async {
      tester.view.physicalSize = const Size(600, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      state = VisionFilterState();
      await tester.pumpWidget(
        ChangeNotifierProvider<VisionFilterState>.value(
          value: state,
          child: const MaterialApp(
            locale: Locale('ja'),
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Column(
                children: [
                  LayerChipStrip(),
                  SizedBox(key: ValueKey('below'), height: 10),
                ],
              ),
            ),
          ),
        ),
      );
      final below = find.byKey(const ValueKey('below'));
      final dy0 = tester.getTopLeft(below).dy;
      state.toggle('myopia');
      await tester.pump();
      expect(tester.getTopLeft(below).dy, dy0);
      state.toggle('glaucoma');
      await tester.pump();
      expect(tester.getTopLeft(below).dy, dy0);
    });

    testWidgets('2 層で適用順のチップと「すべて解除」が出る', (tester) async {
      await pumpStrip(tester);
      state.toggle('glaucoma');
      state.toggle('myopia');
      await tester.pump();
      expect(chip('myopia'), findsOneWidget);
      expect(chip('glaucoma'), findsOneWidget);
      expect(clearAll, findsOneWidget);
      // 段順（近視 → 緑内障）で 1, 2 の番号。
      expect(
        tester.getTopLeft(chip('myopia')).dx,
        lessThan(tester.getTopLeft(chip('glaucoma')).dx),
      );
      expect(
        find.descendant(of: chip('myopia'), matching: find.text('1')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: chip('glaucoma'), matching: find.text('2')),
        findsOneWidget,
      );
    });
  });

  group('操作', () {
    testWidgets('チップを押すとそのフィルタが調整中になる', (tester) async {
      await pumpStrip(tester);
      state.toggle('myopia');
      state.toggle('glaucoma');
      await tester.pump();
      expect(state.focusedId, 'glaucoma');
      await tester.tap(chip('myopia'));
      await tester.pump();
      expect(state.focusedId, 'myopia');
      expect(state.layers.length, 2, reason: 'フォーカスだけ移り、層は変わらない');
    });

    testWidgets('✕ でその 1 層だけが外れる', (tester) async {
      await pumpStrip(tester);
      state.toggle('myopia');
      state.toggle('glaucoma');
      state.toggle('cataract');
      await tester.pump();
      await tester.tap(remove('glaucoma'));
      await tester.pump();
      expect(state.layers.map((l) => l.id), ['myopia', 'cataract']);
      expect(chip('glaucoma'), findsNothing);
    });

    testWidgets('1 層でも ✕ でそのフィルタが外れる', (tester) async {
      await pumpStrip(tester);
      state.toggle('myopia');
      await tester.pump();
      await tester.tap(remove('myopia'));
      await tester.pump();
      expect(state.layers, isEmpty);
      expect(chip('myopia'), findsNothing);
    });

    testWidgets('✕ で 1 層に減ってもチップ帯は残る', (tester) async {
      await pumpStrip(tester);
      state.toggle('myopia');
      state.toggle('glaucoma');
      await tester.pump();
      await tester.tap(remove('glaucoma'));
      await tester.pump();
      expect(state.layers.map((l) => l.id), ['myopia']);
      expect(chip('myopia'), findsOneWidget);
      expect(clearAll, findsNothing);
    });

    testWidgets('「すべて解除」で全部外れる', (tester) async {
      await pumpStrip(tester);
      state.toggle('myopia');
      state.toggle('glaucoma');
      await tester.pump();
      await tester.tap(clearAll);
      await tester.pump();
      expect(state.layers, isEmpty);
      expect(clearAll, findsNothing);
    });

    testWidgets('色覚の層を ✕ で外すと、その層だけが消える', (tester) async {
      await pumpStrip(tester);
      state.toggle('protanopia');
      state.toggle('myopia');
      await tester.pump();
      // 色覚は適用順（段順）で他の層より後ろに並ぶ。
      expect(state.layers.map((l) => l.id), ['myopia', 'protanopia']);
      await tester.tap(remove('protanopia'));
      await tester.pump();
      expect(state.layers.map((l) => l.id), ['myopia']);
      expect(chip('protanopia'), findsNothing);
    });

    testWidgets('別名（-omaly）の層のチップは variantId の表示名を出し、✕ で外れる', (tester) async {
      await pumpStrip(tester);
      final l10n = lookupAppLocalizations(const Locale('ja'));
      state.toggle('protanopia', variantId: 'protanomaly');
      state.toggle('myopia');
      await tester.pump();
      expect(
        find.descendant(
            of: chip('protanopia'),
            matching: find.text(visionFilterName(l10n, 'protanomaly'))),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: chip('protanopia'),
            matching: find.text(visionFilterName(l10n, 'protanopia'))),
        findsNothing,
        reason: '-opia ではなく -omaly の名前になる',
      );
      await tester.tap(remove('protanopia'));
      await tester.pump();
      expect(state.layers.map((l) => l.id), ['myopia']);
    });
  });

  group('見た目・アクセシビリティ', () {
    testWidgets('調整中のチップは selected の Semantics を持つ', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpStrip(tester);
      state.toggle('myopia');
      state.toggle('glaucoma');
      await tester.pump();
      final focused =
          tester.getSemantics(find.bySemanticsLabel(RegExp('^適用順 2 番目')));
      final other =
          tester.getSemantics(find.bySemanticsLabel(RegExp('^適用順 1 番目')));
      expect(focused.flagsCollection.isSelected, Tristate.isTrue);
      expect(other.flagsCollection.isSelected, Tristate.isFalse);
      handle.dispose();
    });

    testWidgets('✕ とチップ本体は 48dp 以上のタップ領域', (tester) async {
      await pumpStrip(tester);
      state.toggle('myopia');
      state.toggle('glaucoma');
      await tester.pump();
      expect(tester.getSize(remove('myopia')).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(remove('myopia')).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(chip('myopia')).height, greaterThanOrEqualTo(48));
    });

    testWidgets('0 層の案内文は面の上で 4.5:1 以上のコントラスト（明・暗・高コントラスト）', (tester) async {
      double lum(Color c) {
        double ch(double v) => v <= 0.03928
            ? v / 12.92
            : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
        return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
      }

      for (final theme in [
        AppTheme.lightTheme,
        AppTheme.darkTheme,
        AppTheme.highContrastTheme,
        AppTheme.highContrastDarkTheme,
      ]) {
        final scheme = theme.colorScheme;
        // プレビューのカード面（cardTheme.color = surfaceContainerHighest）の上に描く。
        final a = lum(scheme.onSurfaceVariant) + 0.05;
        final b = lum(scheme.surfaceContainerHighest) + 0.05;
        final ratio = a > b ? a / b : b / a;
        expect(ratio, greaterThanOrEqualTo(4.5), reason: '${theme.brightness}');
      }
    });

    testWidgets('スクロールバーの段はチップの下（チップの枠と重ならない）', (tester) async {
      await pumpStrip(tester, width: 280);
      state.toggle('myopia');
      state.toggle('glaucoma');
      await tester.pump();
      final strip = tester.getRect(find.byType(LayerChipStrip));
      expect(tester.getRect(chip('myopia')).bottom,
          lessThanOrEqualTo(strip.bottom - LayerChipStrip.scrollbarLane));
    });

    testWidgets('狭幅でも溢れず、1 行のまま横スクロールで末尾に届く', (tester) async {
      await pumpStrip(tester, width: 280);
      for (final id in ['myopia', 'glaucoma', 'cataract', 'floaters']) {
        state.toggle(id);
      }
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(LayerChipStrip)).height, 52);
      // 「すべて解除」は帯の外（右端固定）なので、スクロールせずに常に見えて押せる。
      expect(tester.getTopLeft(clearAll).dx, lessThan(280));
      expect(tester.getRect(clearAll).right, lessThanOrEqualTo(280));
      // 末尾のチップはスクロールで届く。
      await tester.ensureVisible(chip('floaters'));
      await tester.pump();
      expect(tester.getRect(chip('floaters')).right, lessThanOrEqualTo(280));
    });
  });
}
