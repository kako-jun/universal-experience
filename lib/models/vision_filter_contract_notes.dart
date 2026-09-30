/// sensus の API 契約上、ユーザーに知らせるべき挙動の定義（#51 → #66）。
///
/// 定義（不変データ）だけを持つ層で、文言は持たない（規律2: 表示文言は
/// `lib/l10n/l10n_extensions.dart` が ARB から引く）。sensus-core 0.6.1 の
/// メタデータ API（urgency / urgency_escalation / recommended_strength）には
/// 「強度の上限付近の注意」を表す項目が無いので、対象フィルタ id と閾値は
/// ここに置き、sensus 側の挙動（下記）の変更に追従する責務は本ファイルが持つ。
library;

/// 強度スライダの上限付近で注意を出す定義。
class StrengthCaution {
  const StrengthCaution({required this.threshold})
      : assert(threshold > 0.0 && threshold < 1.0);

  /// 注意を出し始める強度（0.0..1.0）。スライダにはこの位置に目盛り（印）を
  /// 出し、強度がこの値以上のとき注記を警告の表現に切り替える。
  final double threshold;
}

/// フィルタ id（`kVisionFilterCatalog` の id）→ 上限付近の注意の定義。
///
/// - `tunnel_vision`（#51 注記1）: 可視半径 = (1−strength)×0.5 の線形縮小で、
///   strength=1.0 は**ほぼ全黒**（視野のほぼすべてを失った最も進行した
///   段階を再現する設計）。0.8 のとき可視半径は 0.1。半径は画像の半対角線に対する
///   比なので（sensus-core 0.6.1 の `field.rs` で `max_r` = 半対角線で割っている）、
///   16:9 なら幅の約 1 割の円で、外側 0.05 はぼかしの帯。これより先は
///   「見える部分がほとんど無い」領域になる。sensus の推奨強度は 0.5。
const Map<String, StrengthCaution> kStrengthCautionByFilterId = {
  'tunnel_vision': StrengthCaution(threshold: 0.8),
};
