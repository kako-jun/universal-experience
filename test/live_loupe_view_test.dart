import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/rendering/live_filter_plan.dart';
import 'package:universal_experience/rendering/live_filter_renderer.dart';
import 'package:universal_experience/rendering/shader_filter.dart';
import 'package:universal_experience/services/preview_selection.dart';
import 'package:universal_experience/services/live_capture_service.dart';
import 'package:universal_experience/services/live_loupe_session.dart';
import 'package:universal_experience/services/loupe_window_controller.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/widgets/live_loupe_view.dart';

import 'support/color_vision_select.dart';
import 'support/home_screen_harness.dart';

/// ライブのルーペの描画経路（#180）: ネイティブから受け取った窓の下の画面を、選んだ層の
/// GPU シェーダに通して窓いっぱいに描く。ネイティブはフェイクにし、入力に GPU golden の
/// 入力画像を流して、描かれた画像が sensus 参照（deuteranopia_ref.png）と一致するかを見る。

class _OneFrameBackend implements LiveCaptureBackend {
  _OneFrameBackend(this.frame);

  final LiveCaptureFrame frame;
  bool _sent = false;
  int _sequence = 0;

  @override
  set onStopped(void Function(String reason)? callback) {}

  @override
  Future<LiveCaptureAvailability> probe() async =>
      const LiveCaptureAvailability.available();

  @override
  Future<LiveCaptureStartResult> start({required String restoreToken}) async =>
      const LiveCaptureStartResult();

  @override
  Future<void> stop() async {}

  @override
  Future<int> setHidden(bool hidden) async => _sequence;

  @override
  Future<int> frameSequence() async => _sequence++;

  @override
  Future<LiveCaptureFrame?> readFrame({required int maxPixels}) async {
    if (_sent) return null;
    _sent = true;
    return frame;
  }
}

/// 最初の readFrame を [firstFrame] が完了するまで返さない（読み込み中に idle へ
/// 落ちる経路を作る）。以後は null（変化なし）。
class _HeldFrameBackend implements LiveCaptureBackend {
  final Completer<LiveCaptureFrame?> firstFrame = Completer();
  bool firstRequested = false;
  int _sequence = 0;

  @override
  set onStopped(void Function(String reason)? callback) {}

  @override
  Future<LiveCaptureAvailability> probe() async =>
      const LiveCaptureAvailability.available();

  @override
  Future<LiveCaptureStartResult> start({required String restoreToken}) async =>
      const LiveCaptureStartResult();

  @override
  Future<void> stop() async {}

  @override
  Future<int> setHidden(bool hidden) async => _sequence;

  @override
  Future<int> frameSequence() async => _sequence++;

  @override
  Future<LiveCaptureFrame?> readFrame({required int maxPixels}) {
    if (firstRequested) return Future.value(null);
    firstRequested = true;
    return firstFrame.future;
  }
}

Future<ui.Image> _decodeFile(String path) async {
  final codec = await ui.instantiateImageCodec(await File(path).readAsBytes());
  return (await codec.getNextFrame()).image;
}

Future<Uint8List> _rgba(ui.Image img) async =>
    (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();

List<double> _goldenUniforms(String key) => [
      for (final v in (jsonDecode(
              File('test/golden/color_uniforms.json').readAsStringSync())
          as Map<String, dynamic>)['filters'][key] as List)
        (v as num).toDouble(),
    ];

/// RGB の PSNR と最大差。
({double psnr, int maxDiff}) _compare(Uint8List out, Uint8List ref) {
  double sumSq = 0;
  int maxDiff = 0;
  int count = 0;
  for (int i = 0; i + 3 < out.length; i += 4) {
    for (int c = 0; c < 3; c++) {
      final d = (out[i + c] - ref[i + c]).abs();
      if (d > maxDiff) maxDiff = d;
      sumSq += d * d;
      count++;
    }
  }
  final mse = sumSq / count;
  final psnr =
      mse == 0 ? double.infinity : 10 * math.log(255 * 255 / mse) / math.ln10;
  return (psnr: psnr, maxDiff: maxDiff);
}

/// ルーペ窓のライブ表示を組み、ルーペ窓へ切り替えて最初に描かれた画像を返す。
Future<ui.Image> _pumpAndCapture(
  WidgetTester tester, {
  required VisionFilterState vision,
  required LiveCaptureBackend backend,
  required LoupeWindowController loupe,
}) async {
  final session = LiveLoupeSession(
    loupeWindow: loupe,
    backend: backend,
    hideWindow: () async {},
    showWindow: () async {},
    pollInterval: Duration.zero,
  );
  addTearDown(session.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<VisionFilterState>.value(value: vision),
        ChangeNotifierProvider<LoupeWindowController>.value(value: loupe),
        ChangeNotifierProvider<LiveLoupeSession>.value(value: session),
      ],
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Stack(children: [Positioned.fill(child: LiveLoupeView())]),
        ),
      ),
    ),
  );

  // ルーペ窓へ切り替えると共有が始まり、窓の真下を撮って running になる。
  await tester.runAsync(() => loupe.setAppMode(AppMode.loupe));
  RawImage? shown;
  for (var i = 0; i < 50 && shown == null; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    final found = find.byType(RawImage);
    if (found.evaluate().isNotEmpty) {
      shown = tester.widget<RawImage>(found);
    }
  }
  expect(session.state, LiveLoupeState.running);
  expect(shown, isNotNull, reason: 'フィルタ済みの画面が描かれていない');
  return shown!.image!;
}

void main() {
  setUp(installHomeScreenFixtures);
  tearDown(() {
    resetHomeScreenFixtures();
    liveUniformsProvider = visionUniforms;
  });

  testWidgets('受け取った画面を段のシェーダに通し、sensus 参照と一致する絵を描く', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final uniforms = _goldenUniforms('deuteranopia');
    liveUniformsProvider = ({
      required VisionFilter filter,
      required double strength,
      required double time,
      required int width,
      required int height,
    }) =>
        Float32List.fromList(uniforms);

    final input = (await tester.runAsync(
      () => _decodeFile('test/golden/protanopia_input.png'),
    ))!;
    final pixels = (await tester.runAsync(() => _rgba(input)))!;
    final backend = _OneFrameBackend(LiveCaptureFrame(
      sequence: 1,
      width: input.width,
      height: input.height,
      pixels: pixels,
      unprimed: false,
    ));

    final loupe = LoupeWindowController(loupeModeAvailable: true);
    final vision = VisionFilterState();
    selectColorVisionKey(vision, 'deuteranopia');
    vision.setStrength(1.0);

    final shown = await _pumpAndCapture(tester,
        vision: vision, backend: backend, loupe: loupe);
    final out = (await tester.runAsync(() => _rgba(shown)))!;
    final ref = (await tester.runAsync(
      () async => _rgba(await _decodeFile('test/golden/deuteranopia_ref.png')),
    ))!;
    expect(out.length, ref.length);
    final r = _compare(out, ref);
    // GPU golden（vision_filter_golden_test.dart）と同じ基準。
    expect(r.psnr, greaterThanOrEqualTo(30.0));
    expect(r.maxDiff, lessThanOrEqualTo(8));

    // ルーペ窓を出たら何も描かない。
    await tester.runAsync(() => loupe.setAppMode(AppMode.settings));
    await tester.pump();
    expect(find.byType(RawImage), findsNothing);
    input.dispose();
  });

  testWidgets('複数層は段順に 1 層 1 パスで重ねて通し、GPU の無い層は飛ばす', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final deuteranopia = _goldenUniforms('deuteranopia');
    // contrast_sensitivity の uniform は [uStrength] だけ（shaders/contrast_sensitivity.frag）。
    const contrast = [1.0];
    final called = <VisionFilter>[];
    liveUniformsProvider = ({
      required VisionFilter filter,
      required double strength,
      required double time,
      required int width,
      required int height,
    }) {
      called.add(filter);
      return Float32List.fromList(switch (filter) {
        VisionFilter_Deuteranopia() => deuteranopia,
        VisionFilter_ContrastSensitivity() => contrast,
        _ => throw StateError('unexpected $filter'),
      });
    };

    final input = (await tester.runAsync(
      () => _decodeFile('test/golden/protanopia_input.png'),
    ))!;
    final pixels = (await tester.runAsync(() => _rgba(input)))!;
    final backend = _OneFrameBackend(LiveCaptureFrame(
      sequence: 1,
      width: input.width,
      height: input.height,
      pixels: pixels,
      unprimed: false,
    ));

    final loupe = LoupeWindowController(loupeModeAvailable: true);
    final vision = VisionFilterState();
    selectColorVisionKey(vision, 'deuteranopia');
    vision.setStrength(1.0);
    vision.toggle('contrast_sensitivity');
    vision.toggle('vertigo'); // GPU シェーダが無い → 飛ばす
    final plan = planLiveFilters(previewPipelineSteps(vision));
    expect(plan.passes, hasLength(2));
    expect(plan.skipped, [isA<VisionFilter_Vertigo>()]);

    final shown = await _pumpAndCapture(tester,
        vision: vision, backend: backend, loupe: loupe);
    // uniform は段順に 1 層 1 回ずつ求める（飛ばした層は求めない）。
    expect(called.map((f) => f.runtimeType),
        plan.passes.map((p) => p.filter.runtimeType));

    // 期待値: 同じ段順で 1 パスずつ直接シェーダに通した絵。
    final expected = (await tester.runAsync(() async {
      var current = input;
      for (final pass in plan.passes) {
        final u = switch (pass.filter) {
          VisionFilter_Deuteranopia() => deuteranopia,
          _ => contrast,
        };
        final next =
            await ShaderFilter.applyColorFilterGpu(current, pass.asset, u);
        if (!identical(current, input)) current.dispose();
        current = next;
      }
      final bytes = await _rgba(current);
      current.dispose();
      return bytes;
    }))!;
    final out = (await tester.runAsync(() => _rgba(shown)))!;
    final same = _compare(out, expected);
    expect(same.maxDiff, lessThanOrEqualTo(1));

    // 2 段目まで効いている（1 層だけの sensus 参照とは明らかに違う）。
    final single = (await tester.runAsync(
      () async => _rgba(await _decodeFile('test/golden/deuteranopia_ref.png')),
    ))!;
    expect(_compare(out, single).maxDiff, greaterThan(8));
    input.dispose();
  });

  testWidgets('読み込み中に共有が止まったら、遅れて届いた絵を書き戻さない', (tester) async {
    SharedPreferences.setMockInitialValues({});
    liveUniformsProvider = ({
      required VisionFilter filter,
      required double strength,
      required double time,
      required int width,
      required int height,
    }) =>
        Float32List.fromList(_goldenUniforms('deuteranopia'));
    final backend = _HeldFrameBackend();
    final loupe = LoupeWindowController(loupeModeAvailable: true);
    final vision = VisionFilterState();
    final session = LiveLoupeSession(
      loupeWindow: loupe,
      backend: backend,
      hideWindow: () async {},
      showWindow: () async {},
      pollInterval: Duration.zero,
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<VisionFilterState>.value(value: vision),
          ChangeNotifierProvider<LoupeWindowController>.value(value: loupe),
          ChangeNotifierProvider<LiveLoupeSession>.value(value: session),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Stack(children: [Positioned.fill(child: LiveLoupeView())]),
          ),
        ),
      ),
    );

    await tester.runAsync(() => loupe.setAppMode(AppMode.loupe));
    for (var i = 0; i < 50 && !backend.firstRequested; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(backend.firstRequested, isTrue);

    // 読み込みの途中で設定窓へ戻る（idle で画像を捨てる）。
    await tester.runAsync(() => loupe.setAppMode(AppMode.settings));
    await tester.pump();
    // 遅れて絵が届く。
    final stale = Uint8List(4 * 4 * 4)..fillRange(0, 64, 200);
    backend.firstFrame.complete(LiveCaptureFrame(
      sequence: 1,
      width: 4,
      height: 4,
      pixels: stale,
      unprimed: false,
    ));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    // もう一度ルーペ窓に入っても、新しい絵が届くまでは待ちの表示（古い絵を出さない）。
    await tester.runAsync(() => loupe.setAppMode(AppMode.loupe));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(session.state, LiveLoupeState.running);
    expect(find.byType(RawImage), findsNothing);
  });
}
