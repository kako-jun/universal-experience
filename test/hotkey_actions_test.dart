// HotkeyActions（#63）の単体テスト。すべてのコールバックをフェイクに差し替え、
// 実 OS のホットキー/window_manager 無しで検証する。
//
// #79: bypass は acquireBypass/releaseBypass/clearBypass/isHeldBy（入力元ごと
// の保持）経由になった。ほとんどのテストは HotkeyActions 自身の hold/toggle/
// 非常口ロジックだけを検証するため、フェイクの acquire/release/clear はローカル
// な bool 変数を直接書き換えるだけの単純なものにしている（実際の複数 holder の
// 振る舞いは `test/vision_filter_state_bypass_test.dart`、ホットキーと HUD の
// 相互作用は `test/loupe_hud_test.dart` で検証する）。ただし「外部からの
// clearBypass に追従できず ON にならない」バグの再現には実際の
// VisionFilterState を使う 1 本がある。

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/services/hotkey_actions.dart';
import 'package:universal_experience/services/vision_filter_state.dart';

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
        acquireBypass: () {},
        releaseBypass: () {},
        clearBypass: () {},
        isBypassHeldByHotkey: () => false,
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
        acquireBypass: () => bypassed = true,
        releaseBypass: () => bypassed = false,
        clearBypass: () => bypassed = false,
        isBypassHeldByHotkey: () => bypassed,
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

    test('keyUp が届く環境: keyDown で ON、keyUp で OFF になる（正しい hold 挙動）', () {
      var bypassed = false;
      final actions = HotkeyActions(
        deactivateFilters: () {},
        setClickThrough: (value) async {},
        setAlwaysOnTop: (value) async {},
        getClickThrough: () => false,
        acquireBypass: () => bypassed = true,
        releaseBypass: () => bypassed = false,
        clearBypass: () => bypassed = false,
        isBypassHeldByHotkey: () => bypassed,
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
        acquireBypass: () => bypassed = true,
        releaseBypass: () => bypassed = false,
        clearBypass: () => bypassed = false,
        isBypassHeldByHotkey: () => bypassed,
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
        acquireBypass: () => bypassed = true,
        releaseBypass: () => bypassed = false,
        clearBypass: () => bypassed = false,
        isBypassHeldByHotkey: () => bypassed,
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
      expect(bypassed, isTrue, reason: '押しっぱなしの間、トグルは最初の1回だけになる');
    });

    test('一度 keyUp を受け取った後は keyDown 連打しても常に true のまま', () {
      var bypassed = false;
      final now = DateTime(2026, 1, 1, 0, 0, 0);
      final actions = HotkeyActions(
        deactivateFilters: () {},
        setClickThrough: (value) async {},
        setAlwaysOnTop: (value) async {},
        getClickThrough: () => false,
        acquireBypass: () => bypassed = true,
        releaseBypass: () => bypassed = false,
        clearBypass: () => bypassed = false,
        isBypassHeldByHotkey: () => bypassed,
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

    test('keyUp はホットキーが保持していなければ何もしない（no-op）', () {
      var bypassed = false;
      var releaseCalls = 0;
      final actions = HotkeyActions(
        deactivateFilters: () {},
        setClickThrough: (value) async {},
        setAlwaysOnTop: (value) async {},
        getClickThrough: () => false,
        acquireBypass: () => bypassed = true,
        releaseBypass: () {
          releaseCalls++;
          bypassed = false;
        },
        clearBypass: () => bypassed = false,
        isBypassHeldByHotkey: () => bypassed,
        showAndFocusLoupe: () async {},
        toggleLoupeVisible: () async {},
        setLoupeVisible: (value) async {},
      );

      actions.holdOriginalKeyUp();
      expect(releaseCalls, 0);
      expect(bypassed, isFalse);
    });

    test(
        'トグルモードで外部から holder が clear された後、次の keyDown 1 回で ON になる '
        '(#79)', () {
      // 実際の VisionFilterState を使う — ローカルにミラーした bool
      // （旧 `_heldByHotkey`）だと、フィルタ選択等の外部操作が holder を
      // まとめて解除しても追従できず、次の keyDown が「まだ保持している」と
      // 誤認して release を呼ぶだけ（実際には何も起きず ON にならない）
      // というバグがあった。isBypassHeldByHotkey は都度クエリするので
      // 正しく ON になる。
      final visionState = VisionFilterState();
      const hotkeySource = 'hotkey';
      var now = DateTime(2026, 1, 1, 0, 0, 0);
      final actions = HotkeyActions(
        deactivateFilters: () {},
        setClickThrough: (value) async {},
        setAlwaysOnTop: (value) async {},
        getClickThrough: () => false,
        acquireBypass: () => visionState.acquireBypass(hotkeySource),
        releaseBypass: () => visionState.releaseBypass(hotkeySource),
        clearBypass: visionState.clearBypass,
        isBypassHeldByHotkey: () => visionState.isHeldBy(hotkeySource),
        showAndFocusLoupe: () async {},
        toggleLoupeVisible: () async {},
        setLoupeVisible: (value) async {},
        now: () => now,
      );

      // トグルモード（keyUp 未到達）で ON にする。
      actions.holdOriginalKeyDown();
      expect(visionState.bypassed, isTrue);

      // フィルタ選択などの外部操作が全 holder を一括解除する。
      visionState.clearBypass();
      expect(visionState.bypassed, isFalse);

      // 1100ms 以上空けた次の keyDown は ON になるべき（stale なローカル
      // 状態に基づいて release を呼んでしまってはいけない）。
      now = now.add(const Duration(milliseconds: 1200));
      actions.holdOriginalKeyDown();
      expect(visionState.bypassed, isTrue);
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
      var clearCalls = 0;
      bool? loupeVisiblePassed;

      final actions = HotkeyActions(
        deactivateFilters: () => deactivateCalled = true,
        setClickThrough: (value) async => clickThroughPassed = value,
        setAlwaysOnTop: (value) async => alwaysOnTopPassed = value,
        getClickThrough: () => true,
        acquireBypass: () => bypassed = true,
        releaseBypass: () => bypassed = false,
        clearBypass: () {
          clearCalls++;
          bypassed = false;
        },
        isBypassHeldByHotkey: () => bypassed,
        showAndFocusLoupe: () async => showAndFocusCalled = true,
        toggleLoupeVisible: () async {},
        setLoupeVisible: (value) async => loupeVisiblePassed = value,
      );

      await actions.emergencyExit();

      expect(deactivateCalled, isTrue, reason: '非常口はフィルタを全停止するべき');
      expect(clickThroughPassed, isFalse, reason: '非常口はクリックスルーを解除するべき');
      expect(alwaysOnTopPassed, isFalse, reason: '非常口は最前面固定を解除するべき');
      expect(showAndFocusCalled, isTrue, reason: '非常口はルーペ窓を表示・前面化するべき');
      expect(bypassed, isFalse, reason: '非常口は bypassed も解除するべき');
      expect(clearCalls, 1, reason: '非常口は誰が保持していても解除する clearBypass を呼ぶべき');
      expect(loupeVisiblePassed, isTrue, reason: '非常口はトレイの表示状態ブックキーピングも同期するべき');
    });

    test('showAndFocusLoupe が throw しても残りのステップは実行される', () async {
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
        acquireBypass: () => bypassed = true,
        releaseBypass: () => bypassed = false,
        clearBypass: () => bypassed = false,
        isBypassHeldByHotkey: () => bypassed,
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

    test('setClickThrough が throw しても残りのステップは実行される', () async {
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
        acquireBypass: () => bypassed = true,
        releaseBypass: () => bypassed = false,
        clearBypass: () => bypassed = false,
        isBypassHeldByHotkey: () => bypassed,
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
