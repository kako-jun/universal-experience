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

Future<ui.Image> _decodeFile(String path) async {
  final codec = await ui.instantiateImageCodec(await File(path).readAsBytes());
  return (await codec.getNextFrame()).image;
}

Future<Uint8List> _rgba(ui.Image img) async =>
    (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();

void main() {
  setUp(installHomeScreenFixtures);
  tearDown(() {
    resetHomeScreenFixtures();
    liveUniformsProvider = visionUniforms;
  });

  testWidgets('受け取った画面を段のシェーダに通し、sensus 参照と一致する絵を描く', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final uniforms =
        (jsonDecode(File('test/golden/color_uniforms.json').readAsStringSync())
            as Map<String, dynamic>)['filters']['deuteranopia'] as List;
    liveUniformsProvider = ({
      required VisionFilter filter,
      required double strength,
      required double time,
      required int width,
      required int height,
    }) =>
        Float32List.fromList([for (final v in uniforms) (v as num).toDouble()]);

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

    final out = (await tester.runAsync(() => _rgba(shown!.image!)))!;
    final ref = (await tester.runAsync(
      () async => _rgba(await _decodeFile('test/golden/deuteranopia_ref.png')),
    ))!;
    expect(out.length, ref.length);
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
    // GPU golden（vision_filter_golden_test.dart）と同じ基準。
    expect(psnr, greaterThanOrEqualTo(30.0));
    expect(maxDiff, lessThanOrEqualTo(8));

    // ルーペ窓を出たら何も描かない。
    await tester.runAsync(() => loupe.setAppMode(AppMode.settings));
    await tester.pump();
    expect(find.byType(RawImage), findsNothing);
    input.dispose();
  });
}
