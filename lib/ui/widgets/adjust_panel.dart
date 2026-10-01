import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/vision_filter_contract_notes.dart';
import '../../services/layer_consult_notice.dart';
import '../../services/settings_service.dart'
    show dismissWelcomeBannerOnUserChange;
import '../../services/vision_filter_state.dart';
import '../../services/vision_layer.dart';
import 'consult_notice_block.dart';
import 'experience_presets.dart';
import 'experimental_badge.dart';
import 'filter_list_tile.dart' show LayerOrderBadge;
import 'filter_param_panel.dart';
import 'filter_provenance.dart';
import 'strength_caution.dart';

/// 右カラム「調整」（#72）: 選んだ見え方の説明・強度・受診喚起・パラメータ。
///
/// 並びは上から **見出し（+ 解除）→ 選んだ症状の名前と説明 → 強度 → 受診喚起 →
/// パラメータ → モデルと出典・表現できないこと（#80、折りたたみ）**。受診喚起は強度のすぐ下に常時展開で出す（動かさない・隠さない、
/// DESIGN §6.2）。
///
/// - 1 層のとき: 従来と同じ 1 つの節（強度スライダーは [FilterParamPanel] の 1 本だけ。色覚の行も
///   advanced の行・体験プリセットも同じ、#120）。プリセットのときは体験としての緊急度
///   （[experienceConsultNotice]）を優先する。
/// - 複数層のとき（#120）: **層ごとの節**を適用順に並べる。調整中（`focusedId`）の層だけが
///   展開され（名前・説明・強度・受診喚起・パラメータ・出典）、ほかの層は 1 行（番号・名前・強さ）に
///   たたまれる。たたんだ行を押すとその層が調整中になる。受診喚起は**各層の節ごとに**その層
///   単体の入力で出す（複数層の合成 `mergeConsultInputs` は 1 枚の画像になる PNG 書き出しだけが使う、#121）。
///   強度上限付近の注意（#66）もその層の節に出る。
/// - 何も選んでいないとき: 空のカードを出さず、「何も選択されていません」と
///   次の一手だけを出す。
///
/// 列の面（`Card`）と高さの制約は呼び出し側（`HomeScreen`）が持つ。節どうしは区切り線で
/// 分け、カードは入れ子にしない（DESIGN §6.2）。
class AdjustPanel extends StatelessWidget {
  const AdjustPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Consumer<VisionFilterState>(
      builder: (context, state, _) {
        final hasSelection = state.selectedId != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      l10n.adjustHeading,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
                TextButton.icon(
                  // 色覚・advanced・プリセットのどの選択でも、選択を丸ごと
                  // 外す唯一の入口（`VisionFilterState.clear`）。
                  onPressed: hasSelection
                      ? () {
                          state.clear();
                          dismissWelcomeBannerOnUserChange(context);
                        }
                      : null,
                  icon: const Icon(Icons.clear, size: 18),
                  label: Text(l10n.clearFilter),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (hasSelection)
              _SelectedContent(state: state)
            else
              const _EmptyState(),
          ],
        );
      },
    );
  }
}

/// 何も選ばれていないときの案内（空のカードを残さない、DESIGN §6.2）。
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          ExcludeSemantics(
            child: Icon(
              Icons.touch_app_outlined,
              size: 32,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Semantics(
            header: true,
            child: Text(
              l10n.selectionEmptyTitle,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.selectionEmptyBody,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// 選択がある間の中身。1 層なら 1 つの節だけ（従来どおり）、複数層なら層ごとの節を並べる。
class _SelectedContent extends StatelessWidget {
  const _SelectedContent({required this.state});

  final VisionFilterState state;

  @override
  Widget build(BuildContext context) {
    final layers = state.layers;
    if (layers.length <= 1) {
      return _FocusedSection(state: state);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < layers.length; i++) ...[
          if (i > 0) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
          ],
          if (layers[i].id == state.focusedId)
            _FocusedSection(state: state, order: i + 1)
          else
            _CollapsedSection(state: state, layer: layers[i], order: i + 1),
        ],
      ],
    );
  }
}

/// たたまれた層の節（#120）: 1 行（番号・名前・強さ）と、その層の受診喚起。押すとその層が調整中になる。
class _CollapsedSection extends StatelessWidget {
  const _CollapsedSection({
    required this.state,
    required this.layer,
    required this.order,
  });

  final VisionFilterState state;
  final VisionLayer layer;
  final int order;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;
    final name = visionLayerDisplayName(l10n, layer);
    final strength = state.strengthOf(layer);
    final percent = strengthPercent(strength);
    final notice = layerConsultNotice(l10n, state, layer);
    final caution = kStrengthCautionByFilterId[layer.id];
    final nearLimit = caution != null &&
        StrengthCautionNote(caution: caution, strength: strength).isNearLimit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          label: l10n.layerSectionSummary(order, name, percent),
          hint: l10n.layerChipFocusHint,
          excludeSemantics: true,
          onTap: () => state.focusLayer(layer.id),
          child: InkWell(
            key: ValueKey('layer_section_${layer.id}'),
            onTap: () => state.focusLayer(layer.id),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: [
                  LayerOrderBadge(order: order),
                  const SizedBox(width: 12),
                  Expanded(child: Text(name, style: theme.textTheme.bodyLarge)),
                  const SizedBox(width: 8),
                  Text(
                    '$percent%',
                    style:
                        theme.textTheme.bodyMedium?.copyWith(color: secondary),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.expand_more, size: 24, color: secondary),
                ],
              ),
            ),
          ),
        ),
        if (notice != null) ...[
          const SizedBox(height: 8),
          ConsultNoticeBlock(notice: notice, l10n: l10n),
        ],
        if (nearLimit) ...[
          const SizedBox(height: 8),
          StrengthCautionNote(caution: caution, strength: strength),
        ],
      ],
    );
  }
}

/// 調整中の層の節（展開）。[order] が null のときは 1 層だけの従来の見た目（番号の丸なし）。
class _FocusedSection extends StatelessWidget {
  const _FocusedSection({required this.state, this.order});

  final VisionFilterState state;
  final int? order;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;
    final experience = selectedExperience(state);
    final focusKey = state.focusedLayer?.strengthKey;
    final entry = state.selectedEntry;
    final provenanceFilter = state.build();

    final String name;
    final String? categoryLabel;
    if (experience != null) {
      name = experienceName(l10n, experience.id);
      categoryLabel = l10n.experienceSectionTitle;
    } else {
      name = visionFilterDisplayName(
        l10n,
        state.focusedVariantId,
        state.selectedId,
      );
      categoryLabel =
          entry == null ? null : visionCategoryName(l10n, entry.category);
    }

    // 説明文: 色覚と体験プリセットだけが持つ（advanced の各フィルタには
    // 説明文の文字列が無いので、名前とカテゴリだけを出す）。
    final String? description;
    final String? prevalence;
    if (experience != null) {
      description = experienceDescription(l10n, experience.id);
      prevalence = null;
    } else if (focusKey != null &&
        visionFilterDescription(l10n, focusKey) != null) {
      description = visionFilterDescription(l10n, focusKey);
      prevalence = l10n.prevalenceLabel(
        visionFilterPrevalence(l10n, focusKey)!,
      );
    } else {
      description = null;
      prevalence = null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (order != null) LayerOrderBadge(order: order!),
              Text(name, style: theme.textTheme.titleLarge),
              if (experience == null && (entry?.isExperimental ?? false))
                const ExperimentalBadge(),
            ],
          ),
        ),
        if (categoryLabel != null) ...[
          const SizedBox(height: 4),
          Text(
            categoryLabel,
            style: theme.textTheme.bodySmall?.copyWith(color: secondary),
          ),
        ],
        if (description != null) ...[
          const SizedBox(height: 8),
          Text(description, style: theme.textTheme.bodyMedium),
        ],
        if (prevalence != null) ...[
          const SizedBox(height: 4),
          Text(
            prevalence,
            style: theme.textTheme.bodySmall?.copyWith(color: secondary),
          ),
        ],
        if (experience?.hearing != null) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.hearing, size: 18, color: secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.experienceIncludesHearingNote,
                  style: theme.textTheme.bodySmall?.copyWith(color: secondary),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        // 強度（1 本）・受診喚起・パラメータ。強度は層ごとのキーの記憶
        // （VisionFilterState.strengthByKey）を動かす。
        FilterParamPanel(
          noticeOverride: experience == null
              ? null
              : experienceConsultNotice(l10n, experience),
        ),
        // モデルと出典・表現できないこと（#80）。受診喚起・パラメータより下に
        // 置き、それらの位置を動かさない。
        if (provenanceFilter != null) ...[
          const SizedBox(height: 16),
          FilterProvenanceSection(
            filter: provenanceFilter,
            // 体験プリセットの見出しは体験名なので、情報がどの視覚フィルタの
            // ものかを添える。
            filterName: experience == null
                ? null
                : visionFilterName(l10n, state.selectedId!),
          ),
        ],
      ],
    );
  }
}
