import 'package:flutter/services.dart' show MethodChannel;
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

  group('LoupeWindowPolicy.initialSizeFor（起動時のウィンドウサイズ、#197）', () {
    const def = LoupeWindowPolicy.defaultSize;
    const min = LoupeWindowPolicy.minimumSize;

    test('既定は 1280x800', () {
      expect(def, const Size(1280, 800));
    });

    test('画面の大きさが取れない（null）ときは既定のまま', () {
      expect(LoupeWindowPolicy.initialSizeFor(null), def);
    });

    test('既定より大きい画面では既定のまま（画面いっぱいには広げない）', () {
      for (final display in const [
        Size(1920, 1080),
        Size(2560, 1440),
        Size(3840, 2160),
        Size(1281, 801),
      ]) {
        expect(LoupeWindowPolicy.initialSizeFor(display), def,
            reason: '$display');
      }
    });

    test('画面がちょうど既定と同じなら既定', () {
      expect(LoupeWindowPolicy.initialSizeFor(def), def);
    });

    test('既定より小さい画面では、軸ごとに画面の大きさまで縮める', () {
      // 幅は足りるが高さが足りない（1366x768 のノート PC）。
      expect(LoupeWindowPolicy.initialSizeFor(const Size(1366, 768)),
          const Size(1280, 768));
      // 高さは足りるが幅が足りない（縦置きの画面）。
      expect(LoupeWindowPolicy.initialSizeFor(const Size(1080, 1920)),
          const Size(1080, 800));
      // 両方足りない。
      expect(LoupeWindowPolicy.initialSizeFor(const Size(1024, 768)),
          const Size(1024, 768));
      expect(LoupeWindowPolicy.initialSizeFor(const Size(800, 600)),
          const Size(800, 600));
      // 1 dp だけ小さい。
      expect(LoupeWindowPolicy.initialSizeFor(const Size(1279, 799)),
          const Size(1279, 799));
      // 小数の論理ピクセル（物理 1920x1080 を DPR 1.75 で割った画面）。
      final fractional =
          LoupeWindowPolicy.initialSizeFor(const Size(1920, 1080) / 1.75);
      expect(fractional.width, closeTo(1920 / 1.75, 1e-9));
      expect(fractional.height, closeTo(1080 / 1.75, 1e-9));
    });

    test('最小サイズ以上の画面では、どの軸も画面・既定より大きくならず、最小を下回らない', () {
      for (var w = min.width; w <= 2000; w += 53) {
        for (var h = min.height; h <= 1400; h += 47) {
          final display = Size(w, h);
          final size = LoupeWindowPolicy.initialSizeFor(display);
          expect(size.width, lessThanOrEqualTo(display.width),
              reason: '$display');
          expect(size.height, lessThanOrEqualTo(display.height),
              reason: '$display');
          expect(size.width, lessThanOrEqualTo(def.width), reason: '$display');
          expect(size.height, lessThanOrEqualTo(def.height),
              reason: '$display');
          expect(size.width, greaterThanOrEqualTo(min.width),
              reason: '$display');
          expect(size.height, greaterThanOrEqualTo(min.height),
              reason: '$display');
        }
      }
    });

    test('画面がちょうど最小サイズなら最小サイズ', () {
      expect(LoupeWindowPolicy.initialSizeFor(min), min);
    });

    test('最小サイズより小さい画面では最小サイズで止まる（軸ごと。このときだけ画面より大きくなる）', () {
      expect(LoupeWindowPolicy.initialSizeFor(const Size(200, 100)), min);
      expect(LoupeWindowPolicy.initialSizeFor(const Size(1, 1)), min);
      expect(LoupeWindowPolicy.initialSizeFor(const Size(0.5, 0.5)), min);
      // 片方の軸だけ最小より小さい。
      expect(LoupeWindowPolicy.initialSizeFor(const Size(200, 600)),
          const Size(320, 600));
      expect(LoupeWindowPolicy.initialSizeFor(const Size(1000, 100)),
          const Size(1000, 240));
    });

    test('0・負・NaN・無限大の画面は「取れない」扱いで既定のまま（片方の軸だけでも）', () {
      for (final display in const [
        Size.zero,
        Size(0, 600),
        Size(800, 0),
        Size(-1, -1),
        Size(-800, 600),
        Size(800, -600),
        Size(double.nan, double.nan),
        Size(double.nan, 600),
        Size(800, double.nan),
        Size.infinite,
        Size(double.infinity, 600),
        Size(800, double.infinity),
        Size(double.negativeInfinity, 600),
      ]) {
        final size = LoupeWindowPolicy.initialSizeFor(display);
        expect(size, def, reason: '$display');
        expect(size.isFinite, isTrue, reason: '$display');
      }
    });
  });

  group('LoupeWindowPolicy.initialSizeFor: 作業領域とウィンドウ枠（#197）', () {
    const def = LoupeWindowPolicy.defaultSize;
    const min = LoupeWindowPolicy.minimumSize;

    test('作業領域が画面より小さい（1366x768 の画面でタスクバー 40 → 作業領域 1366x728）: 枠ぶんも引いて収める', () {
      // 画面全体（1366x768）を基準にすると高さ 768 になり、作業領域 728 からはみ出す。
      const workArea = Size(1366, 728);
      final size = LoupeWindowPolicy.initialSizeFor(workArea, titleBarHeight: 40);
      expect(size, const Size(1280, 688));
      expect(size.height + 40, lessThanOrEqualTo(workArea.height),
          reason: 'タイトルバーを足しても作業領域に収まる');
    });

    test('作業領域に余裕があれば、枠ぶんを引いても既定のまま', () {
      expect(
        LoupeWindowPolicy.initialSizeFor(const Size(1920, 1040),
            titleBarHeight: 40),
        def,
      );
      // ちょうど「既定 + 枠」の高さ。
      expect(
        LoupeWindowPolicy.initialSizeFor(const Size(1280, 840),
            titleBarHeight: 40),
        def,
      );
      // 1 dp 足りない。
      expect(
        LoupeWindowPolicy.initialSizeFor(const Size(1280, 839),
            titleBarHeight: 40),
        const Size(1280, 799),
      );
    });

    test('枠ぶんは高さだけから引く（幅は作業領域いっぱいまで）', () {
      expect(
        LoupeWindowPolicy.initialSizeFor(const Size(1024, 700),
            titleBarHeight: 40),
        const Size(1024, 660),
      );
    });

    test('枠ぶんを引いても最小サイズは下回らない', () {
      expect(
        LoupeWindowPolicy.initialSizeFor(const Size(400, 250),
            titleBarHeight: 40),
        Size(400, min.height),
      );
    });

    test('タイトルバーの高さが 0・負・NaN・無限大なら引かない', () {
      for (final h in [0.0, -10.0, double.nan, double.infinity]) {
        expect(
          LoupeWindowPolicy.initialSizeFor(const Size(1366, 728),
              titleBarHeight: h),
          const Size(1280, 728),
          reason: '$h',
        );
      }
    });

    test('見込みのタイトルバーの高さ（取れないとき用）は正の値', () {
      expect(LoupeWindowPolicy.fallbackTitleBarHeight, greaterThan(0));
    });
  });

  group('LoupeWindowPolicy.initialSizeFor: 起動モード（#197）', () {
    const loupe = LoupeWindowPolicy.loupeDefaultSize;

    test('ルーペ窓モードの既定は 800x600（覗き窓。主画面の 1280x800 にしない）', () {
      expect(loupe, const Size(800, 600));
      expect(
          LoupeWindowPolicy.initialSizeFor(null, mode: AppMode.loupe), loupe);
      expect(
        LoupeWindowPolicy.initialSizeFor(const Size(1920, 1040),
            mode: AppMode.loupe, titleBarHeight: 40),
        loupe,
      );
    });

    test('設定モード（既定の引数）は 1280x800', () {
      expect(
        LoupeWindowPolicy.initialSizeFor(const Size(1920, 1040),
            mode: AppMode.settings),
        LoupeWindowPolicy.defaultSize,
      );
      expect(LoupeWindowPolicy.initialSizeFor(const Size(1920, 1040)),
          LoupeWindowPolicy.defaultSize);
    });

    test('ルーペ窓モードでも、作業領域に収まらなければ枠ごと収める', () {
      expect(
        LoupeWindowPolicy.initialSizeFor(const Size(640, 480),
            mode: AppMode.loupe, titleBarHeight: 40),
        const Size(640, 440),
      );
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

  group('LoupeWindowPolicy.resolveAppMode (#156)', () {
    test('ルーペ窓が使えない間は loupe の要求も settings に解決される', () {
      expect(LoupeWindowPolicy.loupeModeAvailable, isFalse);
      expect(LoupeWindowPolicy.resolveAppMode(AppMode.loupe), AppMode.settings);
      expect(
        LoupeWindowPolicy.resolveAppMode(AppMode.settings),
        AppMode.settings,
      );
    });

    test('ルーペ窓が使えるなら要求どおり', () {
      expect(
        LoupeWindowPolicy.resolveAppMode(
          AppMode.loupe,
          loupeAvailable: true,
        ),
        AppMode.loupe,
      );
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

  group('ルーペ窓が使えない間のフォールバック (#156)', () {
    test('保存値が loupe でも settings で起動し、クリックスルーも OFF、保存値は残る', () async {
      SharedPreferences.setMockInitialValues({
        'loupeWindow.appMode': 'loupe',
        'loupeWindow.clickThrough': true,
      });
      final controller = LoupeWindowController();
      await controller.load();

      expect(controller.loupeModeAvailable, isFalse);
      expect(controller.appMode, AppMode.settings);
      expect(controller.clickThrough, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('loupeWindow.appMode'), 'loupe');
      expect(prefs.getBool('loupeWindow.clickThrough'), isFalse);
    });

    test('setAppMode(loupe) は拒否され、他の設定を保存しても保存値は残る', () async {
      SharedPreferences.setMockInitialValues({
        'loupeWindow.appMode': 'loupe',
      });
      final controller = LoupeWindowController();
      await controller.load();

      await controller.setAppMode(AppMode.loupe);
      await controller.setAlwaysOnTop(true);
      await controller.setClickThrough(true);

      expect(controller.appMode, AppMode.settings);
      expect(controller.clickThrough, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('loupeWindow.appMode'), 'loupe');
    });

    test('setAppMode(loupe) の拒否では通知もウィンドウ操作もしない', () async {
      SharedPreferences.setMockInitialValues({});
      final controller = LoupeWindowController();
      await controller.load();
      var notified = 0;
      controller.addListener(() => notified++);
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (call) async {
          calls.add(call.method);
          return null;
        },
      );
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('window_manager'), null));

      await controller.setAppMode(AppMode.loupe);

      expect(notified, 0);
      expect(calls, isNot(contains('setBackgroundColor')));
      expect(controller.appMode, AppMode.settings);
    });

    test('settings を明示的に選ぶと保存値も settings になる', () async {
      SharedPreferences.setMockInitialValues({
        'loupeWindow.appMode': 'loupe',
      });
      final controller = LoupeWindowController();
      await controller.load();

      await controller.setAppMode(AppMode.settings);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('loupeWindow.appMode'), 'settings');
    });
  });

  group('LoupeWindowController.load() / 永続化往復 (#63)', () {
    // setAppMode/setAlwaysOnTop/setClickThrough は内部で windowManager.xxx()
    // を呼ぶが、プラットフォームチャンネル未モックの `flutter test` では
    // 例外が飛ぶ。LoupeWindowController._guard がそれを catch するので、
    // ここでは「状態と永続化」だけを検証し、実ウィンドウ I/O の成否は見ない。
    test('保存値が無いときは既定（settings / OFF / OFF）を保つ', () async {
      SharedPreferences.setMockInitialValues({});
      final controller = LoupeWindowController(loupeModeAvailable: true);
      await controller.load();

      expect(controller.appMode, AppMode.settings);
      expect(controller.alwaysOnTop, isFalse);
      expect(controller.clickThrough, isFalse);
    });

    test('setAppMode/setAlwaysOnTop/setClickThrough が別インスタンスの load で復元される',
        () async {
      SharedPreferences.setMockInitialValues({});
      final a = LoupeWindowController(loupeModeAvailable: true);
      await a.load();

      await a.setAppMode(AppMode.loupe);
      await a.setAlwaysOnTop(true);
      await a.setClickThrough(true);

      final b = LoupeWindowController(loupeModeAvailable: true);
      await b.load();

      expect(b.appMode, AppMode.loupe);
      expect(b.alwaysOnTop, isTrue);
      expect(b.clickThrough, isTrue);
    });

    test('settings モードへ切り替えるとクリックスルーを強制 OFF にする', () async {
      SharedPreferences.setMockInitialValues({});
      final controller = LoupeWindowController(loupeModeAvailable: true);
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
      final controller = LoupeWindowController(loupeModeAvailable: true);
      await controller.load();

      expect(controller.appMode, LoupeWindowPolicy.defaultAppMode);
    });

    test('settings モード中は setClickThrough(true) を呼んでも ON にならない (#63)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final controller = LoupeWindowController(loupeModeAvailable: true);
      await controller.load();
      expect(controller.appMode, AppMode.settings);

      await controller.setClickThrough(true);

      expect(controller.clickThrough, isFalse);
    });

    test('loupe モード中は setClickThrough(true) が通常どおり ON になる', () async {
      SharedPreferences.setMockInitialValues({});
      final controller = LoupeWindowController(loupeModeAvailable: true);
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
      final controller = LoupeWindowController(loupeModeAvailable: true);
      await controller.load();
      await controller.setAppMode(AppMode.loupe);
      await controller.setClickThrough(true);
      expect(controller.clickThrough, isTrue);

      await controller.restorePersistedClickThrough();

      expect(controller.clickThrough, isTrue);
    });

    test('_clickThrough が false なら何もしない（早期 return）', () async {
      SharedPreferences.setMockInitialValues({});
      final controller = LoupeWindowController(loupeModeAvailable: true);
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
      final controller = LoupeWindowController(loupeModeAvailable: true);
      await controller.load();

      expect(controller.appMode, AppMode.settings);
      expect(controller.clickThrough, isFalse);

      // 正規化した値が実際に persist されていることを、別インスタンスの
      // load() で確認する。
      final other = LoupeWindowController(loupeModeAvailable: true);
      await other.load();
      expect(other.clickThrough, isFalse);
    });

    test('loupe モードで clickThrough=true が保存されていたらそのまま復元する',
        () async {
      SharedPreferences.setMockInitialValues({
        'loupeWindow.appMode': 'loupe',
        'loupeWindow.clickThrough': true,
      });
      final controller = LoupeWindowController(loupeModeAvailable: true);
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
      final controller = LoupeWindowController(loupeModeAvailable: true);
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
      final controller = LoupeWindowController(loupeModeAvailable: true);
      await controller.load();
      expect(controller.clickThrough, isFalse);

      controller.onWindowFocus();
      controller.releaseClickThroughOnFirstKeyPress();

      expect(controller.clickThrough, isFalse);
    });
  });
}
