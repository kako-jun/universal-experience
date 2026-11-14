import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/models/vision_filter_catalog.dart';
import 'package:universal_experience/rendering/live_filter_plan.dart';
import 'package:universal_experience/services/live_capture_service.dart';
import 'package:universal_experience/services/live_loupe_session.dart';
import 'package:universal_experience/services/loupe_window_controller.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/services/vision_layer.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';

/// ライブのルーペ（#180）の純粋ロジック: シェーダの計画・ネイティブ応答の読み取り・
/// ルーペ窓モードと共有の寿命。

class _FakeBackend implements LiveCaptureBackend {
  _FakeBackend({this.startResult = const LiveCaptureStartResult()});

  LiveCaptureStartResult startResult;
  final List<String> calls = [];
  String? lastToken;
  int sequence = 0;
  void Function(String reason)? stoppedCallback;

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
    return startResult;
  }

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<int> setHidden(bool hidden) async {
    calls.add('setHidden:$hidden');
    return sequence;
  }

  @override
  Future<int> frameSequence() async {
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
  });
}
