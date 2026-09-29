// 実ブリッジ smoke test（#76）。
//
// widget/unit test（test/filter_param_panel_test.dart 等）は
// `visionFilterUrgencyProvider` 等をフィクスチャに差し替えて UI の配線だけを
// 検証しているため、「UI に出す urgency が実際に sensus ブリッジの値と一致する
// こと」自体は検知できない。本テストは実ネイティブライブラリをロードし、
// カタログ全 30 種について ue が公開する urgency/urgency_escalation/
// recommended_strength が sensus-core 0.6.1 の値をそのまま透過していることを
// 確認する。ue 側は緊急度・推奨強度を独自に持たない（#76）ため、この透過が
// 崩れていない＝「UI の値は常に sensus と一致する」が保証される。
//
// 実行: `flutter test integration_test/vision_filter_urgency_parity_test.dart -d macos`
// 他の integration_test ファイルと同様、デスクトップでは 1 回の `flutter test
// integration_test` 呼び出しに複数ファイルを渡すと2番目以降のアプリ起動が失敗する
// 既知の制約があるため、CI でも個別コマンドとして実行する。

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:universal_experience/models/vision_filter_catalog.dart';
import 'package:universal_experience/services/native_bridge_service.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final ok = await initNativeBridge();
    if (!ok) {
      fail('initNativeBridge() failed; check RustLib bundling (#55)');
    }
  });

  group('vision_filter_urgency 系メタデータ: kVisionFilterCatalog 全 30 種', () {
    for (final entry in kVisionFilterCatalog) {
      testWidgets('${entry.id}: 実ブリッジで例外なく取得でき、recommended_strength は (0.0, 1.0]',
          (tester) async {
        final state = VisionFilterState()..select(entry.id);
        final filter = state.build();
        expect(filter, isNotNull, reason: '${entry.id} が build() できなかった');

        final urgency = visionFilterUrgency(filter: filter!);
        final escalation = visionFilterUrgencyEscalation(filter: filter);
        final recommended = visionFilterRecommendedStrength(filter: filter);

        expect(urgency, isNotNull);
        expect(escalation, isNotNull);
        expect(recommended, greaterThan(0.0), reason: entry.id);
        expect(recommended, lessThanOrEqualTo(1.0), reason: entry.id);
      });
    }

    // rust 側の `vision_filter_urgency_escalation_nonempty_count_matches_sensus`
    // （rust/src/api/sensus_bridge.rs）と同じ不変条件を、Dart から見た実ブリッジ
    // 経由でも確認する（ブリッジ層で取りこぼす／余計に足すと壊れる）。
    testWidgets('escalation が非空なのはちょうど 3 フィルタ（photophobia/bppv_rotation/dry_eye）',
        (tester) async {
      final nonEmptyIds = <String>[];
      for (final entry in kVisionFilterCatalog) {
        final state = VisionFilterState()..select(entry.id);
        final filter = state.build()!;
        if (visionFilterUrgencyEscalation(filter: filter).isNotEmpty) {
          nonEmptyIds.add(entry.id);
        }
      }
      expect(nonEmptyIds.toSet(),
          {'photophobia', 'bppv_rotation', 'dry_eye'});
    });
  });

  group('#76 の食い違い回帰: BPPV はプリセット・advanced のどちらでも urgency=none', () {
    testWidgets('Experience(bppv).urgency と Filter(bppv_rotation).urgency が一致する',
        (tester) async {
      final presetUrgency =
          experiences().firstWhere((e) => e.id == 'bppv').urgency;

      final state = VisionFilterState()..select('bppv_rotation');
      final advancedUrgency = visionFilterUrgency(filter: state.build()!);

      expect(presetUrgency, Urgency.none);
      expect(advancedUrgency, Urgency.none);
      expect(presetUrgency, advancedUrgency);

      // 典型的には良性だが、反復・重症例では受診喚起の対象になる
      // （urgency_escalation が非空）ことも確認する。
      final escalation =
          visionFilterUrgencyEscalation(filter: state.build()!);
      expect(escalation, isNotEmpty);
      expect(escalation.first.urgency, Urgency.earlyConsultation);
    });
  });

  group('代表フィルタの urgency（sensus-core 0.6.1 の分類との対応、退行検出用）', () {
    testWidgets('色覚・屈折は none、突然の半盲・前庭神経炎は emergency、緑内障は earlyConsultation',
        (tester) async {
      Urgency urgencyOf(String id) {
        final state = VisionFilterState()..select(id);
        return visionFilterUrgency(filter: state.build()!);
      }

      expect(urgencyOf('protanopia'), Urgency.none);
      expect(urgencyOf('myopia'), Urgency.none);
      expect(urgencyOf('glaucoma'), Urgency.earlyConsultation);
      expect(urgencyOf('hemianopia'), Urgency.emergency);
      expect(urgencyOf('vestibular_neuritis'), Urgency.emergency);
      expect(urgencyOf('flickering_stars'), Urgency.emergency);
    });
  });
}
