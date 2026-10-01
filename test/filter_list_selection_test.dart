// 統合フィルタ一覧（filter_list_selection.dart、#72）の純粋ロジックのテスト。
//
// 色覚 7 型と advanced 30 フィルタが 1 つの一覧になること、検索（日本語・英語・
// かな/カナ）、選択の書き込み入口（色覚も advanced も toggleFilterListEntry 経由で
// VisionFilterState.toggle に入る。別名は variantId 付きの層になる）、↑↓ の順送り
// （端で折り返す）を確認する。

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/models/vision_filter_catalog.dart';
import 'package:universal_experience/services/filter_list_selection.dart';
import 'package:universal_experience/services/vision_layer.dart';
import 'package:universal_experience/services/vision_filter_state.dart';

import 'support/vision_filter_metadata_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installVisionFilterMetadataFixture);
  tearDown(resetVisionFilterMetadataProviders);

  FilterListEntry entryByKey(String key) =>
      kFilterListEntries.firstWhere((e) => e.key == key);

  group('kFilterListEntries', () {
    test('advanced 30 件 + 色覚クイック選択にしか無い 3 型 = 33 行で、キーは一意', () {
      expect(kFilterListEntries.length, kVisionFilterCatalog.length + 3);
      expect(
        kFilterListEntries.map((e) => e.key).toSet().length,
        kFilterListEntries.length,
      );
    });

    test('色覚 7 型はすべて一覧に 1 行ずつある', () {
      final keys = kFilterListEntries
          .map((e) => e.strengthKey)
          .where(isColorVisionQuickKey)
          .toList();
      expect(keys.toSet(), {
        'protanopia',
        'deuteranopia',
        'tritanopia',
        'achromatopsia',
        'protanomaly',
        'deuteranomaly',
        'tritanomaly',
      });
      expect(keys.length, 7, reason: '1 キー 1 行');
    });

    test('-omaly の行は対応する -opia のカタログ id + variantId を持つ', () {
      final omaly = entryByKey('cv:protanomaly');
      expect(omaly.catalogId, 'protanopia');
      expect(omaly.variantId, 'protanomaly');
      expect(omaly.strengthKey, 'protanomaly');
      final full = entryByKey('cv:protanopia');
      expect(full.catalogId, 'protanopia');
      expect(full.variantId, isNull);
      expect(full.strengthKey, 'protanopia');
    });

    test('advanced だけの行（starbursts 等）は variantId を持たず、色覚キーでもない', () {
      final row = entryByKey('catalog:starbursts');
      expect(row.variantId, isNull);
      expect(isColorVisionQuickKey(row.strengthKey), isFalse);
    });
  });

  group('検索', () {
    test('空の検索語は全行（カテゴリ null）', () {
      expect(visibleFilterListEntries(), kFilterListEntries);
      expect(visibleFilterListEntries(query: '   '), kFilterListEntries);
    });

    test('英語名・日本語名・大文字小文字・空白のどれでも当たる', () {
      for (final q in ['protanopia', 'PROTANOPIA', 'protan opia', '1型2色覚']) {
        expect(
          visibleFilterListEntries(query: q).map((e) => e.key),
          contains('cv:protanopia'),
          reason: q,
        );
      }
    });

    test('正規化はカタカナ→ひらがな・小文字化・区切り除去', () {
      expect(normalizeFilterSearchText('プロタノピア'),
          normalizeFilterSearchText('ぷろたのぴあ'));
      expect(normalizeFilterSearchText('Pro-Tan_opia'), 'protanopia');
    });

    test('該当なしは空', () {
      expect(visibleFilterListEntries(query: 'zzzzzzzz'), isEmpty);
    });

    test('検索語があるときはカテゴリを無視して全体から探す', () {
      final other = VisionFilterCategory.values
          .firstWhere((c) => c != entryByKey('cv:protanopia').category);
      expect(
        visibleFilterListEntries(query: 'protanopia', category: other)
            .map((e) => e.key),
        contains('cv:protanopia'),
      );
    });

    test('検索語が空ならカテゴリだけで絞る', () {
      final category = entryByKey('cv:protanopia').category;
      final rows = visibleFilterListEntries(category: category);
      expect(rows, isNotEmpty);
      expect(rows.every((e) => e.category == category), isTrue);
    });

    test('体験プリセットも ja/en/id で当たる', () {
      expect(experienceMatchesQuery('meniere', 'meniere'), isTrue);
      expect(experienceMatchesQuery('meniere', 'メニエール'), isTrue);
      expect(experienceMatchesQuery('meniere', 'bppv'), isFalse);
      expect(experienceMatchesQuery('meniere', ''), isTrue);
    });
  });

  group('選択の書き込み', () {
    test('色覚の別名の行は variantId 付きの層になる', () {
      final state = VisionFilterState();
      toggleFilterListEntry(state, entryByKey('cv:deuteranomaly'));
      expect(state.selectedId, 'deuteranopia');
      expect(state.focusedVariantId, 'deuteranomaly');
      expect(state.focusedLayer!.strengthKey, 'deuteranomaly');
      expect(selectedFilterListEntry(state), entryByKey('cv:deuteranomaly'));
    });

    test('advanced だけの行は variantId の無い層になる', () {
      final state = VisionFilterState();
      toggleFilterListEntry(state, entryByKey('catalog:starbursts'));
      expect(state.selectedId, 'starbursts');
      expect(state.focusedVariantId, isNull);
      expect(selectedFilterListEntry(state), entryByKey('catalog:starbursts'));
    });

    test('何も選んでいなければ null、体験プリセット選択中も null', () {
      final state = VisionFilterState();
      expect(selectedFilterListEntry(state), isNull);
      state.selectPreset('bppv', 'bppv_rotation');
      expect(selectedFilterListEntry(state), isNull);
    });
  });

  group('nextFilterListEntry（↑↓）', () {
    final visible = kFilterListEntries.take(3).toList();

    test('未選択から ↓ は先頭、↑ は末尾', () {
      expect(nextFilterListEntry(visible, null, forward: true), visible.first);
      expect(nextFilterListEntry(visible, null, forward: false), visible.last);
    });

    test('順に進み、端で折り返す', () {
      expect(
          nextFilterListEntry(visible, visible[0], forward: true), visible[1]);
      expect(
          nextFilterListEntry(visible, visible[2], forward: true), visible[0]);
      expect(
          nextFilterListEntry(visible, visible[0], forward: false), visible[2]);
      expect(
          nextFilterListEntry(visible, visible[2], forward: false), visible[1]);
    });

    test('今見えている行に現在の選択が無ければ、方向に応じて端から始める', () {
      final outside = kFilterListEntries.last;
      expect(
          nextFilterListEntry(visible, outside, forward: true), visible.first);
      expect(
          nextFilterListEntry(visible, outside, forward: false), visible.last);
    });

    test('空の一覧は null', () {
      expect(nextFilterListEntry(const [], null, forward: true), isNull);
    });
  });

  group('多選択の入口（#120）', () {
    late VisionFilterState state;
    setUp(() {
      state = VisionFilterState();
    });

    test('toggleFilterListEntry は足し引きし、番号は段順', () {
      toggleFilterListEntry(state, entryByKey('catalog:glaucoma'));
      toggleFilterListEntry(state, entryByKey('catalog:myopia'));
      expect(filterListEntryOrder(state, entryByKey('catalog:myopia')), 1);
      expect(filterListEntryOrder(state, entryByKey('catalog:glaucoma')), 2);
      expect(
          filterListEntryOrder(state, entryByKey('catalog:floaters')), isNull);

      final result = toggleFilterListEntry(state, entryByKey('catalog:myopia'));
      expect(result, VisionLayerResult.removed);
      expect(filterListEntryOrder(state, entryByKey('catalog:glaucoma')), 1);
    });

    test('色覚の行は別名（-omaly）まで区別して対応づく', () {
      final omaly = entryByKey('cv:protanomaly');
      final full = entryByKey('cv:protanopia');
      toggleFilterListEntry(state, omaly);
      expect(layerForFilterListEntry(state, omaly), isNotNull);
      expect(layerForFilterListEntry(state, full), isNull);
      expect(filterListEntryForLayer(state.layers.single), omaly);
      expect(state.focusedVariantId, 'protanomaly');
    });

    test('上限では未選択の行が layerLimit になるが、色覚の行は色覚層があれば選べる', () {
      for (final k in [
        'catalog:myopia',
        'catalog:cataract',
        'catalog:floaters',
        'catalog:glaucoma',
        'cv:protanopia',
      ]) {
        toggleFilterListEntry(state, entryByKey(k));
      }
      expect(
        filterListEntryBlockReason(state, entryByKey('catalog:hyperopia')),
        VisionLayerBlockReason.layerLimit,
      );
      expect(filterListEntryBlockReason(state, entryByKey('cv:tritanopia')),
          isNull);
      // チェック済みの行は外せるので理由なし。
      expect(filterListEntryBlockReason(state, entryByKey('catalog:myopia')),
          isNull);
      final blocked =
          toggleFilterListEntry(state, entryByKey('catalog:hyperopia'));
      expect(blocked.change, VisionLayerChange.blocked);
      expect(state.layers.length, 5);
    });

    test('isExclusiveFilterListEntry は色覚カテゴリだけ', () {
      expect(isExclusiveFilterListEntry(entryByKey('cv:protanopia')), isTrue);
      expect(isExclusiveFilterListEntry(entryByKey('catalog:myopia')), isFalse);
    });
  });
}
