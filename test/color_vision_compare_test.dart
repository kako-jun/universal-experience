import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/models/vision_filter_catalog.dart';
import 'package:universal_experience/services/color_vision_compare.dart';
import 'package:universal_experience/services/filter_service.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';

/// 色覚 4 型の一覧比較（2×2、#84）で何を並べるかを決める pure な部分のテスト。
void main() {
  group('kColorVisionCompareEntries', () {
    test('カタログ id で protanopia・deuteranopia・tritanopia・achromatopsia の順', () {
      expect(
        [for (final e in kColorVisionCompareEntries) e.id],
        ['protanopia', 'deuteranopia', 'tritanopia', 'achromatopsia'],
      );
      expect(kColorVisionCompareEntries.length, 4);
    });

    test('実験的な四色覚は含まない（他の 4 型と同列に比べる対象ではない）', () {
      expect(
        kColorVisionCompareEntries.any((e) => e.id == 'tetrachromacy'),
        isFalse,
      );
      expect(
          kColorVisionCompareEntries.every((e) => !e.isExperimental), isTrue);
    });

    test('色覚カテゴリのカタログ項目のうち非実験的なものと同じ集合・同じ順', () {
      final expected = [
        for (final e in kVisionFilterCatalog)
          if (e.category == VisionFilterCategory.colorVision &&
              !e.isExperimental)
            e.id,
      ];
      expect([for (final e in kColorVisionCompareEntries) e.id], expected);
    });

    test('変更不可のリスト', () {
      expect(
        () => kColorVisionCompareEntries.add(kVisionFilterCatalog.first),
        throwsUnsupportedError,
      );
    });
  });

  group('isColorVisionFilterId', () {
    test('色覚カテゴリの id（四色覚を含む）は true', () {
      for (final e in kVisionFilterCatalog) {
        if (e.category == VisionFilterCategory.colorVision) {
          expect(isColorVisionFilterId(e.id), isTrue, reason: e.id);
        }
      }
      expect(isColorVisionFilterId('tetrachromacy'), isTrue);
    });

    test('色覚以外のカテゴリの id は false', () {
      for (final e in kVisionFilterCatalog) {
        if (e.category != VisionFilterCategory.colorVision) {
          expect(isColorVisionFilterId(e.id), isFalse, reason: e.id);
        }
      }
      expect(isColorVisionFilterId('myopia'), isFalse);
    });

    test('未選択（null）・未知の id は false', () {
      expect(isColorVisionFilterId(null), isFalse);
      expect(isColorVisionFilterId('no-such-filter'), isFalse);
      expect(isColorVisionFilterId(''), isFalse);
    });
  });

  group('colorVisionCompareFilter', () {
    test('色覚クイック選択と同じ対応表（visionFilterForColorVisionType）を引く', () {
      const expected = <String, VisionFilter>{
        'protanopia': VisionFilter.protanopia(),
        'deuteranopia': VisionFilter.deuteranopia(),
        'tritanopia': VisionFilter.tritanopia(),
        'achromatopsia': VisionFilter.achromatopsia(),
      };
      for (final entry in kColorVisionCompareEntries) {
        final type =
            ColorVisionType.values.singleWhere((t) => t.id == entry.id);
        expect(colorVisionCompareFilter(entry), expected[entry.id],
            reason: entry.id);
        expect(
          colorVisionCompareFilter(entry),
          visionFilterForColorVisionType(type),
          reason: entry.id,
        );
      }
    });

    test('4 セルのフィルタはすべて互いに異なる', () {
      final filters = [
        for (final e in kColorVisionCompareEntries) colorVisionCompareFilter(e),
      ];
      for (var i = 0; i < filters.length; i++) {
        for (var j = i + 1; j < filters.length; j++) {
          expect(filters[i], isNot(filters[j]), reason: '$i vs $j');
        }
      }
    });

    test('色覚型に対応しないカタログ項目は StateError（黙って別物に落とさない）', () {
      expect(
        () => colorVisionCompareFilter(
          kVisionFilterCatalog.firstWhere(
            (e) => e.category != VisionFilterCategory.colorVision,
          ),
        ),
        throwsStateError,
      );
      // 四色覚は色覚カテゴリだが ColorVisionType に対応が無い。
      expect(
        () => colorVisionCompareFilter(
          kVisionFilterCatalog.firstWhere((e) => e.id == 'tetrachromacy'),
        ),
        throwsStateError,
      );
    });
  });
}
