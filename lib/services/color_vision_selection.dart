import '../models/disability_type.dart';
import '../models/vision_filter_catalog.dart';
import 'filter_service.dart';
import 'vision_filter_state.dart';

/// 色覚のクイック選択（`FilterSelector`・トレイ・起動時の復元）が [FilterService]
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
/// （[FilterSelector]・トレイ・`main.dart` の起動時復元）が呼ばれた**その場で**
/// 両方のサービスを更新する。[FilterSelector]/トレイ以外は呼ばない。
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
    // 「Normal vision」チップを選ぶ／解除するのも「別のフィルタを手動で選ぶ」
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
