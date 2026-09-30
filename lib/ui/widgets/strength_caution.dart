import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/vision_filter_contract_notes.dart';

/// 強度スライダの「上限付近の注意」の見た目（#66、#51 注記1）。
///
/// 上限付近で注意が要るフィルタ（[kStrengthCautionByFilterId]）に対して、
/// スライダの閾値位置へ**印**を描く [StrengthCautionTrackShape] と、その下の
/// **注記**（[StrengthCautionNote]）を提供する。定義（どのフィルタ・どの閾値か）は
/// `lib/models/vision_filter_contract_notes.dart`、文言は ARB が正本。
///
/// 色は colorScheme のロールだけ・文字は textTheme のロールだけを使う
/// （DESIGN §2/§3）。受診喚起（`ConsultNoticeBlock`）と混同しないよう、
/// コンテナ色（tertiary/error）は使わず、注意の強さはアイコン・太さ・文言の
/// 違いで伝える（色だけで意味を伝えない）。

/// 閾値位置に縦線の印を描くトラック形状。
///
/// Flutter のスライダは、目盛り（divisions）を打つとき（`isDiscrete`）トラックの
/// 両端に丸みの分（トラックの高さ）の余白を取り、つまみ・目盛りを
/// `left + v * (width - 高さ) + 高さ / 2` の位置に置く。印も同じ式で置くので、
/// 閾値と同じ値のつまみ・目盛りにぴったり重なり、スライダの幅が変わってもずれない。
class StrengthCautionTrackShape extends RoundedRectSliderTrackShape {
  const StrengthCautionTrackShape({
    required this.threshold,
    required this.markColor,
  });

  /// 印を描く位置（0.0..1.0、スライダの min..max に対する比）。
  final double threshold;

  /// 印の色（呼び出し側が colorScheme のロールから渡す）。
  final Color markColor;

  /// 印の太さ・トラックからはみ出す長さ（dp）。
  static const double markWidth = 2;
  static const double markOverhang = 8;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
    );
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final t = textDirection == TextDirection.rtl ? 1 - threshold : threshold;
    // divisions ありのとき、つまみ・目盛りと同じ式（Flutter の Slider と同じ）。
    final pad = isDiscrete && isRounded ? trackRect.height : 0.0;
    final x = trackRect.left + t * (trackRect.width - pad) + pad / 2;
    final half = trackRect.height / 2 + markOverhang;
    final markRect = Rect.fromLTRB(
      x - markWidth / 2,
      trackRect.center.dy - half,
      x + markWidth / 2,
      trackRect.center.dy + half,
    );
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(markRect, const Radius.circular(1)),
      // 無効時は DESIGN §2.2 の無効表現（不透明度 38%）。
      Paint()
        ..color = isEnabled ? markColor : markColor.withValues(alpha: 0.38),
    );
  }
}

/// スライダの下に置く注記。強度が閾値未満のあいだは印の説明（補足の見た目）、
/// 閾値以上では警告（アイコン・太字・onSurface）に切り替わる。
///
/// どちらの文言も sensus の契約（最も進行した段階＝視野のほぼすべてを失った状態を
/// 再現する設計）を伝えるもので、故障ではない旨を含む。
/// `Semantics(liveRegion)` で、閾値をまたいだ変化をスクリーンリーダーにも伝える。
class StrengthCautionNote extends StatelessWidget {
  const StrengthCautionNote({
    super.key,
    required this.caution,
    required this.strength,
  });

  final StrengthCaution caution;

  /// 現在の強度（0.0..1.0）。
  final double strength;

  /// 強度が閾値以上か（警告表現にするか）。
  ///
  /// 画面に出す整数パーセント（[strengthPercent]）で比べるので、「80%」と
  /// 表示されているときは必ず警告になり、浮動小数の誤差（0.7999…）で
  /// ずれない。
  bool get isNearLimit =>
      strengthPercent(strength) >= strengthPercent(caution.threshold);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final near = isNearLimit;
    final text = near
        ? l10n.strengthCautionNearLimit
        : l10n.strengthCautionMarkerNote(strengthPercent(caution.threshold));
    final style = near
        ? theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          )
        : theme.textTheme.bodySmall
            ?.copyWith(color: colorScheme.onSurfaceVariant);
    return Semantics(
      liveRegion: near,
      container: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(
              near ? Icons.warning_amber_rounded : Icons.info_outline,
              size: 18,
              color: near ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }
}
