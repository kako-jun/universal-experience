import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/vision_filter_catalog.dart';
import '../../services/vision_filter_state.dart';

/// 選択中フィルタの [VisionParam] 定義から動的にパラメータ UI を生成するパネル。
///
/// - float / int → [Slider]
/// - enum → [DropdownButton]
/// - seed → 表示 + 乱数再生成ボタン
///
/// 加えて strength スライダを常に表示する。値は [VisionFilterState] に反映する。
class FilterParamPanel extends StatelessWidget {
  const FilterParamPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<VisionFilterState>(
      builder: (context, state, _) {
        final entry = state.selectedEntry;
        if (entry == null) {
          return Text(
            'Select a filter to adjust its parameters.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontStyle: FontStyle.italic,
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildUrgency(entry),
            const SizedBox(height: 16),
            _buildStrength(state),
            for (final param in entry.parameters) ...[
              const SizedBox(height: 16),
              _buildParam(state, param),
            ],
          ],
        );
      },
    );
  }

  Widget _buildUrgency(VisionFilterEntry entry) {
    return Row(
      children: [
        const Icon(Icons.priority_high, size: 16),
        const SizedBox(width: 6),
        Text(
          'Urgency: ${entry.urgency.displayName}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildStrength(VisionFilterState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Strength: ${(state.strength * 100).toInt()}%'),
        Slider(
          value: state.strength,
          min: 0.0,
          max: 1.0,
          divisions: 20,
          label: '${(state.strength * 100).toInt()}%',
          onChanged: (v) => state.setStrength(v),
        ),
      ],
    );
  }

  Widget _buildParam(VisionFilterState state, VisionParam param) {
    switch (param.kind) {
      case VisionParamKind.float:
        return _buildFloatSlider(state, param);
      case VisionParamKind.intValue:
        return _buildIntSlider(state, param);
      case VisionParamKind.enumValue:
        return _buildEnumDropdown(state, param);
      case VisionParamKind.seed:
        return _buildSeed(state, param);
    }
  }

  Widget _buildFloatSlider(VisionFilterState state, VisionParam param) {
    final value = (state.paramValue(param) as num?)?.toDouble() ?? 0.0;
    final min = param.min ?? 0.0;
    final max = param.max ?? 1.0;
    final clamped = value.clamp(min, max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${param.displayName}: ${clamped.toStringAsFixed(2)}'),
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

  Widget _buildIntSlider(VisionFilterState state, VisionParam param) {
    final raw = state.paramValue(param);
    final value = raw is num ? raw.toInt() : 0;
    final min = (param.min ?? 0.0).toInt();
    final max = (param.max ?? 100.0).toInt();
    final clamped = value.clamp(min, max);
    final divisions = (max - min) > 0 ? (max - min) : 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${param.displayName}: $clamped'),
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

  Widget _buildEnumDropdown(VisionFilterState state, VisionParam param) {
    final current = state.paramValue(param) as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(param.displayName),
        const SizedBox(height: 4),
        DropdownButton<String>(
          isExpanded: true,
          value: current,
          items: param.options
              .map(
                (o) => DropdownMenuItem<String>(
                  value: o.value,
                  child: Text(o.displayName),
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

  Widget _buildSeed(VisionFilterState state, VisionParam param) {
    final value = state.paramValue(param);
    return Row(
      children: [
        Expanded(child: Text('${param.displayName}: $value')),
        TextButton.icon(
          onPressed: () => state.randomizeSeed(param.name),
          icon: const Icon(Icons.casino),
          label: const Text('Randomize'),
        ),
      ],
    );
  }
}
