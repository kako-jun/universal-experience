import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/vision_filter_catalog.dart';
import '../../services/vision_filter_state.dart';

/// sensus 全 30 [VisionFilter] をカテゴリ別にグルーピングして選択させるセレクタ。
///
/// カテゴリ見出し + [Wrap] の [FilterChip] で表示する。選択は
/// [VisionFilterState.select] に反映する。色覚 7 種のクイック選択
/// （`FilterSelector`/トレイ）も同じ [VisionFilterState] に書き込むため
/// （`lib/services/color_vision_selection.dart`、#60）、色覚のカタログ 5 種
/// （protanopia 等）はここと重なるが、色覚クイック選択で選んだときはここの
/// チップを点灯させない（[state.isColorQuickSelection] が true の間は
/// [_buildCategory] の `isSelected` が常に false になる、#60）。「advanced
/// で選んだのか、色覚クイック選択で選んだのか」を UI 上でも区別するため。
class FilterCatalogSelector extends StatelessWidget {
  const FilterCatalogSelector({super.key, this.focusNode});

  /// `/`（アプリ内ショートカット、#63）でこのカタログへフォーカスを移すための
  /// 外部注入 FocusNode。未指定なら通常の（フォーカス移動対象にならない）
  /// ウィジェットとして振る舞う。
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer<VisionFilterState>(
      builder: (context, state, _) {
        return Focus(
          focusNode: focusNode,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final category in VisionFilterCategory.values)
                _buildCategory(l10n, state, category),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed:
                        state.selectedId != null ? () => state.clear() : null,
                    icon: const Icon(Icons.clear),
                    label: Text(l10n.clear),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCategory(
    AppLocalizations l10n,
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
            visionCategoryName(l10n, category),
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
              // 色覚クイック選択由来の選択では、対応する advanced チップ
              // （例: protanopia）を点灯させない（#60）。
              final isSelected =
                  state.selectedId == entry.id && !state.isColorQuickSelection;
              return FilterChip(
                label: Text(visionFilterName(l10n, entry.id)),
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
