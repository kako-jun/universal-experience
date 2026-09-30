import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/services.dart'
    show HardwareKeyboard, LogicalKeyboardKey;

import '../../l10n/app_localizations.dart';
import 'experimental_badge.dart';

/// 行の選び方の見た目（#120）。
enum FilterListTileKind {
  /// 体験プリセットの行。選ぶと単一選択に置き換わる。選択中は右端にチェック。
  preset,

  /// 足し引きできる行（チェック式）。先頭にチェックボックスの絵、選択中は右端に適用順の番号。
  check,

  /// 同時に 1 つしか選べない行（色覚グループ、ラジオ式）。先頭にラジオの絵、選択中は
  /// 右端に適用順の番号。
  radio,
}

/// 統合フィルタ一覧（`FilterBrowser`、#72）の 1 行。
///
/// 体験プリセット・色覚・advanced の全行が同じ見た目・同じ操作領域を持つように
/// する共通部品。
///
/// - 選択中は色（`secondaryContainer`）に加えて**形**でも示す（DESIGN §7: 色だけで状態を
///   区別しない）。[FilterListTileKind.preset] は右端のチェックマーク、
///   [FilterListTileKind.check]/[FilterListTileKind.radio] は先頭のチェックボックス/ラジオの
///   絵と右端の適用順の番号（[orderNumber]）。スクリーンリーダー向けには
///   [ListTile.selected] に加え、プリセットはチェックに「選択中」ラベル、チェック式/ラジオ式は
///   checked の状態と「適用順 N 番目」を付ける。
/// - [disabledReason] があるとその行は選べない（上限に達したとき）。理由を行の 2 行目に文字で出す。
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
    this.onPointerActivated,
    this.leading,
    this.isExperimental = false,
    this.kind = FilterListTileKind.preset,
    this.orderNumber,
    this.disabledReason,
    this.focusNode,
  });

  /// 行の表示名。
  final String title;

  /// 現在の選択に対応する行か。
  final bool selected;

  /// タップ・Enter・Space で呼ばれる。null なら選べない行になる。
  final VoidCallback? onTap;

  /// [onTap] のあと、**ポインタ（マウス・タッチ）で**選ばれたときだけ呼ばれる。
  /// Enter/Space（キーボード操作）の活性化では呼ばれない。画面が
  /// ショートカットの受け口へフォーカスを戻すのに使う（キーボード操作では
  /// フォーカスを行に残し、次の Tab が先頭からやり直しにならないようにする）。
  final VoidCallback? onPointerActivated;

  /// 先頭のアイコン（体験プリセットの行だけが使う）。
  final Widget? leading;

  /// 名前の横に「実験的」バッジを出すか（#80、
  /// `VisionFilterEntry.isExperimental`）。
  final bool isExperimental;

  /// 行の選び方の見た目。既定はプリセット（従来どおり）。
  final FilterListTileKind kind;

  /// 選択中の行の適用順の番号（1 始まり）。[kind] が check/radio のときだけ使う。
  final int? orderNumber;

  /// 非 null なら選べない行（[onTap] は無視）。値は理由の文言で、行の 2 行目に出す。
  final String? disabledReason;

  /// 行のフォーカス（↑↓ の行移動の行き先）。省略すると行が自前で持つ。
  final FocusNode? focusNode;

  @override
  State<FilterListTile> createState() => _FilterListTileState();
}

class _FilterListTileState extends State<FilterListTile> {
  @override
  void didUpdateWidget(FilterListTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && !oldWidget.selected) {
      // 「視差効果を減らす」等（disableAnimations）の値は、post-frame コールバックの
      // 中ではなくここで読む。didUpdateWidget での MediaQuery の参照は許されており
      // （initState だけが不可）、選択の変更と設定の変更が同じフレームでも最新の値になる（#45）。
      _revealAfterFrame(
        disableAnimations: MediaQuery.disableAnimationsOf(context),
      );
    }
  }

  void _revealAfterFrame({required bool disableAnimations}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scrollable = Scrollable.maybeOf(context);
      final renderObject = context.findRenderObject();
      if (scrollable == null || renderObject == null) return;
      // 最小限のスクロールで見える位置へ（すでに見えていれば動かない）。
      // 行がビューポートより上（↑・末尾→先頭の折り返し）なら上端に、下
      // （↓）なら下端に揃える。`keepVisibleAtEnd` だけだと上方向に効かない。
      final viewport = RenderAbstractViewport.maybeOf(renderObject);
      final position = scrollable.position;
      final isBeforeViewport = viewport != null &&
          viewport.getOffsetToReveal(renderObject, 0.0).offset <
              position.pixels;
      position.ensureVisible(
        renderObject,
        alignmentPolicy: isBeforeViewport
            ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
            : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        // OS の「視差効果を減らす」等（disableAnimations）ではスクロールを瞬時に（#45）。
        duration: disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  /// Enter/Space による活性化のあいだは、そのキーが押されている（InkWell は
  /// キー押下と同じ処理の中で onTap を呼ぶ）。それ以外はポインタ操作。
  bool get _activatedByKeyboard {
    final keyboard = HardwareKeyboard.instance;
    return keyboard.isLogicalKeyPressed(LogicalKeyboardKey.enter) ||
        keyboard.isLogicalKeyPressed(LogicalKeyboardKey.numpadEnter) ||
        keyboard.isLogicalKeyPressed(LogicalKeyboardKey.space);
  }

  /// 行へフォーカスが入ったら、一覧の内側のスクロールだけで画面内へ入れる（↑↓ の行移動・
  /// Tab）。
  void _handleFocusChange(bool focused) {
    if (!focused) return;
    _revealAfterFrame(
      disableAnimations: MediaQuery.disableAnimationsOf(context),
    );
  }

  void _handleTap() {
    final byKeyboard = _activatedByKeyboard;
    widget.onTap?.call();
    if (!byKeyboard) widget.onPointerActivated?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isPreset = widget.kind == FilterListTileKind.preset;
    final disabled = widget.disabledReason != null;
    final order = widget.orderNumber;

    Widget? leading = widget.leading;
    if (!isPreset) {
      final isRadio = widget.kind == FilterListTileKind.radio;
      final icon = isRadio
          ? (widget.selected
              ? Icons.radio_button_checked
              : Icons.radio_button_unchecked)
          : (widget.selected ? Icons.check_box : Icons.check_box_outline_blank);
      // 状態は行の Semantics（checked）が伝えるので、絵は読み上げから外す。
      leading = ExcludeSemantics(child: Icon(icon));
    }

    Widget? trailing;
    if (isPreset) {
      trailing = widget.selected
          ? Icon(Icons.check, semanticLabel: l10n.filterListSelectedSemantics)
          : null;
    } else if (widget.selected && order != null) {
      trailing = Semantics(
        label: l10n.filterListOrderSemantics(order),
        excludeSemantics: true,
        child: LayerOrderBadge(order: order),
      );
    }

    final tile = ListTile(
      focusNode: widget.focusNode,
      onFocusChange: _handleFocusChange,
      minTileHeight: 48,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      selected: widget.selected,
      selectedTileColor: scheme.secondaryContainer,
      selectedColor: scheme.onSecondaryContainer,
      enabled: !disabled,
      leading: leading,
      title: widget.isExperimental
          ? Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [Text(widget.title), const ExperimentalBadge()],
            )
          : Text(widget.title),
      titleTextStyle: theme.textTheme.bodyLarge?.copyWith(
        fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
      ),
      subtitle: disabled ? Text(widget.disabledReason!) : null,
      subtitleTextStyle: theme.textTheme.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      trailing: trailing,
      onTap: widget.onTap == null || disabled ? null : _handleTap,
    );
    if (isPreset) return tile;
    return MergeSemantics(
      child: Semantics(
        checked: widget.selected,
        inMutuallyExclusiveGroup: widget.kind == FilterListTileKind.radio,
        child: tile,
      ),
    );
  }
}

/// 「適用順」の番号の丸（形で状態を伝える、DESIGN §7）。一覧の選択中の行の右端・調整パネルの
/// 層の見出しで使う。
class LayerOrderBadge extends StatelessWidget {
  const LayerOrderBadge({super.key, required this.order});

  final int order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
      child: Text(
        '$order',
        style: theme.textTheme.labelLarge?.copyWith(color: scheme.onPrimary),
      ),
    );
  }
}
