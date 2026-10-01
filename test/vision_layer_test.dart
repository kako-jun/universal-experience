// VisionLayer と層の列の不変条件（#117）のテスト。

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/models/vision_filter_catalog.dart';
import 'package:universal_experience/models/vision_filter_stage.dart';
import 'package:universal_experience/services/vision_layer.dart';

List<String> _ids(List<VisionLayer> layers) => [for (final l in layers) l.id];

void main() {
  group('VisionLayer', () {
    test('強度は持たず、記憶のキーは別名 id ?? カタログ id', () {
      expect(VisionLayer(id: 'myopia').strengthKey, 'myopia');
      expect(
        VisionLayer(id: 'protanopia', variantId: 'protanomaly').strengthKey,
        'protanomaly',
      );
    });

    test('params は読み取り専用で、渡した Map を後から変えても影響しない', () {
      final source = <String, Object>{'seed': BigInt.one};
      final layer = VisionLayer(id: 'floaters', params: source);
      source['seed'] = BigInt.two;

      expect(layer.params['seed'], BigInt.one);
      expect(() => layer.params['seed'] = BigInt.two, throwsUnsupportedError);
    });

    test('copyWith は id・別名を保ち、params だけ差し替える', () {
      final layer = VisionLayer(id: 'protanopia', variantId: 'protanomaly');
      final copy = layer.copyWith(params: const {'x': 1});

      expect(copy.id, 'protanopia');
      expect(copy.variantId, 'protanomaly');
      expect(copy.params, {'x': 1});
      expect(layer.params, isEmpty);
    });
  });

  group('色覚キーとの対応', () {
    test('-opia 4 種のキーはカタログ id そのもので別名なし、-omaly は別名つき', () {
      for (final key in [
        'protanopia',
        'deuteranopia',
        'tritanopia',
        'achromatopsia',
      ]) {
        final target = resolveVisionKey(key)!;
        expect(target.id, key);
        expect(target.variantId, isNull);
        expect(VisionLayer(id: target.id).strengthKey, key);
      }
      final omaly = resolveVisionKey('tritanomaly')!;
      expect(omaly.id, 'tritanopia');
      expect(omaly.variantId, 'tritanomaly');
      expect(
        VisionLayer(id: omaly.id, variantId: omaly.variantId).strengthKey,
        'tritanomaly',
      );
    });

    test('色覚 7 種のクイックキーは isColorVisionQuickKey が真、none と他の id は偽', () {
      for (final key in [
        'protanopia',
        'deuteranopia',
        'tritanopia',
        'achromatopsia',
        'protanomaly',
        'deuteranomaly',
        'tritanomaly',
      ]) {
        expect(isColorVisionQuickKey(key), isTrue, reason: key);
      }
      expect(isColorVisionQuickKey('none'), isFalse);
      expect(isColorVisionQuickKey('myopia'), isFalse);
    });

    test('resolveVisionKey は未知のキーを引かず、none も引かない', () {
      expect(resolveVisionKey('none'), isNull);
      expect(resolveVisionKey('removed_in_sensus'), isNull);
      expect(resolveVisionKey('myopia')!.variantId, isNull);
    });

    test('既定強度は -opia が 1.0、-omaly が 0.6、それ以外は null', () {
      expect(colorVisionDefaultStrength('protanopia'), 1.0);
      expect(
          colorVisionDefaultStrength('deuteranomaly'), kAnomalyDefaultSeverity);
      expect(colorVisionDefaultStrength('myopia'), isNull);
    });

    test('isValidVariantFor は対応する -opia の別名だけを許す', () {
      expect(isValidVariantFor('protanopia', 'protanomaly'), isTrue);
      expect(isValidVariantFor('deuteranopia', 'deuteranomaly'), isTrue);
      expect(isValidVariantFor('tritanopia', 'tritanomaly'), isTrue);
      expect(isValidVariantFor('deuteranopia', 'protanomaly'), isFalse);
      expect(isValidVariantFor('protanopia', 'protanopia'), isFalse);
      expect(isValidVariantFor('myopia', 'protanomaly'), isFalse);
    });

    test('isValidStrengthKey はカタログ id と -omaly の別名だけを許す', () {
      expect(isValidStrengthKey('myopia'), isTrue);
      expect(isValidStrengthKey('deuteranomaly'), isTrue);
      expect(isValidStrengthKey('none'), isFalse);
      expect(isValidStrengthKey('removed_in_sensus'), isFalse);
    });
  });

  group('normalizeVisionLayers', () {
    test('空なら空', () {
      expect(normalizeVisionLayers(const []), isEmpty);
    });

    test('未知の id を捨て、重複は先のものを残す', () {
      final a = VisionLayer(id: 'myopia', params: const {'y': 2});
      final b = VisionLayer(id: 'myopia', params: const {'x': 1});
      final out = normalizeVisionLayers([
        VisionLayer(id: 'removed_in_sensus'),
        a,
        b,
      ]);

      expect(out, hasLength(1));
      expect(identical(out.single, a), isTrue);
    });

    test('色覚グループは 1 つだけ（先に現れたもの）。他の段は巻き込まない', () {
      final out = normalizeVisionLayers([
        VisionLayer(id: 'achromatopsia'),
        VisionLayer(id: 'tetrachromacy'),
        VisionLayer(id: 'protanopia'),
        VisionLayer(id: 'glaucoma'),
      ]);

      expect(_ids(out), ['glaucoma', 'achromatopsia']);
    });

    test('上限 5 を超えたら先のものを残す（色覚で弾かれた層は枠を消費しない）', () {
      final out = normalizeVisionLayers([
        VisionLayer(id: 'tritanopia'),
        VisionLayer(id: 'protanopia'), // 色覚の排他で捨てられる
        VisionLayer(id: 'vertigo'),
        VisionLayer(id: 'myopia'),
        VisionLayer(id: 'floaters'),
        VisionLayer(id: 'glaucoma'),
        VisionLayer(id: 'teichopsia'), // 6 枚目で捨てられる
      ]);

      expect(out, hasLength(kMaxVisionLayers));
      expect(_ids(out),
          ['vertigo', 'myopia', 'floaters', 'glaucoma', 'tritanopia']);
    });

    test('入力順に関わらず適用順に並ぶ（結果が選択の履歴に依存しない）', () {
      const ids = [
        'protanopia',
        'teichopsia',
        'floaters',
        'cataract',
        'vertigo'
      ];
      final forward = _ids(
          normalizeVisionLayers([for (final id in ids) VisionLayer(id: id)]));
      final backward = _ids(normalizeVisionLayers(
          [for (final id in ids.reversed) VisionLayer(id: id)]));

      expect(forward,
          ['vertigo', 'cataract', 'floaters', 'teichopsia', 'protanopia']);
      expect(backward, forward);
    });

    test('戻り値は変更できない', () {
      final out = normalizeVisionLayers([VisionLayer(id: 'myopia')]);
      expect(
          () => out.add(VisionLayer(id: 'floaters')), throwsUnsupportedError);
    });
  });
}
