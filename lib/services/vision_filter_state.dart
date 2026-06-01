import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/vision_filter_catalog.dart';
import '../src/rust/api/sensus_bridge.dart';

/// 「Advanced（sensus 全フィルタ）」UI の選択状態を保持する ChangeNotifier。
///
/// **既存の [FilterService]（ColorVisionType ベース）とは別系統**にして衝突を
/// 避ける。既存の色覚 7 種 UI はそのまま残し、こちらは sensus の全 30
/// [VisionFilter] をカタログ（[kVisionFilterCatalog]）経由で選べるようにする。
///
/// 保持するのは「どのフィルタ id を・どの payload パラメータ値で・どの strength で
/// 選んでいるか」だけ。アルゴリズムは持たず、選択 + パラメータから sensus の
/// [VisionFilter] インスタンスを組み立てる [build] を提供する（実描画/ライブ適用は
/// #11/#1/#3/#4 のブリッジ結線側の責務）。
class VisionFilterState extends ChangeNotifier {
  String? _selectedId;
  double _strength = 1.0;
  final Map<String, Object> _params = {};

  /// 選択中のフィルタ id（snake_case）。未選択なら null。
  String? get selectedId => _selectedId;

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

  /// フィルタを選択する。パラメータ値は当該フィルタの定義 defaultValue で初期化する。
  void select(String id) {
    final entry = kVisionFilterCatalogById[id];
    if (entry == null) {
      throw ArgumentError('Unknown vision filter id: $id');
    }
    _selectedId = id;
    _params.clear();
    for (final p in entry.parameters) {
      if (p.defaultValue == null) continue;
      // seed は sensus u64。カタログの const default は int だが、ここで
      // BigInt 化して保持する（int/double を経由させず精度欠落を防ぐ）。
      if (p.kind == VisionParamKind.seed) {
        _params[p.name] = _toSeedBigInt(p.defaultValue!);
      } else {
        _params[p.name] = p.defaultValue!;
      }
    }
    notifyListeners();
  }

  /// 選択を解除する。
  void clear() {
    _selectedId = null;
    _params.clear();
    notifyListeners();
  }

  /// strength を 0.0..1.0 に clamp して更新する。
  void setStrength(double value) {
    _strength = value.clamp(0.0, 1.0);
    notifyListeners();
  }

  /// パラメータ値を更新する（型は呼び出し側責務: float→double / int→int /
  /// enum→String value / seed→[BigInt]）。
  void setParam(String name, Object value) {
    _params[name] = value;
    notifyListeners();
  }

  /// seed パラメータを乱数で再生成する。
  ///
  /// seed は sensus の `u64`（Dart [BigInt]）。int/double を経由すると 2^53 超で
  /// 精度が落ちるため、生成・保持とも [BigInt] で全 u64 範囲（0..[kSeedMax]）を
  /// 扱う。
  void randomizeSeed(String name) {
    _params[name] = _nextSeed();
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
      case 'glaucoma':
        return VisionFilter.glaucoma(mode: _glaucomaMode('mode'));
      case 'macular_degeneration':
        return const VisionFilter.macularDegeneration();
      case 'hemianopia':
        return VisionFilter.hemianopia(side: _hemianopiaSide('side'));
      case 'tunnel_vision':
        return const VisionFilter.tunnelVision();

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
