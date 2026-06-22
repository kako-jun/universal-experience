import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/vision_filter_catalog.dart';
import '../../services/vision_filter_state.dart';

/// 選択中フィルタの [VisionParam] 定義から動的にパラメータ UI を生成するパネル。
///
/// - float / int → [Slider]
/// - enum → [DropdownButton]
/// - seed → 表示 + 乱数再生成ボタン
///
/// 加えて urgency 注記・受診喚起メッセージ・strength スライダを表示する。
/// 文言はすべて i18n で解決する（カタログは識別子/enum のみ持つ: #18）。
class FilterParamPanel extends StatelessWidget {
  const FilterParamPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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

        final consult = consultMessageForUrgency(l10n, entry.urgency);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildUrgency(l10n, entry),
            if (consult != null) ...[
              const SizedBox(height: 8),
              _buildConsultNote(consult),
            ],
            const SizedBox(height: 16),
            _buildStrength(l10n, state),
            for (final param in entry.parameters) ...[
              const SizedBox(height: 16),
              _buildParam(l10n, state, param),
            ],
          ],
        );
      },
    );
  }

  Widget _buildUrgency(AppLocalizations l10n, VisionFilterEntry entry) {
    return Row(
      children: [
        const Icon(Icons.priority_high, size: 16),
        const SizedBox(width: 6),
        Text(
          l10n.urgencyLabel(visionUrgencyName(l10n, entry.urgency)),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  /// 受診喚起メッセージ（urgency 由来）。当事者に配慮した穏やかな注記として、
  /// 控えめなアイコン + 注釈スタイルで出す。
  Widget _buildConsultNote(String message) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.medical_information_outlined, size: 16),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
          ),
        ),
      ],
    );
  }

  Widget _buildStrength(AppLocalizations l10n, VisionFilterState state) {
    final percent = (state.strength * 100).toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.strengthLabel(percent)),
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
