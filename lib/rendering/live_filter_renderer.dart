import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../src/rust/api/sensus_bridge.dart';
import 'live_filter_plan.dart';
import 'shader_filter.dart';

/// ライブのルーペ（#180）の描画の段取り: 受け取った画素の画像化と、
/// [planLiveFilters] の段を GPU シェーダで順に通すこと。ウィジェット
/// （`lib/ui/widgets/live_loupe_view.dart`）は表示と寿命だけを持ち、描画の段取りは
/// ここに置く（ガイドライン規律3）。

/// 層の uniform の供給源（既定は sensus の [visionUniforms]）。widget test は Rust
/// ブリッジを読み込まないので、正本から汲み出した値（`test/golden/color_uniforms.json`）
/// を返すフェイクに差し替える。
@visibleForTesting
Float32List Function({
  required VisionFilter filter,
  required double strength,
  required double time,
  required int width,
  required int height,
}) liveUniformsProvider = visionUniforms;

/// RGBA8 の画素列を [ui.Image] にする。
Future<ui.Image> decodeLiveRgba(Uint8List pixels, int width, int height) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// [passes] を段順に通す。途中の画像は破棄し、[src] は破棄しない。段が無ければ
/// [src] をそのまま返す（呼び出し側は戻り値が [src] と同一かを見て扱いを分ける）。
Future<ui.Image> applyLiveShaderPasses(
  ui.Image src,
  List<LiveShaderPass> passes,
) async {
  var current = src;
  for (final pass in passes) {
    final uniforms = liveUniformsProvider(
      filter: pass.filter,
      strength: pass.strength,
      time: 0,
      width: current.width,
      height: current.height,
    );
    final ui.Image next;
    try {
      next = await ShaderFilter.applyColorFilterGpu(
        current,
        pass.asset,
        uniforms.toList(),
      );
    } catch (_) {
      if (!identical(current, src)) current.dispose();
      rethrow;
    }
    if (!identical(current, src)) current.dispose();
    current = next;
  }
  return current;
}
