import '../models/vision_filter_catalog.dart';
import '../services/tray_menu_labels.dart';
import '../services/vision_layer.dart';
import '../src/rust/api/sensus_bridge.dart';
import 'app_localizations.dart';

/// 定義（enum / catalog id）→ 表示文言（i18n）の解決をここに集約する (#18)。
///
/// 規律2（定義と表示文言を混ぜない）に従い、カタログ id・別名 id /
/// `VisionFilterCategory` / catalog の `id` といった
/// **識別子** は文言を持たず、表示する側がこのマッピングで `AppLocalizations`
/// から文字列を引く。UI（home_screen 等）とトレイ（起動時ロケールの
/// AppLocalizations インスタンス）の両方がここを参照し、二重定義を避ける。

/// 色覚キー（カタログ id または別名 id、[isColorVisionQuickKey]）の説明文を解決する。
/// 色覚クイック選択の 7 種以外は null。
String? visionFilterDescription(AppLocalizations l10n, String key) {
  switch (key) {
    case 'protanopia':
      return l10n.filterProtanopiaDesc;
    case 'deuteranopia':
      return l10n.filterDeuteranopiaDesc;
    case 'tritanopia':
      return l10n.filterTritanopiaDesc;
    case 'achromatopsia':
      return l10n.filterAchromatopsiaDesc;
    case 'protanomaly':
      return l10n.filterProtanomalyDesc;
    case 'deuteranomaly':
      return l10n.filterDeuteranomalyDesc;
    case 'tritanomaly':
      return l10n.filterTritanomalyDesc;
    default:
      return null;
  }
}

/// 色覚キー（カタログ id または別名 id）の有病率（おおよその人口比）を解決する。
/// 色覚クイック選択の 7 種以外は null。
///
/// 統計値（数値・%）は i18n でも変えず、訳語のみローカライズする。
String? visionFilterPrevalence(AppLocalizations l10n, String key) {
  switch (key) {
    case 'protanopia':
      return l10n.prevalenceProtanopia;
    case 'deuteranopia':
      return l10n.prevalenceDeuteranopia;
    case 'tritanopia':
      return l10n.prevalenceTritanopia;
    case 'achromatopsia':
      return l10n.prevalenceAchromatopsia;
    case 'protanomaly':
      return l10n.prevalenceProtanomaly;
    case 'deuteranomaly':
      return l10n.prevalenceDeuteranomaly;
    case 'tritanomaly':
      return l10n.prevalenceTritanomaly;
    default:
      return null;
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
    case 'info_board_ja':
      return l10n.sampleInfoBoardJa;
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

/// Advanced カタログ id（snake_case）→ フィルタ表示名を解決する。別名 id（-omaly）も
/// 引ける（カタログ id ではないが、強度の記憶・一覧の行のキーとして同じ位置に現れる）。
///
/// id は sensus shaders 名と一致する安定識別子。表示名はここで i18n に写像する。
String visionFilterName(AppLocalizations l10n, String id) {
  switch (id) {
    case 'protanomaly':
      return l10n.filterProtanomaly;
    case 'deuteranomaly':
      return l10n.filterDeuteranomaly;
    case 'tritanomaly':
      return l10n.filterTritanomaly;
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

/// フィルタの表示名を解決する、唯一の正本（#60。`before_after_view.dart` の
/// after ペイン見出し・export の caption・ルーペ窓 HUD（`loupe_hud.dart`、#79）
/// が共有する — 重複定義しない）。
///
/// [variantId] が非 null なら常にそれを優先する（-omaly の名前も正しく出る）。
/// カタログ（[filterId]）は色覚を 5 種しか持たず、-omaly は対応する base の -opia と
/// 同じ id に写るため、[filterId] だけで解決すると常に -opia の名前になってしまう。
/// [variantId] が null なら [filterId] からカタログの l10n 名（[visionFilterName]）を引く。
/// どちらも null なら「原画」。
String visionFilterDisplayName(
  AppLocalizations l10n,
  String? variantId,
  String? filterId,
) {
  if (variantId != null) return visionFilterName(l10n, variantId);
  if (filterId == null) return l10n.previewPaneOriginal;
  return visionFilterName(l10n, filterId);
}

/// 重ねている 1 層の表示名（#120）。別名（-omaly）の層は別名の名前、それ以外は
/// カタログの名前。チップ・調整パネルの節・見出し・HUD が共有する。
String visionLayerDisplayName(AppLocalizations l10n, VisionLayer layer) =>
    visionFilterName(l10n, layer.strengthKey);

/// 表示名に入れる層の名前の数の上限。これを超えた分は「…（+N）」にまとめる。
const int kLayerSummaryNamedCount = 2;

/// 複数の層の名前 [names]（適用順）を 1 行にまとめる（#120）。先頭 [kLayerSummaryNamedCount]
/// 個を「 + 」でつなぎ、残りがあれば「 …（+N）」を付ける。名前が 0 件なら空文字。
/// プレビューの after 側の見出しとルーペ HUD が同じ形を使う。
String layerNamesSummary(AppLocalizations l10n, List<String> names) {
  final shown = names.take(kLayerSummaryNamedCount).join(' + ');
  final rest = names.length - kLayerSummaryNamedCount;
  return rest > 0 ? l10n.layerSummaryMore(shown, rest) : shown;
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
/// （`ExperiencePresetTile`、`Experience.urgency`）・export の焼き込み
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
/// 選択可能なテキストとして表示する（#76）。アンカーは節そのもの
/// を指す（#76）。
const String kSensusMedicalNotesUrl =
    'https://github.com/kako-jun/sensus/blob/main/docs/overview.md'
    '#medical-notes-when-to-see-a-doctor';

/// [resolveConsultNotice] が返す、緊急度の段ごとにまとめた escalation
/// （見出し + 条件文のリスト）。UI（`ConsultNoticeBlock`）と PNG export
/// （`ExportCaption.escalationGroups`）の両方がこの単位で表示する
/// （#76: PNG でも段ごとの見出しを出す）。
class ConsultEscalationGroup {
  const ConsultEscalationGroup({required this.header, required this.lines});

  /// 見出し（`escalationHeaderEmergency` / `escalationHeaderEarly`）。
  final String header;

  /// [escalationConditionText] で解決済みの条件文（訳が無ければ英語）。
  final List<String> lines;
}

/// 受診喚起の解決結果。
///
/// urgency/escalation から「何を表示するか」を **1 箇所**（[resolveConsultNotice]）
/// で決め、advanced カタログ（`FilterParamPanel`）・体験プリセットのカード
/// （`ExperiencePresetTile`）・PNG export（`before_after_view.dart` /
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
  /// 段ごとにまとめてある。どちらの段も
  /// 無ければ空リスト。
  final List<ConsultEscalationGroup> escalationGroups;

  /// UI 用の免責文（医療監修を受けていない旨・根拠への言及を含む）。
  final String disclaimer;

  /// PNG 焼き込み用の短い免責文（`ExportCaption.disclaimer`）。
  final String disclaimerShort;

  /// 免責文が参照する根拠（sensus の Medical notes）への URL。
  final Uri citationUrl;
}

/// urgency/escalation から [ConsultNotice] を解決する。
///
/// [urgency] が `none` かつ [escalation] が空なら、表示する喚起が無いので
/// `null` を返す。呼び出し側（`FilterParamPanel`・`ExperiencePresetTile`・
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

/// ロケール解決済みの [AppLocalizations] からトレイメニュー文言を組み立てる (#18/#82)。
///
/// トレイは BuildContext を持てないため、`AppLocalizations.of(context)` ではなく
/// `lookupAppLocalizations(locale)` で得たインスタンスをここに渡す。color-vision
/// ラベルは [visionFilterName]（別名 id も含む）、「高度なフィルタ」サブメニュー（#65）の
/// カテゴリ見出し・フィルタ名は [visionCategoryName]・[visionFilterName] で解決する。
TrayMenuLabels trayMenuLabelsFrom(AppLocalizations l10n) {
  return TrayMenuLabels(
    showLoupe: l10n.trayShowLoupe,
    hideLoupe: l10n.trayHideLoupe,
    clearFilter: l10n.trayClearFilter,
    openSettings: l10n.trayOpenSettings,
    quit: l10n.trayQuit,
    // トップレベルのクイック 4 型に加え、「高度なフィルタ」サブメニュー（#65）の
    // 色覚行（-omaly を含む 7 型）を全てカバーする。
    filterLabels: {
      for (final key in [
        ...kColorVisionQuickCatalogIds,
        ...kVisionAliases.map((a) => a.id),
      ])
        key: visionFilterName(l10n, key),
    },
    advancedFilters: l10n.trayAdvancedFilters,
    categoryLabels: {
      for (final category in VisionFilterCategory.values)
        category: visionCategoryName(l10n, category),
    },
    catalogNames: {
      for (final entry in kVisionFilterCatalog)
        entry.id: visionFilterName(l10n, entry.id),
    },
    // 起動モード・最前面・クリックスルーのトレイ項目 (#63) は WindowModePanel が
    // 使っているのと同じ ARB キーを再利用する（新規キー不要）。
    appModeLoupeLabel: l10n.windowModeLoupe,
    alwaysOnTopLabel: l10n.alwaysOnTopLabel,
    clickThroughLabel: l10n.clickThroughLabel,
  );
}
