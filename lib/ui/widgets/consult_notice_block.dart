import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../src/rust/api/sensus_bridge.dart';

/// [ConsultNotice] の表示ウィジェット（#76 レビュー M1）。
///
/// advanced カタログ（`FilterParamPanel`）・体験プリセットのカード
/// （`ExperiencePresets`）が共有する、受診喚起の唯一の表示ウィジェット。
///
/// - 段階名（旧「緊急度：高」のような表示）は一切出さない。喚起文
///   （[ConsultNotice.message]）だけを、本文サイズ以上で表示する。emergency は
///   本文より大きい見出しサイズにして目立たせる（#76 レビュー N5）。
/// - 色は [ColorScheme] のロールのみ使う（urgency に応じて
///   [ColorScheme.tertiaryContainer] / [ColorScheme.errorContainer]。
///   [Urgency.none] だが escalation が非空のフィルタは中立の
///   [ColorScheme.surfaceContainerHighest]）。
/// - escalation は emergency → earlyConsultation の順で見出しを分けて表示する
///   （#76 レビュー N4。現状 vision フィルタの escalation は全て
///   earlyConsultation だが、聴覚側（#80）は emergency も持つため備えておく）。
/// - 末尾に免責文（医療監修を受けていない旨・sensus の Medical notes への
///   参照）を表示し、参照 URL は選択可能なテキストとして示す（#76 レビュー M2）。
class ConsultNoticeBlock extends StatelessWidget {
  const ConsultNoticeBlock({super.key, required this.notice, required this.l10n});

  final ConsultNotice notice;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final Color background;
    final Color foreground;
    switch (notice.urgency) {
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
    // #76 レビュー N5: emergency は本文（bodyMedium, 14px）より大きい見出し
    // サイズ（titleMedium, 16px）で目立たせる。Material3 の既定タイプスケール
    // では titleSmall が bodyMedium と同じ 14px なので、実際にサイズが上がる
    // titleMedium を使う（太さだけでなくサイズそのものを一段上げる）。
    final messageStyle =
        (notice.urgency == Urgency.emergency ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium)
            ?.copyWith(color: foreground, fontWeight: FontWeight.w600);

    final emergencyLines = [
      for (final e in notice.escalations)
        if (e.urgency == Urgency.emergency) e.text,
    ];
    final earlyLines = [
      for (final e in notice.escalations)
        if (e.urgency == Urgency.earlyConsultation) e.text,
    ];

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
          if (notice.message != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  notice.urgency == Urgency.emergency
                      ? Icons.warning_amber_rounded
                      : Icons.medical_information_outlined,
                  size: 18,
                  color: foreground,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(notice.message!, style: messageStyle)),
              ],
            ),
          if (emergencyLines.isNotEmpty) ...[
            if (notice.message != null) const SizedBox(height: 8),
            _EscalationGroup(
              header: l10n.escalationHeaderEmergency,
              lines: emergencyLines,
              style: bodyStyle,
            ),
          ],
          if (earlyLines.isNotEmpty) ...[
            if (notice.message != null || emergencyLines.isNotEmpty)
              const SizedBox(height: 8),
            _EscalationGroup(
              header: l10n.escalationHeaderEarly,
              lines: earlyLines,
              style: bodyStyle,
            ),
          ],
          const SizedBox(height: 8),
          Text(
            notice.disclaimer,
            style: bodyStyle?.copyWith(fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 2),
          SelectableText(
            notice.citationUrl.toString(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: foreground,
              decoration: TextDecoration.underline,
            ),
          ),
        ],
      ),
    );
  }
}

/// escalation 条件の 1 段（見出し + 箇条書き）。
class _EscalationGroup extends StatelessWidget {
  const _EscalationGroup({
    required this.header,
    required this.lines,
    required this.style,
  });

  final String header;
  final List<String> lines;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(header, style: style?.copyWith(fontWeight: FontWeight.w600)),
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('•  $line', style: style),
          ),
      ],
    );
  }
}
