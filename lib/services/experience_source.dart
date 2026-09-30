import 'package:flutter/foundation.dart';

import '../models/vision_filter_catalog.dart';
import '../src/rust/api/sensus_bridge.dart';

/// 体験プリセットの供給源。既定は sensus bridge の [experiences]。
///
/// FRB の `experiences()` は native lib を要求し `flutter test`（FFI 未ロード）では
/// 呼べないため、widget test はこの seam を fixture で差し替えて検証する。production
/// では bridge の `experiences()` をそのまま消費する（sensus を再実装しない）。
typedef ExperiencesProvider = List<Experience> Function();

/// 体験プリセット供給源（テストで差し替え可能）。既定は bridge の [experiences]。
///
/// production からは既定値（実 bridge）をそのまま使う。差し替えは widget test の
/// fixture 注入専用なので、外部からの書き換えを抑止するため `@visibleForTesting`。
@visibleForTesting
ExperiencesProvider experiencesProvider = experiences;

/// 今表示する体験プリセットの一覧（[experiencesProvider] の現在値）。
///
/// `@visibleForTesting` の [experiencesProvider] を production コードから
/// 直接参照しないための窓口（一覧 `FilterBrowser` はここから読む）。
///
/// 一覧は選択・検索のたびに再構築され、既定の供給源は FFI 呼び出しなので、
/// 結果は供給源の関数ごとに 1 度だけ取得して使い回す。テストが
/// [experiencesProvider] を差し替えると（関数が変わるので）取り直すため、
/// テスト間でキャッシュが漏れない。
List<Experience> availableExperiences() {
  final provider = experiencesProvider;
  final cached = _cachedExperiences;
  if (cached != null && _cachedExperiencesFor == provider) return cached;
  final fresh = provider();
  _cachedExperiencesFor = provider;
  return _cachedExperiences = fresh;
}

ExperiencesProvider? _cachedExperiencesFor;
List<Experience>? _cachedExperiences;

/// 永続化された体験プリセット選択（[presetId] とカタログ id [catalogId] の組、
/// #65）が今も有効か。プリセットが存在し、その体験の視覚フィルタが [catalogId] に
/// 写るときだけ true（sensus の体験一覧が変わっても、古い保存値をプリセット
/// 選択として復元しない）。
bool isValidExperiencePreset(String presetId, String catalogId) {
  for (final exp in availableExperiences()) {
    if (exp.id != presetId) continue;
    final vision = exp.vision;
    return vision != null && visionFilterCatalogId(vision) == catalogId;
  }
  return false;
}
