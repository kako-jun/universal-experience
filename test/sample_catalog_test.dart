// サンプル画像集（#78）のカタログ整合性・生成物そのものの検証。
//
// - kSampleCatalog の 8 件（#99 で日本語の案内板を追加）が assets/samples/ の実ファイルとして存在し、
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
    test('8 件ちょうど（#78 の最低 7 場面 + #99 の日本語案内板）', () {
      expect(kSampleCatalog, hasLength(8));
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

    test('日本語の案内板 info_board_ja がカタログにあり、文字素材として読める（#99）', () async {
      final entry = kSampleCatalogById['info_board_ja'];
      expect(entry, isNotNull);
      expect(entry!.assetPath, 'assets/samples/info_board_ja.png');

      final image = await _decodeAsset(entry.assetPath);
      addTearDown(image.dispose);
      final bytes =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      int px(int x, int y) {
        final o = (y * image.width + x) * 4;
        return (bytes.getUint8(o) << 16) |
            (bytes.getUint8(o + 1) << 8) |
            bytes.getUint8(o + 2);
      }

      // 3 枚の看板の地色（出口=緑・駅=青・営業中=赤）。
      expect(px(60, 150), 0x1B7F4B, reason: '出口の看板（緑）');
      expect(px(360, 150), 0x1E5AA8, reason: '駅の看板（青）');
      expect(px(580, 150), 0xC62828, reason: '営業中の看板（赤）');

      // 看板の文字（白）が実際に描かれている。範囲は文字の部分だけ（y 40〜200。
      // 「出口」の下の矢印 y 200〜280 は含めない）に絞り、閾値は実測
      // （出口 6369・駅 4177・営業中 11328）の 8 割前後にして、文字が無ければ落ちる。
      int whiteIn(int x1, int x2, int y1, int y2) {
        var n = 0;
        for (var y = y1; y < y2; y++) {
          for (var x = x1; x < x2; x++) {
            if (px(x, y) == 0xFFFFFF) n++;
          }
        }
        return n;
      }

      expect(whiteIn(40, 320, 40, 200), greaterThan(5000), reason: '出口（文字）');
      expect(whiteIn(40, 320, 200, 280), greaterThan(2000), reason: '出口の下の矢印');
      expect(whiteIn(340, 540, 40, 280), greaterThan(3400), reason: '駅');
      expect(whiteIn(560, 984, 40, 280), greaterThan(9000), reason: '営業中');

      // 表の小さな文字（24px）も描かれている: 表の領域に暗い画素が多数ある。
      var dark = 0;
      for (var y = 420; y < 1000; y++) {
        for (var x = 60; x < 600; x++) {
          final c = px(x, y);
          final lum = ((c >> 16) & 0xFF) + ((c >> 8) & 0xFF) + (c & 0xFF);
          if (lum < 300) dark++;
        }
      }
      expect(dark, greaterThan(12000), reason: 'のりば案内の表の文字（実測 15928）');
    });

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
