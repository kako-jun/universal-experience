import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/disability_type.dart';
import '../../services/color_vision_selection.dart';
import '../../services/filter_service.dart';
import '../../services/vision_filter_state.dart';

/// 色覚のクイック選択チップ（#60）。
///
/// 強度スライダーの有効/無効（[IntensitySlider]）・解除ボタンは
/// `VisionFilterState.isColorQuickSelection` から導く（advanced カタログ・
/// 体験プリセットを見ている間は、色覚のクイック選択の状態が `FilterService`
/// に残っていても、ここでは何も有効化しない）。色覚型のチップの点灯も
/// 同様だが、「Normal vision」（[ColorVisionType.none]）チップだけは
/// `VisionFilterState.selectedId == null`（＝何も選択されていない）で
/// 判定する — `isColorQuickSelection` は none を「選択中」扱いにしないため
/// （[VisionFilterState.selectColorVisionType] 参照）。
///
/// **意図した挙動**: advanced/プリセットを選択中に「Normal vision」を押すと、
/// 色覚の選択だけでなく advanced/プリセットの選択もすべて消える
/// （`VisionFilterState.selectColorVisionType` は none 以外への手動選択と
/// 同様、既存の選択を常に上書きするため）。「Normal vision」は色覚セクション
/// 内の一操作ではなく、プレビュー全体を原画に戻す操作として扱う。
///
/// 選択・解除はどちらも `lib/services/color_vision_selection.dart` の
/// `selectColorVision`/`deactivateColorVision` を経由し、`FilterService` と
/// `VisionFilterState` の両方を明示的に更新する。
class FilterSelector extends StatelessWidget {
  const FilterSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer2<FilterService, VisionFilterState>(
      builder: (context, filterService, visionState, _) {
        final isColorQuickSelection = visionState.isColorQuickSelection;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: ColorVisionType.values.map((type) {
                // "Normal vision" は「何も選択されていない」ことそのものを
                // 表すチップなので、isColorQuickSelection ではなく
                // selectedId で判定する（#60）。
                final isSelected = type == ColorVisionType.none
                    ? visionState.selectedId == null
                    : isColorQuickSelection &&
                        filterService.currentFilter == type;

                return FilterChip(
                  label: Text(colorVisionTypeName(l10n, type)),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      selectColorVision(filterService, visionState, type);
                    }
                  },
                  selectedColor: Colors.indigo.shade100,
                  checkmarkColor: Colors.indigo.shade700,
                  labelStyle: TextStyle(
                    color: isSelected
                        ? Colors.indigo.shade900
                        : Colors.grey.shade700,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: isColorQuickSelection
                      ? () =>
                          deactivateColorVision(filterService, visionState)
                      : null,
                  icon: const Icon(Icons.clear),
                  label: Text(l10n.clearFilter),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
