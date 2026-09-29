// HotkeyActions（#63）の単体テスト。すべてのコールバックをフェイクに差し替え、
// 実 OS のホットキー/window_manager 無しで検証する。

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/services/hotkey_actions.dart';

void main() {
  group('HotkeyActions.toggleClickThrough', () {
    test('現在値の逆を setClickThrough に渡す（OFF -> ON）', () async {
      var current = false;
      bool? passed;
      final actions = HotkeyActions(
        deactivateFilters: () {},
        setClickThrough: (value) async {
          passed = value;
          current = value;
        },
        setAlwaysOnTop: (value) async {},
        getClickThrough: () => current,
        setBypassed: (value) {},
        getBypassed: () => false,
        showAndFocusLoupe: () async {},
        toggleLoupeVisible: () async {},
        setLoupeVisible: (value) async {},
      );

      await actions.toggleClickThrough();
      expect(passed, isTrue);
      expect(current, isTrue);

      await actions.toggleClickThrough();
      expect(passed, isFalse);
      expect(current, isFalse);
    });
  });

  group('HotkeyActions.holdOriginalKeyDown / holdOriginalKeyUp', () {
    test('keyDown は常にトグルする（1100ms 以上間隔を空けた押下として）', () {
      var bypassed = false;
      var now = DateTime(2026, 1, 1, 0, 0, 0);
      final actions = HotkeyActions(
        deactivateFilters: () {},
        setClickThrough: (value) async {},
        setAlwaysOnTop: (value) async {},
        getClickThrough: () => false,
        setBypassed: (value) => bypassed = value,
        getBypassed: () => bypassed,
        showAndFocusLoupe: () async {},
        toggleLoupeVisible: () async {},
        setLoupeVisible: (value) async {},
        now: () => now,
      );

      actions.holdOriginalKeyDown();
      expect(bypassed, isTrue);
      now = now.add(const Duration(milliseconds: 1200));

      actions.holdOriginalKeyDown();
      expect(bypassed, isFalse);
    });

    test('keyUp が届く環境: keyDown で ON、keyUp で OFF になる（正しい hold 挙動）',
        () {
      var bypassed = false;
      final actions = HotkeyActions(
        deactivateFilters: () {},
        setClickThrough: (value) async {},
        setAlwaysOnTop: (value) async {},
        getClickThrough: () => false,
        setBypassed: (value) => bypassed = value,
        getBypassed: () => bypassed,
        showAndFocusLoupe: () async {},
        toggleLoupeVisible: () async {},
        setLoupeVisible: (value) async {},
      );

      actions.holdOriginalKeyDown();
      expect(bypassed, isTrue);
      actions.holdOriginalKeyUp();
      expect(bypassed, isFalse);
    });

    test('keyUp が届かない環境: 連続する keyDown だけでトグルとして機能する', () {
      var bypassed = false;
      var now = DateTime(2026, 1, 1, 0, 0, 0);
      final actions = HotkeyActions(
        deactivateFilters: () {},
        setClickThrough: (value) async {},
        setAlwaysOnTop: (value) async {},
        getClickThrough: () => false,
        setBypassed: (value) => bypassed = value,
        getBypassed: () => bypassed,
        showAndFocusLoupe: () async {},
        toggleLoupeVisible: () async {},
        setLoupeVisible: (value) async {},
        now: () => now,
      );

      // 1 回目の押下: ON のまま残る（keyUp が来ない）。
      actions.holdOriginalKeyDown();
      expect(bypassed, isTrue);

      // 1100ms 以上空けた 2 回目の押下: OFF に戻る。
      now = now.add(const Duration(milliseconds: 1200));
      actions.holdOriginalKeyDown();
      expect(bypassed, isFalse);
    });

    test('OS のキーリピート（0ms→500ms→以降33ms間隔）が続く間はトグルが1回だけになる', () {
      var bypassed = false;
      var now = DateTime(2026, 1, 1, 0, 0, 0);
      final actions = HotkeyActions(
        deactivateFilters: () {},
        setClickThrough: (value) async {},
        setAlwaysOnTop: (value) async {},
        getClickThrough: () => false,
        setBypassed: (value) => bypassed = value,
        getBypassed: () => bypassed,
        showAndFocusLoupe: () async {},
        toggleLoupeVisible: () async {},
        setLoupeVisible: (value) async {},
        now: () => now,
      );

      // 最初の押下 (0ms)。
      actions.holdOriginalKeyDown();
      expect(bypassed, isTrue);

      // OS のキーリピート開始遅延を模した最初のリピート (500ms 後)。
      now = now.add(const Duration(milliseconds: 500));
      actions.holdOriginalKeyDown();
      expect(bypassed, isTrue, reason: '1100ms 未満のリピートはトグルしない');

      // 以降は一般的なキーリピート速度（33ms 間隔）で連続する。
      for (var i = 0; i < 10; i++) {
        now = now.add(const Duration(milliseconds: 33));
        actions.holdOriginalKeyDown();
      }
      expect(bypassed, isTrue,
          reason: '押しっぱなしの間、トグルは最初の1回だけになる');
    });

    test('一度 keyUp を受け取った後は keyDown 連打しても常に true のまま', () {
      var bypassed = false;
      final now = DateTime(2026, 1, 1, 0, 0, 0);
      final actions = HotkeyActions(
        deactivateFilters: () {},
        setClickThrough: (value) async {},
        setAlwaysOnTop: (value) async {},
        getClickThrough: () => false,
        setBypassed: (value) => bypassed = value,
        getBypassed: () => bypassed,
        showAndFocusLoupe: () async {},
        toggleLoupeVisible: () async {},
        setLoupeVisible: (value) async {},
        now: () => now,
      );

      actions.holdOriginalKeyDown();
      actions.holdOriginalKeyUp();
      expect(bypassed, isFalse);

      // now を進めなくても（= 同一 tick でも）常に true になる。
      actions.holdOriginalKeyDown();
      expect(bypassed, isTrue);
      actions.holdOriginalKeyDown();
      expect(bypassed, isTrue);
      actions.holdOriginalKeyDown();
      expect(bypassed, isTrue);

      actions.holdOriginalKeyUp();
      expect(bypassed, isFalse);
    });

    test('keyUp は bypassed が既に false なら何もしない（no-op）', () {
      var bypassed = false;
      var setCalls = 0;
      final actions = HotkeyActions(
        deactivateFilters: () {},
        setClickThrough: (value) async {},
        setAlwaysOnTop: (value) async {},
        getClickThrough: () => false,
        setBypassed: (value) {
          setCalls++;
          bypassed = value;
        },
        getBypassed: () => bypassed,
        showAndFocusLoupe: () async {},
        toggleLoupeVisible: () async {},
        setLoupeVisible: (value) async {},
      );

      actions.holdOriginalKeyUp();
      expect(setCalls, 0);
      expect(bypassed, isFalse);
    });
  });

  group('HotkeyActions.emergencyExit', () {
    test(
        'フィルタ停止・クリックスルー解除・最前面解除・ルーペ表示・bypassed解除・'
        'トレイ表示状態同期がすべて呼ばれる', () async {
      var deactivateCalled = false;
      bool? clickThroughPassed;
      bool? alwaysOnTopPassed;
      var showAndFocusCalled = false;
      var bypassed = true;
      bool? loupeVisiblePassed;

      final actions = HotkeyActions(
        deactivateFilters: () => deactivateCalled = true,
        setClickThrough: (value) async => clickThroughPassed = value,
        setAlwaysOnTop: (value) async => alwaysOnTopPassed = value,
        getClickThrough: () => true,
        setBypassed: (value) => bypassed = value,
        getBypassed: () => bypassed,
        showAndFocusLoupe: () async => showAndFocusCalled = true,
        toggleLoupeVisible: () async {},
        setLoupeVisible: (value) async => loupeVisiblePassed = value,
      );

      await actions.emergencyExit();

      expect(deactivateCalled, isTrue,
          reason: '非常口はフィルタを全停止するべき');
      expect(clickThroughPassed, isFalse,
          reason: '非常口はクリックスルーを解除するべき');
      expect(alwaysOnTopPassed, isFalse,
          reason: '非常口は最前面固定を解除するべき');
      expect(showAndFocusCalled, isTrue,
          reason: '非常口はルーペ窓を表示・前面化するべき');
      expect(bypassed, isFalse, reason: '非常口は bypassed も解除するべき');
      expect(loupeVisiblePassed, isTrue,
          reason: '非常口はトレイの表示状態ブックキーピングも同期するべき');
    });

    test('showAndFocusLoupe が throw しても残りのステップは実行される',
        () async {
      var deactivateCalled = false;
      bool? clickThroughPassed;
      bool? alwaysOnTopPassed;
      var bypassed = true;
      bool? loupeVisiblePassed;

      final actions = HotkeyActions(
        deactivateFilters: () => deactivateCalled = true,
        setClickThrough: (value) async => clickThroughPassed = value,
        setAlwaysOnTop: (value) async => alwaysOnTopPassed = value,
        getClickThrough: () => true,
        setBypassed: (value) => bypassed = value,
        getBypassed: () => bypassed,
        showAndFocusLoupe: () async => throw Exception('boom'),
        toggleLoupeVisible: () async {},
        setLoupeVisible: (value) async => loupeVisiblePassed = value,
      );

      await actions.emergencyExit();

      expect(deactivateCalled, isTrue);
      expect(bypassed, isFalse);
      expect(clickThroughPassed, isFalse);
      expect(alwaysOnTopPassed, isFalse);
      expect(loupeVisiblePassed, isTrue,
          reason: 'showAndFocusLoupe が失敗しても後続の setLoupeVisible は実行される');
    });

    test('setClickThrough が throw しても残りのステップは実行される',
        () async {
      var deactivateCalled = false;
      bool? alwaysOnTopPassed;
      var showAndFocusCalled = false;
      var bypassed = true;
      bool? loupeVisiblePassed;

      final actions = HotkeyActions(
        deactivateFilters: () => deactivateCalled = true,
        setClickThrough: (value) async => throw Exception('boom'),
        setAlwaysOnTop: (value) async => alwaysOnTopPassed = value,
        getClickThrough: () => true,
        setBypassed: (value) => bypassed = value,
        getBypassed: () => bypassed,
        showAndFocusLoupe: () async => showAndFocusCalled = true,
        toggleLoupeVisible: () async {},
        setLoupeVisible: (value) async => loupeVisiblePassed = value,
      );

      await actions.emergencyExit();

      expect(deactivateCalled, isTrue);
      expect(bypassed, isFalse);
      expect(alwaysOnTopPassed, isFalse);
      expect(showAndFocusCalled, isTrue);
      expect(loupeVisiblePassed, isTrue);
    });
  });
}
