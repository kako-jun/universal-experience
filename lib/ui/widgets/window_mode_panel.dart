import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart' show HotKey;
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../main.dart' show WindowModeUiContext;
import '../../services/hotkey_service.dart';
import '../../services/loupe_window_controller.dart';

/// 起動モード・最前面固定・クリックスルー・グローバルホットキー一覧 (#63)。
///
/// **色は `Theme.of(context).colorScheme` のロールだけを使う**（DESIGN.md）。
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
        // 実際に登録されている toggleClickThrough/emergencyExit ホットキーを、
        // 「戻るにはこのホットキー」ヒントに使う (#63)。toggleClickThrough の
        // 方がクリックスルーを直接解除できて分かりやすいため優先する。Wayland
        // ネイティブセッションでは登録「成功」が実発火を保証しないため、その
        // 判定に該当する Linux では常にヒントから除外する。
        final isLikelyUnreliableHotkeyEnvironment = Platform.isLinux &&
            LoupeWindowPolicy.isLikelyWaylandNativeSession(Platform.environment);
        AppHotkeyAction? hotkeyRecoveryAction;
        if (!isLikelyUnreliableHotkeyEnvironment) {
          if (uiContext.hotkeyStatus
              .isRegistered(AppHotkeyAction.toggleClickThrough)) {
            hotkeyRecoveryAction = AppHotkeyAction.toggleClickThrough;
          } else if (uiContext.hotkeyStatus
              .isRegistered(AppHotkeyAction.emergencyExit)) {
            hotkeyRecoveryAction = AppHotkeyAction.emergencyExit;
          }
        }
        final hotkeyRecoveryText = hotkeyRecoveryAction == null
            ? null
            : describeHotkey(
                uiContext.hotkeyStatus.bindings[hotkeyRecoveryAction] ??
                    defaultHotkeyBindings()[hotkeyRecoveryAction]!,
                useMacSymbols: Platform.isMacOS,
              );

        final recoveryLines = <String>[
          l10n.clickThroughRecoveryFocusHint,
          l10n.clickThroughRecoveryEscapeHint,
          if (uiContext.trayAvailable) l10n.clickThroughRecoveryTrayHint,
          if (hotkeyRecoveryText != null)
            l10n.clickThroughRecoveryHotkeyHint(hotkeyRecoveryText),
        ];

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
                  // 設定窓モードは UI 操作が前提の通常ウィンドウなので、
                  // クリックスルーを ON にはできない。setClickThrough 自身が
                  // 拒否するため機能的には安全だが、拒否されて何も起きないより
                  // 先にスイッチ自体を無効化したほうが分かりやすい (#63)。
                  onChanged: loupeWindow.appMode == AppMode.settings
                      ? null
                      : (value) => loupeWindow.setClickThrough(value),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in recoveryLines)
                        Text(
                          line,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                    ],
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
                    hotKey: uiContext.hotkeyStatus.bindings[action] ??
                        defaultHotkeyBindings()[action]!,
                    label: _hotkeyLabel(l10n, action),
                    failed: uiContext.hotkeyStatus.failed.contains(action),
                  ),
                const SizedBox(height: 4),
                Text(
                  l10n.hotkeyRegistrationCaveat,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
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
    required this.hotKey,
    required this.label,
    required this.failed,
  });

  final HotKey hotKey;
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
            describeHotkey(hotKey, useMacSymbols: Platform.isMacOS),
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
