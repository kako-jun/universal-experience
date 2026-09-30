import '../models/vision_filter_catalog.dart';
import 'vision_layer.dart';

/// [VisionFilterSnapshot] の JSON スキーマ版。形式を変えるときに上げる。
/// 版 1（単一選択）は [VisionFilterSnapshot.fromJson] が v2 の形へ変換して読む。
/// それ以外の未知の版（新しすぎる・壊れている）は丸ごと捨てて既定値で起動する
/// （null を返す）。
const int kVisionFilterSnapshotVersion = 2;

/// 読み込みだけは今も受け付ける旧版（単一選択 + フィルタ id ごとの強度）。
const int _kLegacySnapshotVersion = 1;

/// [entry] の payload パラメータを、カタログの defaultValue から組み立てる
/// （純粋関数）。seed は sensus の u64 なので [BigInt] 化する（int/double を
/// 経由させず精度欠落を防ぐ）。[VisionFilterState] の初回選択・推奨値へのリセット・
/// プリセット選択と、永続値の補正（[sanitizeVisionParams]）が共有する。
Map<String, Object> defaultVisionParams(VisionFilterEntry entry) {
  final params = <String, Object>{};
  for (final p in entry.parameters) {
    if (p.defaultValue == null) continue;
    params[p.name] = p.kind == VisionParamKind.seed
        ? _toSeedBigInt(p.defaultValue!)
        : p.defaultValue!;
  }
  return params;
}

BigInt _toSeedBigInt(Object value) {
  if (value is BigInt) return value;
  if (value is int) return BigInt.from(value);
  if (value is num) return BigInt.from(value.toInt());
  return BigInt.zero;
}

/// 永続化されていた payload 値 [raw] を、カタログの定義（[entry] の
/// min/max/default/options）に照らして補正した完全なパラメータマップを返す。
///
/// - 定義に無いキー（sensus 側で引数が消えた等）は捨てる。
/// - 型が合わない・範囲外・未知の選択肢・非有限（NaN/Infinity）は、範囲外なら
///   min/max に丸め、それ以外は既定値に戻す。
/// - 定義にあるのに [raw] に無いキー（引数が増えた等）は既定値で埋める。
///
/// 戻り値は常に [defaultVisionParams] と同じキー集合を持つので、呼び出し側は
/// 保存内容とカタログのずれを気にせずそのまま [VisionFilterState] に入れられる。
Map<String, Object> sanitizeVisionParams(
  VisionFilterEntry entry,
  Object? raw,
) {
  final result = defaultVisionParams(entry);
  if (raw is! Map) return result;
  for (final p in entry.parameters) {
    if (!raw.containsKey(p.name)) continue;
    final value = _sanitizeParamValue(p, raw[p.name]);
    if (value != null) result[p.name] = value;
  }
  return result;
}

/// 1 つの値の補正。採用できなければ null（= 既定値のまま）。
Object? _sanitizeParamValue(VisionParam p, Object? value) {
  switch (p.kind) {
    case VisionParamKind.float:
      if (value is! num || !value.isFinite) return null;
      return _clampToDefinition(p, value.toDouble());
    case VisionParamKind.intValue:
      if (value is! num || !value.isFinite) return null;
      return _clampToDefinition(p, value.round().toDouble()).round();
    case VisionParamKind.enumValue:
      if (value is String && p.options.any((o) => o.value == value)) {
        return value;
      }
      return null;
    case VisionParamKind.seed:
      final BigInt? seed;
      if (value is String) {
        // 保存形式は 10 進の整数文字列だけ。BigInt.tryParse は "0x10" や前後の
        // 空白も受け付けるので、形式を先に絞る。
        seed = _decimalInteger.hasMatch(value) ? BigInt.tryParse(value) : null;
      } else if (value is int) {
        seed = BigInt.from(value);
      } else {
        seed = null;
      }
      if (seed == null || seed < BigInt.zero || seed > kSeedMax) return null;
      return seed;
  }
}

final RegExp _decimalInteger = RegExp(r'^-?\d+$');

double _clampToDefinition(VisionParam p, double v) {
  var out = v;
  final min = p.min;
  final max = p.max;
  if (min != null && out < min) out = min;
  if (max != null && out > max) out = max;
  return out;
}

/// [VisionFilterState] の「再起動をまたいで残す部分」の値オブジェクト（#65, #117 で v2）。
///
/// 保持するもの:
/// - 重ねているレイヤー列 [layers]（適用順。各層は id・payload・別名・起源）と、
///   フォーカス中の層 [focusedId]、体験プリセット [presetId]
/// - キーごとの強度の記憶 [strengthByKey]（キーは別名 id ?? カタログ id。層に強度は
///   持たせない）と、カタログ id ごとの payload の記憶 [paramsById]
///
/// 保持しないもの: 原画比較（bypass）など一時的な状態。
///
/// JSON へは [toJson]、JSON からは [fromJson]（補正込み）で往復する。seed は
/// u64 で JSON の数値（double 経由）では精度が落ちるため、10 進文字列で持つ。
///
/// 定義（カタログ）と状態を分けるため、この型はカタログを参照して**読み込み時に
/// 補正する**だけで、カタログの値そのものは保存しない。
class VisionFilterSnapshot {
  const VisionFilterSnapshot({
    this.layers = const [],
    this.focusedId,
    this.presetId,
    this.strengthByKey = const {},
    this.paramsById = const {},
    this.fromLegacy = false,
  });

  /// 適用順に並んだレイヤー列。
  final List<VisionLayer> layers;

  /// フォーカス中の層のカタログ id。[layers] のどれかの id のときだけ有効。
  final String? focusedId;

  /// 選択中の体験プリセット id（`Experience.id`）。プリセット経由でなければ null。
  /// 層がちょうど 1 つのときだけ持つ。
  final String? presetId;

  /// キー（別名 id ?? カタログ id）ごとの強度（0.0..1.0）。
  final Map<String, double> strengthByKey;

  /// カタログ id ごとの payload パラメータ（seed は [BigInt]）。
  final Map<String, Map<String, Object>> paramsById;

  /// 版 1 の保存値から変換した snapshot か。v2 として書き戻されるまでの間だけ true
  /// （[VisionFilterStore] が、旧 per-type 強度の取り込みの要否の判断に使う）。
  final bool fromLegacy;

  /// 何も保存すべきものが無い（層なし・記憶なし）か。
  bool get isEmpty =>
      layers.isEmpty && strengthByKey.isEmpty && paramsById.isEmpty;

  Map<String, Object?> toJson() => {
        'version': kVisionFilterSnapshotVersion,
        'layers': [
          for (final l in layers)
            {
              'id': l.id,
              'params': {
                for (final e in l.params.entries) e.key: _paramToJson(e.value),
              },
              if (l.variantId != null) 'variantId': l.variantId,
              'origin': l.origin.name,
            },
        ],
        'focusedId': focusedId,
        'presetId': presetId,
        'strengthByKey': Map<String, double>.of(strengthByKey),
        'paramsById': {
          for (final e in paramsById.entries)
            e.key: {
              for (final p in e.value.entries) p.key: _paramToJson(p.value),
            },
        },
      };

  static Object _paramToJson(Object value) =>
      value is BigInt ? value.toString() : value;

  /// [json]（`jsonDecode` の結果）から復元する。カタログに照らして補正済みの
  /// 値だけを持つ snapshot を返す。
  ///
  /// 復元できない（Map でない・版が違う・版が無い）ときは null。版 1 は v2 の形へ
  /// 変換して読む（[fromLegacy] が true）。それ以外の部分的な破損（未知のフィルタ id・
  /// 範囲外・型違い・欠損）は、その部分だけを捨てる/補正し、起動を止めない。層の列は
  /// [normalizeVisionLayers] の規則（重複・色覚排他・上限は先のものを残す）で整える。
  static VisionFilterSnapshot? fromJson(Object? json) {
    if (json is! Map) return null;
    final version = json['version'];
    if (version == kVisionFilterSnapshotVersion) return _fromV2(json);
    if (version == _kLegacySnapshotVersion) return _fromV1(json);
    return null;
  }

  static const Set<String> _quickCapableIds = {
    'protanopia',
    'deuteranopia',
    'tritanopia',
    'achromatopsia',
  };

  static Map<String, double> _sanitizeStrengths(Object? raw) {
    final out = <String, double>{};
    if (raw is! Map) return out;
    for (final e in raw.entries) {
      final key = e.key;
      final v = e.value;
      if (key is String && isValidStrengthKey(key) && v is num && v.isFinite) {
        out[key] = v.toDouble().clamp(0.0, 1.0);
      }
    }
    return out;
  }

  static VisionFilterSnapshot _fromV2(Map json) {
    final paramsById = <String, Map<String, Object>>{};
    final rawParams = json['paramsById'];
    if (rawParams is Map) {
      for (final e in rawParams.entries) {
        final key = e.key;
        final entry = key is String ? kVisionFilterCatalogById[key] : null;
        if (entry == null || entry.parameters.isEmpty) continue;
        paramsById[entry.id] = sanitizeVisionParams(entry, e.value);
      }
    }

    final rawLayers = json['layers'];
    final parsed = <VisionLayer>[];
    if (rawLayers is List) {
      for (final raw in rawLayers) {
        if (raw is! Map) continue;
        final id = raw['id'];
        final entry = id is String ? kVisionFilterCatalogById[id] : null;
        if (entry == null) continue;
        final variant = raw['variantId'];
        final variantId =
            variant is String && isValidVariantFor(entry.id, variant)
                ? variant
                : null;
        final origin = raw['origin'] == VisionLayerOrigin.quick.name &&
                _quickCapableIds.contains(entry.id)
            ? VisionLayerOrigin.quick
            : VisionLayerOrigin.advanced;
        // 層の params が無い・壊れているときは、id ごとの記憶 → 既定値の順で補う。
        final params = entry.parameters.isEmpty
            ? const <String, Object>{}
            : raw.containsKey('params')
                ? sanitizeVisionParams(entry, raw['params'])
                : (paramsById[entry.id] ?? defaultVisionParams(entry));
        parsed.add(VisionLayer(
          id: entry.id,
          params: params,
          variantId: variantId,
          origin: origin,
        ));
      }
    }
    final layers = normalizeVisionLayers(parsed);
    // 層に載っている payload は、id ごとの記憶にも反映しておく（層が正本）。
    for (final l in layers) {
      if (l.params.isNotEmpty) paramsById[l.id] = Map.of(l.params);
    }

    final focused = json['focusedId'];
    final focusedId = focused is String && layers.any((l) => l.id == focused)
        ? focused
        : null;

    final preset = json['presetId'];
    final presetId = layers.length == 1 && preset is String && preset.isNotEmpty
        ? preset
        : null;

    return VisionFilterSnapshot(
      layers: layers,
      focusedId: focusedId,
      presetId: presetId,
      strengthByKey: _sanitizeStrengths(json['strengthByKey']),
      paramsById: paramsById,
    );
  }

  /// 版 1（単一選択）→ v2 の形。
  ///
  /// 選択は層 1 つに、色覚クイック選択は quick 層（-omaly は別名つき）になる。
  /// 版 1 の強度はカタログ id ごとに 1 つだったが、色覚 -opia の強度の正本は
  /// 旧 `settings.intensityByType` 側（[VisionFilterStore.migrateLegacyStrengths]
  /// が取り込む）だったため、-opia 4 種（quick/advanced の別を区別できない記憶）は
  /// 持ち越さない。tetrachromacy は advanced 専用だったので持ち越す。
  static VisionFilterSnapshot _fromV1(Map json) {
    final strengthByKey = <String, double>{};
    final paramsById = <String, Map<String, Object>>{};
    final filters = json['filters'];
    if (filters is Map) {
      for (final e in filters.entries) {
        final id = e.key;
        final entry = id is String ? kVisionFilterCatalogById[id] : null;
        final body = e.value;
        if (entry == null || body is! Map) continue;
        final strength = body['strength'];
        if (strength is num &&
            strength.isFinite &&
            !_quickCapableIds.contains(entry.id)) {
          strengthByKey[entry.id] = strength.toDouble().clamp(0.0, 1.0);
        }
        if (entry.parameters.isNotEmpty && body.containsKey('params')) {
          paramsById[entry.id] = sanitizeVisionParams(entry, body['params']);
        }
      }
    }

    final selected = json['selectedId'];
    final entry =
        selected is String ? kVisionFilterCatalogById[selected] : null;
    var layers = <VisionLayer>[];
    String? presetId;
    if (entry != null) {
      final rawType = json['colorVisionType'];
      final type = rawType is String ? colorVisionTypeByName(rawType) : null;
      // 旧保存値の colorVisionType は ColorVisionType.id（= name と同じ文字列）。
      final quick = type == null ? null : quickColorVisionLayer(type);
      if (quick != null && quick.id == entry.id) {
        layers = [quick];
      } else {
        layers = [
          VisionLayer(
            id: entry.id,
            params: entry.parameters.isEmpty
                ? const {}
                : (paramsById[entry.id] ?? defaultVisionParams(entry)),
          ),
        ];
        final preset = json['presetId'];
        if (preset is String && preset.isNotEmpty) presetId = preset;
      }
      if (layers.first.params.isNotEmpty) {
        paramsById[entry.id] = Map.of(layers.first.params);
      }
    }
    return VisionFilterSnapshot(
      layers: layers,
      focusedId: entry?.id,
      presetId: presetId,
      strengthByKey: strengthByKey,
      paramsById: paramsById,
      fromLegacy: true,
    );
  }
}
