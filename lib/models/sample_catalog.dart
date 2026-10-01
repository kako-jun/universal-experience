/// The built-in preview sample images (#78) — scenes whose shapes are
/// self-made and procedurally generated and whose text is OFL font (see
/// `tools/generate_samples.dart` + `assets/samples/README.md` for provenance;
/// text is drawn with the OFL Noto Sans / Noto Sans JP bitmap fonts in
/// `tools/fonts/`, #99) that replace the old meaningless hue-gradient
/// placeholder with content where a
/// symptom's effect is actually legible: colour-coded lines, a chart legend,
/// signage text at several sizes (Latin and Japanese), red/green fruit,
/// night point-lights, a layered depth scene.
///
/// This is a pure data layer (no algorithm, no `dart:ui`) — mirrors the
/// `VisionFilterCategory`/`VisionFilterEntry` split in
/// `lib/models/vision_filter_catalog.dart`. Display names are resolved by
/// `id` directly (`lib/l10n/l10n_extensions.dart`'s `sampleImageName`, same
/// pattern as `visionFilterName`) — there's no separate i18n-key field here.
library;

/// One built-in sample scene.
class SampleImageEntry {
  const SampleImageEntry({
    required this.id,
    required this.assetPath,
    this.depthAssetPath,
  });

  /// Stable identifier (snake_case), also used as the asset's basename and
  /// as the key `sampleImageName` switches on for the display name.
  final String id;

  /// `assets/samples/...` path (declared under `flutter.assets` in
  /// pubspec.yaml, loaded via `rootBundle`).
  final String assetPath;

  /// Grayscale depth-map companion (`lib/rendering/image_fit.dart` doesn't
  /// consume this — it's material for the future depth_aware_blur
  /// experience, sensus-integration.md's stereo/depth notes, Issue #98).
  /// `null` for every scene except `depth_landscape`.
  final String? depthAssetPath;
}

/// The 8 built-in scenes (#78 issue: minimum required 7 + the Japanese
/// signage board of #99).
const List<SampleImageEntry> kSampleCatalog = [
  SampleImageEntry(
    id: 'route_map',
    assetPath: 'assets/samples/route_map.png',
  ),
  SampleImageEntry(
    id: 'chart',
    assetPath: 'assets/samples/chart.png',
  ),
  SampleImageEntry(
    id: 'traffic_signs',
    assetPath: 'assets/samples/traffic_signs.png',
  ),
  SampleImageEntry(
    id: 'info_board',
    assetPath: 'assets/samples/info_board.png',
  ),
  SampleImageEntry(
    id: 'info_board_ja',
    assetPath: 'assets/samples/info_board_ja.png',
  ),
  SampleImageEntry(
    id: 'fruit_stand',
    assetPath: 'assets/samples/fruit_stand.png',
  ),
  SampleImageEntry(
    id: 'night_scene',
    assetPath: 'assets/samples/night_scene.png',
  ),
  SampleImageEntry(
    id: 'depth_landscape',
    assetPath: 'assets/samples/depth_landscape.png',
    depthAssetPath: 'assets/samples/depth_landscape_depth.png',
  ),
];

/// `id` → entry lookup (mirrors `kVisionFilterCatalogById`).
final Map<String, SampleImageEntry> kSampleCatalogById = {
  for (final e in kSampleCatalog) e.id: e,
};

/// Fallback sample when a filter id has no specific recommendation (there
/// currently isn't one — [kRecommendedSampleByFilterId] covers all 30 — but
/// callers with no filter selected at all, e.g. "Normal vision", use this).
const String kDefaultSampleId = 'route_map';

/// The recommended sample for each of sensus's 30 catalog filter ids (#78).
///
/// Keyed by **catalog id**, not alias id — the colour-vision aliases
/// (protanomaly/deuteranomaly/tritanomaly) map to the same catalog id
/// as their base -opia (`kVisionAliases`), so one
/// map keyed by catalog id covers the quick pick, the advanced catalog, and
/// experience presets uniformly (same reasoning as `VisionFilterState`
/// tracking selection by catalog id).
///
/// `test/sample_catalog_test.dart` asserts every [kVisionFilterCatalog] id
/// has an entry here and every value resolves in [kSampleCatalogById], so
/// this map can't silently drift out of sync with either catalog.
const Map<String, String> kRecommendedSampleByFilterId = {
  // ── 色覚: 赤緑は果物（熟/未熟）。protanopia は信号・標識（赤信号の位置と
  // 禁止標識の赤リングが色だけに頼らず伝わるかを見せる）。tritanopia は
  // 青黄の混同が起きやすい青系/紫系の果物で確認する。achromatopsia/
  // tetrachromacy は色だけに頼る素材（路線図・グラフ）で効果が最も
  // 分かりやすい（#78）──
  'protanopia': 'traffic_signs',
  'deuteranopia': 'fruit_stand',
  'tritanopia': 'fruit_stand',
  'achromatopsia': 'route_map',
  'tetrachromacy': 'chart',

  // ── 屈折: 近見/老視系は文字。乱視も同じ理由で文字素材にする（#78）。
  // 軸依存のぼけの再現自体は depth_aware_blur 配線後の課題（#98）──
  'myopia': 'info_board',
  'hyperopia': 'info_board',
  'presbyopia': 'info_board',
  'astigmatism': 'info_board',

  // ── 視野欠損: 周辺/中心のどちらも空間の広い風景で欠損が分かりやすい。
  // 黄斑変性（中心視野）だけは読字への影響が主症状なので文字素材にする ──
  'glaucoma': 'depth_landscape',
  'macular_degeneration': 'info_board',
  'hemianopia': 'depth_landscape',
  'tunnel_vision': 'depth_landscape',

  // ── 光・透明度: 夜盲・starbursts は Issue の指定通り夜景。畏光
  // （photophobia）は奥行きのある風景の明るい空で眩しさが分かりやすい
  // （#78）。白内障・飛蚊症は文字の上でコントラスト低下・
  // 浮遊物が見やすい ──
  'cataract': 'info_board',
  'floaters': 'info_board',
  'photophobia': 'depth_landscape',
  'night_blindness': 'night_scene',
  'starbursts': 'night_scene',

  // ── 前庭・めまい: 空間の奥行きがある風景で方向感覚の乱れが伝わりやすい
  // （時間依存フィルタなのでプレビューは静止フレームになる、既存の注記どおり）──
  'vertigo': 'depth_landscape',
  'bppv_rotation': 'depth_landscape',
  'vestibular_neuritis': 'depth_landscape',
  'nystagmus': 'depth_landscape',

  // ── 眼精疲労: 長文を読む疲労感の再現に文字素材 ──
  'eye_strain': 'info_board',
  'dry_eye': 'info_board',
  'contrast_sensitivity': 'info_board',

  // ── その他: 複視・歪視は直線の多い路線図でずれ/歪みが顕著。detail_loss は
  // 文字素材。teichopsia はきらめきが淡色背景で見やすく chart、
  // flickering_stars は暗い夜景背景で「星」の効果がそのまま見える ──
  'diplopia': 'route_map',
  'metamorphopsia': 'route_map',
  'detail_loss': 'info_board',
  'teichopsia': 'chart',
  'flickering_stars': 'night_scene',
};

/// Resolves the recommended sample for [filterId] (a
/// [kVisionFilterCatalog] id), falling back to [kDefaultSampleId] for `null`
/// (nothing selected, e.g. "Normal vision") or an id with no specific
/// mapping (shouldn't happen — see [kRecommendedSampleByFilterId]'s doc —
/// but keeps this total rather than throwing).
String recommendedSampleIdForFilter(String? filterId) {
  if (filterId == null) return kDefaultSampleId;
  return kRecommendedSampleByFilterId[filterId] ?? kDefaultSampleId;
}
