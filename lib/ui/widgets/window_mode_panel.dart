import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../main.dart' show WindowModeUiContext;
import '../../services/hotkey_service.dart';
import '../../services/loupe_window_controller.dart';

/// 起動モード・最前面固定・クリックスルー・グローバルホットキー一覧 (#63)。
///
/// **色は `Theme.of(context).colorScheme` のロールだけを使う**（`home_screen.dart`
/// の既存セクションはまだ `Colors.xxx` をハードコードしているが、この新しい
/// ウィジェットだけは colorScheme ロールに従う、#63 の指示）。
class WindowModePanel extends StatelessWidget {
  const WindowModePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final uiContext = context.watch<WindowModeUiContext>();

    return Consumer<LoupeWindowController>(
      builder: (context, loupeWindow, _) {
        final canEnableClickThrough = LoupeWindowPolicy.canEnableClickThrough(
          trayAvailable: uiContext.trayAvailable,
          clickThroughHotkeyAvailable: uiContext.hotkeyStatus
              .isRegistered(AppHotkeyAction.toggleClickThrough),
          emergencyExitHotkeyAvailable: uiContext.hotkeyStatus
              .isRegistered(AppHotkeyAction.emergencyExit),
        );
        // ON にする操作だけを禁止する。既に ON なら OFF へはいつでも戻せる
        // （#63 受け入れ条件: 復帰手段が無い状態で ON にはできないが、既に ON の
        // ものを OFF にする操作を塞いではいけない）。
        final clickThroughDisabled =
            !loupeWindow.clickThrough && !canEnableClickThrough;
        final showClickThroughHint =
            clickThroughDisabled || !uiContext.trayAvailable;
        // 「戻るにはこのホットキー」ヒントに表示する、実際に登録されているホットキー。
        // clickThroughDisabled が false のときに showClickThroughHint が true になるのは
        // tray が無く、かつ toggleClickThrough か emergencyExit のどちらかが登録されている
        // 場合に限られる（canEnableClickThrough の判定と対応）。toggleClickThrough の方が
        // クリックスルーを直接解除できて分かりやすいため優先する。
        final returnPathHotkeyAction = uiContext.hotkeyStatus
                .isRegistered(AppHotkeyAction.toggleClickThrough)
            ? AppHotkeyAction.toggleClickThrough
            : (uiContext.hotkeyStatus.isRegistered(AppHotkeyAction.emergencyExit)
                ? AppHotkeyAction.emergencyExit
                : null);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.window_outlined, color: colorScheme.primary),
                    const SizedBox(width: 12),
                    Text(
                      l10n.windowModeSectionTitle,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SegmentedButton<AppMode>(
                  segments: [
                    ButtonSegment(
                      value: AppMode.settings,
                      label: Text(l10n.windowModeSettings),
                      icon: const Icon(Icons.tune),
                    ),
                    ButtonSegment(
                      value: AppMode.loupe,
                      label: Text(l10n.windowModeLoupe),
                      icon: const Icon(Icons.search),
                    ),
                  ],
                  selected: {loupeWindow.appMode},
                  onSelectionChanged: (selected) {
                    if (selected.isEmpty) return;
                    loupeWindow.setAppMode(selected.first);
                  },
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.alwaysOnTopLabel),
                  value: loupeWindow.alwaysOnTop,
                  onChanged: (value) => loupeWindow.setAlwaysOnTop(value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.clickThroughLabel),
                  value: loupeWindow.clickThrough,
                  // settings モードでは setClickThrough 自身が ON をガードする
                  // ため機能的には安全だが、拒否されて何も起きないより先に
                  // スイッチ自体を無効化したほうが分かりやすい（#63）。
                  onChanged: (clickThroughDisabled ||
                          loupeWindow.appMode == AppMode.settings)
                      ? null
                      : (value) => loupeWindow.setClickThrough(value),
                ),
                if (showClickThroughHint)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: Text(
                      (clickThroughDisabled || returnPathHotkeyAction == null)
                          ? l10n.clickThroughNoReturnPathHint
                          : l10n.clickThroughDisabledHint(
                              describeHotkey(returnPathHotkeyAction),
                            ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  l10n.hotkeySectionTitle,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                for (final action in AppHotkeyAction.values)
                  _HotkeyRow(
                    action: action,
                    label: _hotkeyLabel(l10n, action),
                    failed: uiContext.hotkeyStatus.failed.contains(action),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _hotkeyLabel(AppLocalizations l10n, AppHotkeyAction action) {
    switch (action) {
      case AppHotkeyAction.toggleClickThrough:
        return l10n.hotkeyToggleClickThrough;
      case AppHotkeyAction.holdOriginal:
        return l10n.hotkeyHoldOriginal;
      case AppHotkeyAction.emergencyExit:
        return l10n.hotkeyEmergencyExit;
      case AppHotkeyAction.toggleLoupeVisibility:
        return l10n.hotkeyToggleLoupeVisibility;
    }
  }
}

class _HotkeyRow extends StatelessWidget {
  const _HotkeyRow({
    required this.action,
    required this.label,
    required this.failed,
  });

  final AppHotkeyAction action;
  final String label;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: failed ? colorScheme.error : colorScheme.onSurface,
              ),
            ),
          ),
          Text(
            describeHotkey(action),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
          ),
          if (failed) ...[
            const SizedBox(width: 8),
            Text(
              l10n.hotkeyRegistrationFailed,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
