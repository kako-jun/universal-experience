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
    Duration primeSettle = const Duration(milliseconds: 120),
    Duration pollInterval = const Duration(milliseconds: 30),
  })  : _loupeWindow = loupeWindow,
        _backend = backend,
        _hideWindow = hideWindow,
        _showWindow = showWindow,
        _prefs = prefs ?? SharedPreferences.getInstance,
        _primeTimeout = primeTimeout,
        _primeSettle = primeSettle,
        _pollInterval = pollInterval {
    _backend.onStopped = _handleStopped;
    _loupeWindow.addListener(_sync);
    // 保存値でルーペ窓から起動した場合も、ここで共有を始める。
    _sync();
  }

  static const String _prefsRestoreToken = 'liveCapture.restoreToken';

  /// 窓の真下を撮るとき、**隠し終えた後に**待つフレーム数（画面が動いている場合）。
  /// `windowManager.hide` は XWayland 経由で非同期なので、戻った直後の 1 枚目には
  /// まだ窓が写っていることがあるため 2 枚待つ。隠す呼び出しの途中に届いた枚は
  /// 数えない。
  static const int primeFrames = 2;

  final LoupeWindowController _loupeWindow;
  final LiveCaptureBackend _backend;
  final Future<void> Function() _hideWindow;
  final Future<void> Function() _showWindow;
  final Future<SharedPreferences> Function() _prefs;
  final Duration _primeTimeout;
  final Duration _primeSettle;
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
    try {
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
      if (generation != _generation || _disposed) return;
      await _prime(generation);
      if (generation != _generation || _disposed) return;
      _set(LiveLoupeState.running);
    } catch (_) {
      // ネイティブ・保存の例外（PlatformException 等）でも復帰不能にしない。
      if (generation == _generation && !_disposed) {
        await _fail(LiveCaptureError.failed);
      }
    }
  }

  /// 窓を一瞬隠し、窓の真下が写ったフレームを待ってから戻す。
  ///
  /// PipeWire は画面に変化（damage）があるときだけフレームを送る。静止した画面では
  /// 隠したことによる 1〜2 枚が隠す呼び出しの途中に届いて終わりなので、隠した後の
  /// 枚数だけを条件にすると [_primeTimeout] まで窓が消えたままになる。そこで、
  /// 除外を止めた時点（[LiveCaptureBackend.setHidden] の戻り値）からの到着と経過
  /// 時間を合わせて見る。終わる条件は次のどちらか:
  /// - 隠し終えた後（`hideWindow` から戻った時点の番号から）に [primeFrames] 枚届いた
  ///   （画面が動いている）。隠す呼び出しの途中に届いた枚（まだ窓が写りうる）は
  ///   数えないので、窓自身が写った枚で終わって控えに焼き付くことはない。
  /// - 除外を止めてから 1 枚以上届き、隠し終えてから [_primeSettle] 経った
  ///   （静止した画面。隠したことによる 1 枚で足りる）。
  ///
  /// 途中で例外が出ても、除外の再開と窓の表示は必ず通す（窓が隠れたまま・
  /// 除外が止まったままにしない）。例外は呼び出し元へ投げ直す。
  Future<void> _prime(int generation) async {
    _set(LiveLoupeState.priming);
    try {
      final base = await _backend.setHidden(true);
      await _hideWindow();
      final afterHide = await _backend.frameSequence();
      final hidden = Stopwatch()..start();
      final deadline = DateTime.now().add(_primeTimeout);
      while (generation == _generation &&
          !_disposed &&
          DateTime.now().isBefore(deadline)) {
        final sequence = await _backend.frameSequence();
        final moving = sequence >= afterHide + primeFrames;
        final settled = sequence > base && hidden.elapsed >= _primeSettle;
        if (moving || settled) break;
        await Future<void>.delayed(_pollInterval);
      }
    } finally {
      // 窓を戻す前に除外を再開する（戻した窓を撮り込まない）。
      try {
        await _backend.setHidden(false);
      } finally {
        await _showWindow();
      }
    }
  }

  /// 窓の真下を撮り直す（HUD のボタン）。共有中でなければ何もしない。
  Future<void> refreshBackdrop() async {
    if (_state != LiveLoupeState.running) return;
    final generation = _generation;
    try {
      await _prime(generation);
    } catch (_) {
      if (generation == _generation && !_disposed) {
        await _fail(LiveCaptureError.failed);
      }
      return;
    }
    if (generation == _generation && !_disposed) {
      _set(LiveLoupeState.running);
    }
  }

  Future<void> _fail(LiveCaptureError error) async {
    ++_generation;
    _lastError = error;
    _set(LiveLoupeState.idle);
    await _stopBackend();
    // 設定窓へ戻す。setAppMode の通知で _sync が呼ばれるが、idle なので何もしない。
    await _loupeWindow.setAppMode(AppMode.settings);
    if (!_disposed) notifyListeners();
  }

  /// 共有中の描画（画素の画像化・GPU シェーダ）が失敗した（`LiveLoupeView` から）。
  /// 描けないまま窓を出し続けないよう、共有を止めて [LiveCaptureError.failed] で
  /// 設定窓へ戻す。共有中でなければ何もしない。
  void reportRenderFailure() {
    if (_state != LiveLoupeState.running) return;
    unawaited(_fail(LiveCaptureError.failed));
  }

  void _handleStopped(String reason) {
    if (_state == LiveLoupeState.idle) return;
    unawaited(_fail(LiveCaptureError.stopped));
  }

  Future<void> _stop() async {
    ++_generation;
    _set(LiveLoupeState.idle);
    await _stopBackend();
  }

  /// 共有を止める。止める側の失敗は握る（呼び出し元は idle・設定窓へ戻るだけ）。
  Future<void> _stopBackend() async {
    try {
      await _backend.stop();
    } catch (_) {}
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
    unawaited(_stopBackend());
    super.dispose();
  }
}
