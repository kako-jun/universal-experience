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
  });

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
  /// keyDown は常にトグルする。keyUp が届けば強制的に OFF にする。
  /// これにより:
  /// - keyUp が届く環境（通常の hold ジェスチャ）: 押す→ON、離す→OFF という
  ///   正しい「押している間だけ」の挙動になる。
  /// - keyUp が届かない環境（一部 OS のグローバルホットキーで keyUp が配送されない）:
  ///   毎回の押下が単純なトグルとして機能する（1 回目の押下で ON のまま残り、
  ///   2 回目の押下で OFF に戻る）。
  /// タイマー等での環境判定は不要で、この 2 つのハンドラの組み合わせだけで
  /// 両方の環境に自然にフォールバックする。
  void holdOriginalKeyDown() => setBypassed(!getBypassed());

  void holdOriginalKeyUp() {
    if (getBypassed()) setBypassed(false);
  }

  /// 非常口: 全フィルタ停止 + クリックスルー解除 + 最前面解除 + ウィンドウ表示/前面化
  /// + bypassed 解除 + トレイの表示状態同期。
  Future<void> emergencyExit() async {
    deactivateFilters();
    await setClickThrough(false);
    await setAlwaysOnTop(false);
    await showAndFocusLoupe();
    setBypassed(false);
    await setLoupeVisible(true);
  }
}
