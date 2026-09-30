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
/// 「医療監修を受けたものではありません」の一文は、どちらを開いていても
/// 閉じていても読めるよう、折りたたみの外（最下段の区切り線の下）に 1 行だけ
/// 常時出す。
///
/// **文言の正本は sensus のメタデータ**（`Filter::citation()` /
/// `Filter::limitations()`、供給源は `vision_filter_metadata.dart`）。sensus は
/// 英文しか返さず、医学的な文言を ue が訳すと誤情報になりうるので、原文のまま
/// 出す（英語以外の UI では、出典・表現できないことのどちらにも「原文をそのまま
/// 表示」と明記し、読み上げの言語も英語にする）。有病率・症状の説明は sensus に
/// 無いので、ここでは扱わない。
///
/// 出典が無い（`citation()` が null か空）フィルタは、無いことをそのまま書く
/// （sensus は出典をでっち上げない方針。「出典なし」は情報である）。表現できない
/// ことが空のときは、書かれていないことを「限界が無い」と読ませないよう、
/// その折りたたみ自体を出さない。
class FilterProvenanceSection extends StatelessWidget {
  const FilterProvenanceSection({
    super.key,
    required this.filter,
    this.filterName,
  });

  /// メタデータを引く対象（payload に依存しないので選択中の実インスタンスでよい）。
  final VisionFilter filter;

  /// 出典・限界がどのフィルタについての情報かを見出しに明示するときの名前。
  /// 体験プリセットは見出しが体験名で、情報は裏の視覚フィルタのものなので、
  /// そのときだけ渡す（フィルタを直接選んだときは見出しと同じなので null）。
  final String? filterName;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final citation = visionFilterCitationProvider(filter);
    final limitations = visionFilterLimitationsProvider(filter);
    final hasLimitations = limitations.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (filterName != null) ...[
          Text(
            l10n.provenanceAboutFilter(filterName!),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
        ],
        const Divider(height: 1),
        _ProvenanceTile(
          tileKey: const Key('provenance-model'),
          title: l10n.provenanceModelHeading,
          sensusText: citation,
          emptyText: l10n.provenanceNoCitation,
        ),
        if (hasLimitations) ...[
          const Divider(height: 1),
          _ProvenanceTile(
            tileKey: const Key('provenance-limitations'),
            title: l10n.provenanceLimitationsHeading,
            sensusText: limitations,
            emptyText: null,
          ),
        ],
        const Divider(height: 1),
        const SizedBox(height: 8),
        Text(
          l10n.provenanceSourceNote,
          key: const Key('provenance-source-note'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
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
  });

  final Key tileKey;
  final String title;

  /// sensus の原文。null か空なら [emptyText] を出す。
  final String? sensusText;
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;
    final isEnglishUi = Localizations.localeOf(context).languageCode == 'en';
    final text = sensusText;
    final hasText = text != null && text.trim().isNotEmpty;
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
        if (hasText)
          _SensusText(text: text, isEnglishUi: isEnglishUi)
        else if (emptyText != null)
          Text(emptyText!, style: theme.textTheme.bodyMedium),
        // 原文は英語。英語以外の UI では出典側にも同じ注記を添える。
        if (hasText && !isEnglishUi)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l10n.provenanceEnglishOriginalNote,
              style: theme.textTheme.bodySmall?.copyWith(color: secondary),
            ),
          ),
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
