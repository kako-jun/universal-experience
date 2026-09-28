import 'package:flutter/widgets.dart' show Intent;

/// `/`（アプリ内ショートカット、#63）: advanced カタログ（[kVisionFilterCatalog]）
/// にフォーカスを移す。検索欄は現状存在しないため、常にこの動作になる
/// （Issue の「検索欄が無ければ advanced のカタログに」を字義どおり実装）。
class FocusFilterSearchIntent extends Intent {
  const FocusFilterSearchIntent();
}

/// ↑↓（#63）: advanced カタログを順送り/逆送りする。
class CycleFilterIntent extends Intent {
  const CycleFilterIntent({required this.forward});
  final bool forward;
}

/// ←→（#63）: 選択中フィルタの強度を [kKeyboardStrengthStep] 刻みで動かす。
class AdjustStrengthIntent extends Intent {
  const AdjustStrengthIntent({required this.delta});
  final double delta;
}
