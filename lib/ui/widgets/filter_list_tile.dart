import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// 統合フィルタ一覧（`FilterBrowser`、#72）の 1 行。
///
/// 体験プリセット・色覚・advanced の全行が同じ見た目・同じ操作領域を持つように
/// する共通部品。
///
/// - 選択中は色（`secondaryContainer`）に加えて**チェックマーク**でも示す
///   （DESIGN §7: 色だけで状態を区別しない）。スクリーンリーダー向けには
///   [ListTile.selected] の Semantics に加え、チェックに「選択中」ラベルを付ける。
/// - 行の高さは 48dp 以上（#45 の最小タップ領域）、角丸は 8（DESIGN §4.2）。
/// - 選択が変わって（キーボードの ↑↓ など）この行が選択中になったとき、
///   **一覧の内側のスクロール**だけを動かして画面内へ入れる。外側のページ
///   スクロールは動かさない（狭幅でプレビューが押し出されないため。
///   `Scrollable.ensureVisible` は使わない）。起動直後・再描画で最初から
///   選択中の行は動かさない（一覧の最上段の体験プリセットを隠さないため）。
class FilterListTile extends StatefulWidget {
  const FilterListTile({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.leading,
  });

  /// 行の表示名。
  final String title;

  /// 現在の選択に対応する行か。
  final bool selected;

  /// タップ・Enter・Space で呼ばれる。null なら選べない行になる。
  final VoidCallback? onTap;

  /// 先頭のアイコン（体験プリセットの行だけが使う）。
  final Widget? leading;

  @override
  State<FilterListTile> createState() => _FilterListTileState();
}

class _FilterListTileState extends State<FilterListTile> {
  @override
  void didUpdateWidget(FilterListTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && !oldWidget.selected) {
      _revealAfterFrame();
    }
  }

  void _revealAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scrollable = Scrollable.maybeOf(context);
      final renderObject = context.findRenderObject();
      if (scrollable == null || renderObject == null) return;
      // 最小限のスクロールで見える位置へ（すでに見えていれば動かない）。
      scrollable.position.ensureVisible(
        renderObject,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListTile(
      minTileHeight: 48,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      selected: widget.selected,
      selectedTileColor: scheme.secondaryContainer,
      selectedColor: scheme.onSecondaryContainer,
      leading: widget.leading,
      title: Text(widget.title),
      titleTextStyle: theme.textTheme.bodyLarge?.copyWith(
        fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
      ),
      trailing: widget.selected
          ? Icon(Icons.check, semanticLabel: l10n.filterListSelectedSemantics)
          : null,
      onTap: widget.onTap,
    );
  }
}
