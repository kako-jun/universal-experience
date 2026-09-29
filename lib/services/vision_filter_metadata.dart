import '../src/rust/api/sensus_bridge.dart';

/// フィルタ単位のメタデータ（urgency 系・recommended_strength）を取得する経路の
/// 供給源（#76 / #77）。
///
/// sensus-core 0.6.1 が公開した `Filter::urgency()` / `urgency_escalation()` /
/// `recommended_strength()` を `sensus_bridge.dart` の FRB 関数（
/// [visionFilterUrgency] 等）でそのまま消費する。**この値が唯一の正本**であり、
/// ue 側は緊急度・推奨強度を独自に持たない（#76 の「ue 独自の
/// VisionFilterUrgency を廃止する」方針）。
///
/// FRB の `#[frb(sync)]` 関数は native ライブラリを要求し、`flutter test`
/// （FFI 未ロード）では呼べない（`experiencesProvider` と同じ制約、
/// `experience_presets.dart` の module doc 参照）。そのため呼び出し側
/// （`VisionFilterState` / `FilterParamPanel` / `before_after_view.dart`。
/// いずれもこのファイルの外側にある — `experiencesProvider` 等の
/// `@visibleForTesting` seam は宣言ファイル自身からしか production 利用され
/// ないのに対し、こちらは意図的に複数ファイルから production 利用される
/// 共有の差し替え点なので `@visibleForTesting` は付けない）は、この 3 つの
/// provider seam 経由でのみ値を取得し、widget/unit test は
/// `test/support/vision_filter_metadata_fixture.dart` のフィクスチャに差し替える。
/// urgency の「sensus と UI の値が一致すること」自体は、実ブリッジが使える
/// integration test（`integration_test/vision_filter_urgency_parity_test.dart`）
/// で検証する。

typedef VisionFilterUrgencyFn = Urgency Function(VisionFilter filter);
typedef VisionFilterUrgencyEscalationFn = List<UrgencyEscalation> Function(
    VisionFilter filter);
typedef VisionFilterRecommendedStrengthFn = double Function(
    VisionFilter filter);

/// 受診喚起の緊急度の供給源（既定は実ブリッジ）。production はこの既定値の
/// まま使う。差し替えは widget/unit test の fixture 注入用。
VisionFilterUrgencyFn visionFilterUrgencyProvider =
    (filter) => visionFilterUrgency(filter: filter);

/// 条件付きで緊急度が上がる場合の一覧の供給源（既定は実ブリッジ）。
VisionFilterUrgencyEscalationFn visionFilterUrgencyEscalationProvider =
    (filter) => visionFilterUrgencyEscalation(filter: filter);

/// 推奨強度の供給源（既定は実ブリッジ）。[VisionFilterState] が「初めて選んだ
/// フィルタの初期強度」・「推奨値に戻す」の値として使う（#77）。
VisionFilterRecommendedStrengthFn visionFilterRecommendedStrengthProvider =
    (filter) => visionFilterRecommendedStrength(filter: filter);
