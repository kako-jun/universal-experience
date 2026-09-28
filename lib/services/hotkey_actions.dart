/// 4 つのホットキーアクションの実処理 (#63)。すべて注入されたコールバック経由で
/// 副作用を起こすため、実 OS のホットキー/window_manager 無しでフェイクにより
/// 単体テストできる。main.dart はここへ実際の windowManager/trayService/
/// filterService/visionFilterState/loupeWindow の操作を注入するだけの薄い配線に徹する。
class HotkeyActions {
  HotkeyActions({
    required this.deactivateFilters,
    required this.setClickThrough,
    required this.setAlwaysOnTop,
    required this.getClickThrough,
    required this.setBypassed,
    required this.getBypassed,
    required this.showAndFocusLoupe,
    required this.toggleLoupeVisible,
    required this.setLoupeVisible,
    DateTime Function() now = DateTime.now,
  }) : _now = now;

  final DateTime Function() _now;

  /// keyUp を一度でも受け取ったか。一度受け取れば、この環境は hold ジェスチャを
  /// 正しく配送すると分かる (#63)。
  bool _keyUpSeen = false;

  /// keyUp が一度も届いていない環境で、OS のキーリピートによる keyDown 連打を
  /// トグルとして誤検知しないための直近 keyDown 時刻。
  DateTime? _lastKeyDownAt;

  /// [_lastKeyDownAt] からこの時間内の keyDown はリピートとみなして無視する
  /// (#63)。
  static const Duration _repeatDebounce = Duration(milliseconds: 400);

  /// filterService.deactivate() + visionFilterState.clear() 相当。
  final void Function() deactivateFilters;
  final Future<void> Function(bool value) setClickThrough;
  final Future<void> Function(bool value) setAlwaysOnTop;
  final bool Function() getClickThrough;
  final void Function(bool value) setBypassed;
  final bool Function() getBypassed;

  /// ルーペ窓を表示して前面化する（windowManager.show() + focus() 相当）。
  final Future<void> Function() showAndFocusLoupe;

  /// ルーペ窓の表示/非表示トグル（TrayService.toggleLoupeVisible 相当）。
  final Future<void> Function() toggleLoupeVisible;

  /// トレイの表示状態ブックキーピング（`TrayService.setLoupeVisible`）と
  /// 同期するためのコールバック。
  final Future<void> Function(bool visible) setLoupeVisible;

  /// クリックスルーの ON/OFF。
  Future<void> toggleClickThrough() async {
    await setClickThrough(!getClickThrough());
  }

  /// 押している間だけ原画を表示 (#63)。
  ///
  /// - keyUp が一度でも届いた環境（[_keyUpSeen]）: 以降の keyDown は常に
  ///   bypassed を true にするだけ（冪等）。keyUp が常に false にするので、
  ///   正しい hold 挙動になる。
  /// - keyUp が一度も届いていない環境: keyDown のたびにトグルするが、直前の
  ///   keyDown から [_repeatDebounce]（400ms）以内の keyDown は OS のキー
  ///   リピートとみなして無視する（押しっぱなしで OS が keyDown を連続送出する
  ///   環境でも 1 回のトグルにしかならないようにする、#63）。
  void holdOriginalKeyDown() {
    if (_keyUpSeen) {
      setBypassed(true);
      return;
    }
    final now = _now();
    if (_lastKeyDownAt != null &&
        now.difference(_lastKeyDownAt!) < _repeatDebounce) {
      _lastKeyDownAt = now;
      return;
    }
    _lastKeyDownAt = now;
    setBypassed(!getBypassed());
  }

  void holdOriginalKeyUp() {
    _keyUpSeen = true;
    _lastKeyDownAt = null;
    if (getBypassed()) setBypassed(false);
  }

  /// 非常口: 全フィルタ停止 + 原画表示解除 + クリックスルー解除 + 最前面解除 +
  /// ウィンドウ表示/前面化 (#63)。
  ///
  /// メモリ上の状態変更（[deactivateFilters]/[setBypassed]）を先に行い、以降の
  /// I/O を伴うステップは 1 つずつ個別に try/catch する。どれか 1 ステップが
  /// 失敗しても（例: window_manager の呼び出しが例外を投げる）、残りのステップ
  /// は実行される — 非常口は「できるところまで全部やる」ことが要件のため、
  /// 1 つの失敗で他まで巻き添えにしない。
  Future<void> emergencyExit() async {
    deactivateFilters();
    setBypassed(false);

    await _runStep(() => setClickThrough(false));
    await _runStep(() => setAlwaysOnTop(false));
    await _runStep(showAndFocusLoupe);
    await _runStep(() => setLoupeVisible(true));
  }

  Future<void> _runStep(Future<void> Function() step) async {
    try {
      await step();
    } catch (_) {
      // 個別ステップの失敗は無視して残りを続行する (#63)。
    }
  }
}
