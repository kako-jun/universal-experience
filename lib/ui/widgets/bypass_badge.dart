import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// 「原画表示中」のバッジ（#63 ホットキー「押している間だけ原画」、#183）。
///
/// プレビューの見出し行を廃止したので、After 画像（2×2 のときは右下のセル）の左下に画像の枠の中で
/// 重ねる（[overlaid]）。画像の枠の中なので、書き出しボタンや見出し・注記と重ならない。出た瞬間だけ
/// 読み上げられるよう liveRegion にする（押すたびに 1 回）。
///
/// 画像が小さい（下限 160dp）ときや文字が大きいときに、文字つきの形が画像を大きく覆わないよう、
/// 文字つきの形が画像の幅の [maxWidthRatio] 以下かつ高さの [maxHeightRatio] 以下のときだけ文字つきに
/// する（[fitsAsText]）。そうでなければ、文字倍率を縮小で打ち消さず、アイコンだけの小さい形にする
/// （意味はアイコンの tooltip と読み上げのラベルで伝える）。
/// 採用値は実フォントの実測から決めた（ja ×1 104×40、×2 167×54、en ×1 139×40、×2 234×54、
/// ×3 は ja 237×74 / en 337×74。画像は 800x600 で 190、1280x480 で 160、1280x800 で約 260）:
/// 幅 3/4・高さ 1/4 だと、800x600 の ja ×1〜×1.5 と en ×1 は文字つき、ja ×2 以上・en ×1.5 以上は
/// アイコン。
class BypassBadge extends StatelessWidget {
  const BypassBadge({super.key, this.within});

  /// バッジを重ねる画像の枠の大きさ。null（準備中の表示など、画像が無いとき）は大きさの比率を見ない。
  final Size? within;

  /// 文字つきの形が画像の幅のこの割合以下のときだけ文字つきにする。
  static const double maxWidthRatio = 0.75;

  /// 文字つきの形が画像の高さのこの割合以下のときだけ文字つきにする。
  static const double maxHeightRatio = 0.25;

  /// 文字つきの形（[badge] の大きさ）を、画像の枠 [image] に重ねてよいか。
  static bool fitsAsText(Size badge, Size image) =>
      badge.width <= image.width * maxWidthRatio &&
      badge.height <= image.height * maxHeightRatio;

  /// [image]（正方形の画像の枠）の左下に、[show] のときだけバッジを重ねる。
  static Widget overlaid(Widget image, {required bool show}) {
    if (!show) return image;
    return Stack(
      children: [
        image,
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, box) => Padding(
              padding: const EdgeInsets.all(4),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: BypassBadge(within: box.biggest),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static TextStyle? _labelStyle(ThemeData theme) =>
      theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.onSecondaryContainer,
      );

  /// 文字つきの形の大きさの見積り（実フォントの実測以上。テストで確かめる）。幅は文字 + Chip の左右の
  /// 余白（実測で ×1〜×1.19 は最大 34、+36 で余裕 2）。高さは実測の 40（×1）/ 44（×1.5）/
  /// 54（×2）/ 74（×3）= max(40, 文字の 1 行 + 14)。
  static Size textFormSize(BuildContext context) {
    final label = AppLocalizations.of(context)!.bypassedBadgeLabel;
    final painter = TextPainter(
      text: TextSpan(text: label, style: _labelStyle(Theme.of(context))),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final size = Size(
      painter.width + 36,
      painter.height + 14 < 40 ? 40 : painter.height + 14,
    );
    painter.dispose();
    return size;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final label = l10n.bypassedBadgeLabel;
    final style = _labelStyle(theme);
    return LayoutBuilder(
      builder: (context, box) {
        final fullSize = textFormSize(context);
        final image = within;
        final fits = fullSize.width <= box.maxWidth &&
            (image == null || fitsAsText(fullSize, image));
        if (fits) {
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
