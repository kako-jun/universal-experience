import '../models/disability_type.dart';
import '../models/vision_filter_catalog.dart';
import '../models/vision_filter_stage.dart';
import 'filter_service.dart';
import 'vision_filter_state.dart';
import 'vision_layer.dart';

/// 色覚のクイック選択（`FilterBrowser`・トレイ・起動時の復元）が [FilterService]
/// と [VisionFilterState] の両方を更新する、唯一の入口（#60）。
///
/// 以前は home_screen.dart が [FilterService] の変化を listener で
/// [VisionFilterState] へミラーしていたが、`didChangeDependencies` が最初の
/// build 中に動くため postFrameCallback で遅延させる必要があり、さらに
/// 「[FilterService.currentFilter] が変わったときだけ」という差分検知
/// （`_syncedColorType`）のせいで、advanced/プリセットを経由したあとに同じ
/// 色覚型のチップを再タップしても [VisionFilterState] へ反映されない
/// （型そのものは変わっていないため）という穴があった。
///
/// この関数はミラー（listener による後追い反映）をやめ、色覚を選ぶ操作
/// （[FilterBrowser]・トレイ・`main.dart` の起動時復元）が呼ばれた**その場で**
/// 両方のサービスを更新する。[FilterBrowser]/トレイ以外は呼ばない。
///
/// [type] が [ColorVisionType.none] の場合は [deactivateColorVision] と同じ
/// 効果になる（色覚クイック選択を解除する）。
void selectColorVision(
  FilterService filterService,
  VisionFilterState visionState,
  ColorVisionType type,
) {
  filterService.applyFilter(type);
  if (type == ColorVisionType.none) {
    // 一覧の「正常色覚」行を選ぶ／解除するのも「別のフィルタを手動で選ぶ」
    // 操作の一種として扱う。advanced/プリセットを見ている最中でも上書きする
    // （protanopia 等を選ぶ場合と同じ規約）。
    visionState.selectColorVisionType(ColorVisionType.none);
    return;
  }
  final filter = visionFilterForColorVisionType(type);
  // type != ColorVisionType.none なので filter は必ず非 null（対応表の契約）。
  final catalogId = visionFilterCatalogId(filter!);
  if (catalogId == null) {
    // カタログの色覚 5 種は payload を持たない固定インスタンスとして
    // 登録されているため、ColorVisionType から解決した filter は必ず
    // catalogId を持つはず（filter_catalog_test.dart が保証）。ここに来るのは
    // カタログとの不整合というプログラミングエラーなので、静かに無視せず
    // 早期に気付けるようにする。
    throw StateError('No catalog id for color vision filter: $filter');
  }
  visionState.selectColorVisionType(type, catalogId);
}

/// 色覚のクイック選択を解除する（#60）。[selectColorVision] に
/// [ColorVisionType.none] を渡すのと同じ。
void deactivateColorVision(
  FilterService filterService,
  VisionFilterState visionState,
) {
  selectColorVision(filterService, visionState, ColorVisionType.none);
}

/// 色覚のクイック選択を**多選択の足し引き**（[VisionFilterState.toggle]）で行う入口（#120）。
///
/// 統合一覧の色覚の行（排他のラジオ式）が呼ぶ。[selectColorVision] が「層を全部その 1 つに
/// 置き換える」のに対し、こちらは他のフィルタの層を残したまま、色覚の層だけを足す・外す・
/// 別の色覚へ置き換える。呼んだあと [FilterService] を層の集合へ合わせる
/// （[syncFilterServiceWithLayers]）ので、`settings.filterType` ・トレイ・色覚の強度の記憶の
/// 読み口とずれない。[type] が [ColorVisionType.none] のときは色覚層を外す
/// （外したなら [VisionLayerResult.removed]、色覚層が無ければ何もせず
/// [VisionLayerResult.unchanged]）。
VisionLayerResult toggleColorVision(
  FilterService filterService,
  VisionFilterState visionState,
  ColorVisionType type,
) {
  if (type == ColorVisionType.none) {
    final colorLayerIds = [
      for (final layer in visionState.layers)
        if (isVisionColorGroupId(layer.id)) layer.id,
    ];
    for (final id in colorLayerIds) {
      visionState.remove(id);
    }
    syncFilterServiceWithLayers(filterService, visionState);
    return colorLayerIds.isEmpty
        ? VisionLayerResult.unchanged
        : VisionLayerResult.removed;
  }
  final catalogId =
      visionFilterCatalogId(visionFilterForColorVisionType(type)!);
  if (catalogId == null) {
    throw StateError('No catalog id for color vision type: $type');
  }
  final result = visionState.toggle(
    catalogId,
    variantId: kVisionVariantIds.contains(type.name) ? type.name : null,
    origin: VisionLayerOrigin.quick,
  );
  syncFilterServiceWithLayers(filterService, visionState);
  return result;
}

/// 体験プリセットを選ぶ入口（#120）。[VisionFilterState.selectPreset] は層の集合をそのプリセット
/// 単体へ置き換えるので、色覚クイック選択の層は無くなる。呼んだあと [FilterService] を層の集合へ
/// 合わせる（[syncFilterServiceWithLayers]）ので、`settings.filterType`・トレイに「いま無い色覚」が
/// 残らない。
void selectExperiencePreset(
  FilterService filterService,
  VisionFilterState visionState,
  String presetId,
  String catalogId,
) {
  visionState.selectPreset(presetId, catalogId);
  syncFilterServiceWithLayers(filterService, visionState);
}

/// [FilterService] の色覚型（`currentFilter`）を、[visionState] の層の集合に合わせる（#120）。
///
/// 色覚クイック選択（origin が quick）の層があればその型、無ければ none。色覚グループは
/// 同時に 1 層なので、対象は高々 1 つ。advanced・体験プリセット由来の色覚層は、従来どおり
/// `FilterService` の対象にしない（そこは `origin` が分ける）。
void syncFilterServiceWithLayers(
  FilterService filterService,
  VisionFilterState visionState,
) {
  var type = ColorVisionType.none;
  for (final layer in visionState.layers) {
    if (layer.origin != VisionLayerOrigin.quick) continue;
    final t = colorVisionTypeByName(layer.strengthKey);
    if (t != null) {
      type = t;
      break;
    }
  }
  if (filterService.currentFilter != type) filterService.applyFilter(type);
}
