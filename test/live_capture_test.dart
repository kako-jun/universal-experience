import 'dart:async';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/models/vision_filter_catalog.dart';
import 'package:universal_experience/rendering/live_filter_plan.dart';
import 'package:universal_experience/services/live_capture_service.dart';
import 'package:universal_experience/services/live_loupe_session.dart';
import 'package:universal_experience/services/loupe_window_controller.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/services/vision_layer.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/widgets/window_mode_panel.dart'
    show loupeUnavailableNote;

/// ライブのルーペ（#180）の純粋ロジック: シェーダの計画・ネイティブ応答の読み取り・
/// ルーペ窓モードと共有の寿命。

class _FakeBackend implements LiveCaptureBackend {
  _FakeBackend({this.startResult = const LiveCaptureStartResult()});

  LiveCaptureStartResult startResult;
  final List<String> calls = [];
  String? lastToken;
  int sequence = 0;
  void Function(String reason)? stoppedCallback;

  /// 設定すると start はこれが完了するまで返らない（ダイアログの応答待ち）。
  Completer<LiveCaptureStartResult>? pendingStart;

  /// true なら start が例外を投げる。
  bool throwOnStart = false;

  /// true なら setHidden(true) が例外を投げる（false は投げない）。
  bool throwOnHide = false;

  /// true ならフレームが届かない（frameSequence が進まない）。
  bool frozen = false;

  @override
  set onStopped(void Function(String reason)? callback) =>
      stoppedCallback = callback;

  @override
  Future<LiveCaptureAvailability> probe() async =>
      const LiveCaptureAvailability.available();

  @override
  Future<LiveCaptureStartResult> start({required String restoreToken}) async {
    calls.add('start');
    lastToken = restoreToken;
    if (throwOnStart) throw PlatformException(code: 'boom');
    final pending = pendingStart;
    if (pending != null) return pending.future;
    return startResult;
  }

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<int> setHidden(bool hidden) async {
    calls.add('setHidden:$hidden');
    if (hidden && throwOnHide) throw PlatformException(code: 'boom');
    return sequence;
  }

  @override
  Future<int> frameSequence() async {
    if (frozen) return sequence;
    // 呼ばれるたびに 1 枚届いたことにする。
    return sequence++;
  }

  @override
  Future<LiveCaptureFrame?> readFrame({required int maxPixels}) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('liveShaderAssetFor', () {
    final state = VisionFilterState();
    final filters = {
      for (final id in kVisionFilterCatalogById.keys)
        id: state.buildLayer(VisionLayer(id: id)),
    };

    test('カタログ 30 種のうち、シェーダのある 20 種だけがアセットを持つ', () {
      final withAsset =
          filters.values.where((f) => liveShaderAssetFor(f) != null).length;
      expect(filters.length, 30);
      expect(withAsset, 20);
    });

    test('アセットはすべて pubspec.yaml の flutter.shaders にある', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      for (final f in filters.values) {
        final asset = liveShaderAssetFor(f);
        if (asset == null) continue;
        expect(pubspec, contains('- $asset'), reason: '$f');
        expect(File(asset).existsSync(), isTrue, reason: asset);
      }
    });
  });

  group('planLiveFilters', () {
    test('段順を保ち、シェーダの無い層は飛ばす', () {
      const steps = [
        VisionStep(filter: VisionFilter.myopia(), strength: 0.5),
        VisionStep(filter: VisionFilter.vertigo(), strength: 0.7),
        VisionStep(filter: VisionFilter.protanopia(), strength: 1),
      ];
      final plan = planLiveFilters(steps);
      expect(plan.passes.map((p) => p.asset), [
        'shaders/myopia.frag',
        'shaders/protanopia.frag',
      ]);
      expect(plan.passes.map((p) => p.strength), [0.5, 1]);
      expect(plan.skipped, [const VisionFilter.vertigo()]);
    });

    test('空の列（原画比較中など）は何も通さない', () {
      final plan = planLiveFilters(const []);
      expect(plan.passes, isEmpty);
      expect(plan.skipped, isEmpty);
    });
  });

  group('ネイティブ応答の読み取り', () {
    test('probe', () {
      expect(availabilityFromProbe({'available': true}).available, isTrue);
      expect(
        availabilityFromProbe(
          {'available': false, 'reason': 'unsupportedBackend'},
        ).reason,
        LiveCaptureUnavailableReason.unsupportedBackend,
      );
      expect(
        availabilityFromProbe(null).reason,
        LiveCaptureUnavailableReason.portalUnavailable,
      );
    });

    test('start', () {
      final ok = startResultFromMap({'error': 'none', 'restoreToken': 't'});
      expect(ok.ok, isTrue);
      expect(ok.restoreToken, 't');
      expect(startResultFromMap({'error': 'denied'}).error,
          LiveCaptureError.denied);
      expect(startResultFromMap({'error': 'unavailable'}).error,
          LiveCaptureError.unavailable);
      expect(startResultFromMap(null).error, LiveCaptureError.failed);
    });

    test('Linux 以外はネイティブを呼ばず未実装の OS', () async {
      final a = await probeLiveCapture(backend: _FakeBackend(), isLinux: false);
      expect(a.reason, LiveCaptureUnavailableReason.unsupportedPlatform);
    });
  });

  group('LiveLoupeSession', () {
    late LoupeWindowController loupe;
    late List<String> window;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      loupe = LoupeWindowController(loupeModeAvailable: true);
      window = [];
    });

    LiveLoupeSession make(_FakeBackend backend) => LiveLoupeSession(
          loupeWindow: loupe,
          backend: backend,
          hideWindow: () async => window.add('hide'),
          showWindow: () async => window.add('show'),
          pollInterval: Duration.zero,
        );

    test('ルーペ窓に入ると共有し、窓を一瞬隠して真下を撮ってから running', () async {
      final backend = _FakeBackend(
        startResult: const LiveCaptureStartResult(restoreToken: 'tok'),
      );
      final session = make(backend);
      await loupe.setAppMode(AppMode.loupe);
      await pumpEventQueue();

      expect(session.state, LiveLoupeState.running);
      expect(window, ['hide', 'show']);
      // 窓を戻す前に除外を再開する。
      expect(backend.calls, ['start', 'setHidden:true', 'setHidden:false']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('liveCapture.restoreToken'), 'tok');
      session.dispose();
    });

    test('保存したトークンを次の開始に渡す', () async {
      SharedPreferences.setMockInitialValues(
        {'liveCapture.restoreToken': 'saved'},
      );
      final backend = _FakeBackend();
      final session = make(backend);
      await loupe.setAppMode(AppMode.loupe);
      await pumpEventQueue();
      expect(backend.lastToken, 'saved');
      session.dispose();
    });

    test('拒否されたら設定窓へ戻し、理由を残す', () async {
      final backend = _FakeBackend(
        startResult:
            const LiveCaptureStartResult(error: LiveCaptureError.denied),
      );
      final session = make(backend);
      await loupe.setAppMode(AppMode.loupe);
      await pumpEventQueue();

      expect(loupe.appMode, AppMode.settings);
      expect(session.state, LiveLoupeState.idle);
      expect(session.lastError, LiveCaptureError.denied);
      expect(window, isEmpty);
      // もう一度ルーペ窓を選べる（復帰不能にしない）。
      backend.startResult = const LiveCaptureStartResult();
      await loupe.setAppMode(AppMode.loupe);
      await pumpEventQueue();
      expect(session.state, LiveLoupeState.running);
      expect(session.lastError, isNull);
      session.dispose();
    });

    test('共有中に止まったら設定窓へ戻す', () async {
      final backend = _FakeBackend();
      final session = make(backend);
      await loupe.setAppMode(AppMode.loupe);
      await pumpEventQueue();
      backend.stoppedCallback!('stream error');
      await pumpEventQueue();

      expect(loupe.appMode, AppMode.settings);
      expect(session.lastError, LiveCaptureError.stopped);
      session.dispose();
    });

    test('設定窓へ戻すと共有を止める', () async {
      final backend = _FakeBackend();
      final session = make(backend);
      await loupe.setAppMode(AppMode.loupe);
      await pumpEventQueue();
      await loupe.setAppMode(AppMode.settings);
      await pumpEventQueue();

      expect(session.state, LiveLoupeState.idle);
      expect(backend.calls.last, 'stop');
      session.dispose();
    });

    test('撮り直しは窓をもう一度隠して真下を撮り、running に戻る', () async {
      final backend = _FakeBackend();
      final session = make(backend);
      await loupe.setAppMode(AppMode.loupe);
      await pumpEventQueue();
      expect(session.state, LiveLoupeState.running);
      backend.calls.clear();
      window.clear();

      final states = <LiveLoupeState>[];
      session.addListener(() => states.add(session.state));
      await session.refreshBackdrop();

      expect(window, ['hide', 'show']);
      expect(backend.calls, ['setHidden:true', 'setHidden:false']);
      expect(states, [LiveLoupeState.priming, LiveLoupeState.running]);
      expect(session.state, LiveLoupeState.running);
      session.dispose();
    });

    test('共有していないときの撮り直しは何もしない', () async {
      final backend = _FakeBackend();
      final session = make(backend);
      await session.refreshBackdrop();
      expect(window, isEmpty);
      expect(backend.calls, isEmpty);
      expect(session.state, LiveLoupeState.idle);
      session.dispose();
    });

    test('開始の応答待ちの間に設定窓へ戻すと、遅れて来た応答は捨てる', () async {
      final backend = _FakeBackend()
        ..pendingStart = Completer<LiveCaptureStartResult>();
      final session = make(backend);
      await loupe.setAppMode(AppMode.loupe);
      await pumpEventQueue();
      expect(session.state, LiveLoupeState.starting);

      await loupe.setAppMode(AppMode.settings);
      await pumpEventQueue();
      expect(session.state, LiveLoupeState.idle);
      expect(backend.calls, ['start', 'stop']);

      // ダイアログの応答が後から成功で来ても、窓を隠さず running にしない。
      backend.pendingStart!
          .complete(const LiveCaptureStartResult(restoreToken: 'late'));
      await pumpEventQueue();
      expect(session.state, LiveLoupeState.idle);
      expect(window, isEmpty);
      expect(backend.calls, ['start', 'stop']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('liveCapture.restoreToken'), isNull);
      session.dispose();
    });

    test('フレームが届かなくても、待ち時間が切れたら窓を戻して running', () async {
      final backend = _FakeBackend()..frozen = true;
      final session = LiveLoupeSession(
        loupeWindow: loupe,
        backend: backend,
        hideWindow: () async => window.add('hide'),
        showWindow: () async => window.add('show'),
        primeTimeout: const Duration(milliseconds: 50),
        pollInterval: const Duration(milliseconds: 5),
      );
      final watch = Stopwatch()..start();
      await loupe.setAppMode(AppMode.loupe);
      while (session.state != LiveLoupeState.running &&
          watch.elapsed < const Duration(seconds: 2)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(session.state, LiveLoupeState.running);
      expect(window, ['hide', 'show']);
      expect(backend.calls, ['start', 'setHidden:true', 'setHidden:false']);
      expect(watch.elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 50)));
      session.dispose();
    });

    test('静止した画面（隠したことによる 1 枚だけ）でも、落ち着いたら待ち時間を待たずに戻す',
        () async {
      final backend = _FakeBackend()..frozen = true;
      final session = LiveLoupeSession(
        loupeWindow: loupe,
        backend: backend,
        hideWindow: () async {
          window.add('hide');
          // 隠したことによる damage で 1 枚だけ届き、以後は届かない。
          backend.sequence++;
        },
        showWindow: () async => window.add('show'),
        primeTimeout: const Duration(seconds: 10),
        primeSettle: const Duration(milliseconds: 20),
        pollInterval: const Duration(milliseconds: 5),
      );
      final watch = Stopwatch()..start();
      await loupe.setAppMode(AppMode.loupe);
      while (session.state != LiveLoupeState.running &&
          watch.elapsed < const Duration(seconds: 5)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(session.state, LiveLoupeState.running);
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      expect(window, ['hide', 'show']);
      session.dispose();
    });

    test('開始で例外が出たら failed で設定窓へ戻す', () async {
      final backend = _FakeBackend()..throwOnStart = true;
      final session = make(backend);
      await loupe.setAppMode(AppMode.loupe);
      await pumpEventQueue();

      expect(session.state, LiveLoupeState.idle);
      expect(session.lastError, LiveCaptureError.failed);
      expect(loupe.appMode, AppMode.settings);
      expect(backend.calls, ['start', 'stop']);
      session.dispose();
    });

    test('窓を隠す途中で例外が出ても、除外を再開して窓を戻してから設定窓へ戻す', () async {
      final backend = _FakeBackend()..throwOnHide = true;
      final session = make(backend);
      await loupe.setAppMode(AppMode.loupe);
      await pumpEventQueue();

      expect(backend.calls,
          ['start', 'setHidden:true', 'setHidden:false', 'stop']);
      expect(window, ['show']);
      expect(session.state, LiveLoupeState.idle);
      expect(session.lastError, LiveCaptureError.failed);
      expect(loupe.appMode, AppMode.settings);
      session.dispose();
    });

    test('撮り直しの途中で例外が出ても、窓を戻して設定窓へ戻す', () async {
      final backend = _FakeBackend();
      final session = make(backend);
      await loupe.setAppMode(AppMode.loupe);
      await pumpEventQueue();
      backend.calls.clear();
      window.clear();
      backend.throwOnHide = true;

      await session.refreshBackdrop();
      await pumpEventQueue();

      expect(window, ['show']);
      expect(backend.calls, ['setHidden:true', 'setHidden:false', 'stop']);
      expect(session.lastError, LiveCaptureError.failed);
      expect(loupe.appMode, AppMode.settings);
      session.dispose();
    });
  });

  group('ルーペ窓を選べない理由と文言', () {
    tearDown(() {
      LoupeWindowPolicy.liveCapture = const LiveCaptureAvailability.unavailable(
        LiveCaptureUnavailableReason.unsupportedPlatform,
      );
    });

    test('理由ごとに別の文言（en/ja）', () {
      for (final locale in const [Locale('en'), Locale('ja')]) {
        final l10n = lookupAppLocalizations(locale);
        final table = {
          LiveCaptureUnavailableReason.unsupportedPlatform:
              l10n.windowModeLoupeUnavailablePlatform,
          LiveCaptureUnavailableReason.unsupportedBackend:
              l10n.windowModeLoupeUnavailableBackend,
          LiveCaptureUnavailableReason.portalUnavailable:
              l10n.windowModeLoupeUnavailablePortal,
        };
        // enum の全値を網羅する（値を足したら表も足す）。
        expect(table.keys.toSet(),
            LiveCaptureUnavailableReason.values.toSet());
        for (final e in table.entries) {
          expect(loupeUnavailableNote(l10n, e.key), e.value,
              reason: '$locale ${e.key}');
        }
        expect(table.values.toSet().length, table.length,
            reason: '$locale: 理由ごとに文言が違う');
        // 理由が無い（調査前）は未実装の OS と同じ文言。
        expect(loupeUnavailableNote(l10n, null),
            l10n.windowModeLoupeUnavailablePlatform);
      }
    });

    test('コントローラは起動時の調査の理由を返し、使えるときは null', () {
      for (final reason in LiveCaptureUnavailableReason.values) {
        LoupeWindowPolicy.liveCapture =
            LiveCaptureAvailability.unavailable(reason);
        final c = LoupeWindowController();
        expect(c.loupeModeAvailable, isFalse);
        expect(c.loupeUnavailableReason, reason);
      }
      LoupeWindowPolicy.liveCapture =
          const LiveCaptureAvailability.available();
      final c = LoupeWindowController();
      expect(c.loupeModeAvailable, isTrue);
      expect(c.loupeUnavailableReason, isNull);
    });

    test('テストで可否だけを false に上書きしたら、既定の理由（未実装の OS）', () {
      final c = LoupeWindowController(loupeModeAvailable: false);
      expect(c.loupeUnavailableReason,
          LiveCaptureUnavailableReason.unsupportedPlatform);
    });
  });
}
