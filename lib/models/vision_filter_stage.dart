import 'vision_filter_catalog.dart';

/// 複数フィルタを重ねて適用するときの「段（stage）」。適用順は段で決め、利用者が
/// 選んだ順には依存させない（ADR `docs/adr/2026-09-30-multi-select-filter-state-model.md`
/// の「4. 適用順は段で決める」）。
///
/// 宣言順がそのまま適用順。**結果が選択の履歴に依存しない**ための規約であり、
/// 生理学的な厳密さを主張するものではない。色覚を最後に置く実際の理由は実装上の
/// もの（2×2 比較が「色覚以外の層」を 1 回だけ適用した結果を共有でき、色覚層を
/// 列の末尾で入れ替えるだけで済むため）。
enum VisionFilterStage {
  motion,
  optics,
  media,
  retina,
  visualField,
  perception,
  colorVision,
}

/// 段ごとの、そこに入るカタログ id（sensus の `Filter` 列挙の**宣言順**）。
///
/// ue のカタログの並び（表示順。例: myopia, hyperopia, presbyopia, astigmatism）
/// とは別に、sensus の宣言順で持つ。sensus が標準順序を公開したとき（#125）に
/// この表を置き換えても結果が変わらないようにするため。30 フィルタすべてが
/// ちょうど 1 つの段に入る（`test/vision_filter_stage_test.dart` が固定する）。
/// 順序の正本は本来 sensus（kako-jun/sensus#191）で、ue の表は暫定。
const Map<VisionFilterStage, List<String>> kVisionFilterStageOrder = {
  VisionFilterStage.motion: [
    'vertigo',
    'bppv_rotation',
    'vestibular_neuritis',
    'nystagmus',
  ],
  VisionFilterStage.optics: [
    'myopia',
    'hyperopia',
    'astigmatism',
    'presbyopia',
    'cataract',
    'photophobia',
    'diplopia',
    'starbursts',
    'eye_strain',
    'dry_eye',
  ],
  VisionFilterStage.media: ['floaters'],
  VisionFilterStage.retina: [
    'macular_degeneration',
    'night_blindness',
    'metamorphopsia',
    'contrast_sensitivity',
    'detail_loss',
  ],
  VisionFilterStage.visualField: [
    'glaucoma',
    'hemianopia',
    'tunnel_vision',
  ],
  VisionFilterStage.perception: ['teichopsia', 'flickering_stars'],
  VisionFilterStage.colorVision: [
    'protanopia',
    'deuteranopia',
    'tritanopia',
    'achromatopsia',
    'tetrachromacy',
  ],
};

/// 同時に重ねられるレイヤー数の上限（ADR「上限 5」。GPU の多段パス数の上限にもなる）。
const int kMaxVisionLayers = 5;

/// 全フィルタの適用順（0 始まりの通し番号）。段の順、段内は [kVisionFilterStageOrder]
/// の順。
final Map<String, int> _applyOrderIndex = () {
  final map = <String, int>{};
  var i = 0;
  for (final stage in VisionFilterStage.values) {
    for (final id in kVisionFilterStageOrder[stage]!) {
      map[id] = i++;
    }
  }
  return map;
}();

final Map<String, VisionFilterStage> _stageById = {
  for (final e in kVisionFilterStageOrder.entries)
    for (final id in e.value) id: e.key,
};

/// [id] の属する段。表に無い id は null。
VisionFilterStage? visionFilterStageOf(String id) => _stageById[id];

/// [id] の適用順の通し番号（小さいほど先に適用）。表に無い id は null。
int? visionFilterApplyOrder(String id) => _applyOrderIndex[id];

/// [id] が「色覚グループ」（同時に 1 つしか重ねられない排他グループ）に属するか。
/// 色覚グループはカタログのカテゴリ `colorVision`（5 種）と一致する。
bool isVisionColorGroupId(String id) =>
    kVisionFilterCatalogById[id]?.category == VisionFilterCategory.colorVision;
