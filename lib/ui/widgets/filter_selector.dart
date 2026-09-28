import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/disability_type.dart';
import '../../services/color_vision_selection.dart';
import '../../services/filter_service.dart';
import '../../services/vision_filter_state.dart';

/// 色覚のクイック選択チップ（#60 M1）。
///
/// チップの点灯・強度スライダーの有効/無効（[IntensitySlider]）・解除ボタンの
/// 3 つはすべて `VisionFilterState.isColorQuickSelection` から導く（advanced
/// カタログ・体験プリセットを見ている間は、色覚のクイック選択の状態が
/// `FilterService` に残っていても、ここでは何も点灯させない）。選択・解除は
/// どちらも `lib/services/color_vision_selection.dart` の
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
                final isSelected = isColorQuickSelection &&
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
