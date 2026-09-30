import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// 「実験的」バッジ（#80）。障害ではなく確立したモデルでもない可視化（現状は
/// 四色覚）に付ける。対象は `VisionFilterEntry.isExperimental` が決める。
///
/// 色だけで伝えない（DESIGN §7）ため、枠（形）・アイコン・文言の 3 つで示す。
/// 色は周囲の文字色をそのまま使う（選択中の行の `onSecondaryContainer` の上でも、
/// カード上の `onSurface` の上でも、文字と同じコントラストになる）。
class ExperimentalBadge extends StatelessWidget {
  const ExperimentalBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final color =
        DefaultTextStyle.of(context).style.color ?? theme.colorScheme.onSurface;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: StadiumBorder(side: BorderSide(color: color)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(Icons.science_outlined, size: 16, color: color),
            ),
            const SizedBox(width: 4),
            Text(
              l10n.experimentalBadge,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
