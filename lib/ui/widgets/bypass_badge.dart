import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// 「原画表示中」のバッジ（#63 ホットキー「押している間だけ原画」、#183）。
///
/// プレビューの見出し行を廃止したので、After 画像の左下（2×2 のときは右下のセルの左下）に
/// 重ねる。画像の枠の中なので、書き出しボタンや見出し・注記と重ならない。出た瞬間だけ
/// 読み上げられるよう liveRegion にする。
class BypassBadge extends StatelessWidget {
  const BypassBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      liveRegion: true,
      child: Chip(
        label: Text(l10n.bypassedBadgeLabel),
        backgroundColor: theme.colorScheme.secondaryContainer,
        labelStyle: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
