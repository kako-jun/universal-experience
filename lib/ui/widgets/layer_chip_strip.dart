import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/settings_service.dart'
    show dismissWelcomeBannerOnUserChange;
import '../../services/vision_filter_state.dart';
import 'filter_list_tile.dart' show LayerOrderBadge;

/// プレビューカードの先頭に並べる、重ねているフィルタのチップ帯（#120、#183）。
///
/// 適用順（= 一覧の番号バッジ・調整パネルの層の並びと同じ）にチップを並べ、各チップに ✕ を
/// 付ける。チップを押すとそのフィルタが「調整中」になる（[VisionFilterState.focusLayer]。調整
/// パネルで展開される層・推奨サンプル #78 の追従先・←→ の対象と同じ `focusedId`）。✕ は
/// その 1 層だけを外す。2 層以上のときだけ、右端に「すべて解除」を固定で出す（1 層は ✕ と
/// 調整パネルの解除で足りるので 3 重にしない）。
///
/// 層が 0 個のときも同じ高さの領域を確保し、淡い案内文を出す。層数が変わっても下の
/// レイアウトがずれない（高さは [heightFor] で、層数に依らない）。高さを固定するため折り返さず
/// 1 行の横スクロールにする。スクロールは**帯の自前の ScrollController だけ**で動かす
/// （`Scrollable.ensureVisible` は祖先の縦ページスクロールまで動かすので使わない）。調整中に
/// なったチップは見える位置へ寄せる。マウスは常時表示のスクロールバー・Shift+ホイールで動かす
/// （ドラッグは許可しない: 数 px のぶれでチップのタップを奪うため）。
/// 状態は形で伝える: 調整中のチップは塗り + 太い枠、それ以外は細い枠（色だけに頼らない、DESIGN §7）。
class LayerChipStrip extends StatefulWidget {
  const LayerChipStrip({super.key, this.trailingBuilder, this.trailingLabel});

  /// 帯の右端に固定で置く操作（スクロールの外）。ホームでは「2×2 で比較」の切替を入れる
  /// （#183。プレビューの見出し行を廃止して帯へ移した）。`compact` が true のときは、
  /// 文字が大きい・幅が狭いので、文字を出さないアイコン + tooltip の小さい形にする
  /// （チップの領域を [minChipAreaWidth] 以上に保つため）。
  final Widget Function(BuildContext context, bool compact)? trailingBuilder;

  /// [trailingBuilder] が出す操作の文字つきの形のラベル。右端の固定枠が文字つきの形だと
  /// チップの領域が [minChipAreaWidth] を割るかどうかを、実際のフォント・文字倍率で測って
  /// （TextPainter）決めるために使う。
  final String? trailingLabel;

  /// 右端の固定枠を除いた、チップのスクロール領域の最小幅。これを割りそうなとき（大きい文字・
  /// 狭いカード）は、右端の操作（「すべて解除」「2×2 で比較」）を文字なしのアイコン + tooltip に縮める。
  static const double minChipAreaWidth = 140;

  /// チップの最小の高さ（最小タップ目標 48dp）。
  static const double chipHeight = 48;

  /// スクロールバーの段の高さ。チップの下に専用の段を取り、チップの枠と重ならないようにする。
  static const double scrollbarLane = 6;

  /// スクロールバーのつまみの太さ（段の中に収まる。上下 1dp ずつ余白）。
  static const double scrollbarThickness = 4;

  /// 文字拡大を考慮した帯の中身の高さ。チップの本文（bodyLarge の 1 行）と最小タップ目標
  /// [chipHeight] の大きい方。右端の「2×2 で比較」の `FilterChip` は、文字倍率が
  /// 文字つきの間（ラベルの 1 行 + 上下の余白と枠 18 ≦ 48 は、文字倍率が 1.2 未満で成り立つ）は
  /// [chipHeight] に収まり、文字倍率が大きいときはアイコンだけ（48dp のタップ領域）に縮むので、高さの項に入れなくてよい
  /// （layout テストが ×1.0・×1.19・×2.0 で帯に完全に収まることを確かめる）。
  /// 層の種類・数・色覚の層の有無で帯の高さが動かない。
  static double chipHeightFor(BuildContext context) {
    final body = Theme.of(context).textTheme.bodyLarge;
    final line = MediaQuery.textScalerOf(context).scale(body?.fontSize ?? 16) *
        (body?.height ?? 1.5);
    return line > chipHeight ? line : chipHeight;
  }

  /// 帯全体の高さ（チップ + スクロールバーの段）。層数に関わらず同じ値になる。
  static double heightFor(BuildContext context) =>
      chipHeightFor(context) + scrollbarLane;

  /// スクロールバーのつまみの色。カード面の上で非テキストの 3:1 以上を取る
  /// （`onSurfaceVariant`。テストで測る）。
  static Color thumbColorOf(ThemeData theme) =>
      theme.colorScheme.onSurfaceVariant;

  /// 0 層の案内文の色。カード面の上で 4.5:1 以上を取る（テストで測る）。
  static Color emptyHintColorOf(ThemeData theme) =>
      theme.colorScheme.onSurfaceVariant;

  @override
  State<LayerChipStrip> createState() => _LayerChipStripState();
}

class _LayerChipStripState extends State<LayerChipStrip> {
  final ScrollController _controller = ScrollController();
  final Map<String, GlobalKey> _keys = {};
  String? _lastFocusedId;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 調整中になったチップを、帯の横スクロールだけで見える位置へ寄せる（縦ページは動かさない）。
  void _reveal(String id) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final box = _keys[id]?.currentContext?.findRenderObject();
      if (box == null) return;
      final viewport = RenderAbstractViewport.maybeOf(box);
      if (viewport == null) return;
      final atStart = viewport.getOffsetToReveal(box, 0).offset;
      final atEnd = viewport.getOffsetToReveal(box, 1).offset;
      final pos = _controller.position;
      // チップが帯より広いときは、先頭（左端）を合わせる。
      final target =
          atEnd > atStart ? atStart : pos.pixels.clamp(atEnd, atStart);
      final clamped = target.clamp(pos.minScrollExtent, pos.maxScrollExtent);
      if (clamped != pos.pixels) _controller.jumpTo(clamped);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        return Consumer<VisionFilterState>(
          builder: (context, state, _) {
            final layers = state.layers;
            final height = LayerChipStrip.heightFor(context);
            final compact =
                _needsCompact(context, width, layers.length >= 2, l10n);
            _keys.removeWhere((id, _) => !layers.any((l) => l.id == id));
            // 層 0 個: 同じ高さの空き領域に淡い案内を出す（レイアウトがずれないように）。
            if (layers.isEmpty) {
              _lastFocusedId = null;
              final theme = Theme.of(context);
              return SizedBox(
                height: height,
                child: Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        // 見えない見出しの Semantics と混ざらないよう、自分のノードにする。
                        child: Semantics(
                          container: true,
                          child: Text(
                            l10n.layerStripEmptyHint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: LayerChipStrip.emptyHintColorOf(theme)),
                          ),
                        ),
                      ),
                    ),
                    if (widget.trailingBuilder != null) ...[
                      const SizedBox(width: 8),
                      widget.trailingBuilder!(context, compact),
                    ],
                  ],
                ),
              );
            }
            final focusedId = state.focusedId;
            if (focusedId != _lastFocusedId) {
              _lastFocusedId = focusedId;
              if (focusedId != null) _reveal(focusedId);
            }
            return Semantics(
              container: true,
              label: l10n.layerStripSemantics,
              child: SizedBox(
                height: height,
                child: Row(
                  children: [
                    Expanded(
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context)
                            .copyWith(scrollbars: false),
                        child: ScrollbarTheme(
                          data: ScrollbarThemeData(
                            thumbColor: WidgetStatePropertyAll(
                                LayerChipStrip.thumbColorOf(Theme.of(context))),
                            radius: const Radius.circular(2),
                            crossAxisMargin: 1,
                          ),
                          child: Scrollbar(
                            controller: _controller,
                            thumbVisibility: true,
                            thickness: LayerChipStrip.scrollbarThickness,
                            child: SingleChildScrollView(
                              controller: _controller,
                              scrollDirection: Axis.horizontal,
                              // チップの下にスクロールバーの段を空ける（枠と重ならない）。
                              padding: const EdgeInsets.only(
                                  bottom: LayerChipStrip.scrollbarLane),
                              child: Row(
                                children: [
                                  for (var i = 0; i < layers.length; i++) ...[
                                    if (i > 0) const SizedBox(width: 8),
                                    // 名前が長くても 1 チップが帯を占有しないよう、幅に上限を置く。
                                    ConstrainedBox(
                                      key: _keys.putIfAbsent(
                                          layers[i].id, () => GlobalKey()),
                                      constraints:
                                          const BoxConstraints(maxWidth: 280),
                                      child: _LayerChip(
                                        key: ValueKey(
                                            'layer_chip_${layers[i].id}'),
                                        id: layers[i].id,
                                        order: i + 1,
                                        name: visionLayerDisplayName(
                                            l10n, layers[i]),
                                        focused:
                                            layers[i].id == state.focusedId,
                                        onFocus: () =>
                                            state.focusLayer(layers[i].id),
                                        onRemove: () {
                                          state.remove(layers[i].id);
                                          dismissWelcomeBannerOnUserChange(
                                              context);
                                        },
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (layers.length >= 2) ...[
                      const SizedBox(width: 8),
                      if (compact)
                        IconButton(
                          key: const ValueKey('layer_strip_clear_all'),
                          tooltip: l10n.layerStripClearAll,
                          onPressed: () {
                            state.clear();
                            dismissWelcomeBannerOnUserChange(context);
                          },
                          icon: const Icon(Icons.clear),
                        )
                      else
                        TextButton.icon(
                          key: const ValueKey('layer_strip_clear_all'),
                          onPressed: () {
                            state.clear();
                            dismissWelcomeBannerOnUserChange(context);
                          },
                          icon: const Icon(Icons.clear, size: 18),
                          label: Text(l10n.layerStripClearAll),
                        ),
                    ],
                    if (widget.trailingBuilder != null) ...[
                      const SizedBox(width: 8),
                      widget.trailingBuilder!(context, compact),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 右端の固定枠を文字つきの形で置くと、チップの領域が [LayerChipStrip.minChipAreaWidth] を
  /// 割るか。実際のフォント・文字倍率で、「すべて解除」（2 層以上）と [LayerChipStrip.trailingLabel] の
  /// 文字つきの形の幅を測る。
  bool _needsCompact(BuildContext context, double width, bool hasClearAll,
      AppLocalizations l10n) {
    if (widget.trailingBuilder == null && !hasClearAll) return false;
    final style = Theme.of(context).textTheme.labelLarge;
    final scaler = MediaQuery.textScalerOf(context);
    double textWidth(String t) {
      final p = TextPainter(
        text: TextSpan(text: t, style: style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      return p.width;
    }

    // 「すべて解除」の TextButton.icon: 左右の余白 12 × 2 + アイコン 18 + 間隔 8 + 文字。
    final clearAll =
        hasClearAll ? 24 + 18 + 8 + textWidth(l10n.layerStripClearAll) : 0.0;
    // FilterChip: 左右の余白 8 × 2 + 選択時のチェック 18 + 間隔 8 + 文字。
    final label = widget.trailingLabel;
    final trailing = label == null ? 0.0 : 16 + 18 + 8 + textWidth(label);
    final gaps = (hasClearAll ? 8 : 0) + (label == null ? 0 : 8);
    return width - clearAll - trailing - gaps < LayerChipStrip.minChipAreaWidth;
  }
}

class _LayerChip extends StatelessWidget {
  const _LayerChip({
    super.key,
    required this.id,
    required this.order,
    required this.name,
    required this.focused,
    required this.onFocus,
    required this.onRemove,
  });

  final String id;
  final int order;
  final String name;
  final bool focused;
  final VoidCallback onFocus;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: focused ? scheme.secondaryContainer : scheme.surface,
      shape: StadiumBorder(
        side: BorderSide(
          color: focused ? scheme.primary : scheme.outline,
          width: focused ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Semantics(
              button: true,
              selected: focused,
              label: l10n.layerChipLabel(order, name),
              hint: focused ? null : l10n.layerChipFocusHint,
              excludeSemantics: true,
              onTap: onFocus,
              child: InkWell(
                onTap: onFocus,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8, right: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LayerOrderBadge(order: order),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight:
                                  focused ? FontWeight.w600 : FontWeight.w400,
                              color: focused
                                  ? scheme.onSecondaryContainer
                                  : scheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            key: ValueKey('layer_chip_remove_$id'),
            tooltip: l10n.layerChipRemove(name),
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}
