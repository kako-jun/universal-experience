import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/disability_type.dart';
import '../models/vision_filter_catalog.dart';
import '../src/rust/api/sensus_bridge.dart';
import 'vision_filter_metadata.dart';

/// フィルタ選択状態を保持する ChangeNotifier。**プレビュー（before/after）の
/// 描画対象の唯一の正本**（#60）。
///
/// 色覚 7 種のクイック選択（`FilterSelector`/トレイ、どちらも
/// `lib/services/color_vision_selection.dart` の `selectColorVision` を経由
/// して [selectColorVisionType] を呼ぶ）・advanced カタログ全 30 種・体験
/// プリセットのいずれで選んでも、最終的にここへ書き込まれる
/// （[selectColorVisionType] / [select] / [selectPreset]）。プレビュー
/// （`before_after_view.dart`）は `FilterService` を直接見ず、常にこの state
/// の [build] / [strength] / [selectedId] だけを描画対象にする。
/// `FilterService` は色覚タイプごとの強度の記憶（#57）としては引き続き使う
/// （どちらの強度を使うかの判定は `lib/services/preview_selection.dart` に
/// 集約）。
///
/// 保持するのは「どのフィルタ id を・どの payload パラメータ値で・どの strength で
/// 選んでいるか」（+ 選択の起源: [selectedPresetId] / [isColorQuickSelection] /
/// [colorVisionType]）だけ。アルゴリズムは持たず、選択 + パラメータから
/// sensus の [VisionFilter] インスタンスを組み立てる [build] を提供する。
class VisionFilterState extends ChangeNotifier {
  String? _selectedId;
  double _strength = 1.0;
  final Map<String, Object> _params = {};

  /// フィルタ id ごとの strength の記憶（#77）。初めて選ぶフィルタは
  /// [visionFilterRecommendedStrengthProvider] の推奨値で初期化し、以後は
  /// フィルタを切り替えても値が保持される（[_selectInternal] が読み書きする）。
  /// 構造はそのまま永続化できる形にしてある（永続化自体は #65 のスコープ）。
  final Map<String, double> _strengthById = {};

  /// フィルタ id ごとの payload パラメータの記憶（#77）。[_strengthById] と
  /// 同じ理由・同じライフサイクルで管理する。
  final Map<String, Map<String, Object>> _paramsById = {};

  /// 選択中の体験プリセット id（`Experience.id`。例: `meniere`）。プリセット
  /// 経由の選択でなければ null（#60）。
  ///
  /// meniere と labyrinthitis はどちらもカタログ id `vertigo` に写るため、
  /// `selectedId` だけでは「どちらのプリセットが選ばれているか」を区別できない
  /// （#60 の「2 枚同時に点灯」バグの原因）。この id を正本にして、
  /// `ExperiencePresets` の選択表示（`isSelected`）はカタログ id ではなく
  /// これを比較する。
  String? _selectedPresetId;

  /// 現在の選択が色覚のクイック選択（`FilterSelector`/トレイ、`FilterService`
  /// 経由）由来かどうか（#60）。
  ///
  /// **プレビューにどちらの強度を使うか（`FilterService` のタイプ別記憶 vs
  /// この state 自身の [strength]）を決める、唯一の判定材料**。この state が
  /// 「現在の選択の唯一の正本」になったことで、advanced カタログ・プリセット
  /// 由来の選択と色覚クイック選択のどちらも `selectedId` に同じ id
  /// （例: `protanopia`）が入り得るため、id の値そのものでは起源を区別できない。
  /// 実際の判定は `lib/services/preview_selection.dart` の `previewStrength` に
  /// 1 か所集約する（呼び出し側で個別に分岐させない）。
  bool _isColorQuickSelection = false;

  /// 色覚クイック選択で選ばれた実際の [ColorVisionType]（#60）。
  ///
  /// カタログ（[selectedId]）は色覚を 5 種（protanopia/deuteranopia/
  /// tritanopia/achromatopsia/tetrachromacy）しか持たず、-omaly（anomaly）
  /// 型は対応する base の -opia と同じカタログ id に写る（`FilterService` の
  /// 対応表と同じ規約）。そのため `selectedId` だけでは「protanopia を選んだ
  /// のか protanomaly を選んだのか」を区別できず、見出し・export の caption・
  /// ファイル名で常に -opia の名前が出てしまう（#60）。この値は
  /// その区別を保持するためだけにあり、[build] のフィルタ構築には使わない
  /// （構築は [selectedId] 経由の [_selectInternal] が単一の正本のまま）。
  /// 色覚クイック選択でなければ null。
  ColorVisionType? _colorVisionType;

  bool _bypassed = false;

  /// 一時的に「原画をそのまま表示」するか (#63 ホットキー「押している間だけ原画」)。
  /// 選択中のフィルタ・strength・params は一切変更しない。解除すれば元の見え方に戻る。
  bool get bypassed => _bypassed;

  void setBypassed(bool value) {
    if (_bypassed == value) return;
    _bypassed = value;
    notifyListeners();
  }

  /// 選択中のフィルタ id（snake_case）。未選択なら null。
  String? get selectedId => _selectedId;

  /// 選択中の体験プリセット id。プリセット経由でなければ null（#60）。
  String? get selectedPresetId => _selectedPresetId;

  /// 現在の選択が色覚クイック選択（`FilterSelector`/トレイ）由来か（#60）。
  bool get isColorQuickSelection => _isColorQuickSelection;

  /// 色覚クイック選択で選ばれた実際の [ColorVisionType]。色覚クイック選択で
  /// なければ null（#60）。
  ColorVisionType? get colorVisionType => _colorVisionType;

  /// 選択中のカタログエントリ。未選択なら null。
  VisionFilterEntry? get selectedEntry =>
      _selectedId == null ? null : kVisionFilterCatalogById[_selectedId];

  /// 適用強度 0.0..1.0。
  double get strength => _strength;

  /// 現在のパラメータ値マップ（読み取り専用ビュー）。
  Map<String, Object> get params => Map.unmodifiable(_params);

  /// 指定パラメータの現在値（未設定なら定義の defaultValue）。
  Object? paramValue(VisionParam param) =>
      _params[param.name] ?? param.defaultValue;

  /// フィルタを選択する（advanced カタログ UI から。#60: プリセット/色覚
  /// クイック選択の記録は解除する — 手動での advanced 選択は「別のフィルタを
  /// 手動で選んだ」ことになるため）。強度・パラメータはフィルタ id ごとに
  /// 記憶する（#77、#76 レビュー S5）: 既に選んだことのある id なら記憶値を
  /// 復元し、初めてなら既定パラメータ + sensus の推奨強度で初期化する
  /// （[_selectInternal] 参照）。
  void select(String id) {
    _selectedPresetId = null;
    _isColorQuickSelection = false;
    _colorVisionType = null;
    _bypassed = false;
    _selectInternal(id);
  }

  /// 色覚のクイック選択（`FilterSelector`/トレイ、
  /// `lib/services/color_vision_selection.dart` の `selectColorVision`/
  /// `deactivateColorVision` 経由）からフィルタを選択・解除する（#60）。
  ///
  /// [type] は選択された色覚型そのもの。[ColorVisionType.none] は「何も
  /// シミュレーションしない」ことを表し、解除（[deactivateColorVision]）と
  /// 同じ効果になる — この場合 [isColorQuickSelection] は **false** のまま
  /// になる（[FilterSelector] の「Normal vision」チップ・`IntensitySlider`・
  /// 解除ボタンのいずれも、[isColorQuickSelection] だけを見て点灯/有効化を
  /// 決めるため、none を「選択中」扱いにすると強度スライダーだけが宙に浮いて
  /// 有効化されてしまう。none はカタログにも強度概念にも対応しない）。
  ///
  /// [type] が非 none のときは [isColorQuickSelection] を true にし、
  /// [colorVisionType] として保持する（-omaly の名前を見出し・export の
  /// caption・ファイル名に正しく出すため、#60）。[catalogId] は [type] に
  /// 対応するカタログ id（`visionFilterCatalogId` / `visionFilterForColorVisionType`
  /// 経由で呼び出し側が解決する）— [type] が [ColorVisionType.none] のときは
  /// 無視されるので省略できる。
  ///
  /// advanced/プリセットの選択中に呼ばれても（＝「別のフィルタを手動で選ぶ」
  /// 操作として）常に上書きする。プリセットの選択は解除する。
  void selectColorVisionType(ColorVisionType type, [String? catalogId]) {
    _selectedPresetId = null;
    _bypassed = false;
    if (type == ColorVisionType.none) {
      _isColorQuickSelection = false;
      _colorVisionType = null;
      _selectedId = null;
      _params.clear();
      notifyListeners();
      return;
    }
    if (catalogId == null) {
      throw ArgumentError(
        'catalogId is required when type != ColorVisionType.none',
      );
    }
    _isColorQuickSelection = true;
    _colorVisionType = type;
    _selectInternal(catalogId);
  }

  /// 体験プリセット（`ExperiencePresets`）からフィルタを選択する（#60）。
  /// [presetId] は `Experience.id`、[catalogId] はその体験の視覚フィルタに
  /// 対応するカタログ id。色覚クイック選択の記録は解除する。強度・パラメータは
  /// 常に推奨値・既定値にする（#76 レビュー N1: advanced 側で当該 id を
  /// カスタマイズ済みでも、プリセットは常に『代表的な程度』で体験してもらう
  /// ため、[_selectInternal] の記憶優先ロジックは経由しない。#60 で入れていた
  /// 「強度を強制的に 1.0 に戻す」を #77 で「常に推奨値」へ置き換えた）。
  /// notifyListeners は 1 回だけ呼ぶ（#76 レビュー N2）。
  void selectPreset(String presetId, String catalogId) {
    final entry = kVisionFilterCatalogById[catalogId];
    if (entry == null) {
      throw ArgumentError('Unknown vision filter id: $catalogId');
    }
    _selectedPresetId = presetId;
    _isColorQuickSelection = false;
    _colorVisionType = null;
    _bypassed = false;
    _selectedId = catalogId;
    _params
      ..clear()
      ..addAll(_defaultParamsFor(entry));
    _strength = _recommendedStrength();
    _paramsById[catalogId] = Map<String, Object>.from(_params);
    _strengthById[catalogId] = _strength;
    notifyListeners();
  }

  /// [entry] の payload パラメータを、カタログの defaultValue から組み立てる
  /// （純粋関数。副作用なし）。seed は sensus u64 なので BigInt 化する
  /// （int/double を経由させず精度欠落を防ぐ）。[_selectInternal] の初回選択・
  /// [resetToRecommended]・[selectPreset] が共有する（#76 レビュー N3）。
  Map<String, Object> _defaultParamsFor(VisionFilterEntry entry) {
    final params = <String, Object>{};
    for (final p in entry.parameters) {
      if (p.defaultValue == null) continue;
      params[p.name] = p.kind == VisionParamKind.seed
          ? _toSeedBigInt(p.defaultValue!)
          : p.defaultValue!;
    }
    return params;
  }

  /// 現在の [_selectedId]/[_params] から組み立てた [VisionFilter] の推奨強度
  /// （sensus の `recommended_strength()`、[visionFilterRecommendedStrengthProvider]
  /// 経由）。urgency と同じく payload に依存しないため、呼び出し時点の
  /// payload（既定値・記憶値のどちらでも）をそのまま [build] してよい。未選択
  /// なら 1.0。[_selectInternal]・[resetToRecommended]・[selectPreset] が共有
  /// する（#76 レビュー N3）。
  double _recommendedStrength() {
    final builtFilter = build();
    return builtFilter == null
        ? 1.0
        : visionFilterRecommendedStrengthProvider(builtFilter).clamp(0.0, 1.0);
  }

  /// [id] を選択状態にする。強度・パラメータはフィルタ id ごとに記憶する
  /// （#77）: 既に選んだことのある id なら記憶値を復元し、初めてなら
  /// カタログの既定パラメータ（[_defaultParamsFor]） + sensus の推奨強度
  /// （[_recommendedStrength]）で初期化してから記憶する。
  void _selectInternal(String id) {
    final entry = kVisionFilterCatalogById[id];
    if (entry == null) {
      throw ArgumentError('Unknown vision filter id: $id');
    }
    _selectedId = id;

    final rememberedParams = _paramsById[id];
    if (rememberedParams != null) {
      _params
        ..clear()
        ..addAll(rememberedParams);
    } else {
      _params
        ..clear()
        ..addAll(_defaultParamsFor(entry));
      // 初めて選ぶフィルタ: 今組み立てた既定パラメータをそのまま記憶する。
      _paramsById[id] = Map<String, Object>.from(_params);
    }

    final rememberedStrength = _strengthById[id];
    if (rememberedStrength != null) {
      _strength = rememberedStrength;
    } else {
      _strength = _recommendedStrength();
      _strengthById[id] = _strength;
    }
    notifyListeners();
  }

  /// 選択を解除する。フィルタごとの強度・パラメータの記憶（[_strengthById] /
  /// [_paramsById]）はクリアしない — 同じフィルタを選び直したときに復元される
  /// ためのものなので、選択解除では消さない。
  void clear() {
    _selectedId = null;
    _selectedPresetId = null;
    _isColorQuickSelection = false;
    _colorVisionType = null;
    _bypassed = false;
    _params.clear();
    notifyListeners();
  }

  /// 現在選択中フィルタの強度とパラメータを、推奨値・カタログ既定値に戻す
  /// （#77 の「推奨値に戻す」ボタン）。未選択なら何もしない。プリセット選択中に
  /// 呼ばれたらプリセットの選択表示は解除する（[setStrength]/[setParam] と
  /// 同じ理由）。
  void resetToRecommended() {
    final id = _selectedId;
    final entry = id == null ? null : kVisionFilterCatalogById[id];
    if (id == null || entry == null) return;

    _params
      ..clear()
      ..addAll(_defaultParamsFor(entry));
    _strength = _recommendedStrength();

    _paramsById[id] = Map<String, Object>.from(_params);
    _strengthById[id] = _strength;

    _bypassed = false;
    _clearPresetSelectionOnCustomize();
    notifyListeners();
  }

  /// strength を 0.0..1.0 に clamp して更新する。フィルタ id ごとの記憶
  /// （[_strengthById]、#77）にも書き戻す。プリセット選択中に呼ばれたら
  /// プリセットの選択表示は解除する（#60: strength を弄った時点で「その
  /// プリセットそのもの」ではなくなるため）。
  void setStrength(double value) {
    _strength = value.clamp(0.0, 1.0);
    final id = _selectedId;
    if (id != null) _strengthById[id] = _strength;
    _bypassed = false;
    _clearPresetSelectionOnCustomize();
    notifyListeners();
  }

  /// パラメータ値を更新する（型は呼び出し側責務: float→double / int→int /
  /// enum→String value / seed→[BigInt]）。フィルタ id ごとの記憶
  /// （[_paramsById]、#77）にも書き戻す。プリセット選択中に呼ばれたら
  /// プリセットの選択表示は解除する（#60、[setStrength] と同じ理由）。
  void setParam(String name, Object value) {
    _params[name] = value;
    final id = _selectedId;
    if (id != null) {
      (_paramsById[id] ??= {})[name] = value;
    }
    _bypassed = false;
    _clearPresetSelectionOnCustomize();
    notifyListeners();
  }

  /// プリセット選択中に strength/param が手動で変更されたら、プリセットの
  /// 選択表示（[selectedPresetId]）だけを解除する（#60）。フィルタ自体の
  /// 選択（[selectedId]）・payload はそのまま残す — ユーザーはプリセットの
  /// フィルタを起点にカスタマイズしているだけで、選択を丸ごと解除したい
  /// わけではない。
  void _clearPresetSelectionOnCustomize() {
    if (_selectedPresetId != null) {
      _selectedPresetId = null;
    }
  }

  /// seed パラメータを乱数で再生成する。プリセット選択中に呼ばれたらプリセットの
  /// 選択表示は解除する（[setParam]/[setStrength] と同じ理由、#60）。
  ///
  /// seed は sensus の `u64`（Dart [BigInt]）。int/double を経由すると 2^53 超で
  /// 精度が落ちるため、生成・保持とも [BigInt] で全 u64 範囲（0..[kSeedMax]）を
  /// 扱う。
  void randomizeSeed(String name) {
    final seed = _nextSeed();
    _params[name] = seed;
    final id = _selectedId;
    if (id != null) {
      (_paramsById[id] ??= {})[name] = seed;
    }
    _bypassed = false;
    _clearPresetSelectionOnCustomize();
    notifyListeners();
  }

  /// 選択 + パラメータ値から sensus の [VisionFilter] を構築する。
  ///
  /// 未選択なら null。payload を持つフィルタは [_params]（未設定は定義の
  /// defaultValue）から組み立てる。
  VisionFilter? build() {
    final id = _selectedId;
    if (id == null) return null;

    switch (id) {
      // ── 色覚 ──
      case 'protanopia':
        return const VisionFilter.protanopia();
      case 'deuteranopia':
        return const VisionFilter.deuteranopia();
      case 'tritanopia':
        return const VisionFilter.tritanopia();
      case 'achromatopsia':
        return const VisionFilter.achromatopsia();
      case 'tetrachromacy':
        return const VisionFilter.tetrachromacy();

      // ── 屈折 ──
      case 'myopia':
        return const VisionFilter.myopia();
      case 'hyperopia':
        return const VisionFilter.hyperopia();
      case 'presbyopia':
        return const VisionFilter.presbyopia();
      case 'astigmatism':
        return VisionFilter.astigmatism(axisDeg: _float('axisDeg'));

      // ── 視野 ──
      // 4 フィルタとも field_loss_mode は常に darken 固定で構築する。
      // GPU 経路が field_loss_mode を無視する（常に Darken 相当で描画される）ため、
      // カタログには UI パラメータとして出していない
      // （kVisionFilterCatalog の doc コメント参照）。
      case 'glaucoma':
        return VisionFilter.glaucoma(
          mode: _glaucomaMode('mode'),
          fieldLossMode: VisionFieldLossMode.darken,
        );
      case 'macular_degeneration':
        return const VisionFilter.macularDegeneration(
          fieldLossMode: VisionFieldLossMode.darken,
        );
      case 'hemianopia':
        return VisionFilter.hemianopia(
          side: _hemianopiaSide('side'),
          fieldLossMode: VisionFieldLossMode.darken,
        );
      case 'tunnel_vision':
        return const VisionFilter.tunnelVision(
          fieldLossMode: VisionFieldLossMode.darken,
        );

      // ── 光・透明度 ──
      case 'cataract':
        return VisionFilter.cataract(seed: _seed('seed'));
      case 'floaters':
        return VisionFilter.floaters(
          seed: _seed('seed'),
          density: _float('density'),
          size: _float('size'),
          gazeX: _float('gazeX'),
          gazeY: _float('gazeY'),
        );
      case 'photophobia':
        return const VisionFilter.photophobia();
      case 'night_blindness':
        return const VisionFilter.nightBlindness();
      case 'starbursts':
        return VisionFilter.starbursts(
          numRays: _int('numRays'),
          rayLengthRatio: _float('rayLengthRatio'),
          threshold: _float('threshold'),
          dispersion: _float('dispersion'),
        );

      // ── 前庭・めまい ──
      case 'vertigo':
        return const VisionFilter.vertigo();
      case 'bppv_rotation':
        return const VisionFilter.bppvRotation();
      case 'vestibular_neuritis':
        return const VisionFilter.vestibularNeuritis();
      case 'nystagmus':
        return VisionFilter.nystagmus(
          amplitude: _float('amplitude'),
          directionDeg: _float('directionDeg'),
        );

      // ── 眼精疲労 ──
      case 'eye_strain':
        return const VisionFilter.eyeStrain();
      case 'dry_eye':
        return const VisionFilter.dryEye();
      case 'contrast_sensitivity':
        return const VisionFilter.contrastSensitivity();

      // ── その他 ──
      case 'diplopia':
        return VisionFilter.diplopia(
          offsetX: _float('offsetX'),
          offsetY: _float('offsetY'),
          ghostStrength: _float('ghostStrength'),
        );
      case 'metamorphopsia':
        return VisionFilter.metamorphopsia(
          freq: _float('freq'),
          seed: _seed('seed'),
        );
      case 'detail_loss':
        return VisionFilter.detailLoss(cellSize: _int('cellSize'));
      case 'teichopsia':
        return const VisionFilter.teichopsia();
      case 'flickering_stars':
        return VisionFilter.flickeringStars(seed: _seed('seed'));
    }
    throw StateError('Unhandled vision filter id in build(): $id');
  }

  // ── payload 値の取り出し（未設定はカタログ定義の defaultValue へフォールバック）──

  Object? _raw(String name) {
    if (_params.containsKey(name)) return _params[name];
    final entry = selectedEntry;
    if (entry == null) return null;
    for (final p in entry.parameters) {
      if (p.name == name) return p.defaultValue;
    }
    return null;
  }

  double _float(String name) {
    final v = _raw(name);
    if (v is num) return v.toDouble();
    return 0.0;
  }

  int _int(String name) {
    final v = _raw(name);
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }

  BigInt _seed(String name) {
    final v = _raw(name);
    if (v is BigInt) return v;
    if (v is int) return BigInt.from(v);
    if (v is num) return BigInt.from(v.toInt());
    return BigInt.zero;
  }

  VisionGlaucomaMode _glaucomaMode(String name) {
    switch (_raw(name)) {
      case 'vignette':
        return VisionGlaucomaMode.vignette;
      case 'arcuateSuperior':
        return VisionGlaucomaMode.arcuateSuperior;
      case 'arcuateInferior':
        return VisionGlaucomaMode.arcuateInferior;
      case 'biarcuate':
        return VisionGlaucomaMode.biarcuate;
      default:
        return VisionGlaucomaMode.vignette;
    }
  }

  /// hemianopia の side: UI の文字列キー（'left'/'right'）を sensus の
  /// `double side` に写像する。写像の定義は [kHemianopiaSideValues] が単一の正本
  /// （'left'→0.0, 'right'→1.0）。ここはそれを参照するだけにして、catalog の
  /// options 定義との不整合を防ぐ。未知キーは 'left'（=0.0）にフォールバック。
  double _hemianopiaSide(String name) {
    final key = _raw(name);
    return kHemianopiaSideValues[key] ?? kHemianopiaSideValues['left']!;
  }

  /// 任意の数値/BigInt を seed 用 [BigInt] に正規化する。
  static BigInt _toSeedBigInt(Object value) {
    if (value is BigInt) return value;
    if (value is int) return BigInt.from(value);
    if (value is num) return BigInt.from(value.toInt());
    return BigInt.zero;
  }

  final Random _rng = Random();

  /// 全 u64 範囲（0..[kSeedMax]）の [BigInt] を一様に近い形で生成する。
  ///
  /// int/double を経由せず BigInt 空間だけで組み立てるので、2^53 超でも精度欠落
  /// しない。32bit ずつ乱数を引いて連結する。
  BigInt _nextSeed() {
    final bound = kSeedMax + BigInt.one; // 排他上限 = 2^64
    final bitLength = bound.bitLength;
    BigInt result;
    do {
      result = BigInt.zero;
      var remaining = bitLength;
      while (remaining > 0) {
        final take = remaining < 32 ? remaining : 32;
        final chunk = BigInt.from(_rng.nextInt(1 << take));
        result = (result << take) | chunk;
        remaining -= take;
      }
    } while (result >= bound);
    return result;
  }
}
