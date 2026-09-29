import 'dart:async' show Timer, scheduleMicrotask;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyEvent, KeyRepeatEvent, KeyUpEvent, LogicalKeyboardKey;
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/filter_service.dart';
import '../../services/loupe_window_controller.dart';
import '../../services/preview_selection.dart';
import '../../services/vision_filter_metadata.dart';
import '../../services/vision_filter_state.dart';
import '../../src/rust/api/sensus_bridge.dart';
import 'consult_notice_block.dart';

/// [LoupeWindowController] から「全画面かどうか」を取り出す関数の型（#79）。
typedef IsLoupeFullScreen = bool Function(LoupeWindowController controller);

/// 全画面判定の供給源（既定: `LoupeWindowController.mode`）。`LoupeWindowController`
/// は `onWindowEnterFullScreen`/`onWindowLeaveFullScreen`（window_manager の
/// `WindowListener`）で既に `_mode` をリアルタイムに追従させているので、これを
/// そのまま見れば足りる（window_manager の `isFullScreen()` を別途ポーリングする
/// 必要は無い）。他の provider seam（`vision_filter_metadata.dart` の
/// `visionFilterUrgencyProvider` 等）と同じパターンで、widget test から
/// 差し替えられるようにするための seam。production はこの既定値のまま使う。
@visibleForTesting
IsLoupeFullScreen isLoupeFullScreenProvider =
    (controller) => controller.mode == LoupeWindowMode.fullscreen;

/// 縁のホバー検知帯から手を離してから、実際に隠すまでの遅延（#79 レビュー
/// S2）。ホバー検知帯とバー本体の間でポインタが一瞬途切れても隠れないように
/// する猶予。
const Duration kLoupeHudHideDelay = Duration(milliseconds: 700);

/// ルーペ窓 HUD（#79）。
///
/// [LoupeWindowController.appMode] が [AppMode.loupe] のときだけ、窓の縁
/// （上端）に小さなツールバーを出す。設定窓モード（[AppMode.settings]）では
/// 何も描画しない（[SizedBox.shrink]）。
///
/// 表示するもの（このファイルが正本、`docs/ARCHITECTURE.md`「ルーペ窓 HUD」参照）:
/// - 症状名・強度（[VisionFilterState] の現在の選択。表示名の解決は
///   [visionFilterDisplayName]（#60 の元 `_displayName` を共有可能な形に
///   抽出したもの）を `before_after_view.dart` と共有する — 重複させない。
///   強度は bypass に関わらない [selectedStrength] を使う、#79 レビュー S1）
/// - 受診喚起アイコン（[resolveConsultNotice] が非 null を返すときだけ表示。
///   押すと [ConsultNoticeBlock] で全文をダイアログ表示する）
/// - 原画比較ボタン（押している間だけ [VisionFilterState.bypassed] を true に
///   し、離す/キャンセルで必ず false に戻す。スクリーンリーダー等、押し続ける
///   操作ができない場合のトグル代替も持つ、#79 レビュー S4）
/// - 設定を開くボタン（[LoupeWindowController.setAppMode] で設定窓モードへ戻す）
///
/// 全画面（[LoupeWindowMode.fullscreen]）では自動的に隠れ、窓の上端全幅にわたる
/// 検知帯（高さ 12px、#79 レビュー S2）にポインタが入ったときだけ表示する。
/// バー本体の上にいる間は表示を維持し、離れてから [kLoupeHudHideDelay] だけ
/// 遅らせて隠す。
///
/// **将来のライブキャプチャ（#1）に向けた前提**: このウィジェットはキャプチャ
/// 対象・フィルタ対象から**除外する必要がある**（HUD 自体をフィルタ加工したり
/// キャプチャに写り込ませたりしてはいけない）。現状ライブキャプチャは無いため
/// 実際の除外処理は無いが、この HUD は常に独立した最上位レイヤ（`main.dart` の
/// `Stack` で `HomeScreen`/将来のルーペ描画とは別 layer として重ねる）として
/// 置き、除外の実装（#1 実装時にキャプチャ対象の矩形から HUD の矩形を差し引く、
/// またはキャプチャそのものを HUD の下のレイヤだけに限定する）がしやすい構造に
/// してある。
class LoupeHud extends StatefulWidget {
  const LoupeHud({super.key});

  @override
  State<LoupeHud> createState() => _LoupeHudState();
}

class _LoupeHudState extends State<LoupeHud> {
  bool _hovering = false;
  Timer? _hideTimer;

  /// 検知帯・バーいずれかにポインタが入ったら、遅延を予約済みならキャンセル
  /// して即座に表示する（#79 レビュー S2）。
  void _showNow() {
    _hideTimer?.cancel();
    _hideTimer = null;
    if (!_hovering) setState(() => _hovering = true);
  }

  /// 検知帯・バーいずれからもポインタが離れたら、[kLoupeHudHideDelay] だけ
  /// 遅らせて隠す（#79 レビュー S2）。検知帯からバー本体へ移動する一瞬の
  /// 途切れで隠れてしまわないための猶予。
  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(kLoupeHudHideDelay, () {
      _hideTimer = null;
      if (mounted) setState(() => _hovering = false);
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LoupeWindowController>(
      builder: (context, loupeWindow, _) {
        if (loupeWindow.appMode != AppMode.loupe) {
          return const SizedBox.shrink();
        }
        final fullScreen = isLoupeFullScreenProvider(loupeWindow);
        final visible = !fullScreen || _hovering;
        return Stack(
          children: [
            // #79 レビュー S2: 上端全幅・高さ 12px の検知帯。opaque: false で
            // 下の画面へのクリックを奪わない（純粋なホバー検知専用、S3）。
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 12,
              child: MouseRegion(
                opaque: false,
                onEnter: (_) => _showNow(),
                onExit: (_) => _scheduleHide(),
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: MouseRegion(
                onEnter: (_) => _showNow(),
                onExit: (_) => _scheduleHide(),
                child: AnimatedOpacity(
                  opacity: visible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 150),
                  // #79 レビュー S3: 非表示中は IgnorePointer（操作不能）と
                  // ExcludeSemantics（アクセシビリティツリーから除外）の両方で
                  // バーを外す。
                  child: visible
                      ? const _LoupeHudBar()
                      : const ExcludeSemantics(
                          child: IgnorePointer(child: _LoupeHudBar()),
                        ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LoupeHudBar extends StatelessWidget {
  const _LoupeHudBar();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Consumer2<VisionFilterState, FilterService>(
      builder: (context, visionState, filterService, _) {
        final filter = visionState.build();
        final symptomLabel = visionFilterDisplayName(
          l10n,
          visionState.colorVisionType,
          visionState.selectedId,
        );
        // #79 レビュー S1: bypass に関わらない素の強度を表示する（原画比較中も
        // 「今選んでいるフィルタは何%か」が見え続けるように）。原画表示中で
        // あること自体は原画比較ボタンのアイコンの色で示す
        // （[_CompareOriginalButtonState] 参照）。
        final strengthPercent =
            (selectedStrength(visionState, filterService).clamp(0.0, 1.0) * 100)
                .round();
        // #76 と同じく、喚起の解決は resolveConsultNotice 1 箇所に集約する
        // （FilterParamPanel・ExperiencePresets・export と同じ経路）。
        final notice = filter == null
            ? null
            : resolveConsultNotice(
                l10n,
                visionFilterUrgencyProvider(filter),
                visionFilterUrgencyEscalationProvider(filter),
              );

        return Material(
          elevation: 4,
          color: scheme.surfaceContainerHighest,
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        symptomLabel,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        l10n.strengthLabel(strengthPercent),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (notice != null)
                  _HudIconButton(
                    icon: notice.urgency == Urgency.emergency
                        ? Icons.warning_amber_rounded
                        : Icons.medical_information_outlined,
                    tooltip: l10n.hudConsultNoticeTooltip,
                    color: notice.urgency == Urgency.emergency
                        ? scheme.error
                        : scheme.tertiary,
                    onPressed: () => _showConsultDialog(context, l10n, notice),
                  ),
                const _CompareOriginalButton(),
                _HudIconButton(
                  icon: Icons.settings_outlined,
                  tooltip: l10n.hudOpenSettingsTooltip,
                  color: scheme.onSurface,
                  onPressed: () => context
                      .read<LoupeWindowController>()
                      .setAppMode(AppMode.settings),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showConsultDialog(
    BuildContext context,
    AppLocalizations l10n,
    ConsultNotice notice,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.hudConsultDialogTitle),
        content: SingleChildScrollView(
          child: ConsultNoticeBlock(notice: notice, l10n: l10n),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child:
                Text(MaterialLocalizations.of(dialogContext).closeButtonLabel),
          ),
        ],
      ),
    );
  }
}

/// HUD の丸いアイコンボタン。当事者・高齢者の利用を前提に、既定の
/// [IconButton] より大きめのタップ領域（最小 48x48）を確保する。
///
/// [Tooltip] は `excludeFromSemantics: true` にし、代わりに明示的な
/// [Semantics] で `label` を 1 つだけ載せる。両方を素朴に重ねると、
/// アクセシビリティツリーに `label` と `tooltip` の両方が同じ文言で載って
/// 二重に読み上げられる（#79 レビュー nit）。visual なホバー/長押しツール
/// チップ表示自体は `excludeFromSemantics` の影響を受けず機能する。
class _HudIconButton extends StatelessWidget {
  const _HudIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: IconButton(
          icon: Icon(icon, color: color),
          iconSize: 26,
          padding: const EdgeInsets.all(12),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: onPressed,
        ),
      ),
    );
  }
}

/// 原画比較ボタン（#79）。押している間だけ [VisionFilterState.bypassed] を
/// true にし、離すと false に戻す。押している間だけ入力元専用の holder
/// （[_pressHolder]）を確保/解放する（#79 レビュー M3: 入力元ごとの保持に
/// 移行。ホットキー（`hotkey_actions.dart`）の holder とは独立しているため、
/// 互いの状態を消さない）。
///
/// ポインタが領域外に出た場合（[_CompareOriginalButtonState._handlePointerMove]
/// が生の座標を直接見て判定する。[MouseRegion.onExit] は保険として併用する
/// が、**タッチ入力には hover の概念自体が無い**ため、あらゆる入力方式で確実に
/// 動く必要がある「領域外に出たら離す」判定は [Listener.onPointerMove] を
/// 主経路にする、#79 レビュー nit）・ジェスチャがキャンセルされた場合
/// （[Listener.onPointerCancel]）も必ず holder を解放する — 「押したまま
/// 領域外に出て離した」場合に ON のまま固定されてしまうのを防ぐ。
///
/// フォーカスを失ったとき（[Focus.onFocusChange]）・ウィジェット自体が
/// dispose されるとき（[State.dispose]）も必ず holder を解放する（#79
/// レビュー M1/M2）。Tab でフォーカスした状態での Enter/Space 押下でも
/// 同じ挙動にし、OS のキーリピート（[KeyRepeatEvent]）も handled として扱う
/// （キーボード操作、#79 レビュー M2）。
///
/// 押し続ける操作ができない場合の代替として、[Semantics.onTap]（スクリーン
/// リーダー等の「アクティブ化」操作）は押し続けではなく**トグル**にする
/// （専用の holder、[_toggleHolder] で acquire/release する。押している間用の
/// [_pressHolder] とは独立に持つ、#79 レビュー S4）。
class _CompareOriginalButton extends StatefulWidget {
  const _CompareOriginalButton();

  @override
  State<_CompareOriginalButton> createState() => _CompareOriginalButtonState();
}

class _CompareOriginalButtonState extends State<_CompareOriginalButton> {
  /// 押している間だけの bypass 用 holder トークン（このボタンインスタンス専用）。
  final Object _pressHolder = Object();

  /// スクリーンリーダー等、押し続ける操作ができない場合のトグル代替用
  /// holder（[_pressHolder] とは独立、#79 レビュー S4）。
  final Object _toggleHolder = Object();

  /// [VisionFilterState] への参照。[State.dispose] からの安全な参照のため
  /// [didChangeDependencies] でキャッシュする（#79 レビュー M1: `context.read`
  /// は dispose 時点では安全に呼べないことがある）。
  VisionFilterState? _visionState;

  bool _toggledOn = false;
  bool _hasFocus = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visionState = context.read<VisionFilterState>();
  }

  @override
  void dispose() {
    // dispose 時点で押下中/トグル ON のままなら必ず holder を解放する（#79
    // レビュー M1）。releaseBypass は保持していなければ no-op（冪等）なので、
    // 状態を問わず常に呼んでよい。
    //
    // ただし dispose() はウィジェットツリーの unmount 中（フレームワークが
    // ロックされている間）に呼ばれるため、ここで同期的に notifyListeners
    // すると Provider の InheritedWidget が `setState() called when widget
    // tree was locked` で落ちる。解放そのものはマイクロタスクへ遅延し、
    // 現在の unmount パスを抜けてから通知する。
    final visionState = _visionState;
    if (visionState != null) {
      scheduleMicrotask(() {
        visionState.releaseBypass(_pressHolder);
        visionState.releaseBypass(_toggleHolder);
      });
    }
    super.dispose();
  }

  void _acquirePress() => _visionState?.acquireBypass(_pressHolder);

  void _releasePress() => _visionState?.releaseBypass(_pressHolder);

  /// 押したままポインタが領域外に出たら holder を解放する（#79）。
  ///
  /// タッチ入力には hover の概念が無いため [MouseRegion.onExit] は当てに
  /// できない（マウスでも効くとは限らない、上位 doc 参照）。そのため
  /// [Listener.onPointerMove] で生の座標を直接見て、ボタンの実際のレンダリング
  /// サイズ（[RenderBox]、#79 レビュー nit: ハードコードした定数ではなく実測
  /// する）に収まっているかを毎回判定する。
  void _handlePointerMove(PointerEvent event) {
    final renderObject = context.findRenderObject();
    final size = renderObject is RenderBox ? renderObject.size : Size.zero;
    final withinBounds = (Offset.zero & size).contains(event.localPosition);
    if (!withinBounds) _releasePress();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.space) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      _acquirePress();
      return KeyEventResult.handled;
    }
    if (event is KeyRepeatEvent) {
      // 既に押下中として扱っているので、リピート自体は握りつぶす（#79
      // レビュー M2）。他のグローバルショートカットへ意図せず伝播しないよう
      // handled を返す。
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      _releasePress();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 押し続ける操作ができない場合の代替（#79 レビュー S4）。専用の
  /// [_toggleHolder] で acquire/release するトグルで、押している間用の
  /// [_pressHolder] とは独立している。
  void _handleSemanticsToggle() {
    _toggledOn = !_toggledOn;
    if (_toggledOn) {
      _visionState?.acquireBypass(_toggleHolder);
    } else {
      _visionState?.releaseBypass(_toggleHolder);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // グローバルな bypassed（誰が保持していても true）を見て、原画比較中で
    // あることをアイコンの色で示す（#79 レビュー S1）。このボタン自身が
    // 押されているかどうかだけでなく、ホットキー等の他入力元が保持している
    // 場合も反映する。
    final comparing = context.watch<VisionFilterState>().bypassed;
    return Tooltip(
      message: l10n.hudCompareOriginalTooltip,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: l10n.hudCompareOriginalTooltip,
        onTap: _handleSemanticsToggle,
        child: Focus(
          onKeyEvent: _handleKeyEvent,
          onFocusChange: (hasFocus) {
            setState(() => _hasFocus = hasFocus);
            // #79 レビュー M2: フォーカスを失ったら押下中の holder を解放する
            // （マウスボタンを離さないままダイアログ等へフォーカスが移った
            // ケースでも固定されないようにする）。
            if (!hasFocus) _releasePress();
          },
          child: MouseRegion(
            onExit: (_) => _releasePress(),
            child: Listener(
              onPointerDown: (_) => _acquirePress(),
              onPointerMove: _handlePointerMove,
              onPointerUp: (_) => _releasePress(),
              onPointerCancel: (_) => _releasePress(),
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color:
                      comparing ? scheme.primaryContainer : Colors.transparent,
                  borderRadius: BorderRadius.circular(24),
                  border: _hasFocus
                      ? Border.all(color: scheme.primary, width: 2)
                      : null,
                ),
                child: Icon(
                  Icons.visibility_outlined,
                  color:
                      comparing ? scheme.onPrimaryContainer : scheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
