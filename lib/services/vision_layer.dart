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

/// 多選択の操作（[VisionFilterState.toggle]）が層の集合に何をしたか。
enum VisionLayerChange {
  /// 層を 1 つ足した。
  added,

  /// 選択済みの層を外した。
  removed,

  /// 色覚グループの既存の層を別の色覚に置き換えた（層数は増えない）。
  replaced,

  /// 上限のため何もしなかった（状態は変わらない。理由は [VisionLayerResult.blockedBy]）。
  blocked,

  /// 外す対象が無く、何もしなかった（例: 色覚の層が無いときの「色覚を外す」）。
  unchanged,
}

/// 未選択の層を足せない理由（UI が行を無効化するときの文言の出どころ）。
enum VisionLayerBlockReason {
  /// 層の数が上限 [kMaxVisionLayers] に達している。
  layerLimit,
}

/// [VisionFilterState.toggle] の結果。[change] が [VisionLayerChange.blocked] のとき
/// だけ [blockedBy] が非 null。blocked と [VisionLayerChange.unchanged] は、その操作が
/// 状態を変えていない（no-op）。
class VisionLayerResult {
  const VisionLayerResult._(this.change, this.blockedBy);

  const VisionLayerResult.blocked(VisionLayerBlockReason reason)
    : this._(VisionLayerChange.blocked, reason);

  static const added = VisionLayerResult._(VisionLayerChange.added, null);
  static const removed = VisionLayerResult._(VisionLayerChange.removed, null);
  static const replaced = VisionLayerResult._(VisionLayerChange.replaced, null);
  static const unchanged =
      VisionLayerResult._(VisionLayerChange.unchanged, null);

  final VisionLayerChange change;

  /// [change] が blocked のときの理由。それ以外は null。
  final VisionLayerBlockReason? blockedBy;

  /// 状態が変わったか（blocked でも unchanged でもなければ true）。
  bool get changed =>
      change != VisionLayerChange.blocked &&
      change != VisionLayerChange.unchanged;

  @override
  bool operator ==(Object other) =>
      other is VisionLayerResult &&
      other.change == change &&
      other.blockedBy == blockedBy;

  @override
  int get hashCode => Object.hash(change, blockedBy);

  @override
  String toString() =>
      'VisionLayerResult($change${blockedBy == null ? '' : ', $blockedBy'})';
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
