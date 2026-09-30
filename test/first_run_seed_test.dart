// main.dart の buildRootApp() が担う初回起動シード（#78, #124）のテスト。
//
// 起動順は「初回起動の層（VisionFilterState.seedInitialLayers）→ 旧保存の取り込み
// （VisionFilterStore.migrateLegacySettings）→ 保存の復元（restoreAndBind）」。
// 何も保存されていない初回起動は、deuteranomaly（-deuteranopia の別名）・強度 0.6 の層
// で始まる。保存（v2・旧キー）があれば、そちらがシードに勝つ。
// - 初回起動の強度は記憶へ書かず、読むときに導出する（保存にも何も書かない）。
// - 保存済みの「未選択」（v2 の空・旧 settings.filterType = none）はシードで上書きしない。
// - 初回のサンプル画像も、シードした層の推奨サンプルに合わせる。
//
// buildRootApp はアプリ全体で 1 つだけの共有トップレベル singleton
// （main.dart の visionFilterState/imageSourceState）を直接動かすため、各テストの後に
// ニュートラルな状態へ明示的にリセットする（このファイル内の他テスト・同一プロセスで
// 動く他のテストへ影響を残さないため）。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/main.dart';
import 'package:universal_experience/models/sample_catalog.dart';
import 'package:universal_experience/models/vision_filter_catalog.dart'
    show kAnomalyDefaultSeverity;
import 'package:universal_experience/services/settings_service.dart';
import 'package:universal_experience/services/vision_filter_snapshot.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/services/vision_filter_store.dart';

import 'support/vision_filter_metadata_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installVisionFilterMetadataFixture);
  tearDown(() {
    resetVisionFilterMetadataProviders();
    // 強度の記憶も空に戻す（clear() は選択しか解除しない）。
    visionFilterState.restore(const VisionFilterSnapshot());
    imageSourceState.resetToRecommended(kDefaultSampleId);
  });

  /// 新しい store で起動する（テスト後に購読と保留書き込みを片付ける）。
  Future<VisionFilterStore> launch() async {
    final store = VisionFilterStore();
    addTearDown(store.dispose);
    await buildRootApp(
      initBridge: () async => true,
      settings: SettingsService(),
      store: store,
    );
    return store;
  }

  test('seedInitialLayers: deuteranomaly の別名つき 1 層、強度は記憶へ書かず 0.6 を導出する', () {
    final state = VisionFilterState()..seedInitialLayers();

    expect(state.layers, hasLength(1));
    expect(state.selectedId, 'deuteranopia');
    expect(state.focusedVariantId, 'deuteranomaly');
    expect(state.strength, kAnomalyDefaultSeverity);
    expect(state.strengthForKey('deuteranomaly'), isNull);
    expect(state.selectedPresetId, isNull);
  });

  test('初回起動: 何も保存が無ければ deuteranomaly・強度 0.6 の層で始まり、推奨サンプルに合わせる（#78）',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = VisionFilterStore();
    addTearDown(store.dispose);

    final result = await buildRootApp(
        initBridge: () async => true, settings: SettingsService(), store: store);

    expect(result.bridgeReady, isTrue);
    expect(visionFilterState.layers, hasLength(1));
    expect(visionFilterState.selectedId, 'deuteranopia');
    expect(visionFilterState.focusedVariantId, 'deuteranomaly');
    expect(visionFilterState.strength, kAnomalyDefaultSeverity,
        reason: 'deuteranomaly の推奨強度（#78 の「推奨強度で選んだ状態」）');

    final recommendedSample = recommendedSampleIdForFilter('deuteranopia');
    expect(imageSourceState.selectedSampleId, recommendedSample);
    expect(imageSourceState.isUsingUserImage, isFalse);
    expect(imageSourceState.isFollowingRecommended, isTrue);
  });

  test('初回起動: 旧キーが無ければ移行は何も書かず、強度の記憶も空のまま', () async {
    SharedPreferences.setMockInitialValues({});

    await launch();

    expect(visionFilterState.selectedId, 'deuteranopia');
    expect(visionFilterState.focusedVariantId, 'deuteranomaly');
    expect(visionFilterState.strengthForKey('deuteranomaly'), isNull,
        reason: '推奨強度は記憶へ書かず、読むときに導出する');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(VisionFilterStore.keySnapshot), isFalse,
        reason: '旧キーが無ければ移行は保存に触れない');
  });

  test('2回目以降: 保存済みの v2（何も選ばず終了）は初回起動の層で上書きしない（#78）', () async {
    // 「何も選ばずに終了した」状態（層なし）の v2 を保存しておく。
    final saved = VisionFilterState()..clear();
    SharedPreferences.setMockInitialValues({
      VisionFilterStore.keySnapshot: jsonEncode(saved.snapshot().toJson()),
    });

    await launch();

    expect(visionFilterState.layers, isEmpty);
    expect(visionFilterState.selectedId, isNull);
  });

  test('2回目以降: 旧 settings.filterType が none（明示的な Normal vision）なら未選択で始まる（#78）',
      () async {
    SharedPreferences.setMockInitialValues({
      VisionFilterStore.keyLegacyFilterType: 'none',
    });

    await launch();

    expect(visionFilterState.layers, isEmpty);
    expect(visionFilterState.selectedId, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(VisionFilterStore.keyLegacyFilterType), isFalse,
        reason: '取り込み後に旧キーは消える');
  });

  test('2回目以降: 以前選んでいた色覚をそのまま復元する（#78 は初回のみのシード）', () async {
    final saved = VisionFilterState()..replaceWith('protanopia');
    SharedPreferences.setMockInitialValues({
      VisionFilterStore.keySnapshot: jsonEncode(saved.snapshot().toJson()),
    });

    await launch();

    expect(visionFilterState.selectedId, 'protanopia');
    expect(visionFilterState.focusedVariantId, isNull);
    expect(visionFilterState.strength, 1.0);
    expect(
      imageSourceState.selectedSampleId,
      recommendedSampleIdForFilter('protanopia'),
    );
  });

  // #117/#124: 初回起動でも、旧 settings.intensityByType があれば移行が初回起動の層
  // （deuteranomaly）に旧強度を重ねる。シードと食い違わない。
  group('初回起動と旧 settings.intensityByType の移行（#117）', () {
    test('旧強度がある初回起動: deuteranomaly の層と旧強度で始まり、v2 で保存される', () async {
      SharedPreferences.setMockInitialValues({
        VisionFilterStore.keyIntensityByType:
            jsonEncode({'deuteranomaly': 0.35, 'protanopia': 0.8}),
      });

      await launch();

      expect(visionFilterState.selectedId, 'deuteranopia');
      expect(visionFilterState.focusedVariantId, 'deuteranomaly');
      expect(visionFilterState.strength, 0.35,
          reason: '推奨強度 0.6 ではなく、旧 per-type 強度が記憶として効く');
      expect(visionFilterState.strengthForKey('protanopia'), 0.8);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(VisionFilterStore.keyIntensityByType), isFalse);
      final saved = jsonDecode(prefs.getString(VisionFilterStore.keySnapshot)!)
          as Map<String, Object?>;
      expect(saved['version'], 2);
      final layer = (saved['layers'] as List).single as Map;
      expect(layer['id'], 'deuteranopia');
      expect(layer['variantId'], 'deuteranomaly');
      expect(layer.keys.toSet(), {'id', 'params', 'variantId'},
          reason: '層は id・params・variantId だけを書く');
    });
  });
}
