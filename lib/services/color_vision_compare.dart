import '../models/disability_type.dart';
import '../models/vision_filter_catalog.dart';
import '../src/rust/api/sensus_bridge.dart';
import 'filter_service.dart' show visionFilterForColorVisionType;

/// 色覚 4 型の一覧比較（2×2、#84）で並べる型と、そのフィルタの決め方。
///
/// 並べる型はカタログが正本: 色覚カテゴリのうち、sensus が実際に描き分ける型
/// （[VisionFilterEntry.isExperimental] でないもの。現在は protanopia /
/// deuteranopia / tritanopia / achromatopsia）を **カタログの宣言順** に並べる。
/// id をここに書き並べない（型が増減したらカタログだけを変える）。
/// 実験的な四色覚は「障害ではなく確立したモデルでもない可視化」なので、他の 4 型と
/// 同じ強さで並べて比べる対象にしない。
final List<VisionFilterEntry> kColorVisionCompareEntries = List.unmodifiable([
  for (final e in kVisionFilterCatalog)
    if (e.category == VisionFilterCategory.colorVision && !e.isExperimental) e,
]);

/// 2×2 比較のセルの数（= [kColorVisionCompareEntries] の数）。
int get colorVisionCompareCellCount => kColorVisionCompareEntries.length;

/// 選択中のフィルタ id [selectedId] が色覚カテゴリなら true（2×2 比較の切替を出す条件）。
///
/// 色覚のクイック選択（-omaly を含む）・advanced カタログ・体験プリセットの
/// どの経路で選んだ色覚でも同じ判定になるよう、選択の起源ではなくカタログの
/// カテゴリだけを見る。未選択（null）・未知の id は false。
bool isColorVisionFilterId(String? selectedId) {
  if (selectedId == null) return false;
  return kVisionFilterCatalogById[selectedId]?.category ==
      VisionFilterCategory.colorVision;
}

/// 2×2 比較のセル [entry] を描くフィルタ。
///
/// 色覚クイック選択（`FilterService`）と同じ対応表
/// （[visionFilterForColorVisionType]）を引くので、1 型を単独で選んだときの
/// プレビューと同じフィルタになる。比較用の別フィルタ・別レンダラは持たない。
/// 色覚型に対応しない id は [StateError]（カタログを増やしたときに気付けるよう
/// 黙って別物へ落とさない）。
VisionFilter colorVisionCompareFilter(VisionFilterEntry entry) {
  for (final type in ColorVisionType.values) {
    if (type.id != entry.id) continue;
    final filter = visionFilterForColorVisionType(type);
    if (filter != null) return filter;
  }
  throw StateError('No color-vision filter for catalog id: ${entry.id}');
}
