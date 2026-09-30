// 重ねているフィルタのチップ帯（#120）の widget test。
//
// 2 層以上のときだけ出る・適用順の番号・チップで「調整中」が移る・✕ で 1 層だけ外れる・
// 「すべて解除」で全部外れる・FilterService が層の集合に追従する、を確認する。

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/services/color_vision_selection.dart';
import 'package:universal_experience/services/filter_service.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/ui/widgets/layer_chip_strip.dart';

import 'support/home_screen_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installHomeScreenFixtures);
  tearDown(resetHomeScreenFixtures);

  late FilterService filterService;
  late VisionFilterState state;

  Future<void> pumpStrip(WidgetTester tester, {double width = 600}) async {
    tester.view.physicalSize = Size(width, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    state = VisionFilterState();
    filterService = FilterService(visionState: state);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<FilterService>.value(value: filterService),
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
    testWidgets('0 層・1 層では何も出ない（単一選択の見た目を変えない）', (tester) async {
      await pumpStrip(tester);
      expect(clearAll, findsNothing);
      state.toggle('myopia');
      await tester.pump();
      expect(chip('myopia'), findsNothing);
      expect(clearAll, findsNothing);
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

    testWidgets('✕ で 1 層に減るとチップ帯が消える', (tester) async {
      await pumpStrip(tester);
      state.toggle('myopia');
      state.toggle('glaucoma');
      await tester.pump();
      await tester.tap(remove('glaucoma'));
      await tester.pump();
      expect(state.layers.map((l) => l.id), ['myopia']);
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

    testWidgets('色覚の層を ✕ で外すと FilterService も追従する', (tester) async {
      await pumpStrip(tester);
      toggleColorVision(filterService, state, ColorVisionType.protanopia);
      state.toggle('myopia');
      await tester.pump();
      expect(filterService.currentFilter, ColorVisionType.protanopia);
      await tester.tap(remove('protanopia'));
      await tester.pump();
      expect(filterService.currentFilter, ColorVisionType.none);
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

    testWidgets('狭幅でも溢れずに折り返す', (tester) async {
      await pumpStrip(tester, width: 280);
      for (final id in ['myopia', 'glaucoma', 'cataract', 'floaters']) {
        state.toggle(id);
      }
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
