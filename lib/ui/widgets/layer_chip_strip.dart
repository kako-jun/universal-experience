import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/settings_service.dart'
    show dismissWelcomeBannerOnUserChange;
import '../../services/vision_filter_state.dart';
import 'filter_list_tile.dart' show LayerOrderBadge;

/// プレビューの見出し行の下に並べる、重ねているフィルタのチップ帯（#120、#183）。
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
  const LayerChipStrip({super.key});

  /// チップの最小の高さ（最小タップ目標 48dp）。
  static const double chipHeight = 48;

  /// スクロールバーの太さ。チップの下に専用の段を取り、チップの枠と重ならないようにする。
  static const double scrollbarLane = 4;

  /// 文字拡大を考慮したチップの高さ（チップの本文 = bodyLarge の 1 行の高さ、最小 [chipHeight]）。
  /// 見出し行の最小の高さにも使い、層の種類・数で行の高さが動かないようにする。
  static double chipHeightFor(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge;
    final line = MediaQuery.textScalerOf(context).scale(style?.fontSize ?? 16) *
        (style?.height ?? 1.5);
    return line > chipHeight ? line : chipHeight;
  }

  /// 帯全体の高さ（チップ + スクロールバーの段）。層数に関わらず同じ値になる。
  static double heightFor(BuildContext context) =>
      chipHeightFor(context) + scrollbarLane;

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
      final target = pos.pixels.clamp(atEnd, atStart);
      final clamped = target.clamp(pos.minScrollExtent, pos.maxScrollExtent);
      if (clamped != pos.pixels) _controller.jumpTo(clamped);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer<VisionFilterState>(
      builder: (context, state, _) {
        final layers = state.layers;
        final height = LayerChipStrip.heightFor(context);
        _keys.removeWhere((id, _) => !layers.any((l) => l.id == id));
        // 層 0 個: 同じ高さの空き領域に淡い案内を出す（レイアウトがずれないように）。
        if (layers.isEmpty) {
          _lastFocusedId = null;
          final theme = Theme.of(context);
          return SizedBox(
            height: height,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                l10n.layerStripEmptyHint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // onSurfaceVariant は面の上で 4.5:1 以上を取る前提の色（テストで測る）。
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
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
                    child: Scrollbar(
                      controller: _controller,
                      thumbVisibility: true,
                      thickness: LayerChipStrip.scrollbarLane - 1,
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
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (layers.length >= 2) ...[
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
              ],
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
