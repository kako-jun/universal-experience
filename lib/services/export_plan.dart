import '../l10n/app_localizations.dart';
import '../l10n/l10n_extensions.dart';
import '../models/vision_filter_catalog.dart';
import '../models/vision_filter_contract_notes.dart' as contract_notes;
import '../src/rust/api/sensus_bridge.dart';
import 'export_layers.dart';
import 'export_service.dart';
import 'vision_filter_metadata.dart';

// 書き出しの「計画」（キャプションの解決・ファイル名の素の決定）。UI の部品を持たない
// 純粋なロジックで、`BeforeAfterView` と 2×2 比較（`ColorVisionCompareView`）が共有する（#159）。

/// 書き出し PNG に焼き込む [ExportCaption] を、描画時の値から解決する（#43/#76/#80、
/// 2×2 比較の各セル #84 と共有）。
///
/// i18n はここで解決し、pure な `exportImageComposer` へは解決済み文字列だけを渡す
/// （規律2）。引数は **画像を描画した時点の値** を渡すこと（呼び出し時点の現在の
/// widget props ではなく）。
///
/// - 受診喚起は プレビューの注記（`FilterParamPanel`・`ExperiencePresetTile`）と同じ
///   正本・同じ解決経路（[resolveConsultNotice]）を使う。色覚 7 型は urgency=none
///   かつ escalation も無いので notice は自然に null になる。
/// - 実験的なフィルタ（四色覚）には、近似であることに加えて「実験的」も焼き込む。
///   対象は [VisionFilterEntry.isExperimental] が正本。
/// - escalation は `ConsultNotice.escalationGroups` を詰め替えるだけで、グルーピングの
///   ロジックはここに複製しない。
ExportCaption buildExportCaption(
  AppLocalizations l10n, {
  required String? filterId,
  required String? variantId,
  required VisionFilter? filter,
  required double strength,
  required String isoDate,
}) {
  final notice = filter == null
      ? null
      : resolveConsultNotice(
          l10n,
          visionFilterUrgencyProvider(filter),
          visionFilterUrgencyEscalationProvider(filter),
        );
  return ExportCaption(
    symptomLabel: visionFilterDisplayName(l10n, variantId, filterId),
    strengthLabel: l10n.strengthLabel(contract_notes.strengthPercent(strength)),
    isoDate: isoDate,
    simulationNotice: l10n.exportSimulationNotice,
    experimentalNotice:
        (kVisionFilterCatalogById[filterId]?.isExperimental ?? false)
        ? l10n.exportExperimentalNotice
        : null,
    urgencyMessage: notice?.message,
    escalationGroups: [
      for (final g in notice?.escalationGroups ?? const [])
        ExportEscalationGroup(header: g.header, lines: g.lines),
    ],
    disclaimer: notice?.disclaimerShort,
  );
}

/// [planExport] の結果: 焼き込むキャプション・ファイル名の症状 id・強度（% の整数。複数層は null）。
typedef ExportPlan = ({
  ExportCaption caption,
  String symptomId,
  int? strengthPercent,
});

/// 書き出しの内容（キャプション・ファイル名の素）を、描画時点の値から決める（#121）。
///
/// [layers] は重ねている全層（`BeforeAfterView.exportLayers`、単一層なら null）。
/// キャプションに数えるのは**強度が 0 より大きい層だけ**（[effectiveExportLayers]。強度 0 の層は
/// 画素に効かないので、症状の行にも受診喚起にもファイル名にも入れない。表示が「0%」になる強度も同じ）。
///
/// - 2 層以上: [buildLayeredExportCaption]（層ごとの行 + 合成した受診喚起）。ファイル名は
///   層の id を適用順につないだもの（[exportSymptomId]）で、強度の % は付けない。
/// - 1 層: その層だけを、単一層の書き出し（[buildExportCaption]）と同じ見た目・同じ名前にする。
/// - 0 層（単一層、原画比較中、表示強度（整数パーセント）が 0 の層しかない）: 引数の
///   [filterId]/[variantId]/[filter]/[strength]（フォーカス中の層の値）で、従来どおりの
///   単一層の書き出し。
ExportPlan planExport(
  AppLocalizations l10n, {
  required List<ExportLayer>? layers,
  required String? filterId,
  required String? variantId,
  required VisionFilter? filter,
  required double strength,
  required String isoDate,
}) {
  final effective = effectiveExportLayers(layers ?? const []);
  if (effective.length >= 2) {
    return (
      caption: buildLayeredExportCaption(l10n,
          layers: effective, isoDate: isoDate),
      symptomId: exportSymptomId([for (final l in effective) l.layer.strengthKey]),
      strengthPercent: null,
    );
  }
  if (effective.length == 1) {
    final only = effective.single;
    filterId = only.layer.id;
    variantId = only.layer.variantId;
    filter = only.filter;
    strength = only.strength;
  }
  return (
    caption: buildExportCaption(
      l10n,
      filterId: filterId,
      variantId: variantId,
      filter: filter,
      strength: strength,
      isoDate: isoDate,
    ),
    // variantId があればその id（-omaly を含む）を使う（#60）。
    // filterId は -omaly を base の -opia と区別できないため。
    symptomId: exportSymptomId([variantId ?? filterId ?? 'none']),
    strengthPercent: contract_notes.strengthPercent(strength),
  );
}

/// 複数の層（[layers]、適用順、2 つ以上。呼び出し側が強度 0 を除いたもの）を重ねた書き出しの
/// [ExportCaption]（#121）。
///
/// - 症状の行: 層ごとに 1 行（名前 + その層の強度）。
/// - 受診喚起: 各層の緊急度の**最大**と、escalation の**段ごとの併合（重複は 1 行）**を
///   [consultInputForFilters]（[mergeConsultInputs]）で 1 つにして、単一層と同じ
///   [resolveConsultNotice] の経路で解決する。
/// - 実験的の注記: どれか 1 層でも [VisionFilterEntry.isExperimental] なら添える。
/// - 「シミュレーション（近似）」は常に焼き込む。
ExportCaption buildLayeredExportCaption(
  AppLocalizations l10n, {
  required List<ExportLayer> layers,
  required String isoDate,
}) {
  final input = consultInputForFilters([for (final l in layers) l.filter]);
  final notice = resolveConsultNotice(l10n, input.urgency, input.escalation);
  return ExportCaption.layered(
    layers: [
      for (final l in layers)
        ExportLayerRow(
          name: visionLayerDisplayName(l10n, l.layer),
          strengthLabel:
              l10n.strengthLabel(contract_notes.strengthPercent(l.strength)),
        ),
    ],
    isoDate: isoDate,
    simulationNotice: l10n.exportSimulationNotice,
    experimentalNotice: layers.any(
            (l) => kVisionFilterCatalogById[l.layer.id]?.isExperimental ?? false)
        ? l10n.exportExperimentalNotice
        : null,
    urgencyMessage: notice?.message,
    escalationGroups: [
      for (final g in notice?.escalationGroups ?? const [])
        ExportEscalationGroup(header: g.header, lines: g.lines),
    ],
    disclaimer: notice?.disclaimerShort,
  );
}
