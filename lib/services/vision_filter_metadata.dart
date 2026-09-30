import '../src/rust/api/sensus_bridge.dart';

/// フィルタ単位のメタデータ（urgency 系・recommended_strength・citation・
/// limitations）を取得する経路の供給源（#76 / #77 / #80）。
///
/// sensus-core 0.6.1 が公開した `Filter::urgency()` / `urgency_escalation()` /
/// `recommended_strength()` / `citation()` / `limitations()` を `sensus_bridge.dart` の FRB 関数（
/// [visionFilterUrgency] 等）でそのまま消費する。**この値が唯一の正本**であり、
/// ue 側は緊急度・推奨強度・出典・限界を独自に持たない（#76 の「ue 独自の
/// VisionFilterUrgency を廃止する」方針）。出典と限界（#80）は sensus の英文を
/// そのまま UI に出し、ue 側で言い換え・翻訳・補足をしない。
///
/// FRB の `#[frb(sync)]` 関数は native ライブラリを要求し、`flutter test`
/// （FFI 未ロード）では呼べない（`experiencesProvider` と同じ制約、
/// `experience_presets.dart` の module doc 参照）。そのため呼び出し側
/// （`VisionFilterState` / `FilterParamPanel` / `before_after_view.dart`。
/// いずれもこのファイルの外側にある — `experiencesProvider` 等の
/// `@visibleForTesting` seam は宣言ファイル自身からしか production 利用され
/// ないのに対し、こちらは意図的に複数ファイルから production 利用される
/// 共有の差し替え点なので `@visibleForTesting` は付けない）は、この
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
typedef VisionFilterCitationFn = String? Function(VisionFilter filter);
typedef VisionFilterLimitationsFn = String Function(VisionFilter filter);

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

/// モデル名と出典（DOI 等）の供給源（既定は実ブリッジ、#80）。出典が無い
/// フィルタは null（sensus は「出典のでっち上げはしない」ので、null は
/// 「示せる出典が無い」の意味）。英文のみ。
VisionFilterCitationFn visionFilterCitationProvider =
    (filter) => visionFilterCitation(filter: filter);

/// 「このシミュレーションで表現できないこと」の供給源（既定は実ブリッジ、#80）。
/// 英文 1〜2 文のみ（i18n は消費側の責務とされているが、医学的な文言を ue が
/// 訳すと誤情報になりうるので原文のまま出す）。
VisionFilterLimitationsFn visionFilterLimitationsProvider =
    (filter) => visionFilterLimitations(filter: filter);
