import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/vision_filter_contract_notes.dart';
import '../../services/filter_service.dart';
import '../../services/vision_filter_state.dart';

/// 色覚クイック選択の強度スライダー（#60）。右カラム「調整」（`AdjustPanel`、
/// #72）の、色覚の行を選んでいるときの強度の入口。
///
/// 有効/無効は `VisionFilterState.isColorQuickSelection` から導く（何も
/// 選択していない・advanced カタログ/体験プリセットを見ている間は無効）。
/// 選んでいないときの案内は `AdjustPanel` の「何も選択されていません」が担う
/// ので、このウィジェット自身は説明文を持たない。
///
/// 文字の大きさ・太さは `textTheme` のロールで指定する（DESIGN §3）。
class IntensitySlider extends StatelessWidget {
  const IntensitySlider({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Consumer2<FilterService, VisionFilterState>(
      builder: (context, filterService, visionState, _) {
        final isEnabled = visionState.isColorQuickSelection;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 狭い右カラムでも収まるよう Wrap にする（幅が足りなければ状態表示が
            // 次の行へ落ちる）。
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(
                  l10n.intensityValue(strengthPercent(filterService.intensity)),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: isEnabled
                        ? colorScheme.onSurface
                        : colorScheme.onSurface.withValues(alpha: 0.38),
                  ),
                ),
                // 有効なのは色覚を選んでいる間だけ（= 必ず適用中）。「未適用」の
                // 状態は表示され得ないので、有効ならいつでも「適用中」を出す。
                if (isEnabled)
                  Text(
                    l10n.intensityActive,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Slider(
              value: filterService.intensity,
              onChanged: isEnabled
                  ? (value) {
                      visionState.clearBypass();
                      filterService.setIntensity(value);
                    }
                  : null,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              label: '${strengthPercent(filterService.intensity)}%',
            ),
          ],
        );
      },
    );
  }
}
