import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/vision_filter_catalog.dart';
import '../../services/preview_selection.dart';
import '../../services/vision_filter_metadata.dart';
import '../../services/vision_filter_state.dart';
import '../../src/rust/api/sensus_bridge.dart';

/// 選択中フィルタの [VisionParam] 定義から動的にパラメータ UI を生成するパネル。
///
/// - float / int → [Slider]
/// - enum → [DropdownButton]
/// - seed → 表示 + 乱数再生成ボタン
///
/// 加えて受診喚起の注記ブロック・strength スライダ・「推奨値に戻す」ボタンを
/// 表示する。受診喚起（緊急度・条件付き上振れ）は sensus ブリッジ
/// （`visionFilterUrgencyProvider` / `visionFilterUrgencyEscalationProvider`、
/// `lib/services/vision_filter_metadata.dart`）を**唯一の正本**にする（#76）。
/// ue 独自の段階名（旧 `VisionFilterUrgency`）は UI に一切出さない。
///
/// strength スライダは、選択が色覚クイック選択（`FilterSelector`/トレイ）
/// 由来のときは出さない（`lib/services/preview_selection.dart` の
/// `showsAdvancedStrengthSlider` を参照。その場合の強度は #57 のタイプ別
/// 記憶が決め、このスライダーを動かしても反映されないため、#60）。
/// 文言はすべて i18n で解決する（カタログは識別子/enum のみ持つ: #18）。
class FilterParamPanel extends StatelessWidget {
  const FilterParamPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Consumer<VisionFilterState>(
      builder: (context, state, _) {
        final entry = state.selectedEntry;
        if (entry == null) {
          return Text(
            l10n.advancedParamPanelHint,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontStyle: FontStyle.italic,
            ),
          );
        }

        // urgency/urgency_escalation は payload に依存しない（sensus 側 doc
        // 参照）ため、現在の選択（payload 込み）から組み立てた実インスタンスを
        // そのまま渡せばよい（メタデータ専用の別インスタンスは不要）。
        final filter = state.build();
        final urgency = filter == null
            ? Urgency.none
            : visionFilterUrgencyProvider(filter);
        final escalation = filter == null
            ? const <UrgencyEscalation>[]
            : visionFilterUrgencyEscalationProvider(filter);
        final consult = urgencyConsultMessage(l10n, urgency);
        // 色覚クイック選択由来の選択では、強度は previewStrength が
        // FilterService のタイプ別記憶（#57）から決める — この strength
        // スライダーを動かしても実際のプレビューには反映されないので出さない
        // （判定は showsAdvancedStrengthSlider に集約、#60）。
        final showStrength = showsAdvancedStrengthSlider(state);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (consult != null || escalation.isNotEmpty)
              _buildConsultBlock(theme, l10n, urgency, consult, escalation),
            if (showStrength) ...[
              const SizedBox(height: 16),
              _buildStrength(l10n, state),
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

  /// 受診喚起の専用ブロック（#76）。
  ///
  /// - 段階名（旧「緊急度：高」）は一切表示しない。喚起文（[consult]）だけを、
  ///   本文サイズ以上（[TextTheme.bodyMedium]）で表示する。
  /// - 色は [ColorScheme] のロールのみを使う（urgency に応じて
  ///   [ColorScheme.tertiaryContainer] / [ColorScheme.errorContainer]。
  ///   [Urgency.none] だが escalation が非空のフィルタ（bppv_rotation 等）は
  ///   中立の [ColorScheme.surfaceContainerHighest] を使う）。
  /// - [escalation]（`urgency_escalation()`）の条件文は「次の場合は受診を」の
  ///   形で併記する。条件文は英語で返るため [escalationConditionText] で
  ///   ja/en に対応表があれば訳し、無ければ英語のまま表示する。
  /// - 末尾に「一般的な案内であり、診断ではない」の注記を必ず添える。
  Widget _buildConsultBlock(
    ThemeData theme,
    AppLocalizations l10n,
    Urgency urgency,
    String? consult,
    List<UrgencyEscalation> escalation,
  ) {
    final scheme = theme.colorScheme;
    final Color background;
    final Color foreground;
    switch (urgency) {
      case Urgency.emergency:
        background = scheme.errorContainer;
        foreground = scheme.onErrorContainer;
        break;
      case Urgency.earlyConsultation:
        background = scheme.tertiaryContainer;
        foreground = scheme.onTertiaryContainer;
        break;
      case Urgency.none:
        background = scheme.surfaceContainerHighest;
        foreground = scheme.onSurfaceVariant;
        break;
    }
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(color: foreground);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (consult != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  urgency == Urgency.emergency
                      ? Icons.warning_amber_rounded
                      : Icons.medical_information_outlined,
                  size: 18,
                  color: foreground,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    consult,
                    style: bodyStyle?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          if (escalation.isNotEmpty) ...[
            if (consult != null) const SizedBox(height: 8),
            Text(
              l10n.escalationHeader,
              style: bodyStyle?.copyWith(fontWeight: FontWeight.w600),
            ),
            for (final e in escalation)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '•  ${escalationConditionText(l10n, e.condition)}',
                  style: bodyStyle,
                ),
              ),
          ],
          const SizedBox(height: 8),
          Text(
            l10n.consultDisclaimer,
            style: bodyStyle?.copyWith(fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _buildStrength(AppLocalizations l10n, VisionFilterState state) {
    final percent = (state.strength * 100).toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(l10n.strengthLabel(percent))),
            TextButton.icon(
              onPressed: () => state.resetToRecommended(),
              icon: const Icon(Icons.restart_alt, size: 18),
              label: Text(l10n.resetToRecommendedStrength),
            ),
          ],
        ),
        Slider(
          value: state.strength,
          min: 0.0,
          max: 1.0,
          divisions: 20,
          label: '$percent%',
          onChanged: (v) => state.setStrength(v),
        ),
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
        Slider(
          value: clamped,
          min: min,
          max: max,
          label: clamped.toStringAsFixed(2),
          onChanged: (v) => state.setParam(param.name, v),
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
        Slider(
          value: clamped.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: divisions,
          label: '$clamped',
          onChanged: (v) => state.setParam(param.name, v.round()),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(visionParamLabel(l10n, param.labelKey)),
        const SizedBox(height: 4),
        DropdownButton<String>(
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
        ),
      ],
    );
  }

  Widget _buildSeed(
    AppLocalizations l10n,
    VisionFilterState state,
    VisionParam param,
  ) {
    final value = state.paramValue(param);
    final label = visionParamLabel(l10n, param.labelKey);
    return Row(
      children: [
        Expanded(child: Text('$label: $value')),
        TextButton.icon(
          onPressed: () => state.randomizeSeed(param.name),
          icon: const Icon(Icons.casino),
          label: Text(l10n.randomize),
        ),
      ],
    );
  }
}
