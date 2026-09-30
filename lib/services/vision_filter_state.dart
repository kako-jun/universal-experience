import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/disability_type.dart';
import '../models/vision_filter_catalog.dart';
import '../models/vision_filter_stage.dart';
import '../src/rust/api/sensus_bridge.dart';
import 'filter_service.dart' show recommendedStrength;
import 'vision_filter_metadata.dart';
import 'vision_filter_snapshot.dart';
import 'vision_layer.dart';

/// フィルタ選択状態を保持する ChangeNotifier。**プレビュー（before/after）の
/// 描画対象の唯一の正本**（#60）。
///
/// 色覚 7 種のクイック選択（`FilterBrowser`/トレイ、どちらも
/// `lib/services/color_vision_selection.dart` の `selectColorVision` を経由
/// して [selectColorVisionType] を呼ぶ）・advanced カタログ全 30 種・体験
/// プリセットのいずれで選んでも、最終的にここへ書き込まれる
/// （[selectColorVisionType] / [select] / [selectPreset]）。プレビュー
/// （`before_after_view.dart`）は `FilterService` を直接見ず、常にこの state
/// の [build] / [strength] / [selectedId] だけを描画対象にする。
///
/// ## 順序つきレイヤー列（#117）
///
/// 状態の正本は [layers]（[VisionLayer] の適用順の列）。各層は「カタログ id・
/// payload・別名（-omaly）・起源（quick/advanced）」を持ち、**強度は持たない**。
/// 強度は「キー（別名 id ?? カタログ id）ごとの記憶」（[strengthForKey]）に 1 つだけ
/// あり、層の強度は読むときに [strengthOf] が導出する（記憶が無ければ推奨強度。
/// 導出した既定値は記憶へ書かない）。色覚クイック選択と advanced で同じ色覚を
/// 選んでも強度が二重にならない。
///
/// 層の列は [normalizeVisionLayers] の不変条件（id 重複なし・色覚グループ排他・
/// 上限 [kMaxVisionLayers]・適用順）を満たす。多選択の操作は [toggle] / [remove] /
/// [setLayerStrength] / [setLayerParams] / [replaceWith] / [clear]（#119）。適用順は
/// 段（`vision_filter_stage.dart`）で決まり、選んだ順には依存しない。従来の単一選択
/// API（[selectedId] / [strength] / [params] / [isColorQuickSelection] /
/// [colorVisionType]）は **フォーカス中の層**（[focusedId]）を指す互換の読み口として
/// 残している（単一選択 = 1 層の多選択）。複数層の UI は #120 以降。
///
/// アルゴリズムは持たず、層 + パラメータから sensus の [VisionFilter] インスタンスを
/// 組み立てる [build] / [buildLayer] を提供する。
class VisionFilterState extends ChangeNotifier {
  List<VisionLayer> _layers = const [];
  String? _focusedId;

  /// キー（[VisionLayer.strengthKey]）ごとの強度の記憶（0.0..1.0）。書き込むのは
  /// 利用者の操作（[setStrength] / [setStrengthForKey]）だけで、推奨強度のフォール
  /// バックは書かない（[strengthOf] は読むたびに導出する）。永続化は [snapshot] /
  /// [restore]（`vision_filter_store.dart` が JSON で保存する、#65）。
  final Map<String, double> _strengthByKey = {};

  /// フィルタ id ごとの payload パラメータの記憶（#77）。フィルタを切り替えても
  /// 値が保持される。[_strengthByKey] と同じライフサイクルで管理する。
  final Map<String, Map<String, Object>> _paramsById = {};

  /// 選択中の体験プリセット id（`Experience.id`。例: `meniere`）。プリセット
  /// 経由の選択でなければ null（#60）。層がちょうど 1 つのときだけ持つ。
  ///
  /// meniere と labyrinthitis はどちらもカタログ id `vertigo` に写るため、
  /// `selectedId` だけでは「どちらのプリセットが選ばれているか」を区別できない
  /// （#60 の「2 枚同時に点灯」バグの原因）。この id を正本にして、
  /// `ExperiencePresetTile` の選択表示（`isSelected`）はカタログ id ではなく
  /// これを比較する。
  String? _selectedPresetId;

  /// [_selectedPresetId] を選んだときの層のカタログ id。層の集合が「この 1 層だけ」で
  /// なくなったらプリセット選択を外す判定（[_dropPresetIfLayersDiverged]）に使う。
  /// プリセット選択が無いときは null。
  String? _presetLayerId;

  /// 一時的に「原画をそのまま表示」させている入力元の集合（#79）。
  ///
  /// #63 では単一の bool だったが、ホットキー（`hotkey_actions.dart`）と
  /// ルーペ HUD（`loupe_hud.dart`、#79）の両方が同時に「押している間だけ原画」を
  /// 要求しうるようになったため、入力元ごとの保持（holder）に変更した。片方が
  /// 離してももう片方が保持していれば bypassed のままになる（#79）。
  /// 各呼び出し元は自分専用の識別子（Object の同一性で十分。文字列でも可）を
  /// [acquireBypass]/[releaseBypass] に渡し、同じ識別子で対にする。
  final Set<Object> _bypassHolders = {};

  /// 一時的に「原画をそのまま表示」するか (#63 ホットキー「押している間だけ原画」)。
  /// 選択中のフィルタ・strength・params は一切変更しない。誰も保持していなければ
  /// false（#79: holder が 1 つでもあれば true）。
  bool get bypassed => _bypassHolders.isNotEmpty;

  /// [source] を bypass の holder として追加する（#79）。既に保持していれば
  /// no-op（冪等）。
  void acquireBypass(Object source) {
    if (_bypassHolders.add(source)) notifyListeners();
  }

  /// [source] の bypass 保持を解除する（#79）。保持していなければ no-op
  /// （冪等 — dispose 等から無条件に呼んでよい）。
  void releaseBypass(Object source) {
    if (_bypassHolders.remove(source)) notifyListeners();
  }

  /// 誰が保持しているかに関わらず、すべての bypass holder を強制的に解除する
  /// （#79）。フィルタ選択・強度変更・非常口など、「原画比較の状態に関わらず
  /// 必ずフィルタ表示に戻す」操作から呼ぶ。[select] 等の内部呼び出しは
  /// notifyListeners の二重呼び出しを避けるため直接 [_bypassHolders] を
  /// clear するだけに留め、この公開メソッドは外部（`hotkey_actions.dart` の
  /// 非常口）から明示的に呼ぶ用。
  void clearBypass() {
    if (_bypassHolders.isEmpty) return;
    _bypassHolders.clear();
    notifyListeners();
  }

  /// [source] が現在 bypass を保持しているか（#79）。ホットキー
  /// （`hotkey_actions.dart`）の hold/toggle 判定や、ルーペ HUD の原画比較
  /// ボタンのトグル代替（`loupe_hud.dart`）が、ローカルにミラーした bool を
  /// 持つ代わりにこれを直接クエリする — ローカルなミラーは `clearBypass()`
  /// 等の外部からの一括解除に追従できず、解除済みなのに release し続けて
  /// 何も起きない（あるいはその逆）というズレを起こすため。
  bool isHeldBy(Object source) => _bypassHolders.contains(source);

  // ── レイヤー列の読み口 ──

  /// 重ねている層（適用順。読み取り専用）。
  List<VisionLayer> get layers => _layers;

  /// フォーカス中の層のカタログ id（最後に追加または触れた層）。層が無ければ null。
  String? get focusedId => _focusedId;

  /// フォーカス中の層。層が無ければ null。
  VisionLayer? get focusedLayer {
    final id = _focusedId;
    if (id == null) return null;
    for (final l in _layers) {
      if (l.id == id) return l;
    }
    return null;
  }

  /// キー（別名 id ?? カタログ id）ごとに記憶している強度。未記憶なら null
  /// （推奨強度へのフォールバックは [strengthOf] / 呼び出し側が行う）。
  double? strengthForKey(String key) => _strengthByKey[key];

  /// 強度の記憶の読み取り専用ビュー。
  Map<String, double> get strengthByKey => Map.unmodifiable(_strengthByKey);

  /// [key] の強度の記憶を 0.0..1.0 に clamp して書く。選択・bypass・プリセット表示は
  /// 触らない（`FilterService.setIntensity` が色覚クイック選択の強度スライダーから
  /// 書く入口）。listener へは 1 回通知する。
  void setStrengthForKey(String key, double value) {
    _strengthByKey[key] = value.clamp(0.0, 1.0);
    notifyListeners();
  }

  /// [layer] の強度。記憶があればそれ、無ければ推奨強度を**導出**する（記憶へは
  /// 書かない）。別名（-omaly）と色覚 -opia は [recommendedStrength]、それ以外は
  /// sensus の `recommended_strength()`（[visionFilterRecommendedStrengthProvider]）。
  double strengthOf(VisionLayer layer) =>
      _strengthByKey[layer.strengthKey] ?? _defaultStrength(layer);

  double _defaultStrength(VisionLayer layer) {
    final key = layer.variantId ?? layer.id;
    final colorType = colorVisionTypeByName(key);
    if (colorType != null) return recommendedStrength(colorType);
    return visionFilterRecommendedStrengthProvider(buildLayer(layer))
        .clamp(0.0, 1.0);
  }

  // ── 単一選択の互換の読み口（フォーカス中の層を指す）──

  /// 選択中（フォーカス中）のフィルタ id（snake_case）。未選択なら null。
  String? get selectedId => focusedLayer?.id;

  /// 選択中の体験プリセット id。プリセット経由でなければ null（#60）。
  String? get selectedPresetId => _selectedPresetId;

  /// フォーカス中の層が色覚クイック選択（`FilterBrowser`/トレイ）由来か（#60）。
  /// かつての state 全体のフラグは、層ごとの [VisionLayer.origin] に置き換わった。
  bool get isColorQuickSelection =>
      focusedLayer?.origin == VisionLayerOrigin.quick;

  /// 色覚クイック選択で選ばれた実際の [ColorVisionType]。色覚クイック選択で
  /// なければ null（#60）。-omaly は別名（[VisionLayer.variantId]）から復元する。
  ColorVisionType? get colorVisionType {
    final layer = focusedLayer;
    return layer == null ? null : quickColorVisionTypeOf(layer);
  }

  /// 選択中のカタログエントリ。未選択なら null。
  VisionFilterEntry? get selectedEntry {
    final id = selectedId;
    return id == null ? null : kVisionFilterCatalogById[id];
  }

  /// フォーカス中の層の適用強度 0.0..1.0（[strengthOf]）。未選択なら 1.0。
  double get strength {
    final layer = focusedLayer;
    return layer == null ? 1.0 : strengthOf(layer);
  }

  /// フォーカス中の層の現在のパラメータ値マップ（読み取り専用ビュー）。
  Map<String, Object> get params =>
      Map.unmodifiable(focusedLayer?.params ?? const <String, Object>{});

  /// 指定パラメータの現在値（未設定なら定義の defaultValue）。
  Object? paramValue(VisionParam param) =>
      focusedLayer?.params[param.name] ?? param.defaultValue;

  // ── 選択操作 ──

  VisionFilterEntry _entryOrThrow(String id) {
    final entry = kVisionFilterCatalogById[id];
    if (entry == null) {
      throw ArgumentError('Unknown vision filter id: $id');
    }
    return entry;
  }

  VisionLayer? _layerById(String id) {
    for (final l in _layers) {
      if (l.id == id) return l;
    }
    return null;
  }

  /// [entry] の payload。記憶があればそれ、初めてなら既定値（記憶にも入れる）。
  Map<String, Object> _paramsFor(VisionFilterEntry entry) {
    final remembered = _paramsById[entry.id];
    if (remembered != null) return Map<String, Object>.from(remembered);
    final params = defaultVisionParams(entry);
    if (params.isNotEmpty) {
      _paramsById[entry.id] = Map<String, Object>.from(params);
    }
    return params;
  }

  /// [id] を [variantId]・[origin] の層にする。別名は [isValidVariantFor] に合うものだけ。
  VisionLayer _newLayer(
    String id,
    String? variantId,
    VisionLayerOrigin origin,
  ) {
    final entry = _entryOrThrow(id);
    if (variantId != null && !isValidVariantFor(id, variantId)) {
      throw ArgumentError('Invalid variant "$variantId" for vision filter $id');
    }
    return VisionLayer(
      id: entry.id,
      params: _paramsFor(entry),
      variantId: variantId,
      origin: origin,
    );
  }

  void _setSingleLayer(VisionLayer layer) {
    _layers = List.unmodifiable([layer]);
    _focusedId = layer.id;
  }

  /// 層の集合が変わった後、プリセット選択を外すべきなら外す。**戻さない**: 集合が
  /// プリセットのフィルタ 1 つ以外になったら外れ、のちに集合が 1 つに戻っても復活しない。
  void _dropPresetIfLayersDiverged() {
    if (_selectedPresetId == null) return;
    if (_layers.length == 1 && _layers.single.id == _presetLayerId) return;
    _selectedPresetId = null;
    _presetLayerId = null;
  }

  /// [id] の層を外した後のフォーカス。外した層がフォーカス中だった場合は適用順で最後の
  /// 層（[_layers] は常に適用順）、それ以外は変えない。層が無ければ null。
  void _refocusAfterRemoval(String removedId) {
    if (_focusedId != removedId) return;
    _focusedId = _layers.isEmpty ? null : _layers.last.id;
  }

  /// 未選択の [id] をいま足せない理由。足せる（または選択済みで、外す/別の色覚への
  /// 置換になるだけの）なら null。UI が行の無効化に使う（#120）。[toggle] が上限で
  /// 何もしない条件と同じ判定。
  ///
  /// 上限 [kMaxVisionLayers] に達していても受け付けるもの: ①選択済みの id（外す、または
  /// 同じ id の別名への切り替え）、②既に色覚層があるときの色覚行（置換なので層数が増えない）。
  /// 色覚層が無いまま上限のときの色覚行は受け付けない。
  VisionLayerBlockReason? blockReasonFor(String id) {
    _entryOrThrow(id);
    if (_layerById(id) != null) return null;
    if (_layers.length < kMaxVisionLayers) return null;
    if (isVisionColorGroupId(id) &&
        _layers.any((l) => isVisionColorGroupId(l.id))) {
      return null;
    }
    return VisionLayerBlockReason.layerLimit;
  }

  /// [id] を選択/解除する（多選択の入口、#119）。
  ///
  ///  * 同じ層（id と [variantId] が同じ）が選択済みなら外す（[VisionLayerResult.removed]）。
  ///    外した層がフォーカス中なら、フォーカスは適用順で最後の層へ移る。
  ///  * 未選択なら足す（[VisionLayerResult.added]）。フォーカスは足した層へ。層は選んだ順でなく
  ///    段順（`vision_filter_stage.dart`）に並ぶ。
  ///  * 色覚グループ（5 フィルタ + -omaly）は同時に 1 つ。既に色覚層があれば、それを外して
  ///    これに置き換える（[VisionLayerResult.replaced]。-opia ⇄ -omaly も同じ id の別名への
  ///    置換）。
  ///  * 上限（[kMaxVisionLayers]）で足せないときは**何も変えずに**
  ///    [VisionLayerResult.blocked]（理由 [VisionLayerBlockReason.layerLimit]）を返す。
  ///    例外は [blockReasonFor] のとおり。
  ///
  /// 足す層の [origin] は既定で advanced（色覚クイック選択の層を足すときは
  /// [VisionLayerOrigin.quick] と、-omaly なら [variantId] を渡す）。payload は id ごとの記憶
  /// から、強度はキーごとの記憶から導出する。体験プリセットの選択は、層の集合がそのフィルタ
  /// 1 つ以外になった時点で外れる（戻さない）。原画比較（bypass）は解除する。
  VisionLayerResult toggle(
    String id, {
    String? variantId,
    VisionLayerOrigin origin = VisionLayerOrigin.advanced,
  }) {
    final existing = _layerById(id);
    if (existing != null && existing.variantId == variantId) {
      _removeLayer(existing);
      return VisionLayerResult.removed;
    }
    final blocked = blockReasonFor(id);
    if (blocked != null) return VisionLayerResult.blocked(blocked);

    final layer = _newLayer(id, variantId, origin);
    final replacing =
        isVisionColorGroupId(id) &&
        _layers.any((l) => isVisionColorGroupId(l.id));
    _layers = normalizeVisionLayers([
      for (final l in _layers)
        if (!(replacing && isVisionColorGroupId(l.id))) l,
      layer,
    ]);
    _focusedId = layer.id;
    _bypassHolders.clear();
    _dropPresetIfLayersDiverged();
    notifyListeners();
    return replacing ? VisionLayerResult.replaced : VisionLayerResult.added;
  }

  /// [id] の層を外す。選択されていなければ何もせず false。フォーカスの移り方は [toggle] の
  /// 解除と同じ。強度・payload の記憶は消さない。
  bool remove(String id) {
    final layer = _layerById(id);
    if (layer == null) return false;
    _removeLayer(layer);
    return true;
  }

  void _removeLayer(VisionLayer layer) {
    _layers = List.unmodifiable([
      for (final l in _layers)
        if (l.id != layer.id) l,
    ]);
    _refocusAfterRemoval(layer.id);
    _bypassHolders.clear();
    _dropPresetIfLayersDiverged();
    notifyListeners();
  }

  /// [id] の層の強度を 0.0..1.0 に clamp して、その層のキーの記憶へ書く。その層がフォーカスの
  /// 移り先になる（「最後に触れた層」）。[id] の層が無ければ何もしない。プリセット選択中は
  /// プリセットの選択表示を解除する（[setStrength] と同じ理由）。強度 0 の層は描画から
  /// 除かれるが、層としては残る（上限にも数える）。
  void setLayerStrength(String id, double value) {
    final layer = _layerById(id);
    if (layer == null) return;
    _focusedId = id;
    _writeStrength(layer, value);
  }

  /// [id] の層の payload を [params] に置き換え、id ごとの記憶にも書く。その層がフォーカスの
  /// 移り先になる。[id] の層が無ければ何もしない。値の型は呼び出し側責務（[setParam] と同じ）。
  /// プリセット選択中はプリセットの選択表示を解除する。
  void setLayerParams(String id, Map<String, Object> params) {
    final layer = _layerById(id);
    if (layer == null) return;
    _focusedId = id;
    _replaceLayer(layer.copyWith(params: Map<String, Object>.from(params)));
    _paramsById[id] = Map<String, Object>.from(params);
    _bypassHolders.clear();
    _clearPresetSelectionOnCustomize();
    notifyListeners();
  }

  /// 層を全部外して [id] だけにする（従来の単一選択）。上限・排他の判定は要らない
  /// （結果は常に 1 層）。プリセット選択・原画比較は解除する。payload はフィルタ id ごとに
  /// 記憶する（#77）。強度はキーごとの記憶から導出する（初めてなら推奨強度。記憶へは書かない）。
  void replaceWith(
    String id, {
    String? variantId,
    VisionLayerOrigin origin = VisionLayerOrigin.advanced,
  }) {
    _selectedPresetId = null;
    _presetLayerId = null;
    _bypassHolders.clear();
    _setSingleLayer(_newLayer(id, variantId, origin));
    notifyListeners();
  }

  /// フィルタを選択する（advanced カタログ UI から）。[replaceWith] と同じ
  /// （従来の単一選択 API の名前。#60: プリセット/色覚クイック選択の記録は解除する）。
  void select(String id) => replaceWith(id);

  /// 色覚のクイック選択（`FilterBrowser`/トレイ、
  /// `lib/services/color_vision_selection.dart` の `selectColorVision`/
  /// `deactivateColorVision` 経由）からフィルタを選択・解除する（#60）。
  ///
  /// [type] は選択された色覚型そのもの。[ColorVisionType.none] は「何も
  /// シミュレーションしない」ことを表し、解除（[deactivateColorVision]）と
  /// 同じ効果になる — この場合 [isColorQuickSelection] は **false** のまま
  /// になる（[FilterBrowser] 一覧の「正常色覚」行・`IntensitySlider`・
  /// 解除ボタンのいずれも、[isColorQuickSelection] だけを見て点灯/有効化を
  /// 決めるため、none を「選択中」扱いにすると強度スライダーだけが宙に浮いて
  /// 有効化されてしまう。none はカタログにも強度概念にも対応しない）。
  ///
  /// [type] が非 none のときは origin=quick の層にし、-omaly は
  /// [VisionLayer.variantId] に別名を持たせる（-omaly の名前を見出し・export の
  /// caption・ファイル名に正しく出すため、#60）。[catalogId] は [type] に
  /// 対応するカタログ id（`visionFilterCatalogId` / `visionFilterForColorVisionType`
  /// 経由で呼び出し側が解決する）— [type] が [ColorVisionType.none] のときは
  /// 無視されるので省略できる。
  ///
  /// advanced/プリセットの選択中に呼ばれても（＝「別のフィルタを手動で選ぶ」
  /// 操作として）常に上書きする（[replaceWith]）。プリセットの選択は解除する。
  void selectColorVisionType(ColorVisionType type, [String? catalogId]) {
    if (type == ColorVisionType.none) {
      clear();
      return;
    }
    if (catalogId == null) {
      throw ArgumentError(
        'catalogId is required when type != ColorVisionType.none',
      );
    }
    replaceWith(
      catalogId,
      variantId: kVisionVariantIds.contains(type.name) ? type.name : null,
      origin: VisionLayerOrigin.quick,
    );
  }

  /// 体験プリセット（`ExperiencePresetTile`）からフィルタを選択する（#60）。
  /// [presetId] は `Experience.id`、[catalogId] はその体験の視覚フィルタに
  /// 対応するカタログ id。**層全体をその 1 フィルタに置き換える**（上限・排他に関わらず
  /// 常に受け付ける）。強度・パラメータは
  /// 常に推奨値・既定値にする（advanced 側で当該 id を
  /// カスタマイズ済みでも、プリセットは常に『代表的な程度』で体験してもらう
  /// ため、記憶優先ロジックは経由しない）。強度は当該キーの記憶を消して推奨強度の
  /// 導出に戻す。notifyListeners は 1 回だけ呼ぶ。層の集合がこのフィルタ 1 つ以外に
  /// なった時点でプリセット選択は外れ、戻らない。
  void selectPreset(String presetId, String catalogId) {
    final entry = _entryOrThrow(catalogId);
    _selectedPresetId = presetId;
    _presetLayerId = entry.id;
    _bypassHolders.clear();
    final params = defaultVisionParams(entry);
    _setSingleLayer(VisionLayer(id: entry.id, params: params));
    if (params.isNotEmpty) {
      _paramsById[entry.id] = Map<String, Object>.from(params);
    }
    _strengthByKey.remove(entry.id);
    notifyListeners();
  }

  /// 再起動をまたいで残す部分（層・フォーカス・キーごとの強度/id ごとの payload の
  /// 記憶）の写し（#65, #117 で v2）。値は複製なので、以後の変更は写しに影響しない。
  VisionFilterSnapshot snapshot() => VisionFilterSnapshot(
        layers: [
          for (final l in _layers)
            VisionLayer(
              id: l.id,
              params: Map<String, Object>.from(l.params),
              variantId: l.variantId,
              origin: l.origin,
            ),
        ],
        focusedId: _focusedId,
        presetId: _selectedPresetId,
        strengthByKey: Map<String, double>.from(_strengthByKey),
        paramsById: {
          for (final e in _paramsById.entries)
            e.key: Map<String, Object>.from(e.value),
        },
      );

  /// [snapshot] の内容でこの state を置き換える（#65。起動時の復元用）。
  ///
  /// 記憶（[_strengthByKey] / [_paramsById]）は丸ごと [snapshot] のものになる。
  /// 層は [normalizeVisionLayers] で整え直す（未知 id・重複・色覚排他・上限の違反は
  /// 先のものを残す）。フォーカスは保存された id が層にあればそれ、無ければ適用順で
  /// 最後の層。強度は層に載せず、記憶から導出する（記憶が無ければ推奨強度）。
  ///
  /// 復元できないものは安全側に倒す:
  ///  * 体験プリセット: 層がちょうど 1 つで、[isValidPreset]（preset id とカタログ
  ///    id の組が今も有効か）が true を返したときだけプリセット選択として戻す。
  ///    null・false ならプリセットの表示なしで advanced の層として戻す。
  ///  * quick の層: 別名と id が色覚型の対応表と一致するときだけ quick のまま戻す。
  ///
  /// snapshot は [VisionFilterSnapshot.fromJson] で補正済みの値を前提とする。
  /// 原画比較（bypass）は復元しない（常に解除）。
  ///
  /// 途中で例外が出たら、呼び出し前の状態へ巻き戻してから rethrow する
  /// （state が半端に消えた状態を残さない）。
  void restore(
    VisionFilterSnapshot snapshot, {
    bool Function(String presetId, String catalogId)? isValidPreset,
  }) {
    // 復元の途中（プリセット検証の FFI など）で例外が出ても半端に消えた状態を
    // 残さないよう、変更前の内容を控えて巻き戻す。
    final backup = (
      strengthByKey: Map<String, double>.from(_strengthByKey),
      paramsById: {
        for (final e in _paramsById.entries)
          e.key: Map<String, Object>.from(e.value),
      },
      layers: _layers,
      focusedId: _focusedId,
      presetId: _selectedPresetId,
      presetLayerId: _presetLayerId,
      bypassHolders: Set<Object>.of(_bypassHolders),
    );
    try {
      _strengthByKey
        ..clear()
        ..addAll(snapshot.strengthByKey);
      _paramsById
        ..clear()
        ..addAll({
          for (final e in snapshot.paramsById.entries)
            e.key: Map<String, Object>.from(e.value),
        });
      _bypassHolders.clear();
      _selectedPresetId = null;
      _presetLayerId = null;

      var layers = normalizeVisionLayers([
        for (final l in snapshot.layers)
          if (kVisionFilterCatalogById.containsKey(l.id)) _restoredLayer(l),
      ]);

      final presetId = snapshot.presetId;
      if (presetId != null &&
          layers.length == 1 &&
          (isValidPreset?.call(presetId, layers.single.id) ?? false)) {
        _selectedPresetId = presetId;
        _presetLayerId = layers.single.id;
        layers = [layers.single.copyWith(origin: VisionLayerOrigin.advanced)];
      }

      _layers = List.unmodifiable(layers);
      final focused = snapshot.focusedId;
      _focusedId = layers.isEmpty
          ? null
          : (focused != null && layers.any((l) => l.id == focused)
              ? focused
              : layers.last.id);
      notifyListeners();
    } catch (_) {
      _strengthByKey
        ..clear()
        ..addAll(backup.strengthByKey);
      _paramsById
        ..clear()
        ..addAll(backup.paramsById);
      _layers = backup.layers;
      _focusedId = backup.focusedId;
      _selectedPresetId = backup.presetId;
      _presetLayerId = backup.presetLayerId;
      _bypassHolders
        ..clear()
        ..addAll(backup.bypassHolders);
      rethrow;
    }
  }

  /// 復元する層を検証する。payload の無い層は記憶 → 既定値で補い、quick は色覚型の
  /// 対応表と矛盾しなければそのまま、矛盾すれば別名を外して advanced にする。
  VisionLayer _restoredLayer(VisionLayer layer) {
    final entry = kVisionFilterCatalogById[layer.id]!;
    var out = layer;
    if (entry.parameters.isNotEmpty && layer.params.isEmpty) {
      out = out.copyWith(
        params: _paramsById[entry.id] ?? defaultVisionParams(entry),
      );
    }
    if (out.origin == VisionLayerOrigin.quick) {
      final type = quickColorVisionTypeOf(out);
      if (type == null ||
          visionFilterForColorVisionTypeCatalogId(type) != out.id) {
        out = VisionLayer(id: out.id, params: out.params);
      }
    }
    return out;
  }

  /// 選択を解除する。フィルタごとの強度・パラメータの記憶は
  /// クリアしない — 同じフィルタを選び直したときに復元される
  /// ためのものなので、選択解除では消さない。
  void clear() {
    _layers = const [];
    _focusedId = null;
    _selectedPresetId = null;
    _presetLayerId = null;
    _bypassHolders.clear();
    notifyListeners();
  }

  /// フォーカス中の層の強度とパラメータを、推奨値・カタログ既定値に戻す
  /// （#77 の「推奨値に戻す」ボタン）。強度は記憶を消して推奨強度の導出に戻す。
  /// 未選択なら何もしない。プリセット選択中に呼ばれたらプリセットの選択表示は解除する
  /// （[setStrength]/[setParam] と同じ理由）。
  void resetToRecommended() {
    final layer = focusedLayer;
    final entry = layer == null ? null : kVisionFilterCatalogById[layer.id];
    if (layer == null || entry == null) return;

    final params = defaultVisionParams(entry);
    _replaceLayer(layer.copyWith(params: params));
    if (params.isNotEmpty) {
      _paramsById[entry.id] = Map<String, Object>.from(params);
    }
    _strengthByKey.remove(layer.strengthKey);

    _bypassHolders.clear();
    _clearPresetSelectionOnCustomize();
    notifyListeners();
  }

  void _replaceLayer(VisionLayer layer) {
    _layers = List.unmodifiable([
      for (final l in _layers) l.id == layer.id ? layer : l,
    ]);
  }

  /// フォーカス中の層の strength を 0.0..1.0 に clamp して、その層のキーの記憶
  /// （[_strengthByKey]、#77）へ書く。未選択なら何もしない。プリセット選択中に
  /// 呼ばれたらプリセットの選択表示は解除する（#60: strength を弄った時点で
  /// 「そのプリセットそのもの」ではなくなるため）。
  void setStrength(double value) {
    final layer = focusedLayer;
    if (layer == null) return;
    _writeStrength(layer, value);
  }

  void _writeStrength(VisionLayer layer, double value) {
    _strengthByKey[layer.strengthKey] = value.clamp(0.0, 1.0);
    _bypassHolders.clear();
    _clearPresetSelectionOnCustomize();
    notifyListeners();
  }

  /// フォーカス中の層のパラメータ値を更新する（型は呼び出し側責務: float→double /
  /// int→int / enum→String value / seed→[BigInt]）。フィルタ id ごとの記憶
  /// （[_paramsById]、#77）にも書き戻す。未選択なら何もしない。プリセット選択中に
  /// 呼ばれたらプリセットの選択表示は解除する（#60、[setStrength] と同じ理由）。
  void setParam(String name, Object value) {
    final layer = focusedLayer;
    if (layer == null) return;
    _writeParam(layer, name, value);
  }

  void _writeParam(VisionLayer layer, String name, Object value) {
    final params = Map<String, Object>.from(layer.params)..[name] = value;
    _replaceLayer(layer.copyWith(params: params));
    (_paramsById[layer.id] ??= {})[name] = value;
    _bypassHolders.clear();
    _clearPresetSelectionOnCustomize();
    notifyListeners();
  }

  /// プリセット選択中に strength/param が手動で変更されたら、プリセットの
  /// 選択表示（[selectedPresetId]）だけを解除する（#60）。フィルタ自体の
  /// 選択・payload はそのまま残す — ユーザーはプリセットの
  /// フィルタを起点にカスタマイズしているだけで、選択を丸ごと解除したい
  /// わけではない。
  void _clearPresetSelectionOnCustomize() {
    _selectedPresetId = null;
    _presetLayerId = null;
  }

  /// seed パラメータを乱数で再生成する。プリセット選択中に呼ばれたらプリセットの
  /// 選択表示は解除する（[setParam]/[setStrength] と同じ理由、#60）。未選択なら
  /// 何もしない。
  ///
  /// seed は sensus の `u64`（Dart [BigInt]）。int/double を経由すると 2^53 超で
  /// 精度が落ちるため、生成・保持とも [BigInt] で全 u64 範囲（0..[kSeedMax]）を
  /// 扱う。
  void randomizeSeed(String name) {
    final layer = focusedLayer;
    if (layer == null) return;
    _writeParam(layer, name, _nextSeed());
  }

  /// フォーカス中の層から sensus の [VisionFilter] を構築する。未選択なら null
  /// （[buildLayer] と同じ）。
  VisionFilter? build() {
    final layer = focusedLayer;
    return layer == null ? null : buildLayer(layer);
  }

  /// 全層の [VisionFilter]（適用順、強度 0 の層も含む）。受診喚起の合成
  /// （`consultInputForFilters`）など、選択されている全層を見たいとき用。
  List<VisionFilter> buildAll() => [for (final l in _layers) buildLayer(l)];

  /// プレビュー合成に渡すステップ列（適用順＝[layers] の順）。**強度 0 の層は除く**
  /// （層としては残り、上限にも数える）。強度は [strengthOf]（キーごとの記憶、無ければ推奨強度）。
  /// 並びは段順で決まり、層を選んだ順には依存しない。
  List<VisionStep> pipelineSteps() {
    final steps = <VisionStep>[];
    for (final layer in _layers) {
      final strength = strengthOf(layer);
      if (strength <= 0) continue;
      steps.add(VisionStep(filter: buildLayer(layer), strength: strength));
    }
    return steps;
  }

  /// [layer] の id + payload から sensus の [VisionFilter] を構築する。payload を
  /// 持つフィルタは [VisionLayer.params]（未設定は定義の defaultValue）から組み立てる。
  /// カタログに無い id は [StateError]。
  VisionFilter buildLayer(VisionLayer layer) {
    final id = layer.id;
    final r = _ParamReader(kVisionFilterCatalogById[id], layer.params);

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
        return VisionFilter.astigmatism(axisDeg: r.float('axisDeg'));

      // ── 視野 ──
      // 4 フィルタとも field_loss_mode は常に darken 固定で構築する。
      // GPU 経路が field_loss_mode を無視する（常に Darken 相当で描画される）ため、
      // カタログには UI パラメータとして出していない
      // （kVisionFilterCatalog の doc コメント参照）。
      case 'glaucoma':
        return VisionFilter.glaucoma(
          mode: r.glaucomaMode('mode'),
          fieldLossMode: VisionFieldLossMode.darken,
        );
      case 'macular_degeneration':
        return const VisionFilter.macularDegeneration(
          fieldLossMode: VisionFieldLossMode.darken,
        );
      case 'hemianopia':
        return VisionFilter.hemianopia(
          side: r.hemianopiaSide('side'),
          fieldLossMode: VisionFieldLossMode.darken,
        );
      case 'tunnel_vision':
        return const VisionFilter.tunnelVision(
          fieldLossMode: VisionFieldLossMode.darken,
        );

      // ── 光・透明度 ──
      case 'cataract':
        return VisionFilter.cataract(seed: r.seed('seed'));
      case 'floaters':
        return VisionFilter.floaters(
          seed: r.seed('seed'),
          density: r.float('density'),
          size: r.float('size'),
          gazeX: r.float('gazeX'),
          gazeY: r.float('gazeY'),
        );
      case 'photophobia':
        return const VisionFilter.photophobia();
      case 'night_blindness':
        return const VisionFilter.nightBlindness();
      case 'starbursts':
        return VisionFilter.starbursts(
          numRays: r.integer('numRays'),
          rayLengthRatio: r.float('rayLengthRatio'),
          threshold: r.float('threshold'),
          dispersion: r.float('dispersion'),
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
          amplitude: r.float('amplitude'),
          directionDeg: r.float('directionDeg'),
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
          offsetX: r.float('offsetX'),
          offsetY: r.float('offsetY'),
          ghostStrength: r.float('ghostStrength'),
        );
      case 'metamorphopsia':
        return VisionFilter.metamorphopsia(
          freq: r.float('freq'),
          seed: r.seed('seed'),
        );
      case 'detail_loss':
        return VisionFilter.detailLoss(cellSize: r.integer('cellSize'));
      case 'teichopsia':
        return const VisionFilter.teichopsia();
      case 'flickering_stars':
        return VisionFilter.flickeringStars(seed: r.seed('seed'));
    }
    throw StateError('Unhandled vision filter id in buildLayer(): $id');
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

  /// dispose 済みかどうか（#79）。`loupe_hud.dart` の原画比較ボタンが
  /// dispose 時に holder 解放をマイクロタスクへ遅延させる際、その時点で
  /// この state 自体が既に dispose 済みなら何もしない（`notifyListeners()`
  /// を dispose 後に呼ぶと落ちるため）ガードに使う。
  bool _disposed = false;

  /// dispose 済みかどうか。
  bool get isDisposed => _disposed;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// 層の payload（未設定は定義の defaultValue へフォールバック）の取り出し。
class _ParamReader {
  _ParamReader(this.entry, this.params);

  final VisionFilterEntry? entry;
  final Map<String, Object> params;

  Object? _raw(String name) {
    if (params.containsKey(name)) return params[name];
    final e = entry;
    if (e == null) return null;
    for (final p in e.parameters) {
      if (p.name == name) return p.defaultValue;
    }
    return null;
  }

  double float(String name) {
    final v = _raw(name);
    if (v is num) return v.toDouble();
    return 0.0;
  }

  int integer(String name) {
    final v = _raw(name);
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }

  BigInt seed(String name) {
    final v = _raw(name);
    if (v is BigInt) return v;
    if (v is int) return BigInt.from(v);
    if (v is num) return BigInt.from(v.toInt());
    return BigInt.zero;
  }

  VisionGlaucomaMode glaucomaMode(String name) {
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
  double hemianopiaSide(String name) {
    final key = _raw(name);
    return kHemianopiaSideValues[key] ?? kHemianopiaSideValues['left']!;
  }
}
