import 'filter_service.dart';
import 'vision_filter_state.dart';

/// 「今選んでいるフィルタの素の強度」を、bypass に関わらず返す（#79）。
/// 強度の出どころは 2 系統ある:
/// - 色覚のクイック選択（`FilterBrowser`/トレイ、[FilterService] 経由）は
///   色覚タイプごとの強度の記憶（#57、[FilterService.intensity]）を使う。
/// - advanced カタログ・体験プリセット経由の選択は [VisionFilterState.strength]
///   を使う。
///
/// [VisionFilterState.isColorQuickSelection] が「今の選択がどちらの経路で
/// 行われたか」を保持しているので、それだけを見て分岐する。[previewStrength]
/// はこれに bypass の判定を重ねたもの。原画比較中（[VisionFilterState.bypassed]）
/// でも「今選んでいるフィルタは何%か」を表示し続けたいルーペ HUD
/// （`loupe_hud.dart`）はこちらを使う。
double selectedStrength(
  VisionFilterState visionState,
  FilterService filterService,
) {
  if (visionState.isColorQuickSelection) {
    return filterService.intensity;
  }
  return visionState.strength;
}

/// プレビュー（before/after）に渡す strength を決める、**唯一の判定箇所**（#60）。
///
/// [selectedStrength] に bypass の判定を重ねたもの。
/// [VisionFilterState.bypassed]（#63 ホットキー「押している間だけ原画」、#79 で
/// ルーペ HUD の原画比較ボタンも同じ状態を共有する）が true のときは、選択・
/// 強度の記憶を一切変更せず常に 0.0 を返す（フィルタを完全にバイパスして原画を
/// そのまま見せる。選択状態はそのまま残るので、解除すれば直前と同じ見え方に
/// 戻る）。呼び出し側（`home_screen.dart`）はここを経由するだけでよく、個別に
/// 判定を書かない。
double previewStrength(
  VisionFilterState visionState,
  FilterService filterService,
) {
  if (visionState.bypassed) return 0.0;
  return selectedStrength(visionState, filterService);
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
  visionState.clearBypass();
  if (visionState.isColorQuickSelection) {
    filterService
        .setIntensity((filterService.intensity + delta).clamp(0.0, 1.0));
  } else {
    visionState.setStrength((visionState.strength + delta).clamp(0.0, 1.0));
  }
}
