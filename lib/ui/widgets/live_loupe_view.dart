import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../rendering/live_filter_plan.dart';
import '../../rendering/shader_filter.dart';
import '../../services/live_capture_service.dart';
import '../../services/live_loupe_session.dart';
import '../../services/loupe_window_controller.dart';
import '../../services/preview_selection.dart';
import '../../services/vision_filter_state.dart';
import '../../src/rust/api/sensus_bridge.dart';

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

/// ルーペ窓モードで、窓の下の画面をフィルタして窓いっぱいに映す (#180)。
///
/// [LiveLoupeSession] が共有中（[LiveLoupeState.running]）の間、表示のたびに
/// ネイティブから窓の描画域ぶんの画面（下の画面の控え）を受け取り、
/// [previewPipelineSteps]（段順・強度 0 を除く・原画比較中は空）を
/// [planLiveFilters] で GPU シェーダの段に分けて順に通す。GPU で描けない層は
/// 飛ばす（HUD が「静止画プレビューのみ」と出す）。
///
/// ルーペ窓モード以外では何も描かない。共有の失敗はスナックバーで知らせる。
class LiveLoupeView extends StatefulWidget {
  const LiveLoupeView({super.key});

  /// Dart へ渡す 1 フレームの画素数の上限。これを超える窓（全画面の 4K など）は
  /// ネイティブ側で間引く（MethodChannel のコピーとシェーダの負荷を抑える）。
  static const int maxPixels = 2560 * 1440;

  @override
  State<LiveLoupeView> createState() => _LiveLoupeViewState();
}

class _LiveLoupeViewState extends State<LiveLoupeView> {
  LiveLoupeSession? _session;
  VisionFilterState? _visionState;
  bool _looping = false;
  ui.Image? _raw;
  ui.Image? _shown;
  bool _filterDirty = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.read<LiveLoupeSession>();
    if (!identical(session, _session)) {
      _session?.removeListener(_onSession);
      _session = session..addListener(_onSession);
    }
    final visionState = context.read<VisionFilterState>();
    if (!identical(visionState, _visionState)) {
      _visionState?.removeListener(_onVision);
      _visionState = visionState..addListener(_onVision);
    }
    _syncSession();
  }

  void _onVision() => _filterDirty = true;

  void _onSession() {
    _syncSession();
    if (mounted) setState(() {});
  }

  /// 失敗の通知・描画ループの開始・画像の破棄。build 中（didChangeDependencies）
  /// からも呼ぶので setState はしない。
  void _syncSession() {
    final session = _session;
    if (session == null || !mounted) return;
    final error = session.lastError;
    if (error != null) {
      session.clearError();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(_errorText(l10n, error))),
        );
      });
    }
    if (session.state == LiveLoupeState.running && !_looping) {
      unawaited(_loop());
    }
    if (session.state == LiveLoupeState.idle) _clearImages();
  }

  static String _errorText(AppLocalizations l10n, LiveCaptureError error) =>
      switch (error) {
        LiveCaptureError.denied => l10n.liveCaptureErrorDenied,
        LiveCaptureError.unavailable => l10n.liveCaptureErrorUnavailable,
        LiveCaptureError.failed => l10n.liveCaptureErrorFailed,
        LiveCaptureError.stopped => l10n.liveCaptureErrorStopped,
      };

  void _clearImages() {
    _raw?.dispose();
    _raw = null;
    _shown?.dispose();
    _shown = null;
  }

  /// 共有中のあいだ、表示のたびに 1 枚受け取ってフィルタする。重ならないよう
  /// 1 本だけ回す。
  Future<void> _loop() async {
    _looping = true;
    try {
      while (mounted && _session?.state == LiveLoupeState.running) {
        await _tick();
        if (!mounted) break;
        await SchedulerBinding.instance.endOfFrame;
      }
    } finally {
      _looping = false;
    }
  }

  Future<void> _tick() async {
    final session = _session;
    final visionState = _visionState;
    if (session == null || visionState == null) return;
    LiveCaptureFrame? frame;
    try {
      frame =
          await session.backend.readFrame(maxPixels: LiveLoupeView.maxPixels);
    } catch (_) {
      frame = null;
    }
    if (!mounted) return;
    if (frame != null) {
      final image = await _decode(frame);
      if (!mounted) {
        image.dispose();
        return;
      }
      _raw?.dispose();
      _raw = image;
      _filterDirty = true;
    }
    final raw = _raw;
    if (raw == null || !_filterDirty) return;
    _filterDirty = false;
    final plan = planLiveFilters(previewPipelineSteps(visionState));
    final filtered = await _applyPasses(raw, plan.passes);
    if (!mounted) {
      if (!identical(filtered, raw)) filtered.dispose();
      return;
    }
    setState(() {
      final old = _shown;
      _shown = identical(filtered, raw) ? raw.clone() : filtered;
      old?.dispose();
    });
  }

  static Future<ui.Image> _decode(LiveCaptureFrame frame) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      frame.pixels,
      frame.width,
      frame.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  /// [passes] を段順に通す。途中の画像は破棄し、[src] は破棄しない。段が無ければ
  /// [src] をそのまま返す。
  static Future<ui.Image> _applyPasses(
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
      final next = await ShaderFilter.applyColorFilterGpu(
        current,
        pass.asset,
        uniforms.toList(),
      );
      if (!identical(current, src)) current.dispose();
      current = next;
    }
    return current;
  }

  @override
  void dispose() {
    _session?.removeListener(_onSession);
    _visionState?.removeListener(_onVision);
    _clearImages();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loupeWindow = context.watch<LoupeWindowController>();
    if (loupeWindow.appMode != AppMode.loupe) return const SizedBox.shrink();
    final shown = _shown;
    final scheme = Theme.of(context).colorScheme;
    if (shown == null) {
      final l10n = AppLocalizations.of(context)!;
      return ColoredBox(
        color: scheme.surface,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n.liveLoupeWaiting,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurface),
            ),
          ),
        ),
      );
    }
    // 窓の描画域ぶんの画面なので、窓いっぱいに引き伸ばせば画面と同じ縮尺になる。
    return Semantics(
      image: true,
      label: AppLocalizations.of(context)!.liveLoupeImageLabel,
      child: RawImage(image: shown, fit: BoxFit.fill),
    );
  }
}
