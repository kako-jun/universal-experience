import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/settings_service.dart'
    show dismissWelcomeBannerOnUserChange;
import '../../services/vision_filter_state.dart';
import 'filter_list_tile.dart' show LayerOrderBadge;

/// プレビューの上に並べる、重ねているフィルタのチップ帯（#120）。
///
/// 適用順（= 一覧の番号バッジ・調整パネルの層の並びと同じ）にチップを並べ、各チップに ✕ を
/// 付ける。チップを押すとそのフィルタが「調整中」になる（[VisionFilterState.focusLayer]。調整
/// パネルで展開される層・推奨サンプル #78 の追従先・←→ の対象と同じ `focusedId`）。✕ は
/// その 1 層だけを外し、末尾の「すべて解除」は全部を外す。
///
/// 層が 1 つ以上のときにチップと「すべて解除」を出す（1 つ目から ✕ で外せる）。層が 0 個のときも
/// 同じ高さの空き領域を確保し、層数が変わっても下のレイアウトがずれない（高さは [stripHeight]
/// で固定）。高さを固定するため折り返さず 1 行の横スクロールにする（フォーカスが移ると
/// 自動でスクロールして見える位置に来る。マウスはドラッグ・スクロールバーで動かせる）。
/// 状態は形で伝える: 調整中のチップは塗り + 太い枠、それ以外は細い枠（色だけに頼らない、DESIGN §7）。
class LayerChipStrip extends StatefulWidget {
  const LayerChipStrip({super.key});

  /// 帯の高さ（チップの最小タップ目標 48dp に等しい）。文字拡大時は [heightFor] で伸びるが、
  /// 層数には依存しない。
  static const double stripHeight = 48;

  /// 文字サイズ拡大を考慮した帯の高さ。層数に関わらず同じ値になる。
  static double heightFor(BuildContext context) {
    final scaled = MediaQuery.textScalerOf(context).scale(16) * 1.5 + 8;
    return scaled > stripHeight ? scaled : stripHeight;
  }

  @override
  State<LayerChipStrip> createState() => _LayerChipStripState();
}

class _LayerChipStripState extends State<LayerChipStrip> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer<VisionFilterState>(
      builder: (context, state, _) {
        final layers = state.layers;
        final height = LayerChipStrip.heightFor(context);
        // 層 0 個: 同じ高さの空き領域（レイアウトがずれないように）。
        if (layers.isEmpty) return SizedBox(height: height);
        return Semantics(
          container: true,
          label: l10n.layerStripSemantics,
          child: SizedBox(
            height: height,
            child: Scrollbar(
              controller: _controller,
              child: SingleChildScrollView(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < layers.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      // 名前が長くても 1 チップが帯を占有しないよう、幅に上限を置く（超過は省略）。
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 280),
                        child: _LayerChip(
                          key: ValueKey('layer_chip_${layers[i].id}'),
                          id: layers[i].id,
                          order: i + 1,
                          name: visionLayerDisplayName(l10n, layers[i]),
                          focused: layers[i].id == state.focusedId,
                          onFocus: () => state.focusLayer(layers[i].id),
                          onRemove: () {
                            state.remove(layers[i].id);
                            dismissWelcomeBannerOnUserChange(context);
                          },
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
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
                ),
              ),
            ),
          ),
        );
      },
    );
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
