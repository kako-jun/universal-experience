import 'package:flutter/widgets.dart' show Rect, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/services/loupe_rect_source.dart';
import 'package:universal_experience/services/loupe_window_controller.dart';

class _FakeLoupeRectSource implements LoupeRectSource {
  const _FakeLoupeRectSource(this.rect);
  final Rect rect;

  @override
  Future<Rect?> currentRect() async => rect;
}

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

  group('LoupeWindowPolicy.isLikelyWaylandNativeSession (#63)', () {
    test('XDG_SESSION_TYPE=wayland なら true', () {
      expect(
        LoupeWindowPolicy.isLikelyWaylandNativeSession(
          {'XDG_SESSION_TYPE': 'wayland'},
        ),
        isTrue,
      );
    });

    test('WAYLAND_DISPLAY が非空なら true', () {
      expect(
        LoupeWindowPolicy.isLikelyWaylandNativeSession(
          {'WAYLAND_DISPLAY': 'wayland-0'},
        ),
        isTrue,
      );
    });

    test('GDK_BACKEND=x11 が明示されていても Wayland セッションの兆候があれば true（信頼できない側に倒す）',
        () {
      expect(
        LoupeWindowPolicy.isLikelyWaylandNativeSession({
          'XDG_SESSION_TYPE': 'wayland',
          'WAYLAND_DISPLAY': 'wayland-0',
          'GDK_BACKEND': 'x11',
        }),
        isTrue,
      );
    });

    test('X11 セッション（環境変数が無い）なら false', () {
      expect(
        LoupeWindowPolicy.isLikelyWaylandNativeSession(
          {'XDG_SESSION_TYPE': 'x11'},
        ),
        isFalse,
      );
    });

    test('環境変数が一切無ければ false', () {
      expect(LoupeWindowPolicy.isLikelyWaylandNativeSession({}), isFalse);
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
    test('永続化された clickThrough=true をそのまま適用する（復帰手段の可用性を問わない）',
        () async {
      SharedPreferences.setMockInitialValues({});
      final controller = LoupeWindowController();
      await controller.load();
      await controller.setAppMode(AppMode.loupe);
      await controller.setClickThrough(true);
      expect(controller.clickThrough, isTrue);

      await controller.restorePersistedClickThrough();

      expect(controller.clickThrough, isTrue);
    });

    test('_clickThrough が false なら何もしない（早期 return）', () async {
      SharedPreferences.setMockInitialValues({});
      final controller = LoupeWindowController();
      await controller.load();
      expect(controller.clickThrough, isFalse);

      await controller.restorePersistedClickThrough();

      expect(controller.clickThrough, isFalse);
    });
  });

  group('LoupeWindowController.load() 正規化', () {
    test('settings モードで clickThrough=true が保存されていたら false へ正規化し、'
        '書き直す', () async {
      SharedPreferences.setMockInitialValues({
        'loupeWindow.appMode': 'settings',
        'loupeWindow.clickThrough': true,
      });
      final controller = LoupeWindowController();
      await controller.load();

      expect(controller.appMode, AppMode.settings);
      expect(controller.clickThrough, isFalse);

      // 正規化した値が実際に persist されていることを、別インスタンスの
      // load() で確認する。
      final other = LoupeWindowController();
      await other.load();
      expect(other.clickThrough, isFalse);
    });

    test('loupe モードで clickThrough=true が保存されていたらそのまま復元する',
        () async {
      SharedPreferences.setMockInitialValues({
        'loupeWindow.appMode': 'loupe',
        'loupeWindow.clickThrough': true,
      });
      final controller = LoupeWindowController();
      await controller.load();

      expect(controller.appMode, AppMode.loupe);
      expect(controller.clickThrough, isTrue);
    });
  });

  group('LoupeWindowController.currentLoupeRect', () {
    test('注入した LoupeRectSource の値を返す', () async {
      const rect = Rect.fromLTWH(10, 20, 300, 200);
      final controller = LoupeWindowController(
        rectSource: const _FakeLoupeRectSource(rect),
      );

      expect(await controller.currentLoupeRect(), rect);
    });
  });

  group(
      'LoupeWindowController.onWindowFocus / onWindowBlur / '
      'releaseClickThroughOnFirstKeyPress (#63)', () {
    Future<LoupeWindowController> buildClickThroughOnController() async {
      SharedPreferences.setMockInitialValues({});
      final controller = LoupeWindowController();
      await controller.load();
      await controller.setAppMode(AppMode.loupe);
      await controller.setClickThrough(true);
      expect(controller.clickThrough, isTrue);
      return controller;
    }

    test('ON の状態で onWindowFocus → releaseClickThroughOnFirstKeyPress の順で呼ぶと解除される',
        () async {
      final controller = await buildClickThroughOnController();

      controller.onWindowFocus();
      controller.releaseClickThroughOnFirstKeyPress();

      expect(controller.clickThrough, isFalse);
    });

    test('onWindowFocus だけを呼んでも解除されない', () async {
      final controller = await buildClickThroughOnController();

      controller.onWindowFocus();

      expect(controller.clickThrough, isTrue);
    });

    test('onWindowFocus の後に onWindowBlur を呼ぶと予約は取り消され、その後の'
        'releaseClickThroughOnFirstKeyPress は何もしない', () async {
      final controller = await buildClickThroughOnController();

      controller.onWindowFocus();
      controller.onWindowBlur();
      controller.releaseClickThroughOnFirstKeyPress();

      expect(controller.clickThrough, isTrue);
    });

    test('クリックスルーが OFF のときは onWindowFocus → releaseClickThroughOnFirstKeyPress '
        'の順で呼んでも何も起きない', () async {
      SharedPreferences.setMockInitialValues({});
      final controller = LoupeWindowController();
      await controller.load();
      expect(controller.clickThrough, isFalse);

      controller.onWindowFocus();
      controller.releaseClickThroughOnFirstKeyPress();

      expect(controller.clickThrough, isFalse);
    });
  });
}
