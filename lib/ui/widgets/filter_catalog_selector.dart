import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/vision_filter_catalog.dart';
import '../../services/vision_filter_state.dart';

/// sensus 全 30 [VisionFilter] をカテゴリ別にグルーピングして選択させるセレクタ。
///
/// カテゴリ見出し + [Wrap] の [FilterChip] で表示する。選択は
/// [VisionFilterState] に反映する（既存の色覚 7 種 UI とは別系統）。
class FilterCatalogSelector extends StatelessWidget {
  const FilterCatalogSelector({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<VisionFilterState>(
      builder: (context, state, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final category in VisionFilterCategory.values)
              _buildCategory(context, state, category),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed:
                      state.selectedId != null ? () => state.clear() : null,
                  icon: const Icon(Icons.clear),
                  label: const Text('Clear'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildCategory(
    BuildContext context,
    VisionFilterState state,
    VisionFilterCategory category,
  ) {
    final entries = visionFilterEntriesByCategory(category);
    if (entries.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            category.displayName,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: entries.map((entry) {
              final isSelected = state.selectedId == entry.id;
              return FilterChip(
                label: Text(entry.displayName),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    state.select(entry.id);
                  } else if (isSelected) {
                    state.clear();
                  }
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
