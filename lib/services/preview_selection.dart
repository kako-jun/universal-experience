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
double previewStrength(
  VisionFilterState visionState,
  FilterService filterService,
) {
  if (visionState.isColorQuickSelection) {
    return filterService.intensity;
  }
  return visionState.strength;
}

/// advanced カタログの strength スライダー（`FilterParamPanel`）を表示すべきか
/// （#60 M2）。
///
/// 色覚クイック選択が起点の選択では、強度は [previewStrength] が使うとおり
/// `FilterService` のタイプ別記憶（#57）で決まり、[VisionFilterState.strength]
/// は使われない。にもかかわらず `FilterParamPanel` が strength スライダーを
/// 出すと、動かしても実際には何も変わらない（#57 の記憶の方が優先される）
/// スライダーになってしまう。[previewStrength] と対になる判定として、ここに
/// 集約する。
bool showsAdvancedStrengthSlider(VisionFilterState visionState) =>
    !visionState.isColorQuickSelection;
