import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/vision_filter_catalog.dart';
import '../../services/vision_filter_metadata.dart';
import '../../services/vision_filter_state.dart';
import '../../src/rust/api/sensus_bridge.dart';
import 'filter_list_tile.dart';

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

/// 今表示する体験プリセットの一覧（[experiencesProvider] の現在値）。
///
/// `@visibleForTesting` の [experiencesProvider] を production コードから
/// 直接参照しないための窓口（一覧 `FilterBrowser` はここから読む）。
List<Experience> availableExperiences() => experiencesProvider();

/// 体験プリセットの行（[ExperiencePresetTile]）を一意に指す [Key]。
///
/// テストが表示名の文字列（ロケール依存・レイアウト変更で位置がずれる）ではなく
/// experience id で安定して行を見つけ、タップ前にスクロールできるようにする
/// ための公開ヘルパ（#60）。
Key experienceCardKey(String experienceId) =>
    ValueKey('experience_card_$experienceId');

/// [experience] の escalation を [Experience.vision] から取得する（#76 レビュー
/// S3）。Experience 自体は urgency_escalation を持たないため、視覚フィルタの
/// escalation をそのまま使う。vision を持たない体験は現状無いが、無い場合は
/// 空リスト（喚起なし）にする。
List<UrgencyEscalation> _escalationFor(Experience experience) =>
    experience.vision == null
        ? const <UrgencyEscalation>[]
        : visionFilterUrgencyEscalationProvider(experience.vision!);

/// 体験プリセット [experience] の受診喚起。`Experience.urgency`（聴覚症状を含む
/// 体験全体の緊急度）と、視覚フィルタから取得した escalation を
/// [resolveConsultNotice] でまとめる（`FilterParamPanel`・export と共有する
/// 唯一の解決経路）。喚起が無ければ null。
///
/// 右カラムの調整パネル（`AdjustPanel`、#72）が、体験プリセットを選んでいる間の
/// 喚起としてこれを使う（視覚フィルタ単体の緊急度ではなく体験としての緊急度）。
ConsultNotice? experienceConsultNotice(
  AppLocalizations l10n,
  Experience experience,
) =>
    resolveConsultNotice(l10n, experience.urgency, _escalationFor(experience));

/// 選択中の体験プリセット（[VisionFilterState.selectedPresetId]）に対応する
/// [Experience]。プリセット選択中でなければ null。
Experience? selectedExperience(VisionFilterState state) {
  final id = state.selectedPresetId;
  if (id == null) return null;
  for (final exp in availableExperiences()) {
    if (exp.id == id) return exp;
  }
  return null;
}

/// 体験プリセット (#19) の一覧の 1 行。
///
/// sensus の [experiences]（meniere / bppv / vestibular_neuritis /
/// labyrinthitis の 4 体験）をタップで「視覚フィルタの選択」に橋渡しする。
/// 統合フィルタ一覧（`FilterBrowser`、#72）の最上段に、色覚・advanced の行より
/// 先に並べる。
///
/// - 視覚: `Experience.vision`（bridge の [VisionFilter]）を [visionFilterCatalogId]
///   でカタログ id（snake_case）へ写し、[VisionFilterState.selectPreset] に渡す
///   （#60: `FilterService.deactivate()` は呼ばない — 色覚クイック選択の状態は
///   このプリセット適用と無関係に残る。プレビューは [VisionFilterState] の
///   選択だけを見るため、干渉しない）。id をハードコードせずカタログを正本に引く。
/// - 選択表示: meniere と labyrinthitis はどちらもカタログ id `vertigo` に写る
///   ため、選択表示はカタログ id ではなく [VisionFilterState.selectedPresetId]
///   （`Experience.id`）で比較する（#60: 2 行同時点灯バグの修正）。
/// - 説明・受診喚起・聴覚症状の注記は一覧の行には出さず、選んだあと右カラム
///   （`AdjustPanel`）に出す（#72）。免責文・根拠 URL も右カラムの
///   `ConsultNoticeBlock` が常に表示する。
/// - 聴覚: hearing を含む体験（meniere / labyrinthitis）は右カラムの注記に留める。
///   **音声再生は本 Issue 非スコープ**（聴覚モード設計に委ねる）。音は鳴らさない。
///
/// 文言は持たず、id / 分類から i18n で解決する（規律2）。
class ExperiencePresetTile extends StatelessWidget {
  const ExperiencePresetTile({
    super.key,
    required this.experience,
    this.onActivated,
  });

  final Experience experience;

  /// ポインタで選択した直後に呼ばれる（一覧がキーボード操作の受け口へ
  /// フォーカスを戻すために使う。キーボードでの活性化では呼ばれない。
  /// `FilterBrowser` 参照）。
  final VoidCallback? onActivated;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = context.watch<VisionFilterState>();
    final catalogId = experience.vision == null
        ? null
        : visionFilterCatalogId(experience.vision!);
    // #60: カタログ id ではなく experience id で比較する。
    final isSelected = state.selectedPresetId == experience.id;
    return FilterListTile(
      key: experienceCardKey(experience.id),
      leading: const Icon(Icons.auto_awesome),
      title: experienceName(l10n, experience.id),
      selected: isSelected,
      // 視覚フィルタを持つ体験のみ適用可能（4 体験はすべて vision を持つ）。
      onTap: catalogId == null
          ? null
          : () => context
              .read<VisionFilterState>()
              .selectPreset(experience.id, catalogId),
      onPointerActivated: onActivated,
    );
  }
}
