import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/vision_filter_catalog.dart';
import '../../services/filter_service.dart';
import '../../services/vision_filter_state.dart';
import '../../src/rust/api/sensus_bridge.dart';

/// 体験プリセットの供給源。既定は sensus bridge の [experiences]。
///
/// FRB の `experiences()` は native lib を要求し `flutter test`（FFI 未ロード）では
/// 呼べないため、widget test はこの seam を fixture で差し替えて検証する。production
/// では bridge の `experiences()` をそのまま消費する（sensus を再実装しない）。
typedef ExperiencesProvider = List<Experience> Function();

/// 体験プリセット供給源（テストで差し替え可能）。既定は bridge の [experiences]。
ExperiencesProvider experiencesProvider = experiences;

/// 体験プリセット集 (#19)。
///
/// sensus の [experiences]（meniere / bppv / vestibular_neuritis / labyrinthitis の
/// 4 体験）を消費し、各体験をタップで「視覚フィルタの選択」に橋渡しする。
///
/// - 視覚: `Experience.vision`（bridge の [VisionFilter]）を [visionFilterCatalogId]
///   でカタログ id（snake_case）へ写し、[VisionFilterState.select] に渡す。id を
///   ハードコードせずカタログを正本に引く。
/// - 受診喚起: `Experience.urgency`（bridge の [Urgency]）を [urgencyConsultMessage]
///   で i18n 注記へ写す。`none` では出さない。
/// - 聴覚: hearing を含む体験（meniere / labyrinthitis）は「聴覚症状も含む」注記に
///   留める。**音声再生は本 Issue 非スコープ**（聴覚モード設計に委ねる）。音は鳴らさない。
///
/// 文言は持たず、id / 分類から i18n で解決する（規律2）。
class ExperiencePresets extends StatelessWidget {
  const ExperiencePresets({super.key});

  @override
  Widget build(BuildContext context) {
    final presets = experiencesProvider();
    return Consumer<VisionFilterState>(
      builder: (context, state, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final exp in presets)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ExperienceCard(experience: exp, state: state),
              ),
          ],
        );
      },
    );
  }
}

class _ExperienceCard extends StatelessWidget {
  const _ExperienceCard({required this.experience, required this.state});

  final Experience experience;
  final VisionFilterState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    final catalogId = experience.vision == null
        ? null
        : visionFilterCatalogId(experience.vision!);
    final isSelected = catalogId != null && state.selectedId == catalogId;
    final consult = urgencyConsultMessage(l10n, experience.urgency);
    final includesHearing = experience.hearing != null;

    return Card(
      // 選択中のプリセットを縁取りで示す。
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: theme.colorScheme.primary, width: 2)
            : BorderSide(color: theme.dividerColor),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        // 視覚フィルタを持つ体験のみ適用可能（4 体験はすべて vision を持つ）。
        onTap: catalogId == null ? null : () => _apply(context, catalogId),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      experienceName(l10n, experience.id),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (isSelected)
                    Icon(Icons.check_circle, color: theme.colorScheme.primary),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                experienceDescription(l10n, experience.id),
                style: theme.textTheme.bodyMedium,
              ),
              if (includesHearing) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.hearing,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l10n.experienceIncludesHearingNote,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (consult != null) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      experience.urgency == Urgency.emergency
                          ? Icons.warning_amber_rounded
                          : Icons.info_outline,
                      size: 16,
                      color: experience.urgency == Urgency.emergency
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        consult,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: experience.urgency == Urgency.emergency
                              ? theme.colorScheme.error
                              : theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 体験を適用する: 視覚フィルタを選択状態にする。
  ///
  /// 体験は advanced 系（[VisionFilterState]）で適用するため、色覚系
  /// （[FilterService]）は none に戻し、色覚との二重適用を避ける（重ね掛けは #41）。
  void _apply(BuildContext context, String catalogId) {
    context.read<VisionFilterState>().select(catalogId);
    context.read<FilterService>().deactivate();
  }
}
