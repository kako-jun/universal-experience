import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'live_capture_service.dart';
import 'loupe_window_controller.dart';

/// ルーペ窓のライブキャプチャの進み具合 (#180)。
enum LiveLoupeState {
  /// 共有していない（設定窓・ルーペ窓に入る前）。
  idle,

  /// ポータルに共有を求めている（ダイアログの応答待ちを含む）。
  starting,

  /// 窓を一瞬隠して、窓の真下を撮っている。
  priming,

  /// 共有中。窓の中にフィルタ済みの画面を映す。
  running,
}

/// ルーペ窓モードとライブキャプチャの寿命を結ぶ (#180)。
///
/// - [LoupeWindowController.appMode] がルーペ窓になったら共有を始め、設定窓に
///   戻ったら止める。
/// - 共有の拒否・失敗・途中停止では設定窓へ戻し、[lastError] に理由を残す
///   （復帰不能にしない）。
/// - 開始直後と [refreshBackdrop] では、窓を一瞬隠して窓の真下を撮る（Wayland では
///   自分の窓を除いて撮れないため。判断は
///   `docs/adr/2026-11-14-linux-live-capture-portal-pipewire.md`）。
class LiveLoupeSession extends ChangeNotifier {
  LiveLoupeSession({
    required LoupeWindowController loupeWindow,
    required LiveCaptureBackend backend,
    required Future<void> Function() hideWindow,
    required Future<void> Function() showWindow,
    Future<SharedPreferences> Function()? prefs,
    Duration primeTimeout = const Duration(milliseconds: 1500),
    Duration pollInterval = const Duration(milliseconds: 30),
  })  : _loupeWindow = loupeWindow,
        _backend = backend,
        _hideWindow = hideWindow,
        _showWindow = showWindow,
        _prefs = prefs ?? SharedPreferences.getInstance,
        _primeTimeout = primeTimeout,
        _pollInterval = pollInterval {
    _backend.onStopped = _handleStopped;
    _loupeWindow.addListener(_sync);
    // 保存値でルーペ窓から起動した場合も、ここで共有を始める。
    _sync();
  }

  static const String _prefsRestoreToken = 'liveCapture.restoreToken';

  /// 窓の真下を撮るとき、隠してから待つフレーム数。隠した直後の 1 枚目には
  /// まだ窓が写っていることがあるため 2 枚待つ。
  static const int primeFrames = 2;

  final LoupeWindowController _loupeWindow;
  final LiveCaptureBackend _backend;
  final Future<void> Function() _hideWindow;
  final Future<void> Function() _showWindow;
  final Future<SharedPreferences> Function() _prefs;
  final Duration _primeTimeout;
  final Duration _pollInterval;

  LiveLoupeState _state = LiveLoupeState.idle;
  LiveCaptureError? _lastError;
  int _generation = 0;
  bool _disposed = false;

  LiveLoupeState get state => _state;

  /// 直近の失敗の理由（次の開始で消える）。UI が通知に使う。
  LiveCaptureError? get lastError => _lastError;

  /// 共有中にフレームを読む先（描画ウィジェットが使う）。
  LiveCaptureBackend get backend => _backend;

  void _set(LiveLoupeState state) {
    if (_disposed || _state == state) return;
    _state = state;
    notifyListeners();
  }

  void _sync() {
    final wantLive = _loupeWindow.appMode == AppMode.loupe;
    if (wantLive && _state == LiveLoupeState.idle) {
      unawaited(_start());
    } else if (!wantLive && _state != LiveLoupeState.idle) {
      unawaited(_stop());
    }
  }

  Future<void> _start() async {
    final generation = ++_generation;
    _lastError = null;
    _set(LiveLoupeState.starting);
    final prefs = await _prefs();
    final token = prefs.getString(_prefsRestoreToken) ?? '';
    final result = await _backend.start(restoreToken: token);
    if (generation != _generation || _disposed) return;
    if (!result.ok) {
      await _fail(result.error!);
      return;
    }
    if (result.restoreToken.isNotEmpty) {
      await prefs.setString(_prefsRestoreToken, result.restoreToken);
    }
    if (generation != _generation) return;
    await _prime(generation);
    if (generation != _generation || _disposed) return;
    _set(LiveLoupeState.running);
  }

  /// 窓を一瞬隠し、窓の真下が写ったフレームを [primeFrames] 枚待ってから戻す。
  Future<void> _prime(int generation) async {
    _set(LiveLoupeState.priming);
    await _backend.setHidden(true);
    await _hideWindow();
    final base = await _backend.frameSequence();
    final deadline = DateTime.now().add(_primeTimeout);
    while (generation == _generation &&
        !_disposed &&
        DateTime.now().isBefore(deadline)) {
      if (await _backend.frameSequence() >= base + primeFrames) break;
      await Future<void>.delayed(_pollInterval);
    }
    // 窓を戻す前に除外を再開する（戻した窓を撮り込まない）。
    await _backend.setHidden(false);
    await _showWindow();
  }

  /// 窓の真下を撮り直す（HUD のボタン）。共有中でなければ何もしない。
  Future<void> refreshBackdrop() async {
    if (_state != LiveLoupeState.running) return;
    final generation = _generation;
    await _prime(generation);
    if (generation == _generation && !_disposed) {
      _set(LiveLoupeState.running);
    }
  }

  Future<void> _fail(LiveCaptureError error) async {
    ++_generation;
    _lastError = error;
    _set(LiveLoupeState.idle);
    await _backend.stop();
    // 設定窓へ戻す。setAppMode の通知で _sync が呼ばれるが、idle なので何もしない。
    await _loupeWindow.setAppMode(AppMode.settings);
    if (!_disposed) notifyListeners();
  }

  void _handleStopped(String reason) {
    if (_state == LiveLoupeState.idle) return;
    unawaited(_fail(LiveCaptureError.stopped));
  }

  Future<void> _stop() async {
    ++_generation;
    _set(LiveLoupeState.idle);
    await _backend.stop();
  }

  /// [lastError] を通知済みにする（同じ失敗を二度出さない）。
  void clearError() {
    _lastError = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _loupeWindow.removeListener(_sync);
    _backend.onStopped = null;
    ++_generation;
    unawaited(_backend.stop());
    super.dispose();
  }
}
