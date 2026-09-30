import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';

import '../l10n/app_localizations.dart';
import '../l10n/l10n_extensions.dart';
import '../models/disability_type.dart';
import '../models/vision_filter_catalog.dart';
import 'color_vision_selection.dart';
import 'filter_service.dart';
import 'vision_filter_state.dart';
import 'vision_layer.dart';

/// 統合フィルタ一覧（#72）の 1 行。色覚 7 型と advanced 30 フィルタを**同じ
/// 一覧**に並べるための純粋なデータ（Widget もサービスの状態も持たない）。
///
/// 一覧は 33 行になる: advanced カタログ 30 件 + 色覚クイック選択にしか無い
/// 3 型（protanomaly / deuteranomaly / tritanomaly）。色覚 4 型（protanopia /
/// deuteranopia / tritanopia / achromatopsia）はカタログにも同名の行があるが、
/// 一覧では 1 行にまとめ、選ぶと従来どおり色覚クイック選択の入口
/// （[selectColorVision]。強度は `VisionFilterState` のキーごとの記憶、#117）を通る。
/// カタログだけにあるもの（tetrachromacy 等）は `VisionFilterState.select`。
/// **書き込みの入口は変えない**（`VisionFilterState` が唯一の正本のまま）。
@immutable
class FilterListEntry {
  const FilterListEntry({
    required this.key,
    required this.category,
    required this.catalogId,
    this.colorVisionType,
  });

  /// 一覧内で一意な安定キー（テストの `Key` にも使う）。
  final String key;

  /// 所属カテゴリ（カテゴリ切替の絞り込み条件）。
  final VisionFilterCategory category;

  /// 対応するカタログ id（-omaly は base の -opia と同じ id に写る）。
  final String catalogId;

  /// 色覚クイック選択で選ぶ行なら、その [ColorVisionType]。advanced だけの行は null。
  final ColorVisionType? colorVisionType;

  @override
  bool operator ==(Object other) =>
      other is FilterListEntry && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// 統合一覧の全行（カテゴリ順・カテゴリ内はカタログ順。色覚は各 -opia の直後に
/// 対応する -omaly を置く）。
final List<FilterListEntry> kFilterListEntries = _buildEntries();

List<FilterListEntry> _buildEntries() {
  // ColorVisionType → そのカタログ id。none 以外の 7 型が対象。
  final Map<ColorVisionType, String> catalogIdByType = {
    for (final type in ColorVisionType.values)
      if (type != ColorVisionType.none)
        type: visionFilterCatalogId(visionFilterForColorVisionType(type)!)!,
  };
  // カタログ id → 「base の -opia」（id と型名が同じもの）。
  final Map<String, ColorVisionType> baseTypeByCatalogId = {
    for (final e in catalogIdByType.entries)
      if (e.key.id == e.value) e.value: e.key,
  };

  final entries = <FilterListEntry>[];
  for (final category in VisionFilterCategory.values) {
    for (final catalogEntry in visionFilterEntriesByCategory(category)) {
      final baseType = baseTypeByCatalogId[catalogEntry.id];
      entries.add(FilterListEntry(
        key: baseType != null
            ? 'cv:${baseType.id}'
            : 'catalog:${catalogEntry.id}',
        category: category,
        catalogId: catalogEntry.id,
        colorVisionType: baseType,
      ));
      // この base 型の -omaly を直後に置く。
      for (final e in catalogIdByType.entries) {
        if (e.value == catalogEntry.id && e.key.id != e.value) {
          entries.add(FilterListEntry(
            key: 'cv:${e.key.id}',
            category: category,
            catalogId: e.value,
            colorVisionType: e.key,
          ));
        }
      }
    }
  }
  return List.unmodifiable(entries);
}

/// [entry] の表示名を [l10n] で解決する。色覚クイック選択の行は
/// [colorVisionTypeName]（-omaly を区別するため）、それ以外は [visionFilterName]。
String filterListEntryName(AppLocalizations l10n, FilterListEntry entry) {
  final type = entry.colorVisionType;
  return type != null
      ? colorVisionTypeName(l10n, type)
      : visionFilterName(l10n, entry.catalogId);
}

final AppLocalizations _ja = lookupAppLocalizations(const Locale('ja'));
final AppLocalizations _en = lookupAppLocalizations(const Locale('en'));

/// 検索の正規化: 小文字化・空白と `-` `_` `・` の除去・カタカナ→ひらがな。
///
/// 「プロタノピア」「ぷろたのぴあ」「Protanopia」「protan opia」が同じ
/// 検索語で当たるようにする。
String normalizeFilterSearchText(String text) {
  final buffer = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    if (rune == 0x20 ||
        rune == 0x3000 ||
        rune == 0x2d ||
        rune == 0x5f ||
        rune == 0x30fb ||
        rune == 0x2f) {
      continue;
    }
    // カタカナ（ァ..ヶ）→ ひらがな。
    if (rune >= 0x30a1 && rune <= 0x30f6) {
      buffer.writeCharCode(rune - 0x60);
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// [query] が空か（空白だけを含む）。
bool isBlankFilterQuery(String query) =>
    normalizeFilterSearchText(query).isEmpty;

/// 文字列群のどれかが [query] を含むか。ja・en 両方の名前を検索対象にする
/// ため、呼び出し側が [texts] に両言語の名前を渡す。
bool matchesFilterQuery(Iterable<String> texts, String query) {
  final needle = normalizeFilterSearchText(query);
  if (needle.isEmpty) return true;
  return texts.any((t) => normalizeFilterSearchText(t).contains(needle));
}

/// [entry] を検索する対象の文字列（ja 名・en 名・catalog id / 型 id）。
List<String> filterListEntrySearchTexts(FilterListEntry entry) => [
      filterListEntryName(_ja, entry),
      filterListEntryName(_en, entry),
      entry.catalogId,
      if (entry.colorVisionType != null) entry.colorVisionType!.id,
    ];

/// 体験プリセット [experienceId] が検索語 [query] に当たるか（ja・en 名と id）。
/// 空の検索語は常に true。
bool experienceMatchesQuery(String experienceId, String query) =>
    matchesFilterQuery([
      experienceName(_ja, experienceId),
      experienceName(_en, experienceId),
      experienceId,
    ], query);

/// [query]（インクリメンタル検索）と [category] で [kFilterListEntries] を絞る。
///
/// 検索語があるときはカテゴリを無視して**全体**から探す（別カテゴリの見え方を
/// 名前で探しても 0 件にならないように）。検索語が空なら [category]（null = すべて）
/// だけで絞る。
List<FilterListEntry> visibleFilterListEntries({
  String query = '',
  VisionFilterCategory? category,
}) {
  if (!isBlankFilterQuery(query)) {
    return [
      for (final e in kFilterListEntries)
        if (matchesFilterQuery(filterListEntrySearchTexts(e), query)) e,
    ];
  }
  return [
    for (final e in kFilterListEntries)
      if (category == null || e.category == category) e,
  ];
}

/// フォーカス中の層に対応する一覧の行（単一選択の見方）。体験プリセット選択中・未選択なら null。
/// トレイ（#121）とメイン画面の一覧のチェックは、これではなく層の集合から決める
/// （[layerForFilterListEntry]）。
///
/// 色覚クイック選択なら [VisionFilterState.colorVisionType] の行、それ以外
/// （advanced）は選択中カタログ id の行。プリセット由来の選択は一覧の行では
/// なく体験プリセットの行が点灯する（[VisionFilterState.selectedPresetId]）。
FilterListEntry? selectedFilterListEntry(VisionFilterState visionState) {
  if (visionState.selectedPresetId != null) return null;
  final id = visionState.selectedId;
  if (id == null) return null;
  if (visionState.isColorQuickSelection) {
    final type = visionState.colorVisionType;
    for (final e in kFilterListEntries) {
      if (e.colorVisionType != null && e.colorVisionType == type) return e;
    }
    return null;
  }
  // advanced 由来（色覚 base 型を `select(id)` で直接選んだ場合も、同じ
  // カタログ id の行を点灯させる）。
  for (final e in kFilterListEntries) {
    if (e.catalogId == id &&
        (e.colorVisionType == null || e.colorVisionType!.id == id)) {
      return e;
    }
  }
  return null;
}

/// ↑↓（#63）で [visible]（今見えている一覧）を順送り/逆送りしたときの次の行。
/// [current] が一覧に無い（未選択・絞り込みで消えた・プリセット選択中）なら、
/// 順送りは先頭・逆送りは末尾に入る。末尾の次は先頭へ折り返す。
/// [visible] が空なら null。
FilterListEntry? nextFilterListEntry(
  List<FilterListEntry> visible,
  FilterListEntry? current, {
  required bool forward,
}) {
  if (visible.isEmpty) return null;
  final index = current == null ? -1 : visible.indexOf(current);
  if (index == -1) return forward ? visible.first : visible.last;
  final next = forward ? index + 1 : index - 1;
  return visible[(next + visible.length) % visible.length];
}

// ── 多選択（#120）──
//
// 統合一覧の行は、単一選択の「今の 1 行」（[selectedFilterListEntry]）ではなく
// **層の集合**と対応づける。チェックされている行 = 層がある行、番号バッジ = 適用順。

/// [entry] が色覚グループ（排他のラジオ式）の行か。
bool isExclusiveFilterListEntry(FilterListEntry entry) =>
    entry.category == VisionFilterCategory.colorVision;

/// [entry] の層の別名（-omaly の別名 id）。別名でなければ null。
String? filterListEntryVariantId(FilterListEntry entry) {
  final type = entry.colorVisionType;
  return type != null && kVisionVariantIds.contains(type.name)
      ? type.name
      : null;
}

/// [layer] が一覧の行 [entry] に当たるか（カタログ id と別名が同じ）。origin は問わない
/// （体験プリセットや advanced で足した色覚の層も、同じ行にチェックが付く）。
bool filterListEntryMatchesLayer(FilterListEntry entry, VisionLayer layer) =>
    layer.id == entry.catalogId &&
    layer.variantId == filterListEntryVariantId(entry);

/// 一覧の行 [entry] にチェックが付いている層。無ければ null。
VisionLayer? layerForFilterListEntry(
  VisionFilterState visionState,
  FilterListEntry entry,
) {
  for (final layer in visionState.layers) {
    if (filterListEntryMatchesLayer(entry, layer)) return layer;
  }
  return null;
}

/// 層 [layer] に対応する一覧の行。対応する行が無ければ null。
FilterListEntry? filterListEntryForLayer(VisionLayer layer) {
  for (final e in kFilterListEntries) {
    if (filterListEntryMatchesLayer(e, layer)) return e;
  }
  return null;
}

/// [entry] の適用順の番号（1 始まり）。チェックが付いていなければ null。層は段順に並んで
/// いるので、番号 = [VisionFilterState.layers] の位置 + 1（チップ帯の並びと同じ）。
int? filterListEntryOrder(
    VisionFilterState visionState, FilterListEntry entry) {
  final layers = visionState.layers;
  for (var i = 0; i < layers.length; i++) {
    if (filterListEntryMatchesLayer(entry, layers[i])) return i + 1;
  }
  return null;
}

/// 未チェックの行 [entry] をいま選べない理由。選べる・すでにチェック済みなら null。
/// 色覚グループの行は、色覚の層があれば置き換えになるので上限でも選べる。
VisionLayerBlockReason? filterListEntryBlockReason(
  VisionFilterState visionState,
  FilterListEntry entry,
) {
  if (layerForFilterListEntry(visionState, entry) != null) return null;
  return visionState.blockReasonFor(entry.catalogId);
}

/// 一覧の行 [entry] を**足し引き**する（多選択の入口、#120）。チェック済みなら外し、未
/// チェックなら足す（色覚は既存の色覚層と置き換え）。上限で足せなければ何もしない。
/// どの行でも、呼んだあと `FilterService` を層の集合へ合わせる（tetrachromacy のような
/// カタログ側の色覚グループの行が、クイック選択の色覚層を置き換えることがあるため）。
VisionLayerResult toggleFilterListEntry(
  FilterService filterService,
  VisionFilterState visionState,
  FilterListEntry entry,
) {
  final type = entry.colorVisionType;
  if (type != null) return toggleColorVision(filterService, visionState, type);
  final result = visionState.toggle(entry.catalogId);
  syncFilterServiceWithLayers(filterService, visionState);
  return result;
}
