import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart' show HotKey;
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../main.dart' show WindowModeUiContext;
import '../../services/hotkey_service.dart';
import '../../services/loupe_window_controller.dart';
import 'click_through_dialog_scope.dart';

/// クリックスルーを解除する方法の文言一覧（#63）。
///
/// フォーカス復帰＋最初のキー入力・アプリ内 Esc は常に使える復帰経路なので
/// 必ず含める。トレイ・ホットキーは、実際に使えるときだけ足す。Wayland
/// ネイティブセッションでは登録「成功」が実発火を保証しないため、その判定に
/// 該当する Linux ではホットキーのヒントを常に除外する。toggleClickThrough の
/// 方がクリックスルーを直接解除できて分かりやすいので優先する。
///
/// [WindowModePanel]（起動モードのダイアログ内、常時表示）と
/// [ClickThroughRecoveryBanner]（クリックスルー ON の間、主画面に常時表示、
/// #72）が共有する。
List<String> clickThroughRecoveryLines(
  AppLocalizations l10n,
  WindowModeUiContext uiContext,
) {
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
  return [
    l10n.clickThroughRecoveryFocusHint,
    l10n.clickThroughRecoveryEscapeHint,
    if (uiContext.trayAvailable) l10n.clickThroughRecoveryTrayHint,
    if (hotkeyRecoveryText != null)
      l10n.clickThroughRecoveryHotkeyHint(hotkeyRecoveryText),
  ];
}

/// 起動モードのダイアログを開く（#72: 主役より後ろ、AppBar のボタンから）。
///
/// クリックスルーが ON になった時点（このダイアログのスイッチでも、グローバル
/// ホットキー・トレイ経由でも）でダイアログを自動で閉じ、主画面の復帰方法の案内
/// （[ClickThroughRecoveryBanner]）を見せる。ON のあとはクリックが窓を素通りして
/// 「閉じる」ボタンを押せず、最初の Esc もダイアログを閉じるだけで解除まで 2 回
/// かかってしまうため（#63）。すでに ON のままダイアログを開いた場合は閉じず、
/// ダイアログの中でも Esc がクリックスルーの解除になる。
///
/// [MaterialApp] より上に置かれた Provider（`main.dart`）を読むので、
/// ダイアログの中でもそのまま [WindowModePanel] が使える。
Future<void> showWindowModeDialog(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.window_outlined,
            color: Theme.of(dialogContext).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(l10n.windowModeSectionTitle)),
        ],
      ),
      content: const ClickThroughDialogScope(
        child: SizedBox(
          width: 480,
          child: SingleChildScrollView(child: WindowModePanel()),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.windowModeCloseButton),
        ),
      ],
    ),
  );
}

/// クリックスルーが ON の間だけ主画面に常時表示する、復帰方法の案内（#63, #72）。
///
/// 復帰手段が見えないと操作不能になるため、起動モードのダイアログを開かなくても
/// 見える場所（主画面の最上部）に出す。色は [ColorScheme] のロールのみ。
class ClickThroughRecoveryBanner extends StatelessWidget {
  const ClickThroughRecoveryBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final uiContext = context.watch<WindowModeUiContext>();
    return Consumer<LoupeWindowController>(
      builder: (context, loupeWindow, _) {
        if (!loupeWindow.clickThrough) return const SizedBox.shrink();
        final lines = clickThroughRecoveryLines(l10n, uiContext);
        return Semantics(
          container: true,
          liveRegion: true,
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.ads_click,
                        size: 18, color: scheme.onTertiaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.clickThroughOnBannerTitle,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: scheme.onTertiaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                for (final line in lines)
                  Text(
                    line,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onTertiaryContainer),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 起動モード・最前面固定・クリックスルー・グローバルホットキー一覧 (#63)。
///
/// #72 で主画面から外し、AppBar のボタンから開くダイアログ
/// （[showWindowModeDialog]）の中身にした。ここは面（`Card`）を持たない。
/// クリックスルーの復帰方法の文言（[clickThroughRecoveryLines]）は、
/// スイッチのすぐ下に常時表示する。
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
        final recoveryLines = clickThroughRecoveryLines(l10n, uiContext);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
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
            Semantics(
              header: true,
              child: Text(
                l10n.hotkeySectionTitle,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
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
              style: theme.textTheme.bodyMedium?.copyWith(
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
              style:
                  theme.textTheme.bodySmall?.copyWith(color: colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
