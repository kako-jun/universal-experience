// 色覚 7 種（-opia 4 + -omaly 3）のキー（カタログ id または別名 id）でフィルタを
// 選ぶテスト用ヘルパ（#124）。`VisionFilterState` が唯一の正本なので、本番の
// 入口（[VisionFilterState.replaceWith]）にカタログ id と別名 id を解いて渡すだけ。

import 'package:universal_experience/models/vision_filter_catalog.dart';
import 'package:universal_experience/services/vision_filter_state.dart';

/// [key]（`protanopia` / `protanomaly` など）を単一選択する（他の層は置き換える）。
/// 別名（-omaly）は対応する -opia のカタログ id + `variantId` で入る。
void selectColorVisionKey(VisionFilterState state, String key) {
  final target = resolveVisionKey(key);
  if (target == null) {
    throw ArgumentError.value(key, 'key', 'unknown vision filter key');
  }
  state.replaceWith(target.id, variantId: target.variantId);
}
