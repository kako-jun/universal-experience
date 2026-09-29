import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyEvent, KeyUpEvent, LogicalKeyboardKey;
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

/// ルーペ窓 HUD（#79）。
///
/// [LoupeWindowController.appMode] が [AppMode.loupe] のときだけ、窓の縁
/// （上端）に小さなツールバーを出す。設定窓モード（[AppMode.settings]）では
/// 何も描画しない（[SizedBox.shrink]）。
///
/// 表示するもの（このファイルが正本、`docs/ARCHITECTURE.md`「ルーペ窓 HUD」参照）:
/// - 症状名・強度（[VisionFilterState] の現在の選択。表示名の解決は
///   [visionFilterDisplayName]（#60 の元 `_displayName` を共有可能な形に
///   抽出したもの）を [before_after_view.dart] と共有する — 重複させない）
/// - 受診喚起アイコン（[resolveConsultNotice] が非 null を返すときだけ表示。
///   押すと [ConsultNoticeBlock] で全文をダイアログ表示する）
/// - 原画比較ボタン（押している間だけ [VisionFilterState.bypassed] を true に
///   し、離す/キャンセルで必ず false に戻す）
/// - 設定を開くボタン（[LoupeWindowController.setAppMode] で設定窓モードへ戻す）
///
/// 全画面（[LoupeWindowMode.fullscreen]）では自動的に隠れ、[MouseRegion] で
/// 窓の上端にポインタが近づいたときだけ表示する。
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

  void _setHovering(bool value) {
    if (_hovering == value) return;
    setState(() => _hovering = value);
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
        return Align(
          alignment: Alignment.topCenter,
          child: MouseRegion(
            onEnter: (_) => _setHovering(true),
            onExit: (_) => _setHovering(false),
            child: AnimatedOpacity(
              // 全画面時、隠れていても MouseRegion 自体は常にレイアウトされて
              // いる（このウィジェット自身は hit test 対象のまま）ので、縁への
              // 接近を検知できる。IgnorePointer が内側の実ボタンだけを
              // 非表示中は操作不能にする。
              opacity: visible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 150),
              child: IgnorePointer(
                ignoring: !visible,
                child: const _LoupeHudBar(),
              ),
            ),
          ),
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
        final strengthPercent =
            (previewStrength(visionState, filterService).clamp(0.0, 1.0) * 100)
                .round();
        // #76 レビュー M1 と同じく、喚起の解決は resolveConsultNotice 1 箇所に
        // 集約する（FilterParamPanel・ExperiencePresets・export と同じ経路）。
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
                _CompareOriginalButton(tooltip: l10n.hudCompareOriginalTooltip),
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
/// [IconButton] の `tooltip` は Semantics の `tooltip` プロパティにしか載らず
/// `label` にはならない（ホバー時のツールチップ表示としては機能するが、
/// スクリーンリーダーの多くはラベルを読む）。Tab フォーカス到達時に
/// アクセシビリティツリーへ確実にラベルが載るよう、明示的に
/// `Semantics(label: tooltip)` で包む（#79）。
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
      child: IconButton(
        icon: Icon(icon, color: color),
        tooltip: tooltip,
        iconSize: 26,
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        onPressed: onPressed,
      ),
    );
  }
}

/// 原画比較ボタン（#79）。押している間だけ [VisionFilterState.bypassed] を
/// true にし、離すと false に戻す。
///
/// ポインタが領域外に出た場合（[_CompareOriginalButtonState._handlePointerMove]、
/// [MouseRegion.onExit] を保険として併用）・ジェスチャがキャンセルされた場合
/// （[Listener.onPointerCancel]）も必ず false に戻す — 「押したまま領域外に
/// 出て離した」場合に ON のまま固定されてしまうのを防ぐ。マウス/タッチに加え、
/// Tab でフォーカスした状態での Enter/Space 押下でも同じ挙動にする
/// （キーボード操作、#79）。
class _CompareOriginalButton extends StatefulWidget {
  const _CompareOriginalButton({required this.tooltip});

  final String tooltip;

  @override
  State<_CompareOriginalButton> createState() => _CompareOriginalButtonState();
}

class _CompareOriginalButtonState extends State<_CompareOriginalButton> {
  /// [Container] の見た目のサイズと一致させる（[_handlePointerMove] の
  /// 領域外判定に使う）。
  static const Size _buttonSize = Size(48, 48);

  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
    context.read<VisionFilterState>().setBypassed(value);
  }

  /// 押したままポインタが領域外に出たら OFF に戻す。
  ///
  /// [MouseRegion.onExit] はホバー専用のイベント（`PointerHoverEvent` 等）で
  /// 更新されるが、Flutter のマウストラッキングはボタンを押したままの移動
  /// （`PointerMoveEvent`）では更新されない既知の制約があり、ドラッグ中に
  /// 領域外へ出ても `onExit` が発火しないことがある。そのため
  /// [Listener.onPointerMove] で生の座標を直接見て、ボタンの矩形
  /// （[_buttonSize]）に収まっているかを毎回判定する — これがドラッグ中の
  /// 「領域外に出た」を確実に検知する主経路。[MouseRegion.onExit] はボタンを
  /// 押していない通常のホバー解除のための保険として残す。
  void _handlePointerMove(PointerEvent event) {
    if (!_pressed) return;
    final withinBounds = (Offset.zero & _buttonSize).contains(
      event.localPosition,
    );
    if (!withinBounds) _setPressed(false);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.space) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      _setPressed(true);
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      _setPressed(false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        label: widget.tooltip,
        toggled: _pressed,
        child: Focus(
          onKeyEvent: _handleKeyEvent,
          child: MouseRegion(
            onExit: (_) => _setPressed(false),
            child: Listener(
              onPointerDown: (_) => _setPressed(true),
              onPointerMove: _handlePointerMove,
              onPointerUp: (_) => _setPressed(false),
              onPointerCancel: (_) => _setPressed(false),
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color:
                      _pressed ? scheme.primaryContainer : Colors.transparent,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  Icons.visibility_outlined,
                  color:
                      _pressed ? scheme.onPrimaryContainer : scheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
