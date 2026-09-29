// #76 / #77: VisionFilterState は選択のたびに sensus ブリッジの
// urgency/urgency_escalation/recommended_strength（`lib/services/
// vision_filter_metadata.dart` の provider seam）を呼ぶ。実ブリッジは native
// lib を要求し `flutter test`（FFI 未ロード）では呼べないため
// （`experiencesProvider` と同じ制約）、widget/unit test は既定でこの
// フィクスチャに差し替える。
//
// 既定値は変更前の挙動（strength の初期値 1.0・urgency 表示なし）に揃えて
// あるので、urgency/strength の値そのものを検証しないテストは無変更で通る。
// #76/#77 固有の挙動（urgency 表示・escalation・推奨値シード）を検証する
// テストは、setUp 後にプロバイダを個別に上書きする。

import 'package:universal_experience/services/vision_filter_metadata.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';

/// urgency=none・escalation なし・recommended_strength=1.0 の一律フィクスチャを
/// 適用する。`setUp` で呼ぶ。
void installVisionFilterMetadataFixture() {
  visionFilterUrgencyProvider = (_) => Urgency.none;
  visionFilterUrgencyEscalationProvider = (_) => const [];
  visionFilterRecommendedStrengthProvider = (_) => 1.0;
}

/// production の既定（実ブリッジ）に戻す。`tearDown` で呼ぶ。
void resetVisionFilterMetadataProviders() {
  visionFilterUrgencyProvider = (filter) => visionFilterUrgency(filter: filter);
  visionFilterUrgencyEscalationProvider =
      (filter) => visionFilterUrgencyEscalation(filter: filter);
  visionFilterRecommendedStrengthProvider =
      (filter) => visionFilterRecommendedStrength(filter: filter);
}
