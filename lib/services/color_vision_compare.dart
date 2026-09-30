import '../models/disability_type.dart';
import '../models/vision_filter_catalog.dart';
import '../src/rust/api/sensus_bridge.dart';
import 'export_layers.dart';
import 'filter_service.dart' show visionFilterForColorVisionType;
import 'vision_filter_state.dart';
import 'vision_layer.dart';

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

/// 層の集合 [layers] に含まれる色覚層（2×2 比較の切替を出す条件、#122）。無ければ null。
///
/// 色覚のクイック選択（-omaly を含む）・advanced カタログ・体験プリセットの
/// どの経路で選んだ色覚でも同じ判定になるよう、層の起源ではなくカタログの
/// カテゴリだけを見る（四色覚も色覚層）。色覚は排他なので高々 1 つ。
/// フォーカス中の層ではなく層の集合で見るので、他の層を調整中でも色覚層があれば返す。
VisionLayer? colorVisionLayerOf(Iterable<VisionLayer> layers) {
  for (final layer in layers) {
    if (kVisionFilterCatalogById[layer.id]?.category ==
        VisionFilterCategory.colorVision) {
      return layer;
    }
  }
  return null;
}

/// 2×2 比較（`ColorVisionCompareView`）に渡す入力（#122）。
///
/// 4 枚は「色覚以外の層を 1 回だけ適用した画像」（土台）を共通の出発点にして、その上に
/// 色覚 4 型を 1 枚ずつ [strength] で適用する。色覚は適用順の最終段なので、色覚以外の層は
/// すべて色覚より前に適用される層で、土台の合成は他の層の数によらず 1 回で済む。
class ColorVisionCompareInput {
  const ColorVisionCompareInput({
    required this.strength,
    this.baseSteps = const [],
    this.baseLayers = const [],
  });

  /// 4 セル共通の強さ 0.0..1.0。色覚層の強度（原画比較中は 0）。
  final double strength;

  /// 土台の合成に渡すステップ列（適用順。強度 0 の層は除く。`VisionFilterState.pipelineSteps`
  /// と同じ基準）。空なら土台 = 原画。
  final List<VisionStep> baseSteps;

  /// [baseSteps] と同じ層の控え（同じ順・同じ数）。書き出しのキャプション・ファイル名の素
  /// （層の名前・強度・受診喚起）になる。
  final List<ExportLayer> baseLayers;
}

/// 2×2 比較の入力を、現在の層の集合 [state] から作る。色覚層が 0 なら null
/// （スイッチも 2×2 も出さない）。
///
/// 原画比較中（[VisionFilterState.bypassed]）は強度 0・土台なし（= 原画）にする
/// （プレビューの `previewPipelineSteps` と同じ。選択・強度の記憶は変えない）。
ColorVisionCompareInput? colorVisionCompareInputOf(VisionFilterState state) {
  final colorLayer = colorVisionLayerOf(state.layers);
  if (colorLayer == null) return null;
  if (state.bypassed) return const ColorVisionCompareInput(strength: 0);
  final base = <ExportLayer>[];
  for (final layer in state.layers) {
    if (identical(layer, colorLayer)) continue;
    final strength = state.strengthOf(layer);
    if (strength <= 0) continue;
    base.add(ExportLayer(
      layer: layer,
      filter: state.buildLayer(layer),
      strength: strength,
    ));
  }
  return ColorVisionCompareInput(
    strength: state.strengthOf(colorLayer),
    baseSteps: [
      for (final l in base) VisionStep(filter: l.filter, strength: l.strength),
    ],
    baseLayers: base,
  );
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
