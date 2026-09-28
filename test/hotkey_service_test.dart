// HotkeyService（#63）の単体テスト。
//
// 実 OS のグローバルホットキー登録は `flutter test` のプラットフォームチャンネル
// では動かせないため、HotkeyGateway をフェイクに差し替えて検証する（実際の
// hotkey_manager への到達は integration test 側の責務）。

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:universal_experience/services/hotkey_service.dart';

/// 登録呼び出しを記録し、[failFor] に含まれるキーの [HotKey.identifier] では
/// 例外を投げるフェイクゲートウェイ。
class _FakeHotkeyGateway implements HotkeyGateway {
  final Map<String, HotKeyHandler?> keyDownHandlers = {};
  final Map<String, HotKeyHandler?> keyUpHandlers = {};
  final List<HotKey> registered = [];
  Set<AppHotkeyAction> failFor = {};
  bool unregisterAllCalled = false;

  /// register() 呼び出し時に、どの action への登録かを識別するための
  /// identifier -> action マップ（テストが bindings の identifier で仕込む）。
  Map<String, AppHotkeyAction> identifierToAction = {};

  @override
  Future<void> register(
    HotKey hotKey, {
    HotKeyHandler? keyDownHandler,
    HotKeyHandler? keyUpHandler,
  }) async {
    final action = identifierToAction[hotKey.identifier];
    if (action != null && failFor.contains(action)) {
      throw Exception('registration failed for $action');
    }
    registered.add(hotKey);
    keyDownHandlers[hotKey.identifier] = keyDownHandler;
    keyUpHandlers[hotKey.identifier] = keyUpHandler;
  }

  @override
  Future<void> unregisterAll() async {
    unregisterAllCalled = true;
    registered.clear();
    keyDownHandlers.clear();
    keyUpHandlers.clear();
  }
}

Map<AppHotkeyAction, HotKey> _testBindings() => {
      AppHotkeyAction.toggleClickThrough: HotKey(
        identifier: 'toggleClickThrough',
        key: LogicalKeyboardKey.keyC,
        scope: HotKeyScope.system,
      ),
      AppHotkeyAction.holdOriginal: HotKey(
        identifier: 'holdOriginal',
        key: LogicalKeyboardKey.keyO,
        scope: HotKeyScope.system,
      ),
      AppHotkeyAction.emergencyExit: HotKey(
        identifier: 'emergencyExit',
        key: LogicalKeyboardKey.escape,
        scope: HotKeyScope.system,
      ),
      AppHotkeyAction.toggleLoupeVisibility: HotKey(
        identifier: 'toggleLoupeVisibility',
        key: LogicalKeyboardKey.keyL,
        scope: HotKeyScope.system,
      ),
    };

void main() {
  group('HotkeyService.init', () {
    test('全アクションが成功すれば registeredActions に入る', () async {
      final gateway = _FakeHotkeyGateway();
      final bindings = _testBindings();
      gateway.identifierToAction = {
        for (final entry in bindings.entries) entry.value.identifier: entry.key,
      };
      final service = HotkeyService(gateway: gateway);

      var toggleClickThroughDown = 0;
      var holdDown = 0;
      var holdUp = 0;
      var emergencyDown = 0;
      var toggleLoupeDown = 0;

      await service.init(
        {
          AppHotkeyAction.toggleClickThrough:
              HotkeyHandlers(onKeyDown: () => toggleClickThroughDown++),
          AppHotkeyAction.holdOriginal: HotkeyHandlers(
            onKeyDown: () => holdDown++,
            onKeyUp: () => holdUp++,
          ),
          AppHotkeyAction.emergencyExit:
              HotkeyHandlers(onKeyDown: () => emergencyDown++),
          AppHotkeyAction.toggleLoupeVisibility:
              HotkeyHandlers(onKeyDown: () => toggleLoupeDown++),
        },
        bindings: bindings,
      );

      expect(service.registeredActions, AppHotkeyAction.values.toSet());
      expect(service.failedActions, isEmpty);

      // フェイクに渡された keyDownHandler/keyUpHandler を実際に呼び出し、
      // HotkeyHandlers の各コールバックが正しく発火することを確認する。
      gateway.keyDownHandlers['toggleClickThrough']!(bindings[AppHotkeyAction.toggleClickThrough]!);
      expect(toggleClickThroughDown, 1);

      gateway.keyDownHandlers['holdOriginal']!(bindings[AppHotkeyAction.holdOriginal]!);
      expect(holdDown, 1);
      gateway.keyUpHandlers['holdOriginal']!(bindings[AppHotkeyAction.holdOriginal]!);
      expect(holdUp, 1);

      gateway.keyDownHandlers['emergencyExit']!(bindings[AppHotkeyAction.emergencyExit]!);
      expect(emergencyDown, 1);

      gateway.keyDownHandlers['toggleLoupeVisibility']!(
          bindings[AppHotkeyAction.toggleLoupeVisibility]!);
      expect(toggleLoupeDown, 1);
    });

    test('一部の登録が失敗しても他のアクションの登録は続行される', () async {
      final gateway = _FakeHotkeyGateway();
      final bindings = _testBindings();
      gateway.identifierToAction = {
        for (final entry in bindings.entries) entry.value.identifier: entry.key,
      };
      gateway.failFor = {AppHotkeyAction.toggleClickThrough};
      final service = HotkeyService(gateway: gateway);

      await service.init(
        {
          for (final action in AppHotkeyAction.values)
            action: HotkeyHandlers(onKeyDown: () {}),
        },
        bindings: bindings,
      );

      expect(service.failedActions, {AppHotkeyAction.toggleClickThrough});
      expect(
        service.registeredActions,
        AppHotkeyAction.values.toSet()..remove(AppHotkeyAction.toggleClickThrough),
      );
      expect(service.isRegistered(AppHotkeyAction.toggleClickThrough), isFalse);
      expect(service.isRegistered(AppHotkeyAction.holdOriginal), isTrue);
    });

    test('未定義のアクションはスキップされる（登録も失敗もしない）', () async {
      final gateway = _FakeHotkeyGateway();
      final bindings = _testBindings();
      gateway.identifierToAction = {
        for (final entry in bindings.entries) entry.value.identifier: entry.key,
      };
      final service = HotkeyService(gateway: gateway);

      await service.init(
        {
          AppHotkeyAction.toggleClickThrough:
              HotkeyHandlers(onKeyDown: () {}),
        },
        bindings: bindings,
      );

      expect(service.registeredActions, {AppHotkeyAction.toggleClickThrough});
      expect(service.failedActions, isEmpty);
    });

    test('dispose() は unregisterAll を呼び登録状態をクリアする', () async {
      final gateway = _FakeHotkeyGateway();
      final bindings = _testBindings();
      gateway.identifierToAction = {
        for (final entry in bindings.entries) entry.value.identifier: entry.key,
      };
      final service = HotkeyService(gateway: gateway);
      await service.init(
        {
          AppHotkeyAction.toggleClickThrough:
              HotkeyHandlers(onKeyDown: () {}),
        },
        bindings: bindings,
      );

      await service.dispose();

      expect(gateway.unregisterAllCalled, isTrue);
      expect(service.registeredActions, isEmpty);
      expect(service.failedActions, isEmpty);
    });
  });

  group('describeHotkey (#63)', () {
    test('既定バインディングを人間可読な文字列にする（useMacSymbols 省略、既定 false）',
        () {
      final bindings = defaultHotkeyBindings();
      expect(
        describeHotkey(bindings[AppHotkeyAction.toggleClickThrough]!),
        'Ctrl+Alt+Shift+C',
      );
      expect(
        describeHotkey(bindings[AppHotkeyAction.holdOriginal]!),
        'Ctrl+Alt+Shift+O',
      );
      expect(
        describeHotkey(bindings[AppHotkeyAction.emergencyExit]!),
        'Ctrl+Alt+Shift+Esc',
      );
      expect(
        describeHotkey(bindings[AppHotkeyAction.toggleLoupeVisibility]!),
        'Ctrl+Alt+Shift+L',
      );
    });

    test('useMacSymbols: true では macOS の記号表記になる', () {
      final bindings = defaultHotkeyBindings();
      expect(
        describeHotkey(
          bindings[AppHotkeyAction.toggleClickThrough]!,
          useMacSymbols: true,
        ),
        '⌃⌥⇧C',
      );
      expect(
        describeHotkey(
          bindings[AppHotkeyAction.emergencyExit]!,
          useMacSymbols: true,
        ),
        '⌃⌥⇧Esc',
      );
    });
  });

  group('HotkeyService.activeBindings (#63)', () {
    test('init() 後、登録を試みた全アクション（失敗分も含む）のバインディングを保持する',
        () async {
      final gateway = _FakeHotkeyGateway();
      final bindings = _testBindings();
      gateway.identifierToAction = {
        for (final entry in bindings.entries) entry.value.identifier: entry.key,
      };
      gateway.failFor = {AppHotkeyAction.toggleClickThrough};
      final service = HotkeyService(gateway: gateway);

      await service.init(
        {
          for (final action in AppHotkeyAction.values)
            action: HotkeyHandlers(onKeyDown: () {}),
        },
        bindings: bindings,
      );

      expect(service.activeBindings, bindings,
          reason: '登録に失敗した toggleClickThrough のぶんも含め、試みた全バインディングを保持する');
    });

    test('dispose() で activeBindings もクリアされる', () async {
      final gateway = _FakeHotkeyGateway();
      final bindings = _testBindings();
      gateway.identifierToAction = {
        for (final entry in bindings.entries) entry.value.identifier: entry.key,
      };
      final service = HotkeyService(gateway: gateway);
      await service.init(
        {
          AppHotkeyAction.toggleClickThrough: HotkeyHandlers(onKeyDown: () {}),
        },
        bindings: bindings,
      );
      expect(service.activeBindings, isNotEmpty);

      await service.dispose();

      expect(service.activeBindings, isEmpty);
    });
  });
}
