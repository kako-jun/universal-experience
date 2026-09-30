import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../src/rust/api/sensus_bridge.dart';

/// [ConsultNotice] の表示ウィジェット（#76）。
///
/// 右カラム「調整」（`FilterParamPanel`、#72）が、advanced カタログ・体験
/// プリセットのどちらを選んでいても使う、受診喚起の唯一の表示ウィジェット。
/// PNG export（`export_service.dart`）と同じ解決経路（[resolveConsultNotice]）を
/// 共有する。常時展開で、折りたたまない・隠さない。
///
/// - 段階名（旧「緊急度：高」のような表示）は一切出さない。喚起文
///   （[ConsultNotice.message]）だけを、本文サイズ以上で表示する。emergency は
///   [TextTheme.bodyLarge]（w600）で目立たせる（#76。
///   プリセットカードのタイトル titleMedium とサイズがぶつからないよう
///   bodyLarge にした）。
/// - 色は [ColorScheme] のロールのみ使う（urgency に応じて
///   [ColorScheme.tertiaryContainer] / [ColorScheme.errorContainer]。
///   [Urgency.none] だが escalation が非空のフィルタは中立の
///   [ColorScheme.surfaceContainerHighest]）。
/// - escalation は emergency → earlyConsultation の順で見出しを分けて表示する
///   （#76。現状 vision フィルタの escalation は全て
///   earlyConsultation だが、聴覚側（#80）は emergency も持つため備えておく。
///   段ごとの構成は [ConsultNotice.escalationGroups]（[resolveConsultNotice]）
///   が組み立て済みで、PNG export もこれをそのまま使う）。
/// - 免責文（医療監修を受けていない旨・sensus の Medical notes への参照）は
///   既定で表示する。[showDisclaimer] を false にすると省略できる
///   （免責文だけを別の場所に出したいとき用。[ConsultDisclaimerFooter]）。
class ConsultNoticeBlock extends StatelessWidget {
  const ConsultNoticeBlock({
    super.key,
    required this.notice,
    required this.l10n,
    this.showDisclaimer = true,
  });

  final ConsultNotice notice;
  final AppLocalizations l10n;

  /// false のとき、免責文・根拠 URL を表示しない。
  final bool showDisclaimer;

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
    // emergency は本文（bodyMedium, 14px）より大きい bodyLarge（16px）で
    // 目立たせる。titleMedium（16px、プリセットカードのタイトルと同じスタイル）
    // は使わない — カードの中で喚起文がタイトルと同格に見えてしまうため。
    final messageStyle =
        (notice.urgency == Urgency.emergency ? theme.textTheme.bodyLarge : theme.textTheme.bodyMedium)
            ?.copyWith(color: foreground, fontWeight: FontWeight.w600);

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
          for (final group in notice.escalationGroups) ...[
            if (notice.message != null || group != notice.escalationGroups.first)
              const SizedBox(height: 8),
            _EscalationGroup(
              header: group.header,
              lines: group.lines,
              style: bodyStyle,
            ),
          ],
          if (showDisclaimer) ...[
            const SizedBox(height: 8),
            ConsultDisclaimerFooter(
              disclaimer: notice.disclaimer,
              citationUrl: notice.citationUrl,
              color: foreground,
            ),
          ],
        ],
      ),
    );
  }
}

/// 免責文 + 根拠 URL だけの独立したフッタ。
///
/// 免責文だけを、urgency に紐づく着色コンテナの外に出したいときに使う。
/// [ConsultNoticeBlock]（`showDisclaimer: true` のとき）も同じ見た目を使う。
class ConsultDisclaimerFooter extends StatelessWidget {
  const ConsultDisclaimerFooter({
    super.key,
    required this.disclaimer,
    required this.citationUrl,
    this.color,
  });

  /// 免責文（`ConsultNotice.disclaimer`、通常は `l10n.consultDisclaimer`）。
  final String disclaimer;

  /// 免責文が参照する根拠への URL。
  final Uri citationUrl;

  /// 文字色。null なら [ColorScheme.onSurfaceVariant]（セクション末尾など、
  /// urgency に紐づく着色コンテナの外で使うとき）。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor = color ?? theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          disclaimer,
          // イタリックは使わない（DESIGN §3: 日本語の長文では崩れて読みにくい）。
          // 本文（w400）と区別しつつ目立たせすぎない w500 にする。
          style: theme.textTheme.bodyMedium?.copyWith(
            color: effectiveColor,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(
          citationUrl.toString(),
          style: theme.textTheme.bodySmall?.copyWith(
            color: effectiveColor,
            decoration: TextDecoration.underline,
          ),
        ),
      ],
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
