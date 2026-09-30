// サンプル画像集（#78）のカタログ整合性・生成物そのものの検証。
//
// - kSampleCatalog の 7 件が assets/samples/ の実ファイルとして存在し、
//   flutter test 環境でも rootBundle 経由でデコードでき、正準サイズ
//   （BeforeAfterView.canonicalSampleSize、1024px）の正方形であること。
// - kRecommendedSampleByFilterId が kVisionFilterCatalog の全 30 id を過不足
//   なくカバーし、値がすべて kSampleCatalogById に存在する既知のサンプル id
//   であること（sample_catalog.dart の doc コメントが謳う契約）。

import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/models/sample_catalog.dart';
import 'package:universal_experience/models/vision_filter_catalog.dart';
import 'package:universal_experience/rendering/image_fit.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart'
    show BeforeAfterView;

Future<ui.Image> _decodeAsset(String path) async {
  final data = await rootBundle.load(path);
  return decodeImageBytes(data.buffer.asUint8List());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('kSampleCatalog', () {
    test('7 件ちょうど（#78 issue: 最低限の場面数）', () {
      expect(kSampleCatalog, hasLength(7));
    });

    test('id は重複しない', () {
      final ids = kSampleCatalog.map((e) => e.id).toSet();
      expect(ids, hasLength(kSampleCatalog.length));
    });

    test('kSampleCatalogById は kSampleCatalog と同じ内容の索引', () {
      for (final entry in kSampleCatalog) {
        expect(kSampleCatalogById[entry.id], same(entry));
      }
      expect(kSampleCatalogById, hasLength(kSampleCatalog.length));
    });

    test('depth_landscape だけが depthAssetPath を持つ', () {
      for (final entry in kSampleCatalog) {
        if (entry.id == 'depth_landscape') {
          expect(entry.depthAssetPath, isNotNull);
        } else {
          expect(entry.depthAssetPath, isNull, reason: entry.id);
        }
      }
    });

    for (final entry in kSampleCatalog) {
      test(
          '${entry.id}: assetPath がデコードでき、'
          '正準サイズ(${BeforeAfterView.canonicalSampleSize}px)の正方形', () async {
        final image = await _decodeAsset(entry.assetPath);
        addTearDown(image.dispose);
        expect(image.width, BeforeAfterView.canonicalSampleSize);
        expect(image.height, BeforeAfterView.canonicalSampleSize);
      });
    }

    test('depth_landscape の深度マップも同じ正準サイズでデコードできる', () async {
      final entry = kSampleCatalogById['depth_landscape']!;
      final image = await _decodeAsset(entry.depthAssetPath!);
      addTearDown(image.dispose);
      expect(image.width, BeforeAfterView.canonicalSampleSize);
      expect(image.height, BeforeAfterView.canonicalSampleSize);
    });
  });

  group('kRecommendedSampleByFilterId (#78)', () {
    test('kVisionFilterCatalog の全 30 id を過不足なくカバーする', () {
      final catalogIds = kVisionFilterCatalog.map((e) => e.id).toSet();
      final mappedIds = kRecommendedSampleByFilterId.keys.toSet();
      expect(mappedIds.difference(catalogIds), isEmpty,
          reason: 'catalog に存在しない id への写像');
      expect(catalogIds.difference(mappedIds), isEmpty,
          reason: '推奨サンプルが未定義の filter id');
    });

    test('値はすべて既知のサンプル id', () {
      for (final entry in kRecommendedSampleByFilterId.entries) {
        expect(kSampleCatalogById.containsKey(entry.value), isTrue,
            reason: '${entry.key} -> ${entry.value}');
      }
    });

    test('recommendedSampleIdForFilter: null は既定サンプルにフォールバックする', () {
      expect(recommendedSampleIdForFilter(null), kDefaultSampleId);
    });

    test('recommendedSampleIdForFilter: 既知 id はそのままマップ値を返す', () {
      expect(recommendedSampleIdForFilter('deuteranopia'), 'fruit_stand');
      expect(recommendedSampleIdForFilter('night_blindness'), 'night_scene');
      expect(recommendedSampleIdForFilter('starbursts'), 'night_scene');
    });

    test('recommendedSampleIdForFilter: 文字・グラフ素材の割り当て', () {
      expect(recommendedSampleIdForFilter('protanopia'), 'traffic_signs');
      expect(recommendedSampleIdForFilter('tritanopia'), 'fruit_stand');
      expect(recommendedSampleIdForFilter('astigmatism'), 'info_board');
      expect(recommendedSampleIdForFilter('photophobia'), 'depth_landscape');
      // flickering_stars は変更なし（night_scene のまま）。
      expect(recommendedSampleIdForFilter('flickering_stars'), 'night_scene');
    });

    test('kDefaultSampleId は既知のサンプル id', () {
      expect(kSampleCatalogById.containsKey(kDefaultSampleId), isTrue);
    });
  });
}
