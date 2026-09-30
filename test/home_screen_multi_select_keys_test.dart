// 多選択でのキー操作（#120、#63 の拡張）。
//
// - ↑↓ は一覧の行のフォーカスだけを動かし、選択（層の集合）は変えない。
// - 足し引きは行の Space/Enter。
// - ←→ は調整中の層（focusedId）の強度を動かす。他の層は動かない。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/services/filter_list_selection.dart';
import 'package:universal_experience/ui/widgets/filter_browser.dart';
import 'package:universal_experience/ui/widgets/filter_list_tile.dart';

import 'support/home_screen_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installHomeScreenFixtures);
  tearDown(resetHomeScreenFixtures);

  const wide = Size(1280, 800);

  FilterListEntry entry(String key) =>
      kFilterListEntries.firstWhere((e) => e.key == key);

  Key? focusedRowKey(WidgetTester tester) =>
      tester.binding.focusManager.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<FilterListTile>()
          ?.key;

  Future<void> focusRow(WidgetTester tester, FilterListEntry target) async {
    await tester.tap(find.byType(TextField));
    await tester.pump();
    for (var i = 0; i < 120; i++) {
      if (focusedRowKey(tester) == filterListTileKey(target)) return;
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    fail('Tab で ${target.key} に届かない');
  }

  group('行の上のキー', () {
    testWidgets('Space/Enter で足し引きし、↑↓ は選択を変えない', (tester) async {
      final h = await pumpHomeScreen(tester, size: wide);
      final myopia = entry('catalog:myopia');
      await focusRow(tester, myopia);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(h.visionState.layers.map((l) => l.id), ['myopia']);

      // ↑↓ で行を動かしても層は増減しない。
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(focusedRowKey(tester), isNot(filterListTileKey(myopia)));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(focusedRowKey(tester), filterListTileKey(myopia));
      expect(h.visionState.layers.map((l) => l.id), ['myopia']);

      // もう一度 Enter で外れる。
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(h.visionState.layers, isEmpty);
    });

    testWidgets('2 つ目のフィルタも Space で足せて、↓ で次の行へ進んでも層は 2 つのまま', (tester) async {
      final h = await pumpHomeScreen(tester, size: wide);
      final myopia = entry('catalog:myopia');
      final vertigo = entry('catalog:vertigo');
      await focusRow(tester, myopia);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();

      await focusRow(tester, vertigo);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(
          h.visionState.layers.map((l) => l.id).toSet(), {'myopia', 'vertigo'});

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(h.visionState.layers, hasLength(2));
    });
  });

  group('←→ は調整中の層の強度', () {
    testWidgets('調整中の層だけが動き、他の層は動かない', (tester) async {
      final h = await pumpHomeScreen(tester, size: wide);
      h.visionState.toggle('myopia');
      h.visionState.toggle('vertigo');
      h.visionState.setLayerStrength('myopia', 0.5);
      h.visionState.setLayerStrength('vertigo', 0.5);
      h.visionState.focusLayer('myopia');
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      final myopia = h.visionState.layers.firstWhere((l) => l.id == 'myopia');
      final vertigo = h.visionState.layers.firstWhere((l) => l.id == 'vertigo');
      expect(h.visionState.strengthOf(myopia), closeTo(0.55, 1e-9));
      expect(h.visionState.strengthOf(vertigo), closeTo(0.5, 1e-9));

      // 調整中を切り替えると、次の ←→ は新しい層に効く。
      h.visionState.focusLayer('vertigo');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(h.visionState.strengthOf(vertigo), closeTo(0.45, 1e-9));
      expect(h.visionState.strengthOf(myopia), closeTo(0.55, 1e-9));
    });
  });
}
