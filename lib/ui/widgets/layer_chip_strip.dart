import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/color_vision_selection.dart';
import '../../services/filter_service.dart';
import '../../services/vision_filter_state.dart';
import 'filter_list_tile.dart' show LayerOrderBadge;

/// プレビューの上に並べる、重ねているフィルタのチップ帯（#120）。
///
/// 適用順（= 一覧の番号バッジ・調整パネルの層の並びと同じ）にチップを並べ、各チップに ✕ を
/// 付ける。チップを押すとそのフィルタが「調整中」になる（[VisionFilterState.focusLayer]。調整
/// パネルで展開される層・推奨サンプル #78 の追従先・←→ の対象と同じ `focusedId`）。✕ は
/// その 1 層だけを外し、末尾の「すべて解除」は全部を外す。
///
/// 層が 2 つ以上のときだけ出す（1 つだけのときは従来どおり、調整パネルの「フィルタを解除」が
/// 入口で、見た目を変えない）。状態は形で伝える: 調整中のチップは塗り + 太い枠、それ以外は細い枠
/// （色だけに頼らない、DESIGN §7）。
class LayerChipStrip extends StatelessWidget {
  const LayerChipStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer2<VisionFilterState, FilterService>(
      builder: (context, state, filterService, _) {
        final layers = state.layers;
        if (layers.length < 2) return const SizedBox.shrink();
        return Semantics(
          container: true,
          label: l10n.layerStripSemantics,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = 0; i < layers.length; i++)
                _LayerChip(
                  key: ValueKey('layer_chip_${layers[i].id}'),
                  id: layers[i].id,
                  order: i + 1,
                  name: visionLayerDisplayName(l10n, layers[i]),
                  focused: layers[i].id == state.focusedId,
                  onFocus: () => state.focusLayer(layers[i].id),
                  onRemove: () {
                    state.remove(layers[i].id);
                    syncFilterServiceWithLayers(filterService, state);
                  },
                ),
              TextButton.icon(
                key: const ValueKey('layer_strip_clear_all'),
                onPressed: () => deactivateColorVision(filterService, state),
                icon: const Icon(Icons.clear, size: 18),
                label: Text(l10n.layerStripClearAll),
              ),
            ],
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
