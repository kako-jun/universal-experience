import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// 「原画表示中」のバッジ（#63 ホットキー「押している間だけ原画」、#183）。
///
/// プレビューの見出し行を廃止したので、After 画像（2×2 のときは右下のセル）の左下に画像の枠の中で
/// 重ねる（[overlaid]）。画像の枠の中なので、書き出しボタンや見出し・注記と重ならない。出た瞬間だけ
/// 読み上げられるよう liveRegion にする（押すたびに 1 回）。
///
/// 画像が小さい（下限 160dp）ときや文字が大きいときに、文字つきの形が画像の下部を大きく覆わない
/// よう、置ける幅に文字つきの形が収まらなければアイコンだけの小さい形にする（文字倍率を縮小で
/// 打ち消さない。意味はアイコンの tooltip と読み上げのラベルで伝える）。
class BypassBadge extends StatelessWidget {
  const BypassBadge({super.key});

  /// [image]（正方形の画像の枠）の左下に、[show] のときだけバッジを重ねる。
  static Widget overlaid(Widget image, {required bool show}) {
    if (!show) return image;
    return Stack(
      children: [
        image,
        const Positioned(
          left: 4,
          right: 4,
          bottom: 4,
          child: Align(
            alignment: Alignment.bottomLeft,
            child: BypassBadge(),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final label = l10n.bypassedBadgeLabel;
    final style = theme.textTheme.labelLarge?.copyWith(
      color: theme.colorScheme.onSecondaryContainer,
    );
    return LayoutBuilder(
      builder: (context, box) {
        final painter = TextPainter(
          text: TextSpan(text: label, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        // Chip の左右の余白（visualDensity.compact）の見積り込みの、文字つきの形の幅。
        final fullWidth = painter.width + 32;
        painter.dispose();
        if (fullWidth <= box.maxWidth) {
          return Semantics(
            liveRegion: true,
            label: label,
            excludeSemantics: true,
            child: Chip(
              label: Text(label),
              backgroundColor: theme.colorScheme.secondaryContainer,
              labelStyle: style,
              visualDensity: VisualDensity.compact,
            ),
          );
        }
        return Semantics(
          liveRegion: true,
          label: label,
          excludeSemantics: true,
          child: Tooltip(
            message: label,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.visibility_outlined,
                size: 18,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        );
      },
    );
  }
}
