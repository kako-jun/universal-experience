import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/vision_filter_catalog.dart';
import '../../services/vision_filter_metadata.dart';
import '../../services/vision_filter_state.dart';
import '../../src/rust/api/sensus_bridge.dart';
import 'consult_notice_block.dart';

/// 体験プリセットの供給源。既定は sensus bridge の [experiences]。
///
/// FRB の `experiences()` は native lib を要求し `flutter test`（FFI 未ロード）では
/// 呼べないため、widget test はこの seam を fixture で差し替えて検証する。production
/// では bridge の `experiences()` をそのまま消費する（sensus を再実装しない）。
typedef ExperiencesProvider = List<Experience> Function();

/// 体験プリセット供給源（テストで差し替え可能）。既定は bridge の [experiences]。
///
/// production からは既定値（実 bridge）をそのまま使う。差し替えは widget test の
/// fixture 注入専用なので、外部からの書き換えを抑止するため `@visibleForTesting`。
@visibleForTesting
ExperiencesProvider experiencesProvider = experiences;

/// 体験プリセットのカード（[_ExperienceCard]）を一意に指す [Key]。
///
/// テストが表示名の文字列（ロケール依存・レイアウト変更で位置がずれる）ではなく
/// experience id で安定してカードを見つけ、タップ前にスクロールできるように
/// するための公開ヘルパ（#60）。
Key experienceCardKey(String experienceId) =>
    ValueKey('experience_card_$experienceId');

/// 体験プリセット集 (#19)。
///
/// sensus の [experiences]（meniere / bppv / vestibular_neuritis / labyrinthitis の
/// 4 体験）を消費し、各体験をタップで「視覚フィルタの選択」に橋渡しする。
///
/// - 視覚: `Experience.vision`（bridge の [VisionFilter]）を [visionFilterCatalogId]
///   でカタログ id（snake_case）へ写し、[VisionFilterState.selectPreset] に渡す
///   （#60: `FilterService.deactivate()` は呼ばない — 色覚クイック選択の状態は
///   このプリセット適用と無関係に残る。プレビューは [VisionFilterState] の
///   選択だけを見るため、干渉しない）。id をハードコードせずカタログを正本に引く。
/// - 選択表示: meniere と labyrinthitis はどちらもカタログ id `vertigo` に写る
///   ため、選択表示（`isSelected`）はカタログ id ではなく
///   [VisionFilterState.selectedPresetId]（`Experience.id`）で比較する
///   （#60: 2 枚同時点灯バグの修正）。
/// - 受診喚起: `Experience.urgency`（bridge の [Urgency]）と、
///   `Experience.vision` から取得した escalation（#76 レビュー S3。
///   `visionFilterUrgencyEscalationProvider`）を [resolveConsultNotice] で
///   まとめ、[ConsultNoticeBlock] で表示する（FilterParamPanel・export と
///   共有する唯一の解決経路・表示ウィジェット）。
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
    // #60: カタログ id ではなく experience id で比較する。meniere と
    // labyrinthitis はどちらも catalogId == 'vertigo' に写るため、catalogId
    // 比較だと選択していない方まで点灯してしまう。
    final isSelected = state.selectedPresetId == experience.id;
    // #76 レビュー S3: escalation は experience.vision から取得する（Experience
    // 自体は urgency_escalation を持たないため、視覚フィルタの escalation を
    // そのまま使う）。vision を持たない体験は現状無いが、無い場合は喚起なし
    // 扱いにする（catalogId が null なのでタップもできない）。
    final escalation = experience.vision == null
        ? const <UrgencyEscalation>[]
        : visionFilterUrgencyEscalationProvider(experience.vision!);
    final notice = resolveConsultNotice(l10n, experience.urgency, escalation);
    final includesHearing = experience.hearing != null;

    return Card(
      key: experienceCardKey(experience.id),
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
              if (notice != null) ...[
                const SizedBox(height: 8),
                ConsultNoticeBlock(notice: notice, l10n: l10n),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 体験を適用する: 視覚フィルタを選択状態にする（#60）。
  ///
  /// [VisionFilterState.selectPreset] は experience id とカタログ id の両方を
  /// 記録する（選択表示の比較・プレビューの単一の正本）。色覚系
  /// （`FilterService`）は触らない — `deactivate()` は呼ばない。色覚クイック
  /// 選択の状態はこのプリセット適用と独立に残るが、プレビューは
  /// [VisionFilterState] の選択（今まさに選んだプリセット）だけを見るため、
  /// 二重適用にはならない。
  void _apply(BuildContext context, String catalogId) {
    context.read<VisionFilterState>().selectPreset(experience.id, catalogId);
  }
}
