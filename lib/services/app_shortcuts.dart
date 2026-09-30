import 'package:flutter/material.dart';

/// `/`（アプリ内ショートカット、#63）: 統合フィルタ一覧の検索欄
/// （`FilterBrowser`、#72）にフォーカスを移す。
class FocusFilterSearchIntent extends Intent {
  const FocusFilterSearchIntent();
}

/// ↑↓（#63）: 統合フィルタ一覧（`FilterBrowser`、#72）の今見えている行を
/// 順送り/逆送りして選択する。
class CycleFilterIntent extends Intent {
  const CycleFilterIntent({required this.forward});
  final bool forward;
}

/// ←→（#63）: 選択中フィルタの強度を [kKeyboardStrengthStep] 刻みで動かす。
class AdjustStrengthIntent extends Intent {
  const AdjustStrengthIntent({required this.delta});
  final double delta;
}

/// Esc（#63）: クリックスルーが ON のとき、OS/プラグインに依存しないアプリ内の
/// 復帰経路としてこれを解除する。[isFocusOnInteractiveControl] によるガード
/// の対象外（復帰用ショートカットは常に効く必要があるため）。
class ReleaseClickThroughIntent extends Intent {
  const ReleaseClickThroughIntent();
}

/// フォーカス中のウィジェットが「テキスト入力・ボタン・スイッチ等」のとき、
/// アプリ内ショートカット（`/`・↑↓・←→）を奪うべきでないかを判定する
/// (#63)。`ReleaseClickThroughIntent`（Esc）はこのガードの対象外
/// — クリックスルーからの復帰は常に効く必要があるため。
bool isFocusOnInteractiveControl() {
  final focusedContext = FocusManager.instance.primaryFocus?.context;
  if (focusedContext == null) return false;
  var found = false;
  focusedContext.visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is EditableText ||
        widget is ButtonStyleButton ||
        widget is IconButton ||
        widget is Switch ||
        widget is SwitchListTile ||
        widget is Checkbox ||
        widget is Radio ||
        widget is Slider ||
        widget is SegmentedButton ||
        widget is RawChip ||
        widget is InkResponse) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

/// [isFocusOnInteractiveControl] が true の間は無効化される [CallbackAction]
/// (#63)。`/`・↑↓・←→ の 3 アクションで使う。
class InteractiveFocusAwareCallbackAction<T extends Intent>
    extends CallbackAction<T> {
  InteractiveFocusAwareCallbackAction({required super.onInvoke});

  @override
  bool isEnabled(T intent) => !isFocusOnInteractiveControl();
}
