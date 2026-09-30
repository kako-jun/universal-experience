// main.dart の buildRootApp() が担う初回起動シード（#78）のテスト。
//
// - 初回起動（settings.filterType が一度も永続化されていない）は
//   deuteranomaly を推奨強度で選択し、即座に永続化する。
// - 2 回目以降は復元済みの選択（明示的な none も含む）をそのまま使い、
//   deuteranomaly へは上書きしない。
// - 初回のサンプル画像も、シードしたフィルタの推奨サンプルに合わせる。
//
// buildRootApp はアプリ全体で 1 つだけの共有トップレベル singleton
// （main.dart の filterService/visionFilterState/imageSourceState）を直接
// 動かすため、各テストの後にニュートラルな状態へ明示的にリセットする
// （このファイル内の他テスト・同一プロセスで動く他のテストへ影響を残さない
// ため）。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/main.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/models/sample_catalog.dart';
import 'package:universal_experience/services/filter_service.dart'
    show kAnomalyDefaultSeverity;
import 'package:universal_experience/services/settings_service.dart';
import 'package:universal_experience/services/vision_filter_snapshot.dart';
import 'package:universal_experience/services/vision_filter_store.dart';

import 'support/vision_filter_metadata_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installVisionFilterMetadataFixture);
  tearDown(() {
    resetVisionFilterMetadataProviders();
    filterService.deactivate();
    // 強度の記憶も空に戻す（clear() は選択しか解除しない）。
    visionFilterState.restore(const VisionFilterSnapshot());
    imageSourceState.resetToRecommended(kDefaultSampleId);
  });

  test('初回起動: deuteranomaly を推奨強度で選択し、推奨サンプルに合わせる（#78）', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();

    final result =
        await buildRootApp(initBridge: () async => true, settings: settings);

    expect(result.bridgeReady, isTrue);
    expect(filterService.currentFilter, ColorVisionType.deuteranomaly);
    expect(filterService.intensity, kAnomalyDefaultSeverity,
        reason: 'deuteranomaly の推奨強度（#78 の「推奨強度で選んだ状態」）');
    expect(visionFilterState.isColorQuickSelection, isTrue);
    expect(visionFilterState.colorVisionType, ColorVisionType.deuteranomaly);

    expect(settings.filterType, ColorVisionType.deuteranomaly,
        reason: '初回シードは即座に永続化される');
    expect(settings.isFirstRun, isFalse,
        reason: 'シード直後は isFirstRun でなくなる（二重シード防止）');

    final recommendedSample = recommendedSampleIdForFilter('deuteranopia');
    expect(imageSourceState.selectedSampleId, recommendedSample);
    expect(imageSourceState.isUsingUserImage, isFalse);
    expect(imageSourceState.isFollowingRecommended, isTrue);
  });

  test('2回目以降: 明示的な "Normal vision"（none）は上書きしない（#78）', () async {
    SharedPreferences.setMockInitialValues({
      SettingsService.keyFilterType: ColorVisionType.none.name,
    });
    final settings = SettingsService();

    await buildRootApp(initBridge: () async => true, settings: settings);

    expect(filterService.currentFilter, ColorVisionType.none);
    expect(visionFilterState.selectedId, isNull);
    expect(settings.isFirstRun, isFalse);
  });

  test('2回目以降: 以前選んでいたタイプをそのまま復元する（#78 は初回のみのシード）', () async {
    SharedPreferences.setMockInitialValues({
      SettingsService.keyFilterType: ColorVisionType.protanopia.name,
    });
    final settings = SettingsService();

    await buildRootApp(initBridge: () async => true, settings: settings);

    expect(filterService.currentFilter, ColorVisionType.protanopia);
    expect(
      imageSourceState.selectedSampleId,
      recommendedSampleIdForFilter('protanopia'),
    );
  });

  // #117: main.dart の seedType（初回起動は deuteranomaly、それ以外は settings の
  // filterType）は、旧強度の移行（migrateLegacyStrengths）と色覚シードの両方に
  // 使われる。初回起動でも移行が seedType の quick 層を書き、シードと食い違わない。
  group('初回起動と旧 settings.intensityByType の移行（#117）', () {
    test('旧強度がある初回起動: seedType（deuteranomaly）の quick 層と旧強度で始まり、v2 で保存される',
        () async {
      SharedPreferences.setMockInitialValues({
        VisionFilterStore.keyIntensityByType:
            jsonEncode({'deuteranomaly': 0.35, 'protanopia': 0.8}),
      });
      final settings = SettingsService();
      final store = VisionFilterStore();
      addTearDown(store.dispose);

      await buildRootApp(
          initBridge: () async => true, settings: settings, store: store);

      expect(settings.isFirstRun, isFalse);
      expect(filterService.currentFilter, ColorVisionType.deuteranomaly);
      expect(filterService.intensity, 0.35,
          reason: '推奨強度 0.6 ではなく、旧 per-type 強度が記憶として効く');
      expect(visionFilterState.colorVisionType, ColorVisionType.deuteranomaly);
      expect(visionFilterState.strengthForKey('protanopia'), 0.8);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(VisionFilterStore.keyIntensityByType), isFalse);
      final saved = jsonDecode(prefs.getString(VisionFilterStore.keySnapshot)!)
          as Map<String, Object?>;
      expect(saved['version'], 2);
      final layer = (saved['layers'] as List).single as Map;
      expect(layer['id'], 'deuteranopia');
      expect(layer['variantId'], 'deuteranomaly');
      expect(layer['origin'], 'quick');
    });

    test('旧強度が無い初回起動: 移行は何も書かず、推奨強度の deuteranomaly で始まる', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      final store = VisionFilterStore();
      addTearDown(store.dispose);

      await buildRootApp(
          initBridge: () async => true, settings: settings, store: store);

      expect(filterService.currentFilter, ColorVisionType.deuteranomaly);
      expect(filterService.intensity, kAnomalyDefaultSeverity);
      expect(visionFilterState.strengthForKey('deuteranomaly'), isNull,
          reason: '推奨強度は記憶へ書かず、読むときに導出する');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(VisionFilterStore.keySnapshot), isFalse,
          reason: '旧キーが無ければ移行は保存に触れない');
    });
  });
}
