import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/color_vision_selection.dart';
import '../../services/filter_service.dart';
import '../../services/vision_filter_state.dart';
import 'experience_presets.dart';
import 'experimental_badge.dart';
import 'filter_param_panel.dart';
import 'filter_provenance.dart';
import 'intensity_slider.dart';

/// 右カラム「調整」（#72）: 選んだ見え方の説明・強度・受診喚起・パラメータ。
///
/// 並びは上から **見出し（+ 解除）→ 選んだ症状の名前と説明 → 強度 → 受診喚起 →
/// パラメータ → モデルと出典・表現できないこと（#80、折りたたみ）**。受診喚起は強度のすぐ下に常時展開で出す（動かさない・隠さない、
/// DESIGN §6.2）。
///
/// - 色覚の行を選んでいるとき: 強度は [IntensitySlider]（`FilterService` の
///   タイプ別記憶 #57）。受診喚起・パラメータは [FilterParamPanel] が続けて出す
///   （色覚 7 型に喚起は無いので実際には何も足されない）。
/// - advanced の行・体験プリセットを選んでいるとき: 強度・受診喚起・パラメータは
///   [FilterParamPanel]。プリセットのときは体験としての緊急度
///   （[experienceConsultNotice]）を優先する。
/// - 何も選んでいないとき: 空のカードを出さず、「何も選択されていません」と
///   次の一手だけを出す。
///
/// 列の面（`Card`）と高さの制約は呼び出し側（`HomeScreen`）が持つ。
class AdjustPanel extends StatelessWidget {
  const AdjustPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Consumer2<VisionFilterState, FilterService>(
      builder: (context, state, filterService, _) {
        final hasSelection = state.selectedId != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.adjustHeading,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  // 色覚・advanced・プリセットのどの選択でも、選択を丸ごと
                  // 外す唯一の入口（`color_vision_selection.dart` 経由で
                  // FilterService と VisionFilterState の両方を更新する）。
                  onPressed: hasSelection
                      ? () => deactivateColorVision(filterService, state)
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
          Text(
            l10n.selectionEmptyTitle,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
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

class _SelectedContent extends StatelessWidget {
  const _SelectedContent({required this.state});

  final VisionFilterState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;
    final experience = selectedExperience(state);
    final colorType = state.colorVisionType;
    final entry = state.selectedEntry;
    final provenanceFilter = state.build();

    final String name;
    final String? categoryLabel;
    if (experience != null) {
      name = experienceName(l10n, experience.id);
      categoryLabel = l10n.experienceSectionTitle;
    } else {
      name = visionFilterDisplayName(l10n, colorType, state.selectedId);
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
    } else if (colorType != null) {
      description = colorVisionTypeDescription(l10n, colorType);
      prevalence =
          l10n.prevalenceLabel(colorVisionTypePrevalence(l10n, colorType));
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
        // 色覚の行: 強度はタイプ別記憶（FilterService）のスライダー。
        if (state.isColorQuickSelection) ...[
          const IntensitySlider(),
          const SizedBox(height: 16),
        ],
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
