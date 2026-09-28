import '../models/vision_filter_catalog.dart';
import 'filter_service.dart';
import 'vision_filter_state.dart';

/// プレビュー（before/after）に渡す strength を決める、**唯一の判定箇所**（#60）。
///
/// [VisionFilterState] が選択の唯一の正本になった一方、強度の出どころは 2 系統
/// 残っている:
/// - 色覚のクイック選択（`FilterSelector`/トレイ、[FilterService] 経由）は
///   色覚タイプごとの強度の記憶（#57、[FilterService.intensity]）を使う。
/// - advanced カタログ・体験プリセット経由の選択は [VisionFilterState.strength]
///   を使う。
///
/// [VisionFilterState.isColorQuickSelection] が「今の選択がどちらの経路で
/// 行われたか」を保持しているので、それだけを見て分岐する。呼び出し側
/// （`home_screen.dart`）はここを経由するだけでよく、個別に判定を書かない。
///
/// [VisionFilterState.bypassed]（#63 ホットキー「押している間だけ原画」）が
/// true のときは、選択・強度の記憶を一切変更せず常に 0.0 を返す（フィルタを
/// 完全にバイパスして原画をそのまま見せる。選択状態はそのまま残るので、解除
/// すれば直前と同じ見え方に戻る）。
double previewStrength(
  VisionFilterState visionState,
  FilterService filterService,
) {
  if (visionState.bypassed) return 0.0;
  if (visionState.isColorQuickSelection) {
    return filterService.intensity;
  }
  return visionState.strength;
}

/// advanced カタログの strength スライダー（`FilterParamPanel`）を表示すべきか
/// （#60）。
///
/// 色覚クイック選択が起点の選択では、強度は [previewStrength] が使うとおり
/// `FilterService` のタイプ別記憶（#57）で決まり、[VisionFilterState.strength]
/// は使われない。にもかかわらず `FilterParamPanel` が strength スライダーを
/// 出すと、動かしても実際には何も変わらない（#57 の記憶の方が優先される）
/// スライダーになってしまう。[previewStrength] と対になる判定として、ここに
/// 集約する。
bool showsAdvancedStrengthSlider(VisionFilterState visionState) =>
    !visionState.isColorQuickSelection;

/// ←→ (#63 アプリ内ショートカット) の 1 回あたりの強度変化量。
/// IntensitySlider の divisions:20 と同じ 5% 刻み。
const double kKeyboardStrengthStep = 0.05;

/// ←→ で強度を動かす。[previewStrength] と同じ判定（isColorQuickSelection）に従い、
/// 色覚クイック選択なら FilterService の強度を、advanced/プリセットなら
/// VisionFilterState.strength を動かす。何も選択されていなければ何もしない。
void adjustPreviewStrength(
  VisionFilterState visionState,
  FilterService filterService,
  double delta,
) {
  if (visionState.selectedId == null) return;
  if (visionState.isColorQuickSelection) {
    filterService.setIntensity((filterService.intensity + delta).clamp(0.0, 1.0));
  } else {
    visionState.setStrength((visionState.strength + delta).clamp(0.0, 1.0));
  }
}

/// ↑↓ (#63) で advanced カタログ（[kVisionFilterCatalog]、30 件）を順送り/逆送りする。
/// 未選択なら down で先頭、up で末尾に入る（wraparound）。
void cycleAdvancedFilter(VisionFilterState visionState, {required bool forward}) {
  final ids = kVisionFilterCatalog.map((e) => e.id).toList();
  if (ids.isEmpty) return;
  final currentIndex = visionState.isColorQuickSelection
      ? -1 // 色覚クイック選択中は advanced の「選択中」とはみなさず先頭/末尾から始める
      : ids.indexOf(visionState.selectedId ?? '');
  int nextIndex;
  if (currentIndex == -1) {
    nextIndex = forward ? 0 : ids.length - 1;
  } else {
    nextIndex = forward ? currentIndex + 1 : currentIndex - 1;
    if (nextIndex >= ids.length) nextIndex = 0;
    if (nextIndex < 0) nextIndex = ids.length - 1;
  }
  visionState.select(ids[nextIndex]);
}
