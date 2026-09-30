// VisionFilterSnapshot（#65）のテスト。
//
// - JSON の往復で、カタログ全 30 フィルタの payload（seed の u64 全域を含む）・
//   強度・選択の起源が失われない。
// - 読み込みはカタログの定義（min/max/default/options）に照らして補正する:
//   範囲外は丸め、型違い・未知の選択肢・NaN は既定値、未知の id・引数は捨てる。
// - 未知・欠落の版、Map でない値は丸ごと捨てる（null）。起動を止めない。
//
// 補正の期待値はテスト内にカタログの値を直書きせず、カタログの定義から導く
// （定義が変わってもテストが追従する。ただし「範囲外を作る」ための入力は
// 定義の外側に出す）。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/models/vision_filter_catalog.dart';
import 'package:universal_experience/services/vision_filter_snapshot.dart';

Map<String, Object?> _json({
  Object? version = kVisionFilterSnapshotVersion,
  String? selectedId,
  String? presetId,
  String? colorVisionType,
  Object? filters = const <String, Object?>{},
}) =>
    {
      'version': version,
      'selectedId': selectedId,
      'presetId': presetId,
      'colorVisionType': colorVisionType,
      'filters': filters,
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

void main() {
  group('JSON の往復', () {
    test('カタログ全フィルタの強度・payload が jsonEncode を経ても一致する', () {
      final strengthById = <String, double>{};
      final paramsById = <String, Map<String, Object>>{};
      var i = 0;
      for (final e in kVisionFilterCatalog) {
        strengthById[e.id] = 0.1 + (i++ % 9) * 0.1;
        if (e.parameters.isNotEmpty) {
          paramsById[e.id] = {
            for (final p in e.parameters) p.name: _nonDefaultValue(p),
          };
        }
      }
      final snapshot = VisionFilterSnapshot(
        selectedId: 'starbursts',
        strengthById: strengthById,
        paramsById: paramsById,
      );

      final restored = VisionFilterSnapshot.fromJson(
        jsonDecode(jsonEncode(snapshot.toJson())),
      )!;

      expect(restored.selectedId, 'starbursts');
      expect(restored.strengthById, strengthById);
      expect(restored.paramsById, paramsById);
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
          selectedId: 'floaters',
          paramsById: {
            'floaters': {'seed': seed},
          },
        );
        final decoded = jsonDecode(jsonEncode(snapshot.toJson()));

        final restored = VisionFilterSnapshot.fromJson(decoded)!;

        expect(restored.paramsById['floaters']!['seed'], seed);
      }
    });

    test('選択の起源（プリセット・色覚クイック選択）も往復する', () {
      final preset = VisionFilterSnapshot.fromJson(jsonDecode(jsonEncode(
        const VisionFilterSnapshot(
          selectedId: 'vertigo',
          presetId: 'labyrinthitis',
        ).toJson(),
      )))!;
      expect(preset.presetId, 'labyrinthitis');
      expect(preset.colorVisionType, isNull);

      final color = VisionFilterSnapshot.fromJson(jsonDecode(jsonEncode(
        const VisionFilterSnapshot(
          selectedId: 'protanopia',
          colorVisionType: ColorVisionType.protanomaly,
        ).toJson(),
      )))!;
      expect(color.colorVisionType, ColorVisionType.protanomaly);
      expect(color.presetId, isNull);
    });

    test('toJson はスキーマ版を書き、seed を文字列で書く', () {
      final json = VisionFilterSnapshot(
        selectedId: 'floaters',
        paramsById: {
          'floaters': {'seed': BigInt.two},
        },
      ).toJson();

      expect(json['version'], kVisionFilterSnapshotVersion);
      final floaters = (json['filters'] as Map)['floaters'] as Map;
      expect((floaters['params'] as Map)['seed'], '2');
    });
  });

  group('版・形式が合わない保存値は捨てる（null）', () {
    test('版が新しい / 古い / 無い / 型違い', () {
      expect(VisionFilterSnapshot.fromJson(_json(version: 2)), isNull);
      expect(VisionFilterSnapshot.fromJson(_json(version: 0)), isNull);
      expect(VisionFilterSnapshot.fromJson(_json(version: null)), isNull);
      expect(VisionFilterSnapshot.fromJson(_json(version: '1')), isNull);
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

  group('カタログに照らした補正', () {
    test('未知のフィルタ id は選択も記憶も捨てる', () {
      final s = VisionFilterSnapshot.fromJson(_json(
        selectedId: 'removed_in_sensus',
        filters: {
          'removed_in_sensus': {'strength': 0.5},
          'myopia': {'strength': 0.4},
        },
      ))!;

      expect(s.selectedId, isNull);
      expect(s.strengthById.keys, ['myopia']);
    });

    test('float は範囲外なら min/max へ丸める', () {
      final p = _entry('astigmatism').parameters.single; // axisDeg
      final over = VisionFilterSnapshot.fromJson(_json(filters: {
        'astigmatism': {
          'params': {p.name: p.max! + 1000},
        },
      }))!;
      final under = VisionFilterSnapshot.fromJson(_json(filters: {
        'astigmatism': {
          'params': {p.name: p.min! - 1000},
        },
      }))!;

      expect(over.paramsById['astigmatism']![p.name], p.max);
      expect(under.paramsById['astigmatism']![p.name], p.min);
    });

    test('int は四捨五入して範囲へ丸め、int 型で返す', () {
      final p = _entry('starbursts')
          .parameters
          .firstWhere((p) => p.kind == VisionParamKind.intValue);
      Object? restore(Object? v) => VisionFilterSnapshot.fromJson(_json(
            filters: {
              'starbursts': {
                'params': {p.name: v},
              },
            },
          ))!
              .paramsById['starbursts']![p.name];

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
        final params = VisionFilterSnapshot.fromJson(_json(filters: {
          'astigmatism': {
            'params': {p.name: bad},
          },
        }))!
            .paramsById['astigmatism']!;

        expect(params[p.name], p.defaultValue, reason: 'bad=$bad');
      }
    });

    test('enum は選択肢に無い値を既定値に戻す', () {
      final p = _entry('glaucoma').parameters.single; // mode
      final params = VisionFilterSnapshot.fromJson(_json(filters: {
        'glaucoma': {
          'params': {p.name: 'removed_option'},
        },
      }))!
          .paramsById['glaucoma']!;
      expect(params[p.name], p.defaultValue);

      final valid = p.options.firstWhere((o) => o.value != p.defaultValue);
      final kept = VisionFilterSnapshot.fromJson(_json(filters: {
        'glaucoma': {
          'params': {p.name: valid.value},
        },
      }))!
          .paramsById['glaucoma']!;
      expect(kept[p.name], valid.value);
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
        final params = VisionFilterSnapshot.fromJson(_json(filters: {
          'floaters': {
            'params': {p.name: bad},
          },
        }))!
            .paramsById['floaters']!;

        expect(params[p.name], BigInt.zero, reason: 'bad=$bad');
      }
    });

    test('定義に無い引数は捨て、定義にあって保存に無い引数は既定値で埋める', () {
      final entry = _entry('floaters');
      final keep = entry.parameters
          .firstWhere((p) => p.kind == VisionParamKind.float)
          .name;

      final params = VisionFilterSnapshot.fromJson(_json(filters: {
        'floaters': {
          'params': {keep: 0.25, 'removed_param': 7},
        },
      }))!
          .paramsById['floaters']!;

      expect(params.containsKey('removed_param'), isFalse);
      expect(params[keep], 0.25);
      expect(
        params.keys.toSet(),
        entry.parameters.map((p) => p.name).toSet(),
        reason: '保存に無かった引数も既定値で揃う',
      );
    });

    test('強度は 0..1 に丸め、数値でなければその id の強度だけ捨てる', () {
      final s = VisionFilterSnapshot.fromJson(_json(filters: {
        'myopia': {'strength': 5},
        'hyperopia': {'strength': -2},
        'presbyopia': {'strength': 'strong'},
        'cataract': {'strength': double.nan},
        'dry_eye': 'not a map',
      }))!;

      expect(s.strengthById['myopia'], 1.0);
      expect(s.strengthById['hyperopia'], 0.0);
      expect(s.strengthById.containsKey('presbyopia'), isFalse);
      expect(s.strengthById.containsKey('cataract'), isFalse);
      expect(s.strengthById.containsKey('dry_eye'), isFalse);
    });

    test('filters が Map でなくても選択だけは復元する', () {
      final s = VisionFilterSnapshot.fromJson(
        _json(selectedId: 'myopia', filters: 'broken'),
      )!;

      expect(s.selectedId, 'myopia');
      expect(s.strengthById, isEmpty);
      expect(s.paramsById, isEmpty);
    });

    test('選択が無ければプリセット・色覚の起源も捨てる', () {
      final s = VisionFilterSnapshot.fromJson(_json(
        selectedId: 'removed_in_sensus',
        presetId: 'meniere',
        colorVisionType: 'protanopia',
      ))!;

      expect(s.presetId, isNull);
      expect(s.colorVisionType, isNull);
    });

    test('色覚型は none・未知の名前を受け付けない', () {
      for (final bad in ['none', 'tetrachromacy_x', '']) {
        final s = VisionFilterSnapshot.fromJson(
          _json(selectedId: 'protanopia', colorVisionType: bad),
        )!;
        expect(s.colorVisionType, isNull, reason: 'bad=$bad');
      }
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
