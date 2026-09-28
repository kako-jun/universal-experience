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
    test('keyDown は常にトグルする', () {
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

      // 1 回目の押下: ON のまま残る（keyUp が来ない）。
      actions.holdOriginalKeyDown();
      expect(bypassed, isTrue);

      // 2 回目の押下: OFF に戻る。
      actions.holdOriginalKeyDown();
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
  });
}
