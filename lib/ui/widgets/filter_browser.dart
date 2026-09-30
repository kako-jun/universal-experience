import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/vision_filter_catalog.dart';
import '../../services/filter_list_selection.dart';
import '../../services/filter_service.dart';
import '../../services/vision_filter_state.dart';
import 'experience_presets.dart';
import '../../src/rust/api/sensus_bridge.dart' show Experience;
import 'filter_list_tile.dart';

/// 統合フィルタ一覧（[FilterBrowser]）の検索語・カテゴリ・検索欄フォーカスを
/// 持つコントローラ（#72）。
///
/// 画面（`HomeScreen`）が保持する。理由は 2 つ: `/` で検索欄へフォーカスを
/// 移す（[focusSearch]）のと、↑↓ で「今見えている行」を順送りする
/// （[visibleEntries]）のを、ウィジェットの外のショートカットから行うため。
/// **選択の正本は `VisionFilterState` のまま**で、ここは絞り込みの状態だけを持つ。
class FilterBrowserController extends ChangeNotifier {
  FilterBrowserController() {
    search.addListener(notifyListeners);
  }

  /// 検索欄の入力。
  final TextEditingController search = TextEditingController();

  /// 検索欄の [FocusNode]（`/` の行き先）。
  final FocusNode searchFocus = FocusNode(debugLabel: 'filterSearch');

  VisionFilterCategory? _category;

  /// 選択中のカテゴリ。null は「すべて」。
  VisionFilterCategory? get category => _category;

  /// カテゴリを切り替える。検索語は空に戻す（検索語があるあいだはカテゴリを
  /// 無視して全体から探すため、切り替えた結果が見えなくなるのを避ける）。
  void setCategory(VisionFilterCategory? category) {
    search.clear();
    if (_category == category) return;
    _category = category;
    notifyListeners();
  }

  /// 検索語が空か。
  bool get isSearching => !isBlankFilterQuery(search.text);

  /// 今見えている（検索語とカテゴリで絞った）フィルタの行。
  List<FilterListEntry> get visibleEntries =>
      visibleFilterListEntries(query: search.text, category: _category);

  /// 検索欄へフォーカスを移し、入力済みの文字を全選択する（`/` から）。
  void focusSearch() {
    searchFocus.requestFocus();
    search.selection =
        TextSelection(baseOffset: 0, extentOffset: search.text.length);
  }

  @override
  void dispose() {
    search.removeListener(notifyListeners);
    search.dispose();
    searchFocus.dispose();
    super.dispose();
  }
}

/// 一覧の行 [entry] を一意に指す [Key]（テストと ↑↓ 追従の確認用）。
Key filterListTileKey(FilterListEntry entry) =>
    ValueKey('filter_tile_${entry.key}');

/// 左カラム「選ぶ」（#72）: インクリメンタル検索・カテゴリ切替・統合フィルタ一覧。
///
/// 色覚 7 型と advanced 30 フィルタを 1 つの一覧にまとめる（内部の状態は
/// `VisionFilterState` が唯一の正本のまま）。書き込みの入口は既存のまま:
/// 色覚の行は `selectColorVision`、それ以外は `VisionFilterState.select`
/// （[applyFilterListEntry]）。体験プリセットは一覧の最上段に置く。
///
/// - 検索は日本語名・英語名のどちらでも当たる。検索語があるあいだは
///   カテゴリを無視して全体から探す。
/// - カテゴリは「すべて」+ 7 カテゴリの `ChoiceChip`（選択中は色とチェックで示す）。
///   一覧のスクロール領域の先頭に置く（見出しと検索欄だけが固定）。
/// - 呼び出し側は**高さの制約が有限**の場所に置く（一覧は内側でスクロールする）。
class FilterBrowser extends StatelessWidget {
  const FilterBrowser({
    super.key,
    required this.controller,
    this.onActivated,
  });

  final FilterBrowserController controller;

  /// 行を**ポインタで**選んだ直後に呼ばれる。行にフォーカスが残るとその上の
  /// キー操作（`←→` など）が効かなくなるため、画面がショートカットの受け口へ
  /// フォーカスを戻すのに使う。Enter/Space での選択では呼ばれない（フォーカスを
  /// 行に残し、次の Tab が先頭からやり直しにならないようにする。行の上では
  /// ↑↓ は標準のフォーカス移動になる）。
  final VoidCallback? onActivated;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child:
              Text(l10n.filterListHeading, style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: 12),
        _SearchField(controller: controller),
        const SizedBox(height: 8),
        // カテゴリのチップは一覧のスクロール領域の先頭に入れる（固定にすると、
        // 低い画面でチップの Wrap が高さを食い潰して一覧が潰れる）。
        Expanded(
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => _FilterList(
              controller: controller,
              onActivated: onActivated,
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});

  final FilterBrowserController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: controller.search,
      builder: (context, _) => TextField(
        controller: controller.search,
        focusNode: controller.searchFocus,
        decoration: InputDecoration(
          labelText: l10n.filterSearchLabel,
          hintText: l10n.filterSearchHint,
          hintMaxLines: 1,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: controller.search.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: l10n.filterSearchClearTooltip,
                  onPressed: controller.search.clear,
                ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.controller});

  final FilterBrowserController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      container: true,
      label: l10n.filterCategoryLabel,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final current = controller.category;
          return Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: Text(l10n.filterCategoryAll),
                selected: current == null,
                showCheckmark: true,
                onSelected: (_) => controller.setCategory(null),
              ),
              for (final category in VisionFilterCategory.values)
                ChoiceChip(
                  label: Text(visionCategoryName(l10n, category)),
                  selected: current == category,
                  showCheckmark: true,
                  onSelected: (_) => controller.setCategory(category),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _FilterList extends StatelessWidget {
  const _FilterList({required this.controller, required this.onActivated});

  final FilterBrowserController controller;
  final VoidCallback? onActivated;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final query = controller.search.text;
    final showPresets = controller.isSearching || controller.category == null;
    final presets = showPresets
        ? [
            for (final exp in availableExperiences())
              if (experienceMatchesQuery(exp.id, query)) exp,
          ]
        : const <Experience>[];
    final entries = controller.visibleEntries;
    // 検索語もカテゴリ指定も無いときだけ、カテゴリごとの小見出しを挟む。
    final showGroupHeaders =
        !controller.isSearching && controller.category == null;

    Widget heading(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Semantics(
            header: true,
            child: Text(
              text,
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        );

    final children = <Widget>[
      _CategoryChips(controller: controller),
      const SizedBox(height: 8),
      if (presets.isNotEmpty) ...[
        heading(l10n.experienceSectionTitle),
        for (final exp in presets)
          ExperiencePresetTile(experience: exp, onActivated: onActivated),
      ],
      if (entries.isEmpty && presets.isEmpty)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            l10n.filterListNoResults,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      Consumer2<FilterService, VisionFilterState>(
        builder: (context, filterService, visionState, _) {
          final selected = selectedFilterListEntry(visionState);
          final rows = <Widget>[];
          VisionFilterCategory? previous;
          for (final entry in entries) {
            if (showGroupHeaders && entry.category != previous) {
              rows.add(heading(visionCategoryName(l10n, entry.category)));
            }
            previous = entry.category;
            rows.add(FilterListTile(
              key: filterListTileKey(entry),
              title: filterListEntryName(l10n, entry),
              selected: entry == selected,
              onTap: () =>
                  applyFilterListEntry(filterService, visionState, entry),
              onPointerActivated: onActivated,
              isExperimental:
                  kVisionFilterCatalogById[entry.catalogId]?.isExperimental ??
                      false,
            ));
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,
          );
        },
      ),
    ];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
