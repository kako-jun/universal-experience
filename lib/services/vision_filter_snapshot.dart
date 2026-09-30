import '../models/disability_type.dart';
import '../models/vision_filter_catalog.dart';

/// [VisionFilterSnapshot] の JSON スキーマ版。形式を変えるときに上げる。
/// 未知の版（新しすぎる・壊れている）は丸ごと捨てて既定値で起動する
/// （[VisionFilterSnapshot.fromJson] が null を返す）。
const int kVisionFilterSnapshotVersion = 1;

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

/// [VisionFilterState] の「再起動をまたいで残す部分」の値オブジェクト（#65）。
///
/// 保持するもの:
/// - 選択（[selectedId]・体験プリセット [presetId]・色覚クイック選択の
///   [colorVisionType]）
/// - フィルタ id ごとの強度・payload パラメータの記憶（[strengthById] /
///   [paramsById]。選択中の値もここに含まれる）
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
    this.selectedId,
    this.presetId,
    this.colorVisionType,
    this.strengthById = const {},
    this.paramsById = const {},
  });

  /// 選択中のカタログ id。未選択なら null。
  final String? selectedId;

  /// 選択中の体験プリセット id（`Experience.id`）。プリセット経由でなければ null。
  final String? presetId;

  /// 色覚クイック選択で選んだ型。色覚クイック選択でなければ null。
  final ColorVisionType? colorVisionType;

  /// フィルタ id ごとの強度（0.0..1.0）。
  final Map<String, double> strengthById;

  /// フィルタ id ごとの payload パラメータ（seed は [BigInt]）。
  final Map<String, Map<String, Object>> paramsById;

  /// 何も保存すべきものが無い（未選択・記憶なし）か。
  bool get isEmpty =>
      selectedId == null && strengthById.isEmpty && paramsById.isEmpty;

  Map<String, Object?> toJson() {
    final filters = <String, Object?>{};
    final ids = {...strengthById.keys, ...paramsById.keys};
    for (final id in ids) {
      final params = paramsById[id];
      final strength = strengthById[id];
      filters[id] = {
        if (strength != null) 'strength': strength,
        if (params != null)
          'params': {
            for (final e in params.entries) e.key: _paramToJson(e.value),
          },
      };
    }
    return {
      'version': kVisionFilterSnapshotVersion,
      'selectedId': selectedId,
      'presetId': presetId,
      'colorVisionType': colorVisionType?.id,
      'filters': filters,
    };
  }

  static Object _paramToJson(Object value) =>
      value is BigInt ? value.toString() : value;

  /// [json]（`jsonDecode` の結果）から復元する。カタログに照らして補正済みの
  /// 値だけを持つ snapshot を返す。
  ///
  /// 復元できない（Map でない・版が違う・版が無い）ときは null。それ以外の
  /// 部分的な破損（未知のフィルタ id・範囲外・型違い・欠損）は、その部分だけを
  /// 捨てる/補正し、起動を止めない。sensus 側のフィルタ id・パラメータ定義が
  /// 変わっても、古い保存値は安全に既定値へ落ちる。
  static VisionFilterSnapshot? fromJson(Object? json) {
    if (json is! Map) return null;
    if (json['version'] != kVisionFilterSnapshotVersion) return null;

    final strengthById = <String, double>{};
    final paramsById = <String, Map<String, Object>>{};
    final filters = json['filters'];
    if (filters is Map) {
      for (final e in filters.entries) {
        final id = e.key;
        final entry = id is String ? kVisionFilterCatalogById[id] : null;
        final body = e.value;
        if (entry == null || body is! Map) continue;
        final strength = body['strength'];
        if (strength is num && strength.isFinite) {
          strengthById[entry.id] = strength.toDouble().clamp(0.0, 1.0);
        }
        // 引数を持たないフィルタは params が無くてよい。持つフィルタは
        // 記憶があるときだけ補正して残す（無ければ初回選択の既定値になる）。
        if (entry.parameters.isNotEmpty && body.containsKey('params')) {
          paramsById[entry.id] = sanitizeVisionParams(entry, body['params']);
        }
      }
    }

    final selected = json['selectedId'];
    final selectedId =
        selected is String && kVisionFilterCatalogById.containsKey(selected)
            ? selected
            : null;

    final preset = json['presetId'];
    final presetId = selectedId != null && preset is String && preset.isNotEmpty
        ? preset
        : null;

    ColorVisionType? colorVisionType;
    final rawType = json['colorVisionType'];
    if (selectedId != null && rawType is String) {
      for (final t in ColorVisionType.values) {
        if (t != ColorVisionType.none && t.id == rawType) colorVisionType = t;
      }
    }

    return VisionFilterSnapshot(
      selectedId: selectedId,
      presetId: presetId,
      colorVisionType: colorVisionType,
      strengthById: strengthById,
      paramsById: paramsById,
    );
  }
}
