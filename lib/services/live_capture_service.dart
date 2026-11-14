import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// ルーペ窓のライブ画面キャプチャ（#180）の、ネイティブ側（Linux:
/// `linux/screen_capture/`）との境界。
///
/// 実装は Linux（xdg-desktop-portal ScreenCast → PipeWire）だけ。ほかの OS は
/// [probeLiveCapture] が [LiveCaptureUnavailableReason.unsupportedPlatform] を返し、
/// ネイティブを呼ばない。

/// ルーペ窓のライブキャプチャが使えない理由。
enum LiveCaptureUnavailableReason {
  /// この OS のキャプチャは未実装（Linux 以外）。
  unsupportedPlatform,

  /// Linux だが X11（XWayland を含む）バックエンドで動いていない。自分の窓の位置が
  /// 分からないため、画面のどこを映すか決められない（`UE_ALLOW_WAYLAND=1` 等）。
  unsupportedBackend,

  /// xdg-desktop-portal の ScreenCast（モニタの共有）が無い。
  portalUnavailable,
}

/// キャプチャを使えるか。
@immutable
class LiveCaptureAvailability {
  const LiveCaptureAvailability.available() : reason = null;
  const LiveCaptureAvailability.unavailable(
      LiveCaptureUnavailableReason this.reason);

  final LiveCaptureUnavailableReason? reason;

  bool get available => reason == null;
}

/// 共有の開始・継続に失敗した理由。
enum LiveCaptureError {
  /// 利用者が画面の共有を取り消した・拒否した。
  denied,

  /// ポータルが応答しない・無い。
  unavailable,

  /// それ以外（PipeWire の接続失敗など）。
  failed,

  /// 共有中に止まった（合成器側で共有が終わった等）。
  stopped,
}

/// 共有の開始の結果。
@immutable
class LiveCaptureStartResult {
  const LiveCaptureStartResult({this.error, this.restoreToken = ''});

  final LiveCaptureError? error;

  /// 次回の開始でダイアログを省くためのトークン（ポータルが返したとき）。
  final String restoreToken;

  bool get ok => error == null;
}

/// 窓の描画域ぶんの、下の画面（RGBA8、A=255）。
class LiveCaptureFrame {
  const LiveCaptureFrame({
    required this.sequence,
    required this.width,
    required this.height,
    required this.pixels,
    required this.unprimed,
  });

  final int sequence;
  final int width;
  final int height;
  final Uint8List pixels;

  /// まだ一度も撮れていない画素（黒）が控えに残っているか。
  final bool unprimed;
}

/// ネイティブへの呼び出し。テストではフェイクに差し替える。
abstract class LiveCaptureBackend {
  Future<LiveCaptureAvailability> probe();
  Future<LiveCaptureStartResult> start({required String restoreToken});
  Future<void> stop();

  /// 窓を隠している間は true（窓の下を除外せずに撮る）。現在のフレーム番号を返す。
  Future<int> setHidden(bool hidden);
  Future<int> frameSequence();

  /// 前回から変化が無ければ null。[maxPixels] を超える窓は間引いて返す。
  Future<LiveCaptureFrame?> readFrame({required int maxPixels});

  /// 共有中に止まったとき呼ばれる。
  set onStopped(void Function(String reason)? callback);
}

/// `universal_experience/live_capture` チャネルの実装（`linux/screen_capture/
/// screen_capture_plugin.cc` と対）。
class MethodChannelLiveCaptureBackend implements LiveCaptureBackend {
  MethodChannelLiveCaptureBackend() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'stopped') {
        final args = call.arguments;
        final reason = args is Map ? '${args['reason']}' : '';
        _onStopped?.call(reason);
      }
      return null;
    });
  }

  static const MethodChannel _channel =
      MethodChannel('universal_experience/live_capture');

  void Function(String reason)? _onStopped;

  @override
  set onStopped(void Function(String reason)? callback) =>
      _onStopped = callback;

  @override
  Future<LiveCaptureAvailability> probe() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('probe');
      return availabilityFromProbe(result);
    } on MissingPluginException {
      return const LiveCaptureAvailability.unavailable(
        LiveCaptureUnavailableReason.unsupportedPlatform,
      );
    } on PlatformException {
      return const LiveCaptureAvailability.unavailable(
        LiveCaptureUnavailableReason.portalUnavailable,
      );
    }
  }

  @override
  Future<LiveCaptureStartResult> start({required String restoreToken}) async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'start',
        {'restoreToken': restoreToken},
      );
      return startResultFromMap(result);
    } on PlatformException {
      return const LiveCaptureStartResult(error: LiveCaptureError.failed);
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // 止める側の失敗は握る（呼び出し元は設定窓へ戻るだけ）。
    }
  }

  @override
  Future<int> setHidden(bool hidden) async =>
      await _channel.invokeMethod<int>('setHidden', {'hidden': hidden}) ?? 0;

  @override
  Future<int> frameSequence() async =>
      await _channel.invokeMethod<int>('frameSequence') ?? 0;

  @override
  Future<LiveCaptureFrame?> readFrame({required int maxPixels}) async {
    final m = await _channel.invokeMapMethod<String, Object?>(
      'readFrame',
      {'maxPixels': maxPixels},
    );
    if (m == null) return null;
    return LiveCaptureFrame(
      sequence: m['sequence'] as int,
      width: m['width'] as int,
      height: m['height'] as int,
      pixels: m['pixels'] as Uint8List,
      unprimed: m['unprimed'] as bool? ?? false,
    );
  }
}

/// ネイティブの `probe` の結果を読む。
@visibleForTesting
LiveCaptureAvailability availabilityFromProbe(Map<String, Object?>? result) {
  if (result != null && result['available'] == true) {
    return const LiveCaptureAvailability.available();
  }
  final reason = result?['reason'];
  return LiveCaptureAvailability.unavailable(
    reason == 'unsupportedBackend'
        ? LiveCaptureUnavailableReason.unsupportedBackend
        : LiveCaptureUnavailableReason.portalUnavailable,
  );
}

/// ネイティブの `start` の結果を読む（`screen_cast.cc` の `StartErrorName`）。
@visibleForTesting
LiveCaptureStartResult startResultFromMap(Map<String, Object?>? result) {
  final token = result?['restoreToken'] as String? ?? '';
  final error = switch (result?['error']) {
    'none' => null,
    'denied' => LiveCaptureError.denied,
    'unavailable' => LiveCaptureError.unavailable,
    _ => LiveCaptureError.failed,
  };
  return LiveCaptureStartResult(error: error, restoreToken: token);
}

/// 起動時にキャプチャを使えるか調べる。Linux 以外はネイティブを呼ばない。
Future<LiveCaptureAvailability> probeLiveCapture({
  LiveCaptureBackend? backend,
  bool? isLinux,
}) async {
  if (!(isLinux ?? Platform.isLinux)) {
    return const LiveCaptureAvailability.unavailable(
      LiveCaptureUnavailableReason.unsupportedPlatform,
    );
  }
  return (backend ?? MethodChannelLiveCaptureBackend()).probe();
}
