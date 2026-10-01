import '../src/rust/api/sensus_bridge.dart' show VisionStep;
import 'vision_filter_state.dart';

/// 「今選んでいるフィルタの素の強度」を、bypass に関わらず返す（#79）。
///
/// 強度の正本は [VisionFilterState] のキーごとの記憶 1 つだけ（#117）。色覚
/// クイック選択（`FilterBrowser`/トレイ）も advanced カタログ・体験プリセットも、
/// [VisionFilterState.strength]（フォーカス中の層の強度）を見れば同じ値になる。
/// [previewStrength] はこれに bypass の判定を重ねたもの。原画比較中
/// （[VisionFilterState.bypassed]）でも「今選んでいるフィルタは何%か」を表示し続けたい
/// ルーペ HUD（`loupe_hud.dart`）はこちらを使う。
double selectedStrength(VisionFilterState visionState) => visionState.strength;

/// プレビュー（before/after）に渡す strength を決める、**唯一の判定箇所**（#60）。
///
/// [selectedStrength] に bypass の判定を重ねたもの。
/// [VisionFilterState.bypassed]（#63 ホットキー「押している間だけ原画」、#79 で
/// ルーペ HUD の原画比較ボタンも同じ状態を共有する）が true のときは、選択・
/// 強度の記憶を一切変更せず常に 0.0 を返す（フィルタを完全にバイパスして原画を
/// そのまま見せる。選択状態はそのまま残るので、解除すれば直前と同じ見え方に
/// 戻る）。呼び出し側（`home_screen.dart`）はここを経由するだけでよく、個別に
/// 判定を書かない。
double previewStrength(VisionFilterState visionState) {
  if (visionState.bypassed) return 0.0;
  return selectedStrength(visionState);
}

/// 複数層のプレビュー合成（sensus の `Pipeline`、#118/#119）に渡すステップ列を決める、
/// **唯一の判定箇所**。
///
/// [VisionFilterState.pipelineSteps]（段順・強度 0 の層を除く）に bypass の判定を重ねたもの。
/// 原画比較中（[VisionFilterState.bypassed]）は選択・強度の記憶を変えず常に空（= 原画を
/// そのまま見せる）。層が 1 つ以下のときは従来の単一フィルタの経路（[previewStrength]）を
/// 使うので、呼び出し側は「層が複数のときだけ」これを渡す。
List<VisionStep> previewPipelineSteps(VisionFilterState visionState) {
  if (visionState.bypassed) return const [];
  return visionState.pipelineSteps();
}

/// ←→ (#63 アプリ内ショートカット) の 1 回あたりの強度変化量。
/// 調整パネルの強度スライダー（divisions:20）と同じ 5% 刻み。
const double kKeyboardStrengthStep = 0.05;

/// ←→ で強度を動かす。色覚クイック選択でも advanced/プリセットでも、フォーカス中の
/// 層の強度（キーごとの記憶）を動かす。何も選択されていなければ何もしない。
void adjustPreviewStrength(VisionFilterState visionState, double delta) {
  if (visionState.selectedId == null) return;
  visionState.clearBypass();
  visionState.setStrength((visionState.strength + delta).clamp(0.0, 1.0));
}
