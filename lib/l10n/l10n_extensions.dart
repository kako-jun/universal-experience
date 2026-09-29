import '../models/disability_type.dart';
import '../models/vision_filter_catalog.dart';
import '../services/tray_service.dart';
import '../src/rust/api/sensus_bridge.dart';
import 'app_localizations.dart';

/// 定義（enum / catalog id）→ 表示文言（i18n）の解決をここに集約する (#18)。
///
/// 規律2（定義と表示文言を混ぜない）に従い、`ColorVisionType` /
/// `VisionFilterCategory` / catalog の `id` といった
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

/// サンプル画像集（#78、`lib/models/sample_catalog.dart`）の id → 表示名を
/// 解決する。[visionFilterName] と同じパターン（id は識別子のみ、文言は
/// ここに集約）。未知の id は id をそのまま返す（`test/i18n_test.dart` が
/// 全 [kSampleCatalog] id をフォールバックなしで解決できることを検証する）。
String sampleImageName(AppLocalizations l10n, String id) {
  switch (id) {
    case 'route_map':
      return l10n.sampleRouteMap;
    case 'chart':
      return l10n.sampleChart;
    case 'traffic_signs':
      return l10n.sampleTrafficSigns;
    case 'info_board':
      return l10n.sampleInfoBoard;
    case 'fruit_stand':
      return l10n.sampleFruitStand;
    case 'night_scene':
      return l10n.sampleNightScene;
    case 'depth_landscape':
      return l10n.sampleDepthLandscape;
    default:
      return id;
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

/// 体験プリセット (#19) の id（sensus `Experience.id`）→ 表示名を解決する。
///
/// id は sensus が返す安定識別子（`meniere` / `bppv` / `vestibular_neuritis` /
/// `labyrinthitis`）。表示名・説明は文言を持たず、ここで i18n に写像する（規律2）。
String experienceName(AppLocalizations l10n, String id) {
  switch (id) {
    case 'meniere':
      return l10n.experienceMeniere;
    case 'bppv':
      return l10n.experienceBppv;
    case 'vestibular_neuritis':
      return l10n.experienceVestibularNeuritis;
    case 'labyrinthitis':
      return l10n.experienceLabyrinthitis;
    default:
      return id;
  }
}

/// 体験プリセット (#19) の id → 三徴候の簡潔な説明を解決する。
String experienceDescription(AppLocalizations l10n, String id) {
  switch (id) {
    case 'meniere':
      return l10n.experienceMeniereDesc;
    case 'bppv':
      return l10n.experienceBppvDesc;
    case 'vestibular_neuritis':
      return l10n.experienceVestibularNeuritisDesc;
    case 'labyrinthitis':
      return l10n.experienceLabyrinthitisDesc;
    default:
      return id;
  }
}

/// [Urgency]（sensus 由来）→ 受診喚起メッセージを解決する。
///
/// null = 喚起なし。`Urgency` の分類は bridge（sensus）が唯一の正本として持ち、
/// 当事者への注記文言は ue 側が i18n で所有する（規律2、#76）。
/// `earlyConsultation` = 早期受診を促す穏やかな注記、`emergency` = 速やかな
/// 受診を促す注記。`none` では出さない。
///
/// advanced カタログ（`FilterParamPanel`、フィルタの [VisionFilter] を
/// `visionFilterUrgencyProvider` に渡して得る）・体験プリセット
/// （`ExperiencePresets`、`Experience.urgency`）・export の焼き込み
/// （`before_after_view.dart`）が、この 1 関数を共有する **唯一の正本**にする
/// （#76: 「受診喚起は sensus の単一の正本に統一する」）。
String? urgencyConsultMessage(AppLocalizations l10n, Urgency urgency) {
  switch (urgency) {
    case Urgency.none:
      return null;
    case Urgency.earlyConsultation:
      return l10n.consultEarly;
    case Urgency.emergency:
      return l10n.consultEmergency;
  }
}

/// sensus が返す [UrgencyEscalation.condition]（英語の条件文）→ 表示文言を解決する。
///
/// sensus-core 0.6.1 の `Filter::urgency_escalation()` / `HearingFilter::
/// urgency_escalation()` は、条件文を **英語の固定文字列**で返す（i18n は消費側の
/// 責務、kako-jun/sensus#182）。ここはその英文をキーにした ja/en 対応表で、
/// 訳が無い条件文は英語のままフォールバック表示する（#76: 「訳が見つからない
/// 場合は英語のまま表示する」）。
///
/// 対応表の英文は sensus-core 0.6.1 の `crates/core/src/lib.rs` の
/// `urgency_escalation()` 実装から書き写した一次情報（変更があれば sensus の
/// バージョンアップ時にここも追従する）。
String escalationConditionText(AppLocalizations l10n, String condition) {
  switch (condition) {
    case 'sudden, severe photophobia with eye pain or a headache (e.g. iritis)':
      return l10n.escalationConditionPhotophobiaSevere;
    case 'recurrent or severe episodes':
      return l10n.escalationConditionBppvRecurrentSevere;
    case 'persistent pain or a change in vision':
      return l10n.escalationConditionDryEyePersistent;
    case 'a sudden drop in hearing, especially in one ear (possible sudden '
        'sensorineural hearing loss)':
      return l10n.escalationConditionHearingSuddenOneEar;
    case 'a new or worsening change, particularly in one ear':
      return l10n.escalationConditionHearingNewWorseningOneEar;
    default:
      return condition;
  }
}

/// sensus の公開ドキュメントのうち、受診喚起の根拠（Medical notes 節）を指す URL。
/// [ConsultNotice.citationUrl] の値。UI（`ConsultNoticeBlock`）はこれを
/// 選択可能なテキストとして表示する（#76 レビュー M2）。アンカーは節そのもの
/// を指す（#76 再レビュー nit）。
const String kSensusMedicalNotesUrl =
    'https://github.com/kako-jun/sensus/blob/main/docs/overview.md'
    '#medical-notes-when-to-see-a-doctor';

/// [resolveConsultNotice] が返す、緊急度の段ごとにまとめた escalation
/// （見出し + 条件文のリスト）。UI（`ConsultNoticeBlock`）と PNG export
/// （`ExportCaption.escalationGroups`）の両方がこの単位で表示する
/// （#76 再レビュー S-a: PNG でも段ごとの見出しを出す）。
class ConsultEscalationGroup {
  const ConsultEscalationGroup({required this.header, required this.lines});

  /// 見出し（`escalationHeaderEmergency` / `escalationHeaderEarly`）。
  final String header;

  /// [escalationConditionText] で解決済みの条件文（訳が無ければ英語）。
  final List<String> lines;
}

/// 受診喚起の解決結果（#76 レビュー M1）。
///
/// urgency/escalation から「何を表示するか」を **1 箇所**（[resolveConsultNotice]）
/// で決め、advanced カタログ（`FilterParamPanel`）・体験プリセットのカード
/// （`ExperiencePresets`）・PNG export（`before_after_view.dart` /
/// `export_service.dart`）の 3 箇所がこの結果を共有する。UI 表示は
/// `ConsultNoticeBlock`（`lib/ui/widgets/consult_notice_block.dart`）が担う。
class ConsultNotice {
  const ConsultNotice({
    required this.urgency,
    required this.message,
    required this.escalationGroups,
    required this.disclaimer,
    required this.disclaimerShort,
    required this.citationUrl,
  });

  /// 喚起の緊急度（sensus 由来）。
  final Urgency urgency;

  /// 喚起文（[urgency] が `none` なら null）。
  final String? message;

  /// 条件付きで緊急度が上がる場合の一覧。emergency → earlyConsultation の順で
  /// 段ごとにまとめてある（#76 レビュー N4/再レビュー S-a）。どちらの段も
  /// 無ければ空リスト。
  final List<ConsultEscalationGroup> escalationGroups;

  /// UI 用の免責文（医療監修を受けていない旨・根拠への言及を含む、#76 レビュー M2）。
  final String disclaimer;

  /// PNG 焼き込み用の短い免責文（`ExportCaption.disclaimer`、#76 レビュー M1/再レビュー M1'）。
  final String disclaimerShort;

  /// 免責文が参照する根拠（sensus の Medical notes）への URL。
  final Uri citationUrl;
}

/// urgency/escalation から [ConsultNotice] を解決する（#76 レビュー M1）。
///
/// [urgency] が `none` かつ [escalation] が空なら、表示する喚起が無いので
/// `null` を返す。呼び出し側（`FilterParamPanel`・`ExperiencePresets`・
/// `before_after_view.dart`）はこの 1 関数だけを呼べばよく、喚起文・
/// escalation の訳・免責文をそれぞれ個別に解決しない。
ConsultNotice? resolveConsultNotice(
  AppLocalizations l10n,
  Urgency urgency,
  List<UrgencyEscalation> escalation,
) {
  final message = urgencyConsultMessage(l10n, urgency);
  if (message == null && escalation.isEmpty) return null;

  final emergencyLines = [
    for (final e in escalation)
      if (e.urgency == Urgency.emergency) escalationConditionText(l10n, e.condition),
  ];
  final earlyLines = [
    for (final e in escalation)
      if (e.urgency == Urgency.earlyConsultation)
        escalationConditionText(l10n, e.condition),
  ];
  return ConsultNotice(
    urgency: urgency,
    message: message,
    escalationGroups: [
      if (emergencyLines.isNotEmpty)
        ConsultEscalationGroup(
          header: l10n.escalationHeaderEmergency,
          lines: emergencyLines,
        ),
      if (earlyLines.isNotEmpty)
        ConsultEscalationGroup(
          header: l10n.escalationHeaderEarly,
          lines: earlyLines,
        ),
    ],
    disclaimer: l10n.consultDisclaimer,
    disclaimerShort: l10n.consultDisclaimerShort,
    citationUrl: Uri.parse(kSensusMedicalNotesUrl),
  );
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
    // 起動モード・最前面・クリックスルーのトレイ項目 (#63) は WindowModePanel が
    // 使っているのと同じ ARB キーを再利用する（新規キー不要）。
    appModeLoupeLabel: l10n.windowModeLoupe,
    alwaysOnTopLabel: l10n.alwaysOnTopLabel,
    clickThroughLabel: l10n.clickThroughLabel,
  );
}
