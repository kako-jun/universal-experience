// アプリ内キー操作（Shortcuts/Actions、#63）の widget test。
//
// `/`・↑↓・←→ が home_screen.dart の Shortcuts/Actions 経由で
// preview_selection.dart のロジックへ正しく配線されていることを検証する。
// UniversalExperienceApp はトップレベル共有の visionFilterState/
// loupeWindow シングルトンを使うため（main.dart 参照）、各テストの前後で
// 状態をリセットする。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/main.dart';
import 'package:universal_experience/services/app_shortcuts.dart';
import 'package:universal_experience/services/vision_filter_snapshot.dart';
import 'package:universal_experience/services/filter_list_selection.dart';
import 'package:universal_experience/services/loupe_window_controller.dart';
import 'package:universal_experience/services/settings_service.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/widgets/experience_presets.dart';
import 'package:universal_experience/ui/widgets/filter_browser.dart';
import 'package:universal_experience/ui/widgets/filter_list_tile.dart';

import 'support/vision_filter_metadata_fixture.dart';
import 'support/color_vision_select.dart';

/// isFocusOnInteractiveControl のテスト専用ダミー Intent（本番の 3 Intent の
/// 代わりに、ガードのロジックだけを最小構成で検証するために使う）。
class _ProbeIntent extends Intent {
  const _ProbeIntent();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    experiencesProvider = () => const [];
    installVisionFilterMetadataFixture();
  });
  tearDown(() async {
    experiencesProvider = experiences;
    resetVisionFilterMetadataProviders();
    // トップレベル共有シングルトンをテスト間で汚染しない（#63）。clear() は強度の
    // 記憶を消さない（同じフィルタを選び直したときに戻すため）ので、空の snapshot で
    // 記憶ごと初期状態へ戻す。
    visionFilterState.restore(const VisionFilterSnapshot());
    await loupeWindow.setClickThrough(false);
    await loupeWindow.setAppMode(AppMode.settings);
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = SettingsService();
    await settings.load();

    await tester.pumpWidget(UniversalExperienceApp(settings: settings));
    await tester.pump();
  }

  testWidgets('/ で統合一覧の検索欄にフォーカスが移る（#72）', (WidgetTester tester) async {
    await pumpApp(tester);

    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      isNot('filterSearch'),
      reason: '起動直後は画面のショートカット受け口（autofocus）にフォーカスがあるはず',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.pump();

    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      'filterSearch',
    );
  });

  Key? focusedRowKey(WidgetTester tester) =>
      tester.binding.focusManager.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<FilterListTile>()
          ?.key;

  testWidgets('↓ で統合一覧の行へ先頭から順にフォーカスが進み、選択は変わらない（#120）',
      (WidgetTester tester) async {
    await pumpApp(tester);
    expect(visionFilterState.selectedId, isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focusedRowKey(tester), filterListTileKey(kFilterListEntries[0]));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focusedRowKey(tester), filterListTileKey(kFilterListEntries[1]));
    expect(visionFilterState.layers, isEmpty);
  });

  testWidgets('↑ で統合一覧の行へのフォーカスが一覧順に戻る（選択は変わらない、#120）',
      (WidgetTester tester) async {
    await pumpApp(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focusedRowKey(tester), filterListTileKey(kFilterListEntries[2]));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(focusedRowKey(tester), filterListTileKey(kFilterListEntries[1]));
    expect(visionFilterState.layers, isEmpty);
  });

  testWidgets('← → で advanced 選択中は VisionFilterState.strength が ±5% 動く',
      (WidgetTester tester) async {
    await pumpApp(tester);
    visionFilterState.replaceWith('cataract');
    visionFilterState.setStrength(0.5);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(visionFilterState.strength, closeTo(0.55, 1e-9));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(visionFilterState.strength, closeTo(0.45, 1e-9));
  });

  testWidgets('← → で色覚（別名 -omaly）選択中も別名キーの強度が ±5% 動く',
      (WidgetTester tester) async {
    await pumpApp(tester);
    selectColorVisionKey(visionFilterState, 'protanomaly');
    visionFilterState.setStrength(0.5);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    // 強度の正本は VisionFilterState のキーごとの記憶 1 つ。別名の層は別名 id をキーにする。
    expect(visionFilterState.strength, closeTo(0.55, 1e-9));
    expect(
        visionFilterState.strengthForKey('protanomaly'), closeTo(0.55, 1e-9));
    expect(visionFilterState.strengthForKey('protanopia'), isNull,
        reason: '別名の強度は対応する -opia の記憶と混ざらない');
  });

  testWidgets('← → で色覚 -opia 選択中は カタログ id キーの強度が ±5% 動く',
      (WidgetTester tester) async {
    await pumpApp(tester);
    selectColorVisionKey(visionFilterState, 'protanopia');
    visionFilterState.setStrength(0.5);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(visionFilterState.strength, closeTo(0.55, 1e-9));
    expect(visionFilterState.strengthForKey('protanopia'), closeTo(0.55, 1e-9));
  });

  testWidgets('Esc でクリックスルーが解除される (#63)', (WidgetTester tester) async {
    await pumpApp(tester);
    // loupe モードでないと setClickThrough(true) 自体が拒否されるため、先に
    // 切り替える。window_manager のプラットフォームチャンネル呼び出しの解決に
    // 実イベントループが要るため tester.runAsync 経由で呼ぶ
    // （window_mode_panel_test.dart の同種コメント参照）。
    await tester.runAsync(() => loupeWindow.setAppMode(AppMode.loupe));
    await tester.runAsync(() => loupeWindow.setClickThrough(true));
    await tester.pump();
    expect(loupeWindow.clickThrough, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(loupeWindow.clickThrough, isFalse);
  });

  group(
      'isFocusOnInteractiveControl / InteractiveFocusAwareCallbackAction (#63)',
      () {
    Widget buildProbe(Widget child, {required void Function() onInvoke}) {
      return MaterialApp(
        home: Scaffold(
          body: Shortcuts(
            shortcuts: const <ShortcutActivator, Intent>{
              CharacterActivator('/'): _ProbeIntent(),
              SingleActivator(LogicalKeyboardKey.arrowDown): _ProbeIntent(),
            },
            child: Actions(
              actions: <Type, Action<Intent>>{
                _ProbeIntent: InteractiveFocusAwareCallbackAction<_ProbeIntent>(
                  onInvoke: (_) {
                    onInvoke();
                    return null;
                  },
                ),
              },
              child: child,
            ),
          ),
        ),
      );
    }

    testWidgets('TextField にフォーカスがある間はショートカットが無効化され、文字はそのまま入力される',
        (WidgetTester tester) async {
      var invoked = 0;
      final controller = TextEditingController();

      await tester.pumpWidget(buildProbe(
        TextField(controller: controller, autofocus: true),
        onInvoke: () => invoked++,
      ));
      await tester.pump();

      await tester.enterText(find.byType(TextField), '/');
      await tester.pump();

      expect(controller.text, '/', reason: 'ショートカットが奪わず TextField 自体に文字が入力される');
      expect(invoked, 0, reason: 'TextField にフォーカスがある間はショートカットが無効化される');
    });

    testWidgets('Switch にフォーカスがある間はショートカットが無効化される',
        (WidgetTester tester) async {
      var invoked = 0;
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(buildProbe(
        Switch(
          value: false,
          onChanged: (_) {},
          focusNode: focusNode,
          autofocus: true,
        ),
        onInvoke: () => invoked++,
      ));
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      expect(invoked, 0, reason: 'Switch にフォーカスがある間はショートカットが無効化される');
    });

    testWidgets('FilterChip にフォーカスがある間はショートカットが無効化される',
        (WidgetTester tester) async {
      var invoked = 0;
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(buildProbe(
        FilterChip(
          label: const Text('test'),
          selected: false,
          onSelected: (_) {},
          focusNode: focusNode,
          autofocus: true,
        ),
        onInvoke: () => invoked++,
      ));
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      expect(invoked, 0, reason: 'FilterChip にフォーカスがある間はショートカットが無効化される');
    });

    testWidgets('インタラクティブでないウィジェットにフォーカスがある間は通常どおり発火する',
        (WidgetTester tester) async {
      var invoked = 0;

      await tester.pumpWidget(buildProbe(
        const Focus(autofocus: true, child: Text('probe')),
        onInvoke: () => invoked++,
      ));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      expect(invoked, 1);
    });
  });
}
