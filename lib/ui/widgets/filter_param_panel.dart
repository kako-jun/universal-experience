import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/vision_filter_catalog.dart';
import '../../models/vision_filter_contract_notes.dart';

import '../../services/vision_filter_metadata.dart';
import '../../services/vision_filter_state.dart';
import '../../services/vision_layer.dart';
import '../../src/rust/api/sensus_bridge.dart';
import 'consult_notice_block.dart';
import 'strength_caution.dart';

/// 選択中フィルタの [VisionParam] 定義から動的にパラメータ UI を生成するパネル。
///
/// - float / int → [Slider]
/// - enum → [DropdownButton]
/// - seed → 値は隠し、「パターンを変える」ボタンだけ（#80）
///
/// 加えて strength スライダ・「推奨値に戻す」ボタン・受診喚起の注記ブロックを
/// 表示する。並びは **強度 → 受診喚起 → パラメータ**（#72: 受診喚起は強度の
/// すぐ下に常時展開で出す）。受診喚起（緊急度・条件付き上振れ）は sensus ブリッジ
/// （`visionFilterUrgencyProvider` / `visionFilterUrgencyEscalationProvider`、
/// `lib/services/vision_filter_metadata.dart`）を**唯一の正本**にする（#76）。
/// ue 独自の段階名（旧 `VisionFilterUrgency`）は UI に一切出さない。
///
/// 対象は調整中（`focusedId`）の層 1 つ。強度スライダーはどの由来の層（色覚クイック選択・
/// advanced・体験プリセット）でも**この 1 本だけ**（かつての色覚用スライダーとの二本立ては
/// #120 で 1 本に統合した）。動かす先は層ごとのキーの記憶（`VisionFilterState.strengthByKey`、
/// #117）で、動かすと原画比較（bypass）は解除される。複数層の節の並びは `AdjustPanel` が持つ。
/// 文言はすべて i18n で解決する（カタログは識別子/enum のみ持つ: #18）。
/// [layer] 単体の受診喚起（#120）。複数層の合成（`mergeConsultInputs`）ではなく、その層だけを
/// sensus の入口（[visionFilterUrgencyProvider] / [visionFilterUrgencyEscalationProvider]）に
/// 渡して解決する。出す喚起が無ければ null。
ConsultNotice? layerConsultNotice(
  AppLocalizations l10n,
  VisionFilterState state,
  VisionLayer layer,
) {
  final filter = state.buildLayer(layer);
  return resolveConsultNotice(
    l10n,
    visionFilterUrgencyProvider(filter),
    visionFilterUrgencyEscalationProvider(filter),
  );
}

class FilterParamPanel extends StatelessWidget {
  const FilterParamPanel({super.key, this.noticeOverride});

  /// 受診喚起を、選択中フィルタ単体の緊急度ではなくこの値で表示する。体験
  /// プリセットを選んでいるときの「体験としての緊急度」（`Experience.urgency`、
  /// `experienceConsultNotice`）を渡すために使う。null ならフィルタから解決する。
  final ConsultNotice? noticeOverride;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer<VisionFilterState>(
      builder: (context, state, _) {
        final entry = state.selectedEntry;
        // 未選択のときの表示（「何も選択されていません」）は呼び出し側
        // （`AdjustPanel`）が持つ。ここは何も出さない。
        if (entry == null) return const SizedBox.shrink();

        // urgency/urgency_escalation は payload に依存しない（sensus 側 doc
        // 参照）ため、現在の選択（payload 込み）から組み立てた実インスタンスを
        // そのまま渡せばよい（メタデータ専用の別インスタンスは不要）。
        final filter = state.build();
        final urgency =
            filter == null ? Urgency.none : visionFilterUrgencyProvider(filter);
        final escalation = filter == null
            ? const <UrgencyEscalation>[]
            : visionFilterUrgencyEscalationProvider(filter);
        // 喚起の解決は resolveConsultNotice 1 箇所に集約し、
        // 表示は ConsultNoticeBlock（プリセットカード・export と共有）に委ねる。
        final notice =
            noticeOverride ?? resolveConsultNotice(l10n, urgency, escalation);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStrength(context, l10n, state),
            if (notice != null) ...[
              const SizedBox(height: 16),
              ConsultNoticeBlock(notice: notice, l10n: l10n),
            ],
            for (final param in entry.parameters) ...[
              const SizedBox(height: 16),
              _buildParam(l10n, state, param),
            ],
          ],
        );
      },
    );
  }

  Widget _buildStrength(
    BuildContext context,
    AppLocalizations l10n,
    VisionFilterState state,
  ) {
    final percent = strengthPercent(state.strength);
    final layerId = state.focusedId!;
    final caution = kStrengthCautionByFilterId[layerId];
    final slider = MergeSemantics(
      child: Semantics(
          label: l10n.strengthSliderName,
          child: Slider(
            value: state.strength,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            label: '$percent%',
            semanticFormatterCallback: (v) => '${strengthPercent(v)}%',
            onChanged: (v) => state.setLayerStrength(layerId, v),
          )),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 狭い右カラムでも折り返して収まるよう Wrap にする（ラベルと「推奨に戻す」
        // を横並びにできない幅では、ボタンが次の行へ落ちる）。
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              l10n.strengthLabel(percent),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            TextButton.icon(
              onPressed: () => state.resetToRecommended(),
              icon: const Icon(Icons.restart_alt, size: 18),
              label: Text(l10n.resetToRecommendedStrength),
            ),
          ],
        ),
        if (caution == null)
          slider
        else
          // 上限付近の注意（#66）: 閾値の位置に印を描き、下に注記を出す。
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackShape: StrengthCautionTrackShape(
                threshold: caution.threshold,
                markColor: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            child: slider,
          ),
        if (caution != null) ...[
          const SizedBox(height: 8),
          StrengthCautionNote(caution: caution, strength: state.strength),
        ],
      ],
    );
  }

  Widget _buildParam(
    AppLocalizations l10n,
    VisionFilterState state,
    VisionParam param,
  ) {
    switch (param.kind) {
      case VisionParamKind.float:
        return _buildFloatSlider(l10n, state, param);
      case VisionParamKind.intValue:
        return _buildIntSlider(l10n, state, param);
      case VisionParamKind.enumValue:
        return _buildEnumDropdown(l10n, state, param);
      case VisionParamKind.seed:
        return _buildSeed(l10n, state, param);
    }
  }

  Widget _buildFloatSlider(
    AppLocalizations l10n,
    VisionFilterState state,
    VisionParam param,
  ) {
    final value = (state.paramValue(param) as num?)?.toDouble() ?? 0.0;
    final min = param.min ?? 0.0;
    final max = param.max ?? 1.0;
    final clamped = value.clamp(min, max);
    final label = visionParamLabel(l10n, param.labelKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('$label: ${clamped.toStringAsFixed(2)}'),
        MergeSemantics(
          child: Semantics(
              label: label,
              child: Slider(
                value: clamped,
                min: min,
                max: max,
                label: clamped.toStringAsFixed(2),
                // 既定の読み上げは「範囲に対する割合（%）」で、実際の値と食い違う。
                semanticFormatterCallback: (v) => v.toStringAsFixed(2),
                onChanged: (v) => state.setParam(param.name, v),
              )),
        ),
      ],
    );
  }

  Widget _buildIntSlider(
    AppLocalizations l10n,
    VisionFilterState state,
    VisionParam param,
  ) {
    final raw = state.paramValue(param);
    final value = raw is num ? raw.toInt() : 0;
    final min = (param.min ?? 0.0).toInt();
    final max = (param.max ?? 100.0).toInt();
    final clamped = value.clamp(min, max);
    final divisions = (max - min) > 0 ? (max - min) : 1;
    final label = visionParamLabel(l10n, param.labelKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('$label: $clamped'),
        MergeSemantics(
          child: Semantics(
              label: label,
              child: Slider(
                value: clamped.toDouble(),
                min: min.toDouble(),
                max: max.toDouble(),
                divisions: divisions,
                label: '$clamped',
                semanticFormatterCallback: (v) => '${v.round()}',
                onChanged: (v) => state.setParam(param.name, v.round()),
              )),
        ),
      ],
    );
  }

  Widget _buildEnumDropdown(
    AppLocalizations l10n,
    VisionFilterState state,
    VisionParam param,
  ) {
    final current = state.paramValue(param) as String?;
    final label = visionParamLabel(l10n, param.labelKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 4),
        // 上の Text とドロップダウンは別ノードなので、名前を Semantics に載せる（#45）。
        MergeSemantics(
          child: Semantics(
              label: label,
              child: DropdownButton<String>(
                isExpanded: true,
                value: current,
                items: param.options
                    .map(
                      (o) => DropdownMenuItem<String>(
                        value: o.value,
                        child: Text(visionParamLabel(l10n, o.labelKey)),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) state.setParam(param.name, v);
                },
              )),
        ),
      ],
    );
  }

  /// seed 系のパラメータ（#80）。シードは内部の乱数の種で、数値そのものに
  /// 意味が無く一般の人には伝わらないため、値は表示せず「パターンを変える」
  /// ボタンだけにする。ラベルは「何のパターンか」を示す名前（ARB）。
  Widget _buildSeed(
    AppLocalizations l10n,
    VisionFilterState state,
    VisionParam param,
  ) {
    final label = visionParamLabel(l10n, param.labelKey);
    // 狭い右カラムでは、ラベルとボタンが横に収まらないので折り返す。
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 4,
      children: [
        Text(label),
        // 画面上の文言は短く「パターンを変える」だが、ボタンが複数並ぶ
        // フィルタでどのパターンかを読み上げで区別できるよう、パラメータ名を
        // 含むラベルを読ませる。
        OutlinedButton.icon(
          onPressed: () => state.randomizeSeed(param.name),
          icon: const Icon(Icons.shuffle, size: 16),
          label: Text(
            l10n.changePattern,
            semanticsLabel: l10n.changePatternFor(label),
          ),
        ),
      ],
    );
  }
}
