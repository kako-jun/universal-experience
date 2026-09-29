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
class FilterSelector extends StatefulWidget {
  const FilterSelector({super.key});

  @override
  State<FilterSelector> createState() => FilterSelectorState();
}

/// [FilterSelector.createState] の状態。`GlobalKey<FilterSelectorState>`
/// 経由で外部（`home_screen.dart`、ウェルカムバナーの「ほかの見え方を選ぶ」）
/// から [focusSelectedChip] を呼べるよう public にしてある（#78 レビュー
/// nit: フォーカス移動を目に見えるようにする）。
class FilterSelectorState extends State<FilterSelector> {
  /// 色覚型ごとの FocusNode（チップ 1 枚ずつに固有）。`ColorVisionType.values`
  /// は固定リストなので、State の生存期間中は同じインスタンスを使い回す。
  final Map<ColorVisionType, FocusNode> _chipFocusNodes = {
    for (final type in ColorVisionType.values)
      type: FocusNode(debugLabel: 'colorVisionChip_${type.name}'),
  };

  @override
  void dispose() {
    for (final node in _chipFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// 現在点灯しているチップの [ColorVisionType]。advanced/プリセット選択中
  /// （どのチップも点灯していない）は null。build() の `isSelected` 判定と
  /// 同じロジック（#60）。
  ColorVisionType? _currentlySelectedType(
    FilterService filterService,
    VisionFilterState visionState,
  ) {
    if (visionState.selectedId == null) return ColorVisionType.none;
    if (visionState.isColorQuickSelection) return filterService.currentFilter;
    return null;
  }

  /// 選択中のチップ（無ければ先頭のチップ）へ実際にフォーカスを移し、
  /// スクロールして画面内に入るようにする（#78 レビュー nit）。
  ///
  /// `FocusNode.requestFocus()` だけでは、コンテナ全体に付けた単一の
  /// FocusNode にフォーカスが移っても見た目には何も起きない
  /// （個々の `FilterChip` が視覚的なフォーカスリングを持たないため）。
  /// チップ 1 枚ずつに [FocusNode] を持たせ、実際にそのチップへフォーカスを
  /// 移すことで、Material のフォーカスインジケータが表示される。
  void focusSelectedChip() {
    final filterService = context.read<FilterService>();
    final visionState = context.read<VisionFilterState>();
    final selected = _currentlySelectedType(filterService, visionState);
    final target = (selected != null ? _chipFocusNodes[selected] : null) ??
        _chipFocusNodes[ColorVisionType.values.first]!;
    target.requestFocus();
    final chipContext = target.context;
    if (chipContext != null) {
      Scrollable.ensureVisible(
        chipContext,
        duration: const Duration(milliseconds: 200),
        alignment: 0.5,
      );
    }
  }

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
                  focusNode: _chipFocusNodes[type],
                  label: Text(colorVisionTypeName(l10n, type)),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      selectColorVision(filterService, visionState, type);
                    }
                  },
                  labelStyle: TextStyle(
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
