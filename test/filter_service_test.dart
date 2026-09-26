import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/services/filter_service.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';

/// FilterService の選択状態モデルのテスト。
///
/// #13 で plugin/simulator を撤去し、FilterService は「どのフィルタを・どの強度で
/// 選んでいるか」だけを保持する純粋な状態モデルになった。ここではその選択状態と
/// ColorVisionType → sensus VisionFilter マッピングを検証する（GPU 描画は
/// protanopia_golden_test.dart の担当）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 一部のテストは applyFilter(intensity:)/setIntensity 経由でデバウンス永続化
  // （SharedPreferences 書き込み）を予約する。実行時間を気にしないテストでも
  // その書き込みが（プラグイン未モックの）MissingPluginException で失敗しないよう、
  // ファイル全体でモックしておく。
  SharedPreferences.setMockInitialValues({});

  group('FilterService 選択状態', () {
    test('初期状態は none / 非アクティブ。intensity は none の recommendedStrength（0.0）', () {
      final service = FilterService();
      expect(service.currentFilter, ColorVisionType.none);
      expect(service.intensity, 0.0);
      expect(service.isActive, isFalse);
      expect(service.sensusFilter, isNull);
    });

    test('applyFilter で currentFilter / isActive が変わり notify される', () {
      final service = FilterService();
      var notified = 0;
      service.addListener(() => notified++);

      service.applyFilter(ColorVisionType.deuteranopia);

      expect(service.currentFilter, ColorVisionType.deuteranopia);
      expect(service.isActive, isTrue);
      expect(notified, 1);
    });

    test('none を選ぶと isActive が false に戻る', () {
      final service = FilterService();
      service.applyFilter(ColorVisionType.protanopia);
      expect(service.isActive, isTrue);

      service.applyFilter(ColorVisionType.none);
      expect(service.currentFilter, ColorVisionType.none);
      expect(service.isActive, isFalse);
      expect(service.sensusFilter, isNull);
    });

    test('deactivate で none に戻る', () {
      final service = FilterService();
      service.applyFilter(ColorVisionType.tritanopia);
      service.deactivate();
      expect(service.currentFilter, ColorVisionType.none);
      expect(service.isActive, isFalse);
    });

    test('applyFilter の intensity は 0..1 に clamp される', () {
      final service = FilterService();
      service.applyFilter(ColorVisionType.protanopia, intensity: 1.7);
      expect(service.intensity, 1.0);
      service.applyFilter(ColorVisionType.protanopia, intensity: -0.5);
      expect(service.intensity, 0.0);
    });

    test('setIntensity は 0..1 に clamp し notify する', () {
      final service = FilterService();
      var notified = 0;
      service.addListener(() => notified++);

      service.setIntensity(0.5);
      expect(service.intensity, 0.5);
      service.setIntensity(2.0);
      expect(service.intensity, 1.0);
      service.setIntensity(-1.0);
      expect(service.intensity, 0.0);
      expect(notified, 3);
    });
  });

  group('sensusFilter マッピング', () {
    test('none は null', () {
      final service = FilterService()..applyFilter(ColorVisionType.none);
      expect(service.sensusFilter, isNull);
    });

    test('-opia は対応する VisionFilter へマップ', () {
      final cases = <ColorVisionType, VisionFilter>{
        ColorVisionType.protanopia: const VisionFilter.protanopia(),
        ColorVisionType.deuteranopia: const VisionFilter.deuteranopia(),
        ColorVisionType.tritanopia: const VisionFilter.tritanopia(),
        ColorVisionType.achromatopsia: const VisionFilter.achromatopsia(),
      };
      cases.forEach((type, expected) {
        final service = FilterService()..applyFilter(type);
        expect(service.sensusFilter, expected, reason: '$type');
      });
    });

    test('-anomaly は base の -opia へマップ（強度 < 1 相当）', () {
      final cases = <ColorVisionType, VisionFilter>{
        ColorVisionType.protanomaly: const VisionFilter.protanopia(),
        ColorVisionType.deuteranomaly: const VisionFilter.deuteranopia(),
        ColorVisionType.tritanomaly: const VisionFilter.tritanopia(),
      };
      cases.forEach((type, expected) {
        final service = FilterService()..applyFilter(type);
        expect(service.sensusFilter, expected, reason: '$type');
      });
    });

    test('achromatopsia 適用で isActive=true / sensusFilter=achromatopsia', () {
      final service = FilterService()
        ..applyFilter(ColorVisionType.achromatopsia);
      expect(service.isActive, isTrue);
      expect(service.currentFilter, ColorVisionType.achromatopsia);
      expect(service.sensusFilter, const VisionFilter.achromatopsia());
    });

    test('anomaly 型適用で intensity が渡した値のまま state に保持される', () {
      final service = FilterService()
        ..applyFilter(ColorVisionType.deuteranomaly, intensity: 0.6);
      expect(service.currentFilter, ColorVisionType.deuteranomaly);
      expect(service.intensity, 0.6);
      // anomaly は対応する -opia と同一 VisionFilter にマップされる契約
      expect(service.sensusFilter, const VisionFilter.deuteranopia());
    });

    test('anomalyDefaultSeverity は旧 simulator の severity 0.6 を保持する', () {
      final service = FilterService();
      expect(service.anomalyDefaultSeverity, 0.6);
    });
  });

  group('recommendedStrength / kAnomalyDefaultSeverity', () {
    test('kAnomalyDefaultSeverity は 0.6', () {
      expect(kAnomalyDefaultSeverity, 0.6);
    });

    test('anomaly 系は kAnomalyDefaultSeverity を返す', () {
      expect(
        recommendedStrength(ColorVisionType.protanomaly),
        kAnomalyDefaultSeverity,
      );
      expect(
        recommendedStrength(ColorVisionType.deuteranomaly),
        kAnomalyDefaultSeverity,
      );
      expect(
        recommendedStrength(ColorVisionType.tritanomaly),
        kAnomalyDefaultSeverity,
      );
    });

    test('opia 系および achromatopsia は 1.0 を返す', () {
      expect(recommendedStrength(ColorVisionType.protanopia), 1.0);
      expect(recommendedStrength(ColorVisionType.deuteranopia), 1.0);
      expect(recommendedStrength(ColorVisionType.tritanopia), 1.0);
      expect(recommendedStrength(ColorVisionType.achromatopsia), 1.0);
    });

    test('none は 0.0 を返す', () {
      expect(recommendedStrength(ColorVisionType.none), 0.0);
    });

    test('recommendedStrengthForCurrent は選択中タイプに連動する', () {
      final service = FilterService()..applyFilter(ColorVisionType.protanomaly);
      expect(service.recommendedStrengthForCurrent, kAnomalyDefaultSeverity);
      service.applyFilter(ColorVisionType.protanopia);
      expect(service.recommendedStrengthForCurrent, 1.0);
    });
  });

  group('強度はタイプごとに記憶する（#57）', () {
    test('intensity: を渡さない applyFilter は初めて選ぶタイプで recommendedStrength になる', () {
      final service = FilterService();
      service.applyFilter(ColorVisionType.protanomaly);
      expect(service.intensity, kAnomalyDefaultSeverity);
      service.applyFilter(ColorVisionType.protanopia);
      expect(service.intensity, 1.0);
    });

    test('protanomaly と protanopia は既定強度が異なる（同じ見た目にならない）', () {
      final service = FilterService();
      service.applyFilter(ColorVisionType.protanomaly);
      final protanomalyIntensity = service.intensity;
      service.applyFilter(ColorVisionType.protanopia);
      final protanopiaIntensity = service.intensity;
      expect(protanomalyIntensity, isNot(equals(protanopiaIntensity)));
      expect(protanomalyIntensity, kAnomalyDefaultSeverity);
      expect(protanopiaIntensity, 1.0);
    });

    test('タイプを切り替えても、切替前のタイプの強度は変わらず保持される', () {
      final service = FilterService();
      service.applyFilter(ColorVisionType.protanopia);
      service.setIntensity(0.3);

      service.applyFilter(ColorVisionType.deuteranopia);
      service.setIntensity(0.9);

      // deuteranopia を選んでいる間に protanopia へ戻っても、0.3 のまま。
      service.applyFilter(ColorVisionType.protanopia);
      expect(service.intensity, 0.3);

      service.applyFilter(ColorVisionType.deuteranopia);
      expect(service.intensity, 0.9);
    });

    test('applyFilter に intensity: を渡すと、そのタイプの記憶を明示的に上書きする', () {
      final service = FilterService();
      service.applyFilter(ColorVisionType.protanopia, intensity: 0.2);
      service.applyFilter(ColorVisionType.deuteranopia);
      service.applyFilter(ColorVisionType.protanopia);
      expect(service.intensity, 0.2);
    });

    test('フィルタを切り替えても選択中でない他タイプの記憶は変わらない', () {
      final service = FilterService();
      service.applyFilter(ColorVisionType.protanomaly);
      service.setIntensity(0.4);
      // 選択を protanopia に切り替える（intensity: を渡さない = 記憶を壊さない）。
      service.applyFilter(ColorVisionType.protanopia);
      service.applyFilter(ColorVisionType.protanomaly);
      expect(service.intensity, 0.4);
    });
  });

  group('永続化（#57）', () {
    test('setIntensity はデバウンス後に per-type で保存され、別インスタンスの load で復元される', () async {
      SharedPreferences.setMockInitialValues({});
      final a = FilterService();
      await a.load();
      a.applyFilter(ColorVisionType.protanopia);
      a.setIntensity(0.3);
      a.applyFilter(ColorVisionType.deuteranomaly);
      a.setIntensity(0.9);
      await a.debugFlushPersist();

      final b = FilterService();
      await b.load();
      b.applyFilter(ColorVisionType.protanopia);
      expect(b.intensity, 0.3);
      b.applyFilter(ColorVisionType.deuteranomaly);
      expect(b.intensity, 0.9);
    });

    test('setIntensity の連続呼び出しはデバウンスされ、直近の値だけが保存される', () async {
      SharedPreferences.setMockInitialValues({});
      final a = FilterService(debounce: const Duration(milliseconds: 30));
      await a.load();
      a.applyFilter(ColorVisionType.protanopia);
      a.setIntensity(0.1);
      a.setIntensity(0.2);
      a.setIntensity(0.3);

      // デバウンス窓の途中ではまだ書き込まれていない。
      final prefsBefore = await SharedPreferences.getInstance();
      expect(prefsBefore.getString(FilterService.keyIntensityByType), isNull);

      await Future<void>.delayed(const Duration(milliseconds: 60));

      final b = FilterService();
      await b.load();
      b.applyFilter(ColorVisionType.protanopia);
      expect(b.intensity, 0.3);
    });

    test('旧単一 intensity キー（settings.intensity）は、load 時に指定したタイプへ一度だけ移行される',
        () async {
      SharedPreferences.setMockInitialValues({
        FilterService.legacyIntensityKey: 0.42,
      });
      final service = FilterService();
      await service.load(migrateLegacyIntensityFor: ColorVisionType.protanopia);

      service.applyFilter(ColorVisionType.protanopia);
      expect(service.intensity, 0.42);

      // 移行先ではない他タイプは影響を受けない（recommendedStrength のまま）。
      service.applyFilter(ColorVisionType.deuteranopia);
      expect(service.intensity, 1.0);
    });

    test('per-type の保存が既にあれば旧単一キーは無視される', () async {
      SharedPreferences.setMockInitialValues({
        FilterService.keyIntensityByType: '{"protanopia":0.55}',
        FilterService.legacyIntensityKey: 0.1,
      });
      final service = FilterService();
      await service.load(migrateLegacyIntensityFor: ColorVisionType.protanopia);

      service.applyFilter(ColorVisionType.protanopia);
      expect(service.intensity, 0.55);
    });

    test('範囲外の保存値は 0..1 に clamp して復元する', () async {
      SharedPreferences.setMockInitialValues({
        FilterService.keyIntensityByType:
            '{"protanopia":5.0,"tritanopia":-3.0}',
      });
      final service = FilterService();
      await service.load();

      service.applyFilter(ColorVisionType.protanopia);
      expect(service.intensity, 1.0);
      service.applyFilter(ColorVisionType.tritanopia);
      expect(service.intensity, 0.0);
    });
  });
}
