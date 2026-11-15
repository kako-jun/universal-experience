// 重ねているフィルタのチップ帯（#120）の widget test。
//
// 1 層以上で出る・0 層でも同じ高さを確保する（#183）・適用順の番号・チップで「調整中」が移る・✕ で 1 層だけ外れる・
// 「フィルタをすべて解除」で全部外れる・別名（-omaly）のチップが variantId の表示名になる、を確認する。

import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind, Tristate;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
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
      expect(tester.getSize(find.byType(LayerChipStrip)).height, 54);
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

    testWidgets('2 層で適用順のチップと「フィルタをすべて解除」が出る', (tester) async {
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
      // 「フィルタをすべて解除」が長くなり（#187）、末尾の層が調整中で右へ寄るので、2 番目の✕を見える位置へ。
      await tester.ensureVisible(remove('glaucoma'));
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

    testWidgets('「フィルタをすべて解除」で全部外れる', (tester) async {
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

    testWidgets('部品の実際の色（案内文・スクロールバーのつまみ）が面の上で十分なコントラスト', (tester) async {
      double lum(Color c) {
        double ch(double v) => v <= 0.03928
            ? v / 12.92
            : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
        return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
      }

      double ratio(Color a, Color b) {
        final x = lum(a) + 0.05;
        final y = lum(b) + 0.05;
        return x > y ? x / y : y / x;
      }

      for (final theme in [
        AppTheme.lightTheme,
        AppTheme.darkTheme,
        AppTheme.highContrastTheme,
        AppTheme.highContrastDarkTheme,
      ]) {
        // プレビューのカード面（cardTheme.color）の上に描かれる。
        final surface = theme.cardTheme.color!;
        expect(ratio(LayerChipStrip.emptyHintColorOf(theme), surface),
            greaterThanOrEqualTo(4.5),
            reason: '案内文 ${theme.brightness}');
        expect(ratio(LayerChipStrip.thumbColorOf(theme), surface),
            greaterThanOrEqualTo(3.0),
            reason: 'つまみ（非テキスト 3:1） ${theme.brightness}');
      }
    });

    // デスクトップ 3 種（Linux / macOS / Windows）の variant で回す。プラットフォームの上書きは
    // フレームワークが後始末するので、自分で debugDefaultTargetPlatformOverride を触らない
    // （戻し忘れると「debug variable was changed by the test」で落ちる）。
    testWidgets('マウス（デスクトップ）: Shift+ホイールとスクロールバーのつまみのドラッグで末尾へ届く',
        (tester) async {
      await pumpStrip(tester, width: 280);
      for (final id in ['myopia', 'glaucoma', 'cataract', 'floaters']) {
        state.toggle(id);
      }
      await tester.pump();
      final scrollable = find.descendant(
          of: find.byType(LayerChipStrip), matching: find.byType(Scrollable));
      double offset() =>
          tester.state<ScrollableState>(scrollable.first).position.pixels;
      // 末尾の層が調整中なので、最後のチップが見える位置にいる。先頭へ戻してから確かめる。
      expect(offset(), greaterThan(0));
      tester.state<ScrollableState>(scrollable.first).position.jumpTo(0);
      await tester.pump();
      expect(offset(), 0);

      // Shift+ホイール（縦のホイールを横へ）。
      final strip = tester.getRect(find.byType(LayerChipStrip));
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
          mouse.hover(strip.topLeft + const Offset(20, 20)));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 80)));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendEventToBinding(mouse.removePointer());
      await tester.pump();
      final afterWheel = offset();
      expect(afterWheel, greaterThan(0), reason: 'Shift+ホイールで横へ動く');

      // スクロールバーのつまみ（チップの下の段）を掴んで右へドラッグ（先頭へ戻して、つまみが左端にある状態から）。
      tester.state<ScrollableState>(scrollable.first).position.jumpTo(0);
      await tester.pump();
      // つまみは表示のフェードインが終わってから掴める。
      await tester.pumpAndSettle(const Duration(seconds: 1));
      final grab = Offset(strip.left + 12, strip.bottom - 3);
      final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await g.addPointer(location: grab);
      await tester.pump();
      await g.moveTo(grab);
      await tester.pump(const Duration(milliseconds: 100));
      await g.down(grab);
      await tester.pump(const Duration(milliseconds: 300));
      await g.moveBy(const Offset(40, 0));
      await tester.pump();
      await g.up();
      await tester.pump();
      expect(offset(), greaterThan(0), reason: 'つまみのドラッグで動く');
    }, variant: TargetPlatformVariant.desktop());

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
      expect(tester.getSize(find.byType(LayerChipStrip)).height, 54);
      // 「すべて解除」は帯の外（右端固定）なので、スクロールせずに常に見えて押せる。
      expect(tester.getTopLeft(clearAll).dx, lessThan(280));
      expect(tester.getRect(clearAll).right, lessThanOrEqualTo(280));
      // 末尾のチップはスクロールで届く。
      await tester.ensureVisible(chip('floaters'));
      await tester.pump();
      expect(tester.getRect(chip('floaters')).right, lessThanOrEqualTo(280));
    });
  });

  // 右端の固定枠（「2×2 で比較」）の縮み判定と高さ。選択中・未選択の両方で、幅を細かく動かして
  // 縮む境目をまたぐ。縮む前でも縮んだ後でも、チップの領域が最小幅以上・溢れなし・チップが帯の
  // 中身（スクロールバーの段を除く）に収まる。
  group('右端の固定枠の縮み判定（境目をまたぐ）', () {
    Future<void> pumpWith(WidgetTester tester,
        {required double width,
        required double scale,
        required bool selected,
        required int layers}) async {
      tester.view.physicalSize = const Size(1400, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      state = VisionFilterState();
      for (final id in ['myopia', 'protanopia'].take(layers)) {
        state.toggle(id);
      }
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<VisionFilterState>.value(value: state),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            locale: const Locale('ja'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: LayerChipStrip(
                    trailingLabel: '2×2 で比較',
                    trailingBuilder: (context, compact) => FilterChip(
                      label: compact
                          ? const Icon(Icons.compare, size: 20)
                          : const Text('2×2 で比較'),
                      selected: selected,
                      onSelected: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    // 文字つきのチップは、親の高さの制約に潰されず、単体で置いたときの高さのまま（余白を削られない）。
    for (final scale in [1.0, 2.0, 3.0]) {
      testWidgets('文字 x$scale: 文字つきの「2×2 で比較」は単体と同じ高さで帯に置かれる', (tester) async {
        await pumpWith(tester,
            width: 1300, scale: scale, selected: true, layers: 1);
        expect(find.byIcon(Icons.compare), findsNothing, reason: '幅が十分なので文字つき');
        final inStrip = tester.getSize(find.byType(FilterChip)).height;
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: FilterChip(
                label: const Text('2×2 で比較'),
                selected: true,
                onSelected: (_) {},
              ),
            ),
          ),
        ));
        final natural = tester.getSize(find.byType(FilterChip)).height;
        expect(inStrip, natural, reason: '帯の中のチップ $inStrip と単体 $natural');
      });
    }

    for (final scale in [1.0, 2.0, 3.0]) {
      for (final selected in [false, true]) {
        for (final layers in [1, 2]) {
          testWidgets(
              '文字 x$scale・${selected ? '選択中' : '未選択'}・$layers 層: 幅 280〜700 を動かしても収まる',
              (tester) async {
            final errors = <String>[];
            final previous = FlutterError.onError;
            FlutterError.onError = (d) => errors.add(d.toString());
            try {
              for (var w = 280.0; w <= 700; w += 3) {
                await pumpWith(tester,
                    width: w, scale: scale, selected: selected, layers: layers);
                final strip = tester.getRect(find.byType(LayerChipStrip));
                final area = tester.getSize(find
                    .descendant(
                        of: find.byType(LayerChipStrip),
                        matching: find.byType(Scrollable))
                    .first);
                expect(area.width,
                    greaterThanOrEqualTo(LayerChipStrip.minChipAreaWidth),
                    reason: '幅 $w: チップの領域');
                final r = tester.getRect(find.byType(FilterChip));
                expect(r.left, greaterThanOrEqualTo(strip.left),
                    reason: '幅 $w');
                expect(r.right, lessThanOrEqualTo(strip.right), reason: '幅 $w');
                expect(r.top, greaterThanOrEqualTo(strip.top), reason: '幅 $w');
                expect(
                    r.bottom,
                    lessThanOrEqualTo(
                        strip.bottom - LayerChipStrip.scrollbarLane),
                    reason: '幅 $w: チップ ${r.height} が帯の中身に収まる');
              }
            } finally {
              FlutterError.onError = previous;
            }
            // この部品だけの試験なので、どんな例外（チップ内部の溢れも）も失敗にする。
            expect(errors, isEmpty, reason: '${errors.take(1)}');
          });
        }
      }
    }
  });
}
