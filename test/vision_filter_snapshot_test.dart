// VisionFilterSnapshot（#65, #117 で v2）のテスト。
//
// - JSON の往復で、レイヤー列・フォーカス・強度の記憶・payload（seed の u64 全域を
//   含む）が失われない。
// - 読み込みはカタログの定義（min/max/default/options）と層の不変条件（重複なし・
//   色覚グループ排他・上限 5・適用順）に照らして補正する。
// - 版 1（単一選択）は v2 の形へ変換して読む（fromLegacy）。未知・欠落の版、Map でない
//   値は丸ごと捨てる（null）。起動を止めない。
//
// 補正の期待値はテスト内にカタログの値を直書きせず、カタログの定義から導く
// （定義が変わってもテストが追従する。ただし「範囲外を作る」ための入力は
// 定義の外側に出す）。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/models/vision_filter_catalog.dart';
import 'package:universal_experience/models/vision_filter_stage.dart';
import 'package:universal_experience/services/vision_filter_snapshot.dart';
import 'package:universal_experience/services/vision_layer.dart';

/// v2 の JSON。[layers] は JSON の層（Map）の列。
Map<String, Object?> _json({
  Object? version = kVisionFilterSnapshotVersion,
  Object? layers = const <Object?>[],
  String? focusedId,
  String? presetId,
  Object? strengthByKey = const <String, Object?>{},
  Object? paramsById = const <String, Object?>{},
}) =>
    {
      'version': version,
      'layers': layers,
      'focusedId': focusedId,
      'presetId': presetId,
      'strengthByKey': strengthByKey,
      'paramsById': paramsById,
    };

/// 版 1（単一選択）の JSON。
Map<String, Object?> _v1({
  String? selectedId,
  String? presetId,
  String? colorVisionType,
  Object? filters = const <String, Object?>{},
}) =>
    {
      'version': 1,
      'selectedId': selectedId,
      'presetId': presetId,
      'colorVisionType': colorVisionType,
      'filters': filters,
    };

Map<String, Object?> _layer(
  String id, {
  String? variantId,
  String? origin,
  Object? params,
}) =>
    {
      'id': id,
      if (variantId != null) 'variantId': variantId,
      if (origin != null) 'origin': origin,
      if (params != null) 'params': params,
    };

/// 定義の内側で、既定値とは違う値。
Object _nonDefaultValue(VisionParam p) {
  switch (p.kind) {
    case VisionParamKind.float:
      final mid = (p.min! + p.max!) / 2;
      return mid == p.defaultValue ? p.min! : mid;
    case VisionParamKind.intValue:
      return p.max!.toInt() == p.defaultValue ? p.min!.toInt() : p.max!.toInt();
    case VisionParamKind.enumValue:
      return p.options.firstWhere((o) => o.value != p.defaultValue).value;
    case VisionParamKind.seed:
      return kSeedMax - BigInt.from(12345);
  }
}

VisionFilterEntry _entry(String id) => kVisionFilterCatalogById[id]!;

Map<String, Object> _nonDefaultParams(String id) => {
      for (final p in _entry(id).parameters) p.name: _nonDefaultValue(p),
    };

List<String> _ids(VisionFilterSnapshot s) => [for (final l in s.layers) l.id];

void main() {
  group('JSON の往復', () {
    test('層・フォーカス・強度の記憶・payload が jsonEncode を経ても一致する', () {
      // 適用順に並んだ 5 層（上限ちょうど）。層の payload は既定値と違う値にする。
      const layerIds = [
        'starbursts',
        'floaters',
        'glaucoma',
        'teichopsia',
        'deuteranopia',
      ];
      final layers = [
        for (final id in layerIds)
          VisionLayer(id: id, params: _nonDefaultParams(id)),
      ];
      final strengthByKey = <String, double>{};
      final paramsById = <String, Map<String, Object>>{};
      var i = 0;
      for (final e in kVisionFilterCatalog) {
        strengthByKey[e.id] = 0.1 + (i++ % 9) * 0.1;
        if (e.parameters.isNotEmpty) paramsById[e.id] = _nonDefaultParams(e.id);
      }
      strengthByKey['tritanomaly'] = 0.35; // 別名キーの記憶
      final snapshot = VisionFilterSnapshot(
        layers: layers,
        focusedId: 'glaucoma',
        strengthByKey: strengthByKey,
        paramsById: paramsById,
      );

      final restored = VisionFilterSnapshot.fromJson(
        jsonDecode(jsonEncode(snapshot.toJson())),
      )!;

      expect(_ids(restored), layerIds);
      for (var k = 0; k < layers.length; k++) {
        expect(restored.layers[k].params, layers[k].params,
            reason: layers[k].id);
        expect(restored.layers[k].variantId, layers[k].variantId,
            reason: layers[k].id);
      }
      expect(restored.focusedId, 'glaucoma');
      expect(restored.strengthByKey, strengthByKey);
      expect(restored.paramsById, paramsById);
      expect(restored.fromLegacy, isFalse);
      expect(paramsById.isNotEmpty, isTrue,
          reason: 'payload を持つフィルタが 1 つも無いと往復の検証にならない');
    });

    test('seed は u64 の全域（2^53 超・上限 kSeedMax）でも精度を失わない', () {
      for (final seed in [
        BigInt.zero,
        BigInt.from(1) << 53,
        (BigInt.one << 53) + BigInt.one,
        kSeedMax,
      ]) {
        final snapshot = VisionFilterSnapshot(
          layers: [
            VisionLayer(id: 'floaters', params: {'seed': seed}),
          ],
          focusedId: 'floaters',
          paramsById: {
            'floaters': {'seed': seed},
          },
        );
        final decoded = jsonDecode(jsonEncode(snapshot.toJson()));

        final restored = VisionFilterSnapshot.fromJson(decoded)!;

        expect(restored.layers.single.params['seed'], seed);
        expect(restored.paramsById['floaters']!['seed'], seed);
      }
    });

    test('プリセットと別名（-omaly）の層も往復する', () {
      final preset = VisionFilterSnapshot.fromJson(jsonDecode(jsonEncode(
        VisionFilterSnapshot(
          layers: [VisionLayer(id: 'vertigo')],
          focusedId: 'vertigo',
          presetId: 'labyrinthitis',
        ).toJson(),
      )))!;
      expect(preset.presetId, 'labyrinthitis');
      expect(preset.layers.single.variantId, isNull);

      final omaly = VisionFilterSnapshot.fromJson(jsonDecode(jsonEncode(
        VisionFilterSnapshot(
          layers: [
            VisionLayer(id: 'protanopia', variantId: 'protanomaly'),
          ],
          focusedId: 'protanopia',
        ).toJson(),
      )))!;
      expect(omaly.layers.single.variantId, 'protanomaly');
      expect(omaly.layers.single.strengthKey, 'protanomaly');
      expect(omaly.presetId, isNull);
    });

    test('toJson はスキーマ版 2 を書き、seed を文字列で、層に強度を書かない', () {
      final json = VisionFilterSnapshot(
        layers: [
          VisionLayer(id: 'floaters', params: {'seed': BigInt.two}),
        ],
        focusedId: 'floaters',
        strengthByKey: const {'floaters': 0.5},
      ).toJson();

      expect(json['version'], 2);
      expect(kVisionFilterSnapshotVersion, 2);
      final layer = (json['layers'] as List).single as Map;
      expect((layer['params'] as Map)['seed'], '2');
      expect(layer.containsKey('strength'), isFalse,
          reason: '強度は層でなくキーごとの記憶に持つ');
      expect(layer.containsKey('origin'), isFalse,
          reason: '層の起源は書かない（別名の有無だけで区別する）');
      expect(layer.containsKey('variantId'), isFalse);
      expect((json['strengthByKey'] as Map)['floaters'], 0.5);
    });

    test('isEmpty は層・強度の記憶・payload の記憶がすべて空のときだけ true', () {
      expect(const VisionFilterSnapshot().isEmpty, isTrue);
      expect(
        VisionFilterSnapshot(layers: [VisionLayer(id: 'myopia')]).isEmpty,
        isFalse,
      );
      expect(
        const VisionFilterSnapshot(strengthByKey: {'myopia': 0.5}).isEmpty,
        isFalse,
      );
      expect(
        const VisionFilterSnapshot(paramsById: {
          'floaters': {'seed': 1},
        }).isEmpty,
        isFalse,
      );
    });
  });

  group('版・形式が合わない保存値は捨てる（null）', () {
    test('版が新しい / 古い / 無い / 型違い', () {
      expect(VisionFilterSnapshot.fromJson(_json(version: 3)), isNull);
      expect(VisionFilterSnapshot.fromJson(_json(version: 0)), isNull);
      expect(VisionFilterSnapshot.fromJson(_json(version: null)), isNull);
      expect(VisionFilterSnapshot.fromJson(_json(version: '2')), isNull);
      expect(VisionFilterSnapshot.fromJson(_json(version: 2.5)), isNull);
    });

    test('旧形式（版を持たない素朴な Map）は復元しない', () {
      expect(
        VisionFilterSnapshot.fromJson(
          {'selectedId': 'myopia', 'strength': 0.5},
        ),
        isNull,
      );
    });

    test('Map でない JSON', () {
      expect(VisionFilterSnapshot.fromJson(null), isNull);
      expect(VisionFilterSnapshot.fromJson('myopia'), isNull);
      expect(VisionFilterSnapshot.fromJson(<Object?>[1, 2]), isNull);
      expect(VisionFilterSnapshot.fromJson(42), isNull);
    });
  });

  group('層の不変条件に照らした補正（v2）', () {
    test('未知のカタログ id の層は捨てる', () {
      final s = VisionFilterSnapshot.fromJson(_json(
        layers: [_layer('removed_in_sensus'), _layer('myopia')],
        focusedId: 'removed_in_sensus',
      ))!;

      expect(_ids(s), ['myopia']);
      expect(s.focusedId, isNull);
    });

    test('同じ id の重複は先に現れた層を残す', () {
      final p = _entry('astigmatism').parameters.single;
      final s = VisionFilterSnapshot.fromJson(_json(layers: [
        _layer('astigmatism', params: {p.name: p.min}),
        _layer('astigmatism', params: {p.name: p.max}),
      ]))!;

      expect(_ids(s), ['astigmatism']);
      expect(s.layers.single.params[p.name], p.min);
    });

    test('色覚グループは排他: 先に現れた 1 つだけ残す', () {
      final s = VisionFilterSnapshot.fromJson(_json(layers: [
        _layer('tritanopia'),
        _layer('protanopia'),
        _layer('tetrachromacy'),
        _layer('myopia'),
      ]))!;

      expect(_ids(s), ['myopia', 'tritanopia']);
    });

    test('上限 5 を超える分は先のものを残して捨てる', () {
      // すべて適用順に並べた 6 層。
      const ids = [
        'vertigo',
        'myopia',
        'floaters',
        'glaucoma',
        'teichopsia',
        'protanopia',
      ];
      final s = VisionFilterSnapshot.fromJson(_json(layers: [
        for (final id in ids) _layer(id),
      ]))!;

      expect(kMaxVisionLayers, 5);
      expect(_ids(s), ids.take(5).toList());
    });

    test('保存順が適用順でなくても、読み込み後は適用順（段 → 段内の宣言順）に並ぶ', () {
      final s = VisionFilterSnapshot.fromJson(_json(layers: [
        _layer('protanopia'),
        _layer('teichopsia'),
        _layer('floaters'),
        _layer('cataract'),
        _layer('myopia'),
      ]))!;

      // 光学段は sensus の宣言順（myopia が cataract より先）。
      expect(_ids(s),
          ['myopia', 'cataract', 'floaters', 'teichopsia', 'protanopia']);
      final orders = [for (final l in s.layers) visionFilterApplyOrder(l.id)!];
      expect(orders, [...orders]..sort());
    });

    test('別名（variantId）は対応する -opia の層にだけ付く', () {
      final s = VisionFilterSnapshot.fromJson(_json(layers: [
        _layer('protanopia', variantId: 'protanomaly'),
      ]))!;
      expect(s.layers.single.variantId, 'protanomaly');
      expect(s.layers.single.strengthKey, 'protanomaly');

      for (final bad in [
        ('deuteranopia', 'protanomaly'), // 対応しない別名
        ('protanopia', 'protanopia'), // 別名でない
        ('protanopia', 'not_a_type'),
        ('myopia', 'protanomaly'),
        ('achromatopsia', 'tritanomaly'),
      ]) {
        final t = VisionFilterSnapshot.fromJson(_json(layers: [
          _layer(bad.$1, variantId: bad.$2),
        ]))!;
        expect(t.layers.single.variantId, isNull, reason: '$bad');
      }
    });

    test('旧形式が持っていた origin は読んでも無視する（別名は origin に依らず採る）', () {
      for (final origin in [null, 'quick', 'advanced', 'sideways']) {
        final s = VisionFilterSnapshot.fromJson(_json(layers: [
          _layer('protanopia', variantId: 'protanomaly', origin: origin),
          _layer('myopia', origin: origin),
        ]))!;
        expect(_ids(s), ['myopia', 'protanopia'], reason: 'origin=$origin');
        expect(s.layers.last.variantId, 'protanomaly', reason: 'origin=$origin');
        expect(s.layers.first.variantId, isNull, reason: 'origin=$origin');
      }

      final written = VisionFilterSnapshot.fromJson(_json(layers: [
        _layer('achromatopsia', origin: 'quick'),
      ]))!
          .toJson();
      final layer = (written['layers'] as List).single as Map;
      expect(layer.containsKey('origin'), isFalse,
          reason: '読んだ origin を書き出しへ持ち越さない');
    });

    test('focusedId は層に無ければ捨てる', () {
      final withLayer = VisionFilterSnapshot.fromJson(_json(
        layers: [_layer('myopia'), _layer('floaters')],
        focusedId: 'floaters',
      ))!;
      expect(withLayer.focusedId, 'floaters');

      final notInLayers = VisionFilterSnapshot.fromJson(_json(
        layers: [_layer('myopia')],
        focusedId: 'floaters',
      ))!;
      expect(notInLayers.focusedId, isNull);
    });

    test('presetId は層がちょうど 1 つのときだけ持つ', () {
      final one = VisionFilterSnapshot.fromJson(_json(
        layers: [_layer('vertigo')],
        presetId: 'labyrinthitis',
      ))!;
      expect(one.presetId, 'labyrinthitis');

      final two = VisionFilterSnapshot.fromJson(_json(
        layers: [_layer('vertigo'), _layer('myopia')],
        presetId: 'labyrinthitis',
      ))!;
      expect(two.presetId, isNull);

      final none = VisionFilterSnapshot.fromJson(_json(
        presetId: 'labyrinthitis',
      ))!;
      expect(none.presetId, isNull);

      final empty = VisionFilterSnapshot.fromJson(_json(
        layers: [_layer('vertigo')],
        presetId: '',
      ))!;
      expect(empty.presetId, isNull);
    });

    test('layers が List でない・要素が Map でなくても他の部分は読む', () {
      final broken = VisionFilterSnapshot.fromJson(_json(
        layers: 'broken',
        strengthByKey: {'myopia': 0.4},
      ))!;
      expect(broken.layers, isEmpty);
      expect(broken.strengthByKey, {'myopia': 0.4});

      final mixed = VisionFilterSnapshot.fromJson(_json(
        layers: ['str', 7, null, _layer('myopia')],
      ))!;
      expect(_ids(mixed), ['myopia']);
    });

    test('層の params が無ければ id ごとの記憶 → 既定値の順で補う', () {
      final p = _entry('astigmatism').parameters.single;
      final mid = (p.min! + p.max!) / 2;
      final memory = mid == p.defaultValue ? p.min! : mid;

      final fromMemory = VisionFilterSnapshot.fromJson(_json(
        layers: [_layer('astigmatism')],
        paramsById: {
          'astigmatism': {p.name: memory},
        },
      ))!;
      expect(fromMemory.layers.single.params[p.name], memory);

      final fromDefault = VisionFilterSnapshot.fromJson(_json(
        layers: [_layer('astigmatism')],
      ))!;
      expect(fromDefault.layers.single.params,
          defaultVisionParams(_entry('astigmatism')));
    });

    test('層に載った payload は id ごとの記憶にも反映される（層が正本）', () {
      final p = _entry('astigmatism').parameters.single;
      final s = VisionFilterSnapshot.fromJson(_json(
        layers: [
          _layer('astigmatism', params: {p.name: p.max}),
        ],
        paramsById: {
          'astigmatism': {p.name: p.min},
        },
      ))!;

      expect(s.layers.single.params[p.name], p.max);
      expect(s.paramsById['astigmatism']![p.name], p.max);
    });
  });

  group('強度の記憶の補正', () {
    test('0..1 に丸め、数値でなければそのキーだけ捨てる', () {
      final s = VisionFilterSnapshot.fromJson(_json(strengthByKey: {
        'myopia': 5,
        'hyperopia': -2,
        'presbyopia': 'strong',
        'cataract': double.nan,
        'dry_eye': null,
      }))!;

      expect(s.strengthByKey['myopia'], 1.0);
      expect(s.strengthByKey['hyperopia'], 0.0);
      expect(s.strengthByKey.containsKey('presbyopia'), isFalse);
      expect(s.strengthByKey.containsKey('cataract'), isFalse);
      expect(s.strengthByKey.containsKey('dry_eye'), isFalse);
    });

    test('キーはカタログ id か -omaly の別名 id だけ。未知のキーは捨てる', () {
      final s = VisionFilterSnapshot.fromJson(_json(strengthByKey: {
        'removed_in_sensus': 0.5,
        'protanomaly': 0.6,
        'deuteranomaly': 0.7,
        'tritanomaly': 0.8,
        'none': 0.9,
        'protanopia': 1.0,
      }))!;

      expect(s.strengthByKey, {
        'protanomaly': 0.6,
        'deuteranomaly': 0.7,
        'tritanomaly': 0.8,
        'protanopia': 1.0,
      });
    });

    test('strengthByKey が Map でなければ空', () {
      final s = VisionFilterSnapshot.fromJson(_json(
        layers: [_layer('myopia')],
        strengthByKey: [1, 2],
      ))!;
      expect(s.strengthByKey, isEmpty);
      expect(_ids(s), ['myopia']);
    });
  });

  group('payload のカタログに照らした補正', () {
    Map<String, Object> restoreParams(String id, Object? rawParams) =>
        VisionFilterSnapshot.fromJson(_json(paramsById: {
          id: rawParams,
        }))!
            .paramsById[id]!;

    test('未知のフィルタ id・引数を持たないフィルタの記憶は捨てる', () {
      final s = VisionFilterSnapshot.fromJson(_json(paramsById: {
        'removed_in_sensus': {'x': 1},
        'myopia': {'x': 1},
        'astigmatism': <String, Object?>{},
      }))!;

      expect(s.paramsById.keys, ['astigmatism']);
    });

    test('float は範囲外なら min/max へ丸める', () {
      final p = _entry('astigmatism').parameters.single; // axisDeg

      expect(
          restoreParams('astigmatism', {p.name: p.max! + 1000})[p.name], p.max);
      expect(
          restoreParams('astigmatism', {p.name: p.min! - 1000})[p.name], p.min);
    });

    test('int は四捨五入して範囲へ丸め、int 型で返す', () {
      final p = _entry('starbursts')
          .parameters
          .firstWhere((p) => p.kind == VisionParamKind.intValue);
      Object? restore(Object? v) =>
          restoreParams('starbursts', {p.name: v})[p.name];

      expect(restore(p.max! + 500), p.max!.toInt());
      expect(restore(p.min! - 500), p.min!.toInt());
      final inside = p.min!.toInt() + 1;
      expect(restore(inside + 0.4), inside);
      expect(restore(inside + 0.4), isA<int>());
    });

    test('型違い・NaN・Infinity は既定値に戻す', () {
      final p = _entry('astigmatism').parameters.single;
      for (final bad in <Object?>[
        'ninety',
        null,
        true,
        double.nan,
        double.infinity,
        <Object?>[],
      ]) {
        expect(
            restoreParams('astigmatism', {p.name: bad})[p.name], p.defaultValue,
            reason: 'bad=$bad');
      }
    });

    test('層の params も同じ規則で補正する', () {
      final p = _entry('astigmatism').parameters.single;
      final s = VisionFilterSnapshot.fromJson(_json(layers: [
        _layer('astigmatism', params: {p.name: p.max! + 1000}),
      ]))!;

      expect(s.layers.single.params[p.name], p.max);
    });

    test('enum は選択肢に無い値を既定値に戻す', () {
      final p = _entry('glaucoma').parameters.single; // mode
      expect(restoreParams('glaucoma', {p.name: 'removed_option'})[p.name],
          p.defaultValue);

      final valid = p.options.firstWhere((o) => o.value != p.defaultValue);
      expect(restoreParams('glaucoma', {p.name: valid.value})[p.name],
          valid.value);
    });

    test('seed は u64 の範囲外・数字でない文字列を既定値に戻す', () {
      final p = _entry('floaters')
          .parameters
          .firstWhere((p) => p.kind == VisionParamKind.seed);
      for (final bad in <Object?>[
        (kSeedMax + BigInt.one).toString(),
        '-1',
        'abc',
        '',
        // BigInt.tryParse は受け付けるが、保存形式（10 進の整数文字列）ではない。
        '0x10',
        ' 5',
        '5 ',
        '+5',
        '5\n',
        -5,
        1.5,
        null,
      ]) {
        expect(restoreParams('floaters', {p.name: bad})[p.name], BigInt.zero,
            reason: 'bad=$bad');
      }
    });

    test('定義に無い引数は捨て、定義にあって保存に無い引数は既定値で埋める', () {
      final entry = _entry('floaters');
      final keep = entry.parameters
          .firstWhere((p) => p.kind == VisionParamKind.float)
          .name;

      final params =
          restoreParams('floaters', {keep: 0.25, 'removed_param': 7});

      expect(params.containsKey('removed_param'), isFalse);
      expect(params[keep], 0.25);
      expect(
        params.keys.toSet(),
        entry.parameters.map((p) => p.name).toSet(),
        reason: '保存に無かった引数も既定値で揃う',
      );
    });
  });

  group('版 1（単一選択）の変換', () {
    test('選択は層 1 つ（別名なし）になり、fromLegacy が立つ', () {
      final s = VisionFilterSnapshot.fromJson(_v1(
        selectedId: 'myopia',
        filters: {
          'myopia': {'strength': 0.4},
        },
      ))!;

      expect(s.fromLegacy, isTrue);
      expect(_ids(s), ['myopia']);
      expect(s.layers.single.variantId, isNull);
      expect(s.focusedId, 'myopia');
      expect(s.strengthByKey, {'myopia': 0.4});
    });

    test('色覚の選択は色覚の層になり、-omaly は別名つきになる', () {
      final opia = VisionFilterSnapshot.fromJson(_v1(
        selectedId: 'protanopia',
        colorVisionType: 'protanopia',
      ))!;
      expect(opia.layers.single.id, 'protanopia');
      expect(opia.layers.single.variantId, isNull);

      final omaly = VisionFilterSnapshot.fromJson(_v1(
        selectedId: 'deuteranopia',
        colorVisionType: 'deuteranomaly',
      ))!;
      expect(omaly.layers.single.id, 'deuteranopia');
      expect(omaly.layers.single.variantId, 'deuteranomaly');
      expect(omaly.presetId, isNull);
    });

    test('colorVisionType が選択 id と食い違えば別名を付けず、選択 id の層にする', () {
      final s = VisionFilterSnapshot.fromJson(_v1(
        selectedId: 'tritanopia',
        colorVisionType: 'protanopia',
      ))!;

      expect(s.layers.single.id, 'tritanopia');
      expect(s.layers.single.variantId, isNull);
    });

    test('プリセット由来は層 + presetId を引き継ぐ', () {
      final s = VisionFilterSnapshot.fromJson(_v1(
        selectedId: 'vertigo',
        presetId: 'labyrinthitis',
      ))!;

      expect(s.presetId, 'labyrinthitis');
      expect(_ids(s), ['vertigo']);
    });

    test('-opia 4 種の強度は持ち越さず、tetrachromacy と他のフィルタの強度は残す', () {
      final s = VisionFilterSnapshot.fromJson(_v1(filters: {
        'protanopia': {'strength': 0.3},
        'deuteranopia': {'strength': 0.3},
        'tritanopia': {'strength': 0.3},
        'achromatopsia': {'strength': 0.3},
        'tetrachromacy': {'strength': 0.7},
        'myopia': {'strength': 5},
        'hyperopia': {'strength': 'strong'},
      }))!;

      expect(s.strengthByKey, {'tetrachromacy': 0.7, 'myopia': 1.0});
    });

    test('選択が無い・未知の id なら層は空（強度の記憶だけ残る）', () {
      final none = VisionFilterSnapshot.fromJson(_v1(filters: {
        'myopia': {'strength': 0.4},
      }))!;
      expect(none.layers, isEmpty);
      expect(none.focusedId, isNull);
      expect(none.strengthByKey, {'myopia': 0.4});
      expect(none.isEmpty, isFalse);

      final unknown = VisionFilterSnapshot.fromJson(_v1(
        selectedId: 'removed_in_sensus',
        presetId: 'meniere',
        colorVisionType: 'protanopia',
      ))!;
      expect(unknown.layers, isEmpty);
      expect(unknown.presetId, isNull);
      expect(unknown.isEmpty, isTrue);
    });

    test('-opia の強度だけを持つ版 1 は、強度を持ち越さなくても空として扱わない', () {
      final s = VisionFilterSnapshot.fromJson(_v1(filters: {
        'protanopia': {'strength': 1.0},
      }))!;

      expect(s.layers, isEmpty);
      expect(s.strengthByKey, isEmpty);
      expect(s.legacyHadContent, isTrue);
      expect(s.isEmpty, isFalse, reason: '旧実装は非空の保存値として復元した');

      final truly = VisionFilterSnapshot.fromJson(_v1())!;
      expect(truly.legacyHadContent, isFalse);
      expect(truly.isEmpty, isTrue);
    });

    test('選択中フィルタの payload は層と id ごとの記憶の両方に入る', () {
      final p = _entry('astigmatism').parameters.single;
      final s = VisionFilterSnapshot.fromJson(_v1(
        selectedId: 'astigmatism',
        filters: {
          'astigmatism': {
            'params': {p.name: p.max! + 1000},
          },
        },
      ))!;

      expect(s.layers.single.params[p.name], p.max);
      expect(s.paramsById['astigmatism']![p.name], p.max);
    });

    test('filters が Map でなくても選択だけは読む', () {
      final s = VisionFilterSnapshot.fromJson(
        _v1(selectedId: 'myopia', filters: 'broken'),
      )!;

      expect(_ids(s), ['myopia']);
      expect(s.strengthByKey, isEmpty);
    });

    test('色覚型は none・未知の名前を受け付けない', () {
      for (final bad in ['none', 'tetrachromacy_x', '']) {
        final s = VisionFilterSnapshot.fromJson(
          _v1(selectedId: 'protanopia', colorVisionType: bad),
        )!;
        expect(s.layers.single.id, 'protanopia', reason: 'bad=$bad');
        expect(s.layers.single.variantId, isNull, reason: 'bad=$bad');
      }
    });

    test('v1 を変換して v2 で書き戻すと、そのまま v2 として読める（fromLegacy は落ちる）', () {
      final legacy = VisionFilterSnapshot.fromJson(_v1(
        selectedId: 'protanopia',
        colorVisionType: 'protanomaly',
        filters: {
          'myopia': {'strength': 0.4},
        },
      ))!;

      final again = VisionFilterSnapshot.fromJson(
        jsonDecode(jsonEncode(legacy.toJson())),
      )!;

      expect(again.fromLegacy, isFalse);
      expect(again.layers.single.variantId, 'protanomaly');
      expect(again.strengthByKey, {'myopia': 0.4});
    });
  });

  group('sanitizeVisionParams', () {
    test('引数を持たないフィルタは常に空', () {
      expect(sanitizeVisionParams(_entry('myopia'), {'x': 1}), isEmpty);
    });

    test('raw が Map でなければ既定値そのもの', () {
      final entry = _entry('diplopia');
      expect(
        sanitizeVisionParams(entry, 'oops'),
        defaultVisionParams(entry),
      );
    });
  });
}
