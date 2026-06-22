/// sensus の全 [VisionFilter]（30 種）を UI 向けに分類・記述したカタログ。
///
/// **正本は sensus_bridge.dart の `VisionFilter` sealed class**。このカタログは
/// その 30 variant を、カテゴリ・表示名・緊急度・payload パラメータ定義に
/// メタデータとして写像する純粋なデータ層であり、アルゴリズムは持たない。
///
/// 既存の色覚 7 種 UI（`ColorVisionType` ベースの `FilterService`）とは別系統。
/// こちらは sensus が公開する **全** vision フィルタを破綻なく選べるようにする
/// 「Advanced」UI 用のメタデータである。
///
/// - `id` は snake_case（sensus shaders 名と一致。例: `bppv_rotation`）。
/// - `displayName` は英語フォールバック（i18n 実翻訳は #18）。
/// - `i18nKey` は文字列キーのみ定義（実翻訳は #18）。
/// - `parameters` は payload を持つフィルタの動的パラメータ定義。
///   payload を持たないフィルタは空リスト。
library;

import '../src/rust/api/sensus_bridge.dart';

/// seed パラメータの上限（sensus `u64` の最大値、2^64-1）。
///
/// sensus は `seed` を Rust `u64`（Dart [BigInt]）で受ける。`u64` は
/// [int]/[double] の正確表現範囲（2^53）を超えるため、seed は UI から sensus
/// まで一貫して [BigInt] で運ぶ（int/double を経由すると巨大シードで精度が
/// 落ちる。sensus_bridge.dart のモジュール doc 参照）。
/// [VisionFilterState.randomizeSeed] はこの範囲内（0..[kSeedMax]）の
/// [BigInt] を生成する。
final BigInt kSeedMax = (BigInt.one << 64) - BigInt.one;

/// hemianopia の `side`（UI 上は enum、sensus 上は `double`）の **単一の写像源**。
///
/// sensus は `hemianopia({required double side})` と連続値 `double` で受ける。
/// UI は Left/Right の二択（[VisionParamOption] の文字列 value）で見せる。
/// 「文字列キー → double 実値」の対応はこの 1 箇所だけで定義し、カタログの
/// options 定義と `vision_filter_state` の build()（`_hemianopiaSide`）は
/// 両方ともここを参照する。片方だけ変えても壊れないよう、
/// test/filter_catalog_test.dart が両者の一致を検証する。
///   - 'left'  -> 0.0
///   - 'right' -> 1.0
const Map<String, double> kHemianopiaSideValues = {
  'left': 0.0,
  'right': 1.0,
};

/// フィルタのカテゴリ分類。
///
/// sensus_bridge.dart の `VisionFilter` コメント（種別 / Phase）に従って分類する。
enum VisionFilterCategory {
  /// 色覚（protanopia, deuteranopia, tritanopia, achromatopsia, tetrachromacy）。
  colorVision('Color Vision', 'category.color_vision'),

  /// 屈折（myopia, hyperopia, presbyopia, astigmatism）。
  refraction('Refraction', 'category.refraction'),

  /// 視野（glaucoma, macular degeneration, hemianopia, tunnel vision）。
  visualField('Visual Field', 'category.visual_field'),

  /// 光・透明度（cataract, floaters, photophobia, night blindness, starbursts）。
  lightAndTransparency('Light & Transparency', 'category.light_transparency'),

  /// 前庭・めまい（vertigo, BPPV rotation, vestibular neuritis, nystagmus）。
  vestibular('Vestibular & Dizziness', 'category.vestibular'),

  /// 眼精疲労（eye strain, dry eye, contrast sensitivity）。
  eyeStrain('Eye Strain', 'category.eye_strain'),

  /// その他（diplopia, metamorphopsia, detail loss, teichopsia, flickering stars）。
  other('Other', 'category.other');

  const VisionFilterCategory(this.displayName, this.i18nKey);

  /// 英語フォールバック表示名（i18n 実翻訳は #18）。
  final String displayName;

  /// i18n キー（実翻訳は #18 で定義）。
  final String i18nKey;
}

/// 体験の緊急度／重大度の土台（実際の優先表示ロジックは #19 のプリセット側）。
///
/// 「この見え方をどれだけ早く周囲が把握すべきか」の目安。UI で選択時に小さく
/// 表示する（#16 スコープ）。値そのものの調整・運用は将来 Issue。
///
/// NOTE: 各フィルタへの urgency 初期割り当て（[kVisionFilterCatalog] 内）は
/// **初版・要医療監修**。現状は便宜的な目安であり、確定値ではない。
enum VisionFilterUrgency {
  /// 緊急度の概念が薄い（色覚など）。
  none('None', 'urgency.none'),

  /// 軽度（眼精疲労・ドライアイ等の日常的不快）。
  low('Low', 'urgency.low'),

  /// 中度（屈折・視野の一部欠損等）。
  medium('Medium', 'urgency.medium'),

  /// 高度（めまい・大きな視野欠損等、行動に強く影響）。
  high('High', 'urgency.high');

  const VisionFilterUrgency(this.displayName, this.i18nKey);

  /// 英語フォールバック表示名。
  final String displayName;

  /// i18n キー（実翻訳は #18）。
  final String i18nKey;
}

/// パラメータの種別。UI のウィジェット選択（slider / dropdown / seed ボタン）に使う。
enum VisionParamKind {
  /// 連続値（Slider）。
  float,

  /// 整数値（離散 Slider）。
  intValue,

  /// 列挙（Dropdown）。
  enumValue,

  /// 乱数シード（再生成ボタン + 表示）。
  seed,
}

/// enum パラメータの選択肢 1 つ。
class VisionParamOption {
  const VisionParamOption({
    required this.value,
    required this.displayName,
    required this.labelKey,
  });

  /// 内部値（[VisionFilter] 構築時に使う識別子。enum 名と一致させる）。
  final String value;

  /// 英語フォールバック表示名。
  final String displayName;

  /// i18n キー（実翻訳は #18）。
  final String labelKey;
}

/// payload パラメータ 1 つの定義。
///
/// `vision_filter_state` がこの定義を読んで値を保持し、`filter_param_panel` が
/// この定義から動的にウィジェットを生成する。
class VisionParam {
  const VisionParam({
    required this.name,
    required this.kind,
    required this.labelKey,
    required this.displayName,
    this.min,
    this.max,
    this.defaultValue,
    this.options = const [],
  });

  /// payload フィールド名（sensus_bridge.dart の named param と一致。例: `axisDeg`）。
  final String name;

  /// パラメータ種別（ウィジェット選択に使う）。
  final VisionParamKind kind;

  /// i18n キー（実翻訳は #18）。
  final String labelKey;

  /// 英語フォールバック表示名。
  final String displayName;

  /// float/int の最小値。enum/seed では null。
  final double? min;

  /// float/int の最大値。enum/seed では null。
  final double? max;

  /// 既定値（float/int は数値、seed は数値、enum は [VisionParamOption.value]）。
  final Object? defaultValue;

  /// enum の選択肢（kind が enumValue のときのみ）。
  final List<VisionParamOption> options;
}

/// カタログの 1 エントリ（= 1 つの [VisionFilter] 種別）。
class VisionFilterEntry {
  const VisionFilterEntry({
    required this.id,
    required this.displayName,
    required this.i18nKey,
    required this.category,
    required this.urgency,
    this.parameters = const [],
  });

  /// snake_case の安定 id（sensus shaders 名と一致。例: `bppv_rotation`）。
  final String id;

  /// 英語フォールバック表示名（i18n 実翻訳は #18）。
  final String displayName;

  /// i18n キー（実翻訳は #18）。
  final String i18nKey;

  /// 所属カテゴリ。
  final VisionFilterCategory category;

  /// 緊急度の土台。
  final VisionFilterUrgency urgency;

  /// payload パラメータ定義（payload を持たないフィルタは空リスト）。
  final List<VisionParam> parameters;
}

/// 緑内障モードの選択肢（[VisionGlaucomaMode] のミラー）。
const List<VisionParamOption> _glaucomaModeOptions = [
  VisionParamOption(
    value: 'vignette',
    displayName: 'Vignette (peripheral)',
    labelKey: 'param.glaucoma.mode.vignette',
  ),
  VisionParamOption(
    value: 'arcuateSuperior',
    displayName: 'Arcuate (superior)',
    labelKey: 'param.glaucoma.mode.arcuate_superior',
  ),
  VisionParamOption(
    value: 'arcuateInferior',
    displayName: 'Arcuate (inferior)',
    labelKey: 'param.glaucoma.mode.arcuate_inferior',
  ),
  VisionParamOption(
    value: 'biarcuate',
    displayName: 'Bi-arcuate (advanced)',
    labelKey: 'param.glaucoma.mode.biarcuate',
  ),
];

/// 全 30 [VisionFilter] のカタログ。カテゴリ順・カテゴリ内は宣言順。
///
/// **不変条件**（test/filter_catalog_test.dart が検証）:
/// - 30 エントリちょうど（sensus の `VisionFilter` variant 数と一致）。
/// - id は重複なし。
/// - payload を持つフィルタの parameters 数が sensus payload と一致する。
const List<VisionFilterEntry> kVisionFilterCatalog = [
  // ── 色覚 ──────────────────────────────────────────────
  VisionFilterEntry(
    id: 'protanopia',
    displayName: 'Protanopia',
    i18nKey: 'filter.protanopia',
    category: VisionFilterCategory.colorVision,
    urgency: VisionFilterUrgency.none,
  ),
  VisionFilterEntry(
    id: 'deuteranopia',
    displayName: 'Deuteranopia',
    i18nKey: 'filter.deuteranopia',
    category: VisionFilterCategory.colorVision,
    urgency: VisionFilterUrgency.none,
  ),
  VisionFilterEntry(
    id: 'tritanopia',
    displayName: 'Tritanopia',
    i18nKey: 'filter.tritanopia',
    category: VisionFilterCategory.colorVision,
    urgency: VisionFilterUrgency.none,
  ),
  VisionFilterEntry(
    id: 'achromatopsia',
    displayName: 'Achromatopsia',
    i18nKey: 'filter.achromatopsia',
    category: VisionFilterCategory.colorVision,
    urgency: VisionFilterUrgency.none,
  ),
  VisionFilterEntry(
    id: 'tetrachromacy',
    displayName: 'Tetrachromacy',
    i18nKey: 'filter.tetrachromacy',
    category: VisionFilterCategory.colorVision,
    urgency: VisionFilterUrgency.none,
  ),

  // ── 屈折 ──────────────────────────────────────────────
  VisionFilterEntry(
    id: 'myopia',
    displayName: 'Myopia',
    i18nKey: 'filter.myopia',
    category: VisionFilterCategory.refraction,
    urgency: VisionFilterUrgency.medium,
  ),
  VisionFilterEntry(
    id: 'hyperopia',
    displayName: 'Hyperopia',
    i18nKey: 'filter.hyperopia',
    category: VisionFilterCategory.refraction,
    urgency: VisionFilterUrgency.medium,
  ),
  VisionFilterEntry(
    id: 'presbyopia',
    displayName: 'Presbyopia',
    i18nKey: 'filter.presbyopia',
    category: VisionFilterCategory.refraction,
    urgency: VisionFilterUrgency.medium,
  ),
  VisionFilterEntry(
    id: 'astigmatism',
    displayName: 'Astigmatism',
    i18nKey: 'filter.astigmatism',
    category: VisionFilterCategory.refraction,
    urgency: VisionFilterUrgency.medium,
    parameters: [
      VisionParam(
        name: 'axisDeg',
        kind: VisionParamKind.float,
        labelKey: 'param.astigmatism.axis_deg',
        displayName: 'Axis (deg)',
        min: 0.0,
        max: 180.0,
        defaultValue: 90.0,
      ),
    ],
  ),

  // ── 視野 ──────────────────────────────────────────────
  VisionFilterEntry(
    id: 'glaucoma',
    displayName: 'Glaucoma',
    i18nKey: 'filter.glaucoma',
    category: VisionFilterCategory.visualField,
    urgency: VisionFilterUrgency.high,
    parameters: [
      VisionParam(
        name: 'mode',
        kind: VisionParamKind.enumValue,
        labelKey: 'param.glaucoma.mode',
        displayName: 'Scotoma mode',
        defaultValue: 'vignette',
        options: _glaucomaModeOptions,
      ),
    ],
  ),
  VisionFilterEntry(
    id: 'macular_degeneration',
    displayName: 'Macular Degeneration',
    i18nKey: 'filter.macular_degeneration',
    category: VisionFilterCategory.visualField,
    urgency: VisionFilterUrgency.high,
  ),
  VisionFilterEntry(
    id: 'hemianopia',
    displayName: 'Hemianopia',
    i18nKey: 'filter.hemianopia',
    category: VisionFilterCategory.visualField,
    urgency: VisionFilterUrgency.high,
    parameters: [
      VisionParam(
        name: 'side',
        kind: VisionParamKind.enumValue,
        labelKey: 'param.hemianopia.side',
        displayName: 'Lost field',
        // 文字列 option value は kHemianopiaSideValues のキー。double 実値への
        // 写像（left=0.0 / right=1.0）はそのマップが単一の正本で、build() の
        // _hemianopiaSide が同じマップを参照する。
        defaultValue: 'left',
        options: [
          VisionParamOption(
            value: 'left', // -> kHemianopiaSideValues['left'] == 0.0
            displayName: 'Left field lost',
            labelKey: 'param.hemianopia.side.left',
          ),
          VisionParamOption(
            value: 'right', // -> kHemianopiaSideValues['right'] == 1.0
            displayName: 'Right field lost',
            labelKey: 'param.hemianopia.side.right',
          ),
        ],
      ),
    ],
  ),
  VisionFilterEntry(
    id: 'tunnel_vision',
    displayName: 'Tunnel Vision',
    i18nKey: 'filter.tunnel_vision',
    category: VisionFilterCategory.visualField,
    urgency: VisionFilterUrgency.high,
  ),

  // ── 光・透明度 ────────────────────────────────────────
  VisionFilterEntry(
    id: 'cataract',
    displayName: 'Cataract',
    i18nKey: 'filter.cataract',
    category: VisionFilterCategory.lightAndTransparency,
    urgency: VisionFilterUrgency.medium,
    parameters: [
      VisionParam(
        name: 'seed',
        kind: VisionParamKind.seed,
        labelKey: 'param.cataract.seed',
        displayName: 'Glare seed',
        // seed は sensus u64。const カタログのため defaultValue は const-safe な
        // int 0 とし、VisionFilterState が seed kind を実行時に BigInt 化する。
        defaultValue: 0,
      ),
    ],
  ),
  VisionFilterEntry(
    id: 'floaters',
    displayName: 'Floaters',
    i18nKey: 'filter.floaters',
    category: VisionFilterCategory.lightAndTransparency,
    urgency: VisionFilterUrgency.low,
    parameters: [
      VisionParam(
        name: 'seed',
        kind: VisionParamKind.seed,
        labelKey: 'param.floaters.seed',
        displayName: 'Seed',
        // seed は sensus u64。const カタログのため defaultValue は const-safe な
        // int 0 とし、VisionFilterState が seed kind を実行時に BigInt 化する。
        defaultValue: 0,
      ),
      VisionParam(
        name: 'density',
        kind: VisionParamKind.float,
        labelKey: 'param.floaters.density',
        displayName: 'Density',
        min: 0.0,
        max: 1.0,
        defaultValue: 0.5,
      ),
      VisionParam(
        name: 'size',
        kind: VisionParamKind.float,
        labelKey: 'param.floaters.size',
        displayName: 'Size',
        min: 0.0,
        max: 1.0,
        defaultValue: 0.5,
      ),
      VisionParam(
        name: 'gazeX',
        kind: VisionParamKind.float,
        labelKey: 'param.floaters.gaze_x',
        displayName: 'Gaze X',
        min: 0.0,
        max: 1.0,
        defaultValue: 0.5,
      ),
      VisionParam(
        name: 'gazeY',
        kind: VisionParamKind.float,
        labelKey: 'param.floaters.gaze_y',
        displayName: 'Gaze Y',
        min: 0.0,
        max: 1.0,
        defaultValue: 0.5,
      ),
    ],
  ),
  VisionFilterEntry(
    id: 'photophobia',
    displayName: 'Photophobia',
    i18nKey: 'filter.photophobia',
    category: VisionFilterCategory.lightAndTransparency,
    urgency: VisionFilterUrgency.low,
  ),
  VisionFilterEntry(
    id: 'night_blindness',
    displayName: 'Night Blindness',
    i18nKey: 'filter.night_blindness',
    category: VisionFilterCategory.lightAndTransparency,
    urgency: VisionFilterUrgency.medium,
  ),
  VisionFilterEntry(
    id: 'starbursts',
    displayName: 'Starbursts',
    i18nKey: 'filter.starbursts',
    category: VisionFilterCategory.lightAndTransparency,
    urgency: VisionFilterUrgency.low,
    parameters: [
      VisionParam(
        name: 'numRays',
        kind: VisionParamKind.intValue,
        labelKey: 'param.starbursts.num_rays',
        displayName: 'Ray count',
        min: 2.0,
        max: 24.0,
        defaultValue: 6,
      ),
      VisionParam(
        name: 'rayLengthRatio',
        kind: VisionParamKind.float,
        labelKey: 'param.starbursts.ray_length_ratio',
        displayName: 'Ray length',
        min: 0.0,
        max: 1.0,
        defaultValue: 0.3,
      ),
      VisionParam(
        name: 'threshold',
        kind: VisionParamKind.float,
        labelKey: 'param.starbursts.threshold',
        displayName: 'Threshold',
        min: 0.0,
        max: 1.0,
        defaultValue: 0.8,
      ),
      VisionParam(
        name: 'dispersion',
        kind: VisionParamKind.float,
        labelKey: 'param.starbursts.dispersion',
        displayName: 'Dispersion',
        min: 0.0,
        max: 1.0,
        defaultValue: 0.2,
      ),
    ],
  ),

  // ── 前庭・めまい ──────────────────────────────────────
  VisionFilterEntry(
    id: 'vertigo',
    displayName: 'Vertigo',
    i18nKey: 'filter.vertigo',
    category: VisionFilterCategory.vestibular,
    urgency: VisionFilterUrgency.high,
  ),
  VisionFilterEntry(
    id: 'bppv_rotation',
    displayName: 'BPPV Rotation',
    i18nKey: 'filter.bppv_rotation',
    category: VisionFilterCategory.vestibular,
    urgency: VisionFilterUrgency.high,
  ),
  VisionFilterEntry(
    id: 'vestibular_neuritis',
    displayName: 'Vestibular Neuritis',
    i18nKey: 'filter.vestibular_neuritis',
    category: VisionFilterCategory.vestibular,
    urgency: VisionFilterUrgency.high,
  ),
  VisionFilterEntry(
    id: 'nystagmus',
    displayName: 'Nystagmus',
    i18nKey: 'filter.nystagmus',
    category: VisionFilterCategory.vestibular,
    urgency: VisionFilterUrgency.medium,
    parameters: [
      VisionParam(
        name: 'amplitude',
        kind: VisionParamKind.float,
        labelKey: 'param.nystagmus.amplitude',
        displayName: 'Amplitude',
        min: 0.0,
        max: 1.0,
        defaultValue: 0.1,
      ),
      VisionParam(
        name: 'directionDeg',
        kind: VisionParamKind.float,
        labelKey: 'param.nystagmus.direction_deg',
        displayName: 'Direction (deg)',
        min: 0.0,
        max: 360.0,
        defaultValue: 0.0,
      ),
    ],
  ),

  // ── 眼精疲労 ──────────────────────────────────────────
  VisionFilterEntry(
    id: 'eye_strain',
    displayName: 'Eye Strain',
    i18nKey: 'filter.eye_strain',
    category: VisionFilterCategory.eyeStrain,
    urgency: VisionFilterUrgency.low,
  ),
  VisionFilterEntry(
    id: 'dry_eye',
    displayName: 'Dry Eye',
    i18nKey: 'filter.dry_eye',
    category: VisionFilterCategory.eyeStrain,
    urgency: VisionFilterUrgency.low,
  ),
  VisionFilterEntry(
    id: 'contrast_sensitivity',
    displayName: 'Contrast Sensitivity Loss',
    i18nKey: 'filter.contrast_sensitivity',
    category: VisionFilterCategory.eyeStrain,
    urgency: VisionFilterUrgency.medium,
  ),

  // ── その他 ────────────────────────────────────────────
  VisionFilterEntry(
    id: 'diplopia',
    displayName: 'Diplopia',
    i18nKey: 'filter.diplopia',
    category: VisionFilterCategory.other,
    urgency: VisionFilterUrgency.medium,
    parameters: [
      VisionParam(
        name: 'offsetX',
        kind: VisionParamKind.float,
        labelKey: 'param.diplopia.offset_x',
        displayName: 'Ghost offset X',
        min: -1.0,
        max: 1.0,
        defaultValue: 0.05,
      ),
      VisionParam(
        name: 'offsetY',
        kind: VisionParamKind.float,
        labelKey: 'param.diplopia.offset_y',
        displayName: 'Ghost offset Y',
        min: -1.0,
        max: 1.0,
        defaultValue: 0.0,
      ),
      VisionParam(
        name: 'ghostStrength',
        kind: VisionParamKind.float,
        labelKey: 'param.diplopia.ghost_strength',
        displayName: 'Ghost strength',
        min: 0.0,
        max: 1.0,
        defaultValue: 0.5,
      ),
    ],
  ),
  VisionFilterEntry(
    id: 'metamorphopsia',
    displayName: 'Metamorphopsia',
    i18nKey: 'filter.metamorphopsia',
    category: VisionFilterCategory.other,
    urgency: VisionFilterUrgency.medium,
    parameters: [
      VisionParam(
        name: 'freq',
        kind: VisionParamKind.float,
        labelKey: 'param.metamorphopsia.freq',
        displayName: 'Frequency',
        min: 0.0,
        max: 1.0,
        defaultValue: 0.5,
      ),
      VisionParam(
        name: 'seed',
        kind: VisionParamKind.seed,
        labelKey: 'param.metamorphopsia.seed',
        displayName: 'Distortion seed',
        // seed は sensus u64。const カタログのため defaultValue は const-safe な
        // int 0 とし、VisionFilterState が seed kind を実行時に BigInt 化する。
        defaultValue: 0,
      ),
    ],
  ),
  VisionFilterEntry(
    id: 'detail_loss',
    displayName: 'Detail Loss',
    i18nKey: 'filter.detail_loss',
    category: VisionFilterCategory.other,
    urgency: VisionFilterUrgency.medium,
    parameters: [
      VisionParam(
        name: 'cellSize',
        kind: VisionParamKind.intValue,
        labelKey: 'param.detail_loss.cell_size',
        displayName: 'Cell size (px)',
        min: 1.0,
        max: 64.0,
        defaultValue: 8,
      ),
    ],
  ),
  VisionFilterEntry(
    id: 'teichopsia',
    displayName: 'Teichopsia',
    i18nKey: 'filter.teichopsia',
    category: VisionFilterCategory.other,
    urgency: VisionFilterUrgency.medium,
  ),
  VisionFilterEntry(
    id: 'flickering_stars',
    displayName: 'Flickering Stars',
    i18nKey: 'filter.flickering_stars',
    category: VisionFilterCategory.other,
    urgency: VisionFilterUrgency.low,
    parameters: [
      VisionParam(
        name: 'seed',
        kind: VisionParamKind.seed,
        labelKey: 'param.flickering_stars.seed',
        displayName: 'Seed',
        // seed は sensus u64。const カタログのため defaultValue は const-safe な
        // int 0 とし、VisionFilterState が seed kind を実行時に BigInt 化する。
        defaultValue: 0,
      ),
    ],
  ),
];

/// id → エントリ の参照マップ（重複 id があれば構築時に最後勝ちになるが、
/// テストが重複なしを保証する）。
final Map<String, VisionFilterEntry> kVisionFilterCatalogById = {
  for (final e in kVisionFilterCatalog) e.id: e,
};

/// 指定カテゴリのエントリを宣言順で返す。
List<VisionFilterEntry> visionFilterEntriesByCategory(
  VisionFilterCategory category,
) =>
    kVisionFilterCatalog.where((e) => e.category == category).toList();

/// payload を持たない（const 構築できる）[VisionFilter] → カタログ id の写像。
///
/// 体験プリセット (#19) の `Experience.vision`（bridge の [VisionFilter] インスタンス）
/// を、カタログの snake_case id（[VisionFilterState.select] が受ける値）へ変換する
/// ための単一の正本。**id をハードコード散在させない**ため、ここ 1 箇所に集約する。
///
/// freezed の値等価（payload 無しバリアントは同値）を使って引く。payload を持つ
/// フィルタ（astigmatism 等）は const 構築できず体験プリセットでも使われないため
/// 対象外（[visionFilterCatalogId] が null を返す）。
final Map<VisionFilter, String> _kCatalogIdByParamlessVision = {
  const VisionFilter.protanopia(): 'protanopia',
  const VisionFilter.deuteranopia(): 'deuteranopia',
  const VisionFilter.tritanopia(): 'tritanopia',
  const VisionFilter.achromatopsia(): 'achromatopsia',
  const VisionFilter.tetrachromacy(): 'tetrachromacy',
  const VisionFilter.myopia(): 'myopia',
  const VisionFilter.hyperopia(): 'hyperopia',
  const VisionFilter.presbyopia(): 'presbyopia',
  const VisionFilter.macularDegeneration(): 'macular_degeneration',
  const VisionFilter.tunnelVision(): 'tunnel_vision',
  const VisionFilter.photophobia(): 'photophobia',
  const VisionFilter.nightBlindness(): 'night_blindness',
  const VisionFilter.vertigo(): 'vertigo',
  const VisionFilter.bppvRotation(): 'bppv_rotation',
  const VisionFilter.vestibularNeuritis(): 'vestibular_neuritis',
  const VisionFilter.eyeStrain(): 'eye_strain',
  const VisionFilter.dryEye(): 'dry_eye',
  const VisionFilter.contrastSensitivity(): 'contrast_sensitivity',
  const VisionFilter.teichopsia(): 'teichopsia',
};

/// [VisionFilter] インスタンス → カタログ id（snake_case）を引く。未知なら null。
///
/// 体験プリセット (#19) が `Experience.vision` を [VisionFilterState.select] へ橋渡し
/// するのに使う。payload を持つフィルタ（体験プリセットでは未使用）は null を返す。
String? visionFilterCatalogId(VisionFilter filter) =>
    _kCatalogIdByParamlessVision[filter];
