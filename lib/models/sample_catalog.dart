/// The built-in preview sample images (#78) — self-made, procedurally
/// generated scenes (see `tools/generate_samples.dart` +
/// `assets/samples/README.md` for provenance) that replace the old
/// meaningless hue-gradient placeholder with content where a symptom's
/// effect is actually legible: colour-coded lines, a chart legend, signage
/// text at several sizes, red/green fruit, night point-lights, a layered
/// depth scene.
///
/// This is a pure data layer (no algorithm, no `dart:ui`) — mirrors the
/// `VisionFilterCategory`/`VisionFilterEntry` split in
/// `lib/models/vision_filter_catalog.dart`. `i18nKey`s are resolved by
/// `lib/l10n/l10n_extensions.dart`'s `sampleImageName`.
library;

/// One built-in sample scene.
class SampleImageEntry {
  const SampleImageEntry({
    required this.id,
    required this.assetPath,
    required this.i18nKey,
    this.depthAssetPath,
  });

  /// Stable identifier (snake_case), also used as the asset's basename.
  final String id;

  /// `assets/samples/...` path (declared under `flutter.assets` in
  /// pubspec.yaml, loaded via `rootBundle`).
  final String assetPath;

  /// i18n key for the display name (real translations in `lib/l10n/*.arb`).
  final String i18nKey;

  /// Grayscale depth-map companion (`lib/rendering/image_fit.dart` doesn't
  /// consume this — it's material for the future depth_aware_blur
  /// experience, sensus-integration.md's stereo/depth notes, Issue #78's
  /// kickoff comment). `null` for every scene except `depth_landscape`.
  final String? depthAssetPath;
}

/// The 7 built-in scenes (#78 issue: minimum required set).
const List<SampleImageEntry> kSampleCatalog = [
  SampleImageEntry(
    id: 'route_map',
    assetPath: 'assets/samples/route_map.png',
    i18nKey: 'sample.route_map',
  ),
  SampleImageEntry(
    id: 'chart',
    assetPath: 'assets/samples/chart.png',
    i18nKey: 'sample.chart',
  ),
  SampleImageEntry(
    id: 'traffic_signs',
    assetPath: 'assets/samples/traffic_signs.png',
    i18nKey: 'sample.traffic_signs',
  ),
  SampleImageEntry(
    id: 'info_board',
    assetPath: 'assets/samples/info_board.png',
    i18nKey: 'sample.info_board',
  ),
  SampleImageEntry(
    id: 'fruit_stand',
    assetPath: 'assets/samples/fruit_stand.png',
    i18nKey: 'sample.fruit_stand',
  ),
  SampleImageEntry(
    id: 'night_scene',
    assetPath: 'assets/samples/night_scene.png',
    i18nKey: 'sample.night_scene',
  ),
  SampleImageEntry(
    id: 'depth_landscape',
    assetPath: 'assets/samples/depth_landscape.png',
    i18nKey: 'sample.depth_landscape',
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
/// Keyed by **catalog id**, not [ColorVisionType] — the colour-vision quick
/// pick (protanomaly/deuteranomaly/tritanomaly) maps to the same catalog id
/// as its base -opia (`visionFilterForColorVisionType`'s contract), so one
/// map keyed by catalog id covers the quick pick, the advanced catalog, and
/// experience presets uniformly (same reasoning as `VisionFilterState`
/// tracking selection by catalog id).
///
/// `test/sample_catalog_test.dart` asserts every [kVisionFilterCatalog] id
/// has an entry here and every value resolves in [kSampleCatalogById], so
/// this map can't silently drift out of sync with either catalog.
const Map<String, String> kRecommendedSampleByFilterId = {
  // ── 色覚: 赤緑は果物（熟/未熟）、青黄は凡例付きグラフ、全色覚喪失/強化は
  // 色だけに頼る素材（路線図・グラフ）で効果が最も分かりやすい ──
  'protanopia': 'fruit_stand',
  'deuteranopia': 'fruit_stand',
  'tritanopia': 'chart',
  'achromatopsia': 'route_map',
  'tetrachromacy': 'chart',

  // ── 屈折: 近見/老視系は文字、乱視は軸依存のぼけが線の多い風景で見える ──
  'myopia': 'info_board',
  'hyperopia': 'info_board',
  'presbyopia': 'info_board',
  'astigmatism': 'depth_landscape',

  // ── 視野欠損: 周辺/中心のどちらも空間の広い風景で欠損が分かりやすい。
  // 黄斑変性（中心視野）だけは読字への影響が主症状なので文字素材にする ──
  'glaucoma': 'depth_landscape',
  'macular_degeneration': 'info_board',
  'hemianopia': 'depth_landscape',
  'tunnel_vision': 'depth_landscape',

  // ── 光・透明度: 夜盲・starbursts は Issue の指定通り夜景。畏光も点光源の
  // 夜景で眩しさ/滲みが分かりやすい。白内障・飛蚊症は文字の上でコントラスト
  // 低下・浮遊物が見やすい ──
  'cataract': 'info_board',
  'floaters': 'info_board',
  'photophobia': 'night_scene',
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
