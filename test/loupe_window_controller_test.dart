import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/services/loupe_window_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LoupeWindowPolicy minimum size', () {
    test('minimum size is 320x240 (QVGA 4:3)', () {
      expect(LoupeWindowPolicy.minimumSize, const Size(320, 240));
    });

    test('default size is larger than minimum on both axes', () {
      expect(
        LoupeWindowPolicy.defaultSize.width,
        greaterThan(LoupeWindowPolicy.minimumSize.width),
      );
      expect(
        LoupeWindowPolicy.defaultSize.height,
        greaterThan(LoupeWindowPolicy.minimumSize.height),
      );
    });

    test('minimum size keeps a 4:3 aspect ratio', () {
      const s = LoupeWindowPolicy.minimumSize;
      expect(s.width / s.height, closeTo(4 / 3, 0.0001));
    });
  });

  group('LoupeWindowPolicy defaults', () {
    test('always-on-top is off by default (#63, toggle-style)', () {
      expect(LoupeWindowPolicy.defaultAlwaysOnTop, isFalse);
    });

    test('transparent background is on by default', () {
      expect(LoupeWindowPolicy.defaultTransparent, isTrue);
    });

    test('click-through is off by default (toggle-style)', () {
      expect(LoupeWindowPolicy.defaultClickThrough, isFalse);
    });

    test('startup app mode is settings by default (#63)', () {
      expect(LoupeWindowPolicy.defaultAppMode, AppMode.settings);
    });
  });

  group('LoupeWindowPolicy.transparentForMode (#63)', () {
    test('settings mode is opaque', () {
      expect(LoupeWindowPolicy.transparentForMode(AppMode.settings), isFalse);
    });

    test('loupe mode is transparent', () {
      expect(LoupeWindowPolicy.transparentForMode(AppMode.loupe), isTrue);
    });
  });

  group('LoupeWindowPolicy.canEnableClickThrough (#63)', () {
    test('tray available alone is enough', () {
      expect(
        LoupeWindowPolicy.canEnableClickThrough(
          trayAvailable: true,
          clickThroughHotkeyAvailable: false,
          emergencyExitHotkeyAvailable: false,
        ),
        isTrue,
      );
    });

    test('click-through hotkey alone is enough', () {
      expect(
        LoupeWindowPolicy.canEnableClickThrough(
          trayAvailable: false,
          clickThroughHotkeyAvailable: true,
          emergencyExitHotkeyAvailable: false,
        ),
        isTrue,
      );
    });

    test('emergency-exit hotkey alone is enough', () {
      expect(
        LoupeWindowPolicy.canEnableClickThrough(
          trayAvailable: false,
          clickThroughHotkeyAvailable: false,
          emergencyExitHotkeyAvailable: true,
        ),
        isTrue,
      );
    });

    test('none available forbids enabling', () {
      expect(
        LoupeWindowPolicy.canEnableClickThrough(
          trayAvailable: false,
          clickThroughHotkeyAvailable: false,
          emergencyExitHotkeyAvailable: false,
        ),
        isFalse,
      );
    });
  });

  group('LoupeWindowPolicy.showFrame (frame policy)', () {
    test('normal shows a frame', () {
      expect(LoupeWindowPolicy.showFrame(LoupeWindowMode.normal), isTrue);
    });

    test('maximized still shows a frame (edge stays visible)', () {
      expect(LoupeWindowPolicy.showFrame(LoupeWindowMode.maximized), isTrue);
    });

    test('fullscreen hides the frame (immersive)', () {
      expect(LoupeWindowPolicy.showFrame(LoupeWindowMode.fullscreen), isFalse);
    });
  });

  group('LoupeWindowPolicy.resolveMode (state transitions)', () {
    test('restore always returns to normal', () {
      for (final m in LoupeWindowMode.values) {
        expect(
          LoupeWindowPolicy.resolveMode(m, LoupeWindowAction.restore),
          LoupeWindowMode.normal,
        );
      }
    });

    test('toggleMaximize: normal -> maximized', () {
      expect(
        LoupeWindowPolicy.resolveMode(
          LoupeWindowMode.normal,
          LoupeWindowAction.toggleMaximize,
        ),
        LoupeWindowMode.maximized,
      );
    });

    test('toggleMaximize: maximized -> normal (back)', () {
      expect(
        LoupeWindowPolicy.resolveMode(
          LoupeWindowMode.maximized,
          LoupeWindowAction.toggleMaximize,
        ),
        LoupeWindowMode.normal,
      );
    });

    test('toggleMaximize from fullscreen goes to maximized', () {
      expect(
        LoupeWindowPolicy.resolveMode(
          LoupeWindowMode.fullscreen,
          LoupeWindowAction.toggleMaximize,
        ),
        LoupeWindowMode.maximized,
      );
    });

    test('toggleFullscreen: normal -> fullscreen', () {
      expect(
        LoupeWindowPolicy.resolveMode(
          LoupeWindowMode.normal,
          LoupeWindowAction.toggleFullscreen,
        ),
        LoupeWindowMode.fullscreen,
      );
    });

    test('toggleFullscreen: fullscreen -> normal (back)', () {
      expect(
        LoupeWindowPolicy.resolveMode(
          LoupeWindowMode.fullscreen,
          LoupeWindowAction.toggleFullscreen,
        ),
        LoupeWindowMode.normal,
      );
    });

    test('toggleFullscreen from maximized goes to fullscreen', () {
      expect(
        LoupeWindowPolicy.resolveMode(
          LoupeWindowMode.maximized,
          LoupeWindowAction.toggleFullscreen,
        ),
        LoupeWindowMode.fullscreen,
      );
    });
  });

  group('LoupeWindowController.load() / 永続化往復 (#63)', () {
    // setAppMode/setAlwaysOnTop/setClickThrough は内部で windowManager.xxx()
    // を呼ぶが、プラットフォームチャンネル未モックの `flutter test` では
    // 例外が飛ぶ。LoupeWindowController._guard がそれを catch するので、
    // ここでは「状態と永続化」だけを検証し、実ウィンドウ I/O の成否は見ない。
    test('保存値が無いときは既定（settings / OFF / OFF）を保つ', () async {
      SharedPreferences.setMockInitialValues({});
      final controller = LoupeWindowController();
      await controller.load();

      expect(controller.appMode, AppMode.settings);
      expect(controller.alwaysOnTop, isFalse);
      expect(controller.clickThrough, isFalse);
    });

    test('setAppMode/setAlwaysOnTop/setClickThrough が別インスタンスの load で復元される',
        () async {
      SharedPreferences.setMockInitialValues({});
      final a = LoupeWindowController();
      await a.load();

      await a.setAppMode(AppMode.loupe);
      await a.setAlwaysOnTop(true);
      await a.setClickThrough(true);

      final b = LoupeWindowController();
      await b.load();

      expect(b.appMode, AppMode.loupe);
      expect(b.alwaysOnTop, isTrue);
      expect(b.clickThrough, isTrue);
    });

    test('settings モードへ切り替えるとクリックスルーを強制 OFF にする', () async {
      SharedPreferences.setMockInitialValues({});
      final controller = LoupeWindowController();
      await controller.load();

      await controller.setAppMode(AppMode.loupe);
      await controller.setClickThrough(true);
      expect(controller.clickThrough, isTrue);

      await controller.setAppMode(AppMode.settings);
      expect(controller.clickThrough, isFalse);
    });

    test('未知の保存値は既定の appMode にフォールバックする', () async {
      SharedPreferences.setMockInitialValues({
        'loupeWindow.appMode': 'not_a_mode',
      });
      final controller = LoupeWindowController();
      await controller.load();

      expect(controller.appMode, LoupeWindowPolicy.defaultAppMode);
    });

    test('settings モード中は setClickThrough(true) を呼んでも ON にならない (#63)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final controller = LoupeWindowController();
      await controller.load();
      expect(controller.appMode, AppMode.settings);

      await controller.setClickThrough(true);

      expect(controller.clickThrough, isFalse);
    });

    test('loupe モード中は setClickThrough(true) が通常どおり ON になる', () async {
      SharedPreferences.setMockInitialValues({});
      final controller = LoupeWindowController();
      await controller.load();
      await controller.setAppMode(AppMode.loupe);

      await controller.setClickThrough(true);

      expect(controller.clickThrough, isTrue);
    });
  });

  group('LoupeWindowController.restorePersistedClickThrough (#63)', () {
    Future<LoupeWindowController> loadedWithClickThroughOn() async {
      SharedPreferences.setMockInitialValues({});
      final controller = LoupeWindowController();
      await controller.load();
      // loupe モードでないと setClickThrough(true) 自体が拒否されるため、
      // 先にモードを切り替えてから ON にし、改めて保存値だけを model 化する
      // （実運用では前回セッションの永続化値をそのまま load() で復元する形）。
      await controller.setAppMode(AppMode.loupe);
      await controller.setClickThrough(true);
      return controller;
    }

    test('復帰手段が1つも無ければ clickThrough は false になる', () async {
      final controller = await loadedWithClickThroughOn();
      expect(controller.clickThrough, isTrue);

      await controller.restorePersistedClickThrough(
        trayAvailable: false,
        clickThroughHotkeyAvailable: false,
        emergencyExitHotkeyAvailable: false,
      );

      expect(controller.clickThrough, isFalse);
    });

    test('トレイが使えるなら clickThrough は true のまま', () async {
      final controller = await loadedWithClickThroughOn();

      await controller.restorePersistedClickThrough(
        trayAvailable: true,
        clickThroughHotkeyAvailable: false,
        emergencyExitHotkeyAvailable: false,
      );

      expect(controller.clickThrough, isTrue);
    });

    test('クリックスルー解除ホットキーが使えるなら clickThrough は true のまま',
        () async {
      final controller = await loadedWithClickThroughOn();

      await controller.restorePersistedClickThrough(
        trayAvailable: false,
        clickThroughHotkeyAvailable: true,
        emergencyExitHotkeyAvailable: false,
      );

      expect(controller.clickThrough, isTrue);
    });

    test('非常口ホットキーが使えるなら clickThrough は true のまま', () async {
      final controller = await loadedWithClickThroughOn();

      await controller.restorePersistedClickThrough(
        trayAvailable: false,
        clickThroughHotkeyAvailable: false,
        emergencyExitHotkeyAvailable: true,
      );

      expect(controller.clickThrough, isTrue);
    });

    test('_clickThrough が false なら何もしない（早期 return）', () async {
      SharedPreferences.setMockInitialValues({});
      final controller = LoupeWindowController();
      await controller.load();
      expect(controller.clickThrough, isFalse);

      await controller.restorePersistedClickThrough(
        trayAvailable: false,
        clickThroughHotkeyAvailable: false,
        emergencyExitHotkeyAvailable: false,
      );

      expect(controller.clickThrough, isFalse);
    });
  });
}
