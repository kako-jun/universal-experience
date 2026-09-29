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

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/main.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/models/sample_catalog.dart';
import 'package:universal_experience/services/filter_service.dart'
    show kAnomalyDefaultSeverity;
import 'package:universal_experience/services/settings_service.dart';

import 'support/vision_filter_metadata_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installVisionFilterMetadataFixture);
  tearDown(() {
    resetVisionFilterMetadataProviders();
    filterService.deactivate();
    visionFilterState.clear();
    imageSourceState.resetToRecommended(kDefaultSampleId);
  });

  test('初回起動: deuteranomaly を推奨強度で選択し、推奨サンプルに合わせる（#78）',
      () async {
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

  test('2回目以降: 以前選んでいたタイプをそのまま復元する（#78 は初回のみのシード）',
      () async {
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
}
