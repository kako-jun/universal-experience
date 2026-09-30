import '../models/disability_type.dart';
import '../models/vision_filter_catalog.dart';
import '../models/vision_filter_stage.dart';
import 'filter_service.dart' show visionFilterForColorVisionType;

/// レイヤーの選択の起源。
///
/// [quick] は色覚クイック選択（`FilterBrowser`/トレイ、[selectColorVision] 経由）、
/// [advanced] は advanced カタログ・体験プリセット・復元。かつて state 全体が持っていた
/// `isColorQuickSelection` は、レイヤーごとのこの値に置き換わった（ADR）。
enum VisionLayerOrigin { quick, advanced }

/// 重ねる 1 枚のフィルタ層。カタログ id ごとに高々 1 つ。
///
/// **強度は持たない**。強度は「キーごとの記憶」（[VisionFilterState] の
/// `strengthByKey`、キーは [strengthKey]）に 1 つだけあり、層の強度は読むときに
/// そこから導出する。同じ色覚を quick でも advanced でも選んだときに強度が二重に
/// ならないようにするため。
class VisionLayer {
  VisionLayer({
    required this.id,
    Map<String, Object> params = const {},
    this.variantId,
    this.origin = VisionLayerOrigin.advanced,
  }) : params = Map.unmodifiable(params);

  /// カタログ id（snake_case）。
  final String id;

  /// payload パラメータ（seed は [BigInt]）。読み取り専用。
  final Map<String, Object> params;

  /// 別名の id。-omaly（protanomaly 等）は対応する -opia と同じカタログ id に写る
  /// ので、どちらを選んだかをここで区別する（例: id=protanopia, variantId=protanomaly）。
  /// 別名でなければ null。
  final String? variantId;

  final VisionLayerOrigin origin;

  /// 強度の記憶のキー。別名があればそれ、無ければカタログ id。
  String get strengthKey => variantId ?? id;

  VisionLayer copyWith({
    Map<String, Object>? params,
    VisionLayerOrigin? origin,
  }) =>
      VisionLayer(
        id: id,
        params: params ?? this.params,
        variantId: variantId,
        origin: origin ?? this.origin,
      );

  @override
  String toString() =>
      'VisionLayer($id${variantId == null ? '' : '/$variantId'}, $origin)';
}

/// -omaly の別名 id 一覧（[ColorVisionType.name]）。
const List<String> kVisionVariantIds = [
  'protanomaly',
  'deuteranomaly',
  'tritanomaly',
];

/// 強度の記憶のキーとして有効な文字列か（カタログ id か -omaly の別名 id）。
bool isValidStrengthKey(String key) =>
    kVisionFilterCatalogById.containsKey(key) ||
    kVisionVariantIds.contains(key);

/// [variantId] が [id] の正しい別名か（protanomaly は protanopia にだけ付く）。
bool isValidVariantFor(String id, String variantId) {
  final type = colorVisionTypeByName(variantId);
  if (type == null || !kVisionVariantIds.contains(variantId)) return false;
  return visionFilterForColorVisionTypeCatalogId(type) == id;
}

/// [ColorVisionType.name] から型を引く。none は含めない。
ColorVisionType? colorVisionTypeByName(String name) {
  for (final t in ColorVisionType.values) {
    if (t != ColorVisionType.none && t.name == name) return t;
  }
  return null;
}

/// 色覚型 → カタログ id。none は null。
String? visionFilterForColorVisionTypeCatalogId(ColorVisionType type) {
  final filter = visionFilterForColorVisionType(type);
  return filter == null ? null : visionFilterCatalogId(filter);
}

/// 色覚クイック選択の層。-omaly は [VisionLayer.variantId] を持つ。
/// none は層を作らない（null）。
VisionLayer? quickColorVisionLayer(ColorVisionType type) {
  final id = visionFilterForColorVisionTypeCatalogId(type);
  if (id == null) return null;
  return VisionLayer(
    id: id,
    variantId: kVisionVariantIds.contains(type.name) ? type.name : null,
    origin: VisionLayerOrigin.quick,
  );
}

/// レイヤーが quick 層のときの色覚型（`variantId ?? id` から）。quick でなければ null。
ColorVisionType? quickColorVisionTypeOf(VisionLayer layer) {
  if (layer.origin != VisionLayerOrigin.quick) return null;
  return colorVisionTypeByName(layer.strengthKey);
}

/// 層の列を不変条件に合わせて整える（純粋関数）。
///
/// - 未知のカタログ id の層は捨てる。
/// - 同じ id の重複は**先に現れたもの**を残す。
/// - 色覚グループ（[isVisionColorGroupId]）は排他: 先に現れた 1 つだけ残す。
/// - 上限 [kMaxVisionLayers] を超える分は、先に現れたものを残して捨てる。
/// - 結果は適用順（段 → 段内の宣言順）に並べ替える。
///
/// 「先に現れた」は入力列の順。保存された列は適用順なので、復元では適用順で
/// 先のものが残る。
List<VisionLayer> normalizeVisionLayers(Iterable<VisionLayer> layers) {
  final seen = <String>{};
  var hasColorGroup = false;
  final kept = <VisionLayer>[];
  for (final layer in layers) {
    if (visionFilterApplyOrder(layer.id) == null) continue;
    if (!seen.add(layer.id)) continue;
    if (isVisionColorGroupId(layer.id)) {
      if (hasColorGroup) continue;
      hasColorGroup = true;
    }
    if (kept.length >= kMaxVisionLayers) continue;
    kept.add(layer);
  }
  kept.sort(
    (a, b) =>
        visionFilterApplyOrder(a.id)!.compareTo(visionFilterApplyOrder(b.id)!),
  );
  return List.unmodifiable(kept);
}
