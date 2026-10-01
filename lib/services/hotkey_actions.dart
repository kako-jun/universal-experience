/// 4 つのホットキーアクションの実処理 (#63)。すべて注入されたコールバック経由で
/// 副作用を起こすため、実 OS のホットキー/window_manager 無しでフェイクにより
/// 単体テストできる。main.dart はここへ実際の windowManager/trayService/
/// visionFilterState/loupeWindow の操作を注入するだけの薄い配線に徹する。
class HotkeyActions {
  HotkeyActions({
    required this.deactivateFilters,
    required this.setClickThrough,
    required this.setAlwaysOnTop,
    required this.getClickThrough,
    required this.acquireBypass,
    required this.releaseBypass,
    required this.clearBypass,
    required this.isBypassHeldByHotkey,
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
  static const Duration _repeatDebounce = Duration(milliseconds: 1100);

  /// visionFilterState.clear() 相当（重ねている全層を外す）。
  final void Function() deactivateFilters;
  final Future<void> Function(bool value) setClickThrough;
  final Future<void> Function(bool value) setAlwaysOnTop;
  final bool Function() getClickThrough;

  /// 原画比較の bypass を、このホットキー専用の holder として確保する
  /// （#79。呼び出し元（main.dart）が `VisionFilterState.acquireBypass` に
  /// ホットキー専用の識別子を束縛して渡す）。
  final void Function() acquireBypass;

  /// このホットキー専用の holder を解放する（#79）。
  final void Function() releaseBypass;

  /// 誰が保持しているかに関わらず、すべての bypass holder を強制的に解除する
  /// （#79。`VisionFilterState.clearBypass`）。非常口専用 — 通常の
  /// hold/toggle には使わない。
  final void Function() clearBypass;

  /// このホットキー専用の holder を今まさに保持しているか（#79。呼び出し元が
  /// `VisionFilterState.isHeldBy` にホットキー専用の識別子を束縛して渡す）。
  ///
  /// hold/toggle 判定はこれで行う（グローバルな `VisionFilterState.bypassed`
  /// ではなく）。以前はホットキー側にローカルな bool（`_heldByHotkey`）を
  /// ミラーしていたが、`clearBypass()`（フィルタ選択・非常口）で外部から
  /// holder が解除されてもローカルな bool は追従せず、次の keyDown が
  /// 「まだ保持している」と誤認して release を呼び、実際には何も起きない
  /// （ON にならない）バグがあった。都度クエリすることでこのズレを無くす。
  final bool Function() isBypassHeldByHotkey;

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
  ///   holder を確保するだけ（既に確保済みなら [acquireBypass] は呼ばない）。
  ///   keyUp が常に解放するので、正しい hold 挙動になる。
  /// - keyUp が一度も届いていない環境: keyDown のたびに確保/解放をトグルする
  ///   が、直前の keyDown から [_repeatDebounce]（1100ms）以内の keyDown は
  ///   OS のキーリピートとみなして無視する（押しっぱなしで OS が keyDown を
  ///   連続送出する環境でも 1 回のトグルにしかならないようにする、#63）。
  void holdOriginalKeyDown() {
    if (_keyUpSeen) {
      if (!isBypassHeldByHotkey()) acquireBypass();
      return;
    }
    final now = _now();
    if (_lastKeyDownAt != null &&
        now.difference(_lastKeyDownAt!) < _repeatDebounce) {
      _lastKeyDownAt = now;
      return;
    }
    _lastKeyDownAt = now;
    if (isBypassHeldByHotkey()) {
      releaseBypass();
    } else {
      acquireBypass();
    }
  }

  void holdOriginalKeyUp() {
    _keyUpSeen = true;
    _lastKeyDownAt = null;
    if (isBypassHeldByHotkey()) releaseBypass();
  }

  /// 非常口: 全フィルタ停止 + 原画表示解除 + クリックスルー解除 + 最前面解除 +
  /// ウィンドウ表示/前面化 (#63)。
  ///
  /// メモリ上の状態変更（[deactivateFilters]/[clearBypass]）を先に行い、以降の
  /// I/O を伴うステップは 1 つずつ個別に try/catch する。どれか 1 ステップが
  /// 失敗しても（例: window_manager の呼び出しが例外を投げる）、残りのステップ
  /// は実行される — 非常口は「できるところまで全部やる」ことが要件のため、
  /// 1 つの失敗で他まで巻き添えにしない。
  ///
  /// 原画表示の解除は、ホットキー自身の holder だけでなく **誰が保持していても**
  /// 必ず解除する（[clearBypass]、#79）。非常口は「何が原因でも確実に元へ戻す」
  /// 経路なので、HUD 等の他入力元が原画比較中でも一緒に解除する。
  Future<void> emergencyExit() async {
    deactivateFilters();
    clearBypass();

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
