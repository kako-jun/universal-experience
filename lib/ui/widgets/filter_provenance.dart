import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart'
    show AttributedString, LocaleStringAttribute;

import '../../l10n/app_localizations.dart';
import '../../services/vision_filter_metadata.dart';
import '../../src/rust/api/sensus_bridge.dart';

/// 選んだフィルタの「モデルと出典」「表現できないこと」（#80）。
///
/// 右カラム「調整」（`AdjustPanel`）の最下段に、折りたたみの 2 行で置く。
/// 受診喚起（強度の下に常時展開、DESIGN §6.2）と違い、これは補足なので
/// 既定では閉じ、強度・パラメータ・受診喚起の位置を動かさない。閉じた行も
/// 48dp 以上の操作領域を持つ。
///
/// **文言の正本は sensus のメタデータ**（`Filter::citation()` /
/// `Filter::limitations()`、供給源は `vision_filter_metadata.dart`）。sensus は
/// 英文しか返さず、医学的な文言を ue が訳すと誤情報になりうるので、原文のまま
/// 出す（英語以外の UI では「原文をそのまま表示」と明記し、読み上げの言語も
/// 英語にする）。有病率・症状の説明は sensus に無いので、ここでは扱わない。
///
/// 出典が無い（`citation()` が null）フィルタは、無いことをそのまま書く
/// （sensus は出典をでっち上げない方針。「出典なし」は情報である）。
class FilterProvenanceSection extends StatelessWidget {
  const FilterProvenanceSection({super.key, required this.filter});

  /// メタデータを引く対象（payload に依存しないので選択中の実インスタンスでよい）。
  final VisionFilter filter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final citation = visionFilterCitationProvider(filter);
    final limitations = visionFilterLimitationsProvider(filter);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1),
        _ProvenanceTile(
          tileKey: const Key('provenance-model'),
          title: l10n.provenanceModelHeading,
          sensusText: citation,
          emptyText: l10n.provenanceNoCitation,
          showEnglishNote: false,
          showSourceNote: true,
        ),
        const Divider(height: 1),
        _ProvenanceTile(
          tileKey: const Key('provenance-limitations'),
          title: l10n.provenanceLimitationsHeading,
          sensusText: limitations,
          emptyText: null,
          showEnglishNote: true,
          showSourceNote: false,
        ),
        const Divider(height: 1),
      ],
    );
  }
}

class _ProvenanceTile extends StatelessWidget {
  const _ProvenanceTile({
    required this.tileKey,
    required this.title,
    required this.sensusText,
    required this.emptyText,
    required this.showEnglishNote,
    required this.showSourceNote,
  });

  final Key tileKey;
  final String title;

  /// sensus の原文。null なら [emptyText] を出す。
  final String? sensusText;
  final String? emptyText;

  /// 英語以外の UI で「原文（英語）をそのまま表示」の注記を添えるか。
  final bool showEnglishNote;

  /// 「sensus のメタデータ・医療監修を受けていない」の注記を添えるか。同じ文が
  /// 2 つ続かないよう、出典（モデルと出典）の側にだけ付ける。
  final bool showSourceNote;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;
    final isEnglishUi = Localizations.localeOf(context).languageCode == 'en';
    final text = sensusText;
    return ExpansionTile(
      key: tileKey,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 12),
      expandedAlignment: Alignment.centerLeft,
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      // 既定の上下の線は、区切りの Divider に任せて消す。
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text(title, style: theme.textTheme.titleSmall),
      children: [
        if (text != null && text.isNotEmpty)
          _SensusText(text: text, isEnglishUi: isEnglishUi)
        else if (emptyText != null)
          Text(emptyText!, style: theme.textTheme.bodyMedium),
        if (text != null && text.isNotEmpty && showEnglishNote && !isEnglishUi)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l10n.provenanceEnglishOriginalNote,
              style: theme.textTheme.bodySmall?.copyWith(color: secondary),
            ),
          ),
        if (showSourceNote) ...[
          const SizedBox(height: 8),
          Text(
            l10n.provenanceSourceNote,
            style: theme.textTheme.bodySmall?.copyWith(color: secondary),
          ),
        ],
      ],
    );
  }
}

/// sensus の英文。DOI などをコピーできるよう選択可能にし、英語以外の UI では
/// スクリーンリーダーに英語として読ませる（`LanguageDialog` の自称名と同じ方式）。
class _SensusText extends StatelessWidget {
  const _SensusText({required this.text, required this.isEnglishUi});

  final String text;
  final bool isEnglishUi;

  @override
  Widget build(BuildContext context) {
    final body = SelectableText(
      text,
      style: Theme.of(context).textTheme.bodyMedium,
    );
    if (isEnglishUi) return body;
    return Semantics(
      attributedLabel: AttributedString(
        text,
        attributes: [
          LocaleStringAttribute(
            locale: const Locale('en'),
            range: TextRange(start: 0, end: text.length),
          ),
        ],
      ),
      child: ExcludeSemantics(child: body),
    );
  }
}
