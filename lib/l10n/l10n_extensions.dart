import '../models/disability_type.dart';
import '../models/vision_filter_catalog.dart';
import '../services/tray_service.dart';
import 'app_localizations.dart';

/// 定義（enum / catalog id）→ 表示文言（i18n）の解決をここに集約する (#18)。
///
/// 規律2（定義と表示文言を混ぜない）に従い、`ColorVisionType` /
/// `VisionFilterCategory` / `VisionFilterUrgency` / catalog の `id` といった
/// **識別子** は文言を持たず、表示する側がこのマッピングで `AppLocalizations`
/// から文字列を引く。UI（home_screen 等）とトレイ（起動時ロケールの
/// AppLocalizations インスタンス）の両方がここを参照し、二重定義を避ける。

/// [ColorVisionType] の表示名を解決する。
String colorVisionTypeName(AppLocalizations l10n, ColorVisionType type) {
  switch (type) {
    case ColorVisionType.none:
      return l10n.filterNormalVision;
    case ColorVisionType.protanopia:
      return l10n.filterProtanopia;
    case ColorVisionType.deuteranopia:
      return l10n.filterDeuteranopia;
    case ColorVisionType.tritanopia:
      return l10n.filterTritanopia;
    case ColorVisionType.achromatopsia:
      return l10n.filterAchromatopsia;
    case ColorVisionType.protanomaly:
      return l10n.filterProtanomaly;
    case ColorVisionType.deuteranomaly:
      return l10n.filterDeuteranomaly;
    case ColorVisionType.tritanomaly:
      return l10n.filterTritanomaly;
  }
}

/// [ColorVisionType] の説明文を解決する。
String colorVisionTypeDescription(AppLocalizations l10n, ColorVisionType type) {
  switch (type) {
    case ColorVisionType.none:
      return l10n.filterNormalVisionDesc;
    case ColorVisionType.protanopia:
      return l10n.filterProtanopiaDesc;
    case ColorVisionType.deuteranopia:
      return l10n.filterDeuteranopiaDesc;
    case ColorVisionType.tritanopia:
      return l10n.filterTritanopiaDesc;
    case ColorVisionType.achromatopsia:
      return l10n.filterAchromatopsiaDesc;
    case ColorVisionType.protanomaly:
      return l10n.filterProtanomalyDesc;
    case ColorVisionType.deuteranomaly:
      return l10n.filterDeuteranomalyDesc;
    case ColorVisionType.tritanomaly:
      return l10n.filterTritanomalyDesc;
  }
}

/// [ColorVisionType] の有病率（おおよその人口比）を解決する。
///
/// 統計値（数値・%）は i18n でも変えず、訳語のみローカライズする。
String colorVisionTypePrevalence(AppLocalizations l10n, ColorVisionType type) {
  switch (type) {
    case ColorVisionType.none:
      return l10n.prevalenceNormalVision;
    case ColorVisionType.protanopia:
      return l10n.prevalenceProtanopia;
    case ColorVisionType.deuteranopia:
      return l10n.prevalenceDeuteranopia;
    case ColorVisionType.tritanopia:
      return l10n.prevalenceTritanopia;
    case ColorVisionType.achromatopsia:
      return l10n.prevalenceAchromatopsia;
    case ColorVisionType.protanomaly:
      return l10n.prevalenceProtanomaly;
    case ColorVisionType.deuteranomaly:
      return l10n.prevalenceDeuteranomaly;
    case ColorVisionType.tritanomaly:
      return l10n.prevalenceTritanomaly;
  }
}

/// Advanced カタログの [VisionFilterCategory] 表示名を解決する。
String visionCategoryName(
    AppLocalizations l10n, VisionFilterCategory category) {
  switch (category) {
    case VisionFilterCategory.colorVision:
      return l10n.categoryColorVision;
    case VisionFilterCategory.refraction:
      return l10n.categoryRefraction;
    case VisionFilterCategory.visualField:
      return l10n.categoryVisualField;
    case VisionFilterCategory.lightAndTransparency:
      return l10n.categoryLightTransparency;
    case VisionFilterCategory.vestibular:
      return l10n.categoryVestibular;
    case VisionFilterCategory.eyeStrain:
      return l10n.categoryEyeStrain;
    case VisionFilterCategory.other:
      return l10n.categoryOther;
  }
}

/// Advanced カタログの [VisionFilterUrgency] 表示名を解決する。
String visionUrgencyName(AppLocalizations l10n, VisionFilterUrgency urgency) {
  switch (urgency) {
    case VisionFilterUrgency.none:
      return l10n.urgencyNone;
    case VisionFilterUrgency.low:
      return l10n.urgencyLow;
    case VisionFilterUrgency.medium:
      return l10n.urgencyMedium;
    case VisionFilterUrgency.high:
      return l10n.urgencyHigh;
  }
}

/// 受診喚起メッセージ（urgency 由来）を解決する。null = 喚起なし。
///
/// urgency の土台は catalog（[VisionFilterUrgency]）が持ち、当事者への注記文言は
/// ue 側が i18n で所有する。medium = 早めの受診を促す穏やかな注記、high = 急な
/// 変化への速やかな受診を促す注記。none/low では出さない。
String? consultMessageForUrgency(
  AppLocalizations l10n,
  VisionFilterUrgency urgency,
) {
  switch (urgency) {
    case VisionFilterUrgency.none:
    case VisionFilterUrgency.low:
      return null;
    case VisionFilterUrgency.medium:
      return l10n.consultEarly;
    case VisionFilterUrgency.high:
      return l10n.consultEmergency;
  }
}

/// Advanced カタログ id（snake_case）→ フィルタ表示名を解決する。
///
/// id は sensus shaders 名と一致する安定識別子。表示名はここで i18n に写像する。
String visionFilterName(AppLocalizations l10n, String id) {
  switch (id) {
    case 'protanopia':
      return l10n.filterProtanopia;
    case 'deuteranopia':
      return l10n.filterDeuteranopia;
    case 'tritanopia':
      return l10n.filterTritanopia;
    case 'achromatopsia':
      return l10n.filterAchromatopsia;
    case 'tetrachromacy':
      return l10n.filterTetrachromacy;
    case 'myopia':
      return l10n.filterMyopia;
    case 'hyperopia':
      return l10n.filterHyperopia;
    case 'presbyopia':
      return l10n.filterPresbyopia;
    case 'astigmatism':
      return l10n.filterAstigmatism;
    case 'glaucoma':
      return l10n.filterGlaucoma;
    case 'macular_degeneration':
      return l10n.filterMacularDegeneration;
    case 'hemianopia':
      return l10n.filterHemianopia;
    case 'tunnel_vision':
      return l10n.filterTunnelVision;
    case 'cataract':
      return l10n.filterCataract;
    case 'floaters':
      return l10n.filterFloaters;
    case 'photophobia':
      return l10n.filterPhotophobia;
    case 'night_blindness':
      return l10n.filterNightBlindness;
    case 'starbursts':
      return l10n.filterStarbursts;
    case 'vertigo':
      return l10n.filterVertigo;
    case 'bppv_rotation':
      return l10n.filterBppvRotation;
    case 'vestibular_neuritis':
      return l10n.filterVestibularNeuritis;
    case 'nystagmus':
      return l10n.filterNystagmus;
    case 'eye_strain':
      return l10n.filterEyeStrain;
    case 'dry_eye':
      return l10n.filterDryEye;
    case 'contrast_sensitivity':
      return l10n.filterContrastSensitivity;
    case 'diplopia':
      return l10n.filterDiplopia;
    case 'metamorphopsia':
      return l10n.filterMetamorphopsia;
    case 'detail_loss':
      return l10n.filterDetailLoss;
    case 'teichopsia':
      return l10n.filterTeichopsia;
    case 'flickering_stars':
      return l10n.filterFlickeringStars;
    default:
      return id;
  }
}

/// Advanced カタログの payload パラメータ labelKey → 表示名を解決する。
///
/// labelKey はカタログが持つ安定キー（例 `param.astigmatism.axis_deg`）。
String visionParamLabel(AppLocalizations l10n, String labelKey) {
  switch (labelKey) {
    case 'param.astigmatism.axis_deg':
      return l10n.paramAstigmatismAxisDeg;
    case 'param.glaucoma.mode':
      return l10n.paramGlaucomaMode;
    case 'param.glaucoma.mode.vignette':
      return l10n.paramGlaucomaModeVignette;
    case 'param.glaucoma.mode.arcuate_superior':
      return l10n.paramGlaucomaModeArcuateSuperior;
    case 'param.glaucoma.mode.arcuate_inferior':
      return l10n.paramGlaucomaModeArcuateInferior;
    case 'param.glaucoma.mode.biarcuate':
      return l10n.paramGlaucomaModeBiarcuate;
    case 'param.hemianopia.side':
      return l10n.paramHemianopiaSide;
    case 'param.hemianopia.side.left':
      return l10n.paramHemianopiaSideLeft;
    case 'param.hemianopia.side.right':
      return l10n.paramHemianopiaSideRight;
    case 'param.cataract.seed':
      return l10n.paramCataractSeed;
    case 'param.floaters.seed':
      return l10n.paramFloatersSeed;
    case 'param.floaters.density':
      return l10n.paramFloatersDensity;
    case 'param.floaters.size':
      return l10n.paramFloatersSize;
    case 'param.floaters.gaze_x':
      return l10n.paramFloatersGazeX;
    case 'param.floaters.gaze_y':
      return l10n.paramFloatersGazeY;
    case 'param.starbursts.num_rays':
      return l10n.paramStarburstsNumRays;
    case 'param.starbursts.ray_length_ratio':
      return l10n.paramStarburstsRayLengthRatio;
    case 'param.starbursts.threshold':
      return l10n.paramStarburstsThreshold;
    case 'param.starbursts.dispersion':
      return l10n.paramStarburstsDispersion;
    case 'param.nystagmus.amplitude':
      return l10n.paramNystagmusAmplitude;
    case 'param.nystagmus.direction_deg':
      return l10n.paramNystagmusDirectionDeg;
    case 'param.diplopia.offset_x':
      return l10n.paramDiplopiaOffsetX;
    case 'param.diplopia.offset_y':
      return l10n.paramDiplopiaOffsetY;
    case 'param.diplopia.ghost_strength':
      return l10n.paramDiplopiaGhostStrength;
    case 'param.metamorphopsia.freq':
      return l10n.paramMetamorphopsiaFreq;
    case 'param.metamorphopsia.seed':
      return l10n.paramMetamorphopsiaSeed;
    case 'param.detail_loss.cell_size':
      return l10n.paramDetailLossCellSize;
    case 'param.flickering_stars.seed':
      return l10n.paramFlickeringStarsSeed;
    default:
      return labelKey;
  }
}

/// 起動時ロケールの [AppLocalizations] からトレイメニュー文言を組み立てる (#18)。
///
/// トレイは BuildContext を持てないため、`AppLocalizations.of(context)` ではなく
/// `lookupAppLocalizations(locale)` で得たインスタンスをここに渡す。color-vision
/// ラベルは [quickColorVisionFilters] の各型を [colorVisionTypeName] で解決する。
TrayMenuLabels trayMenuLabelsFrom(AppLocalizations l10n) {
  return TrayMenuLabels(
    showLoupe: l10n.trayShowLoupe,
    hideLoupe: l10n.trayHideLoupe,
    clearFilter: l10n.trayClearFilter,
    openSettings: l10n.trayOpenSettings,
    quit: l10n.trayQuit,
    filterLabels: {
      for (final type in quickColorVisionFilters())
        type: colorVisionTypeName(l10n, type),
    },
  );
}
