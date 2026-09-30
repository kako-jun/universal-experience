import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

/// `/`（アプリ内ショートカット、#63）: 統合フィルタ一覧の検索欄
/// （`FilterBrowser`、#72）にフォーカスを移す。
class FocusFilterSearchIntent extends Intent {
  const FocusFilterSearchIntent();
}

/// ↑↓（#63, #120）: 統合フィルタ一覧（`FilterBrowser`、#72）の今見えている行の間で、
/// フォーカスを順送り/逆送りする。**選択（層の足し引き）は変えない**: 足し引きは行の
/// Space/Enter。
class CycleFilterIntent extends Intent {
  const CycleFilterIntent({required this.forward});
  final bool forward;
}

/// ←→（#63, #120）: 調整中の層（`VisionFilterState.focusedId`）の強度を
/// [kKeyboardStrengthStep] 刻みで動かす。
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

/// Cmd+V（macOS）/ Ctrl+V（それ以外）（#97）: クリップボードの画像をプレビューの
/// 原画として貼り付ける。テキスト入力欄にフォーカスがある間は奪わない
/// （入力欄自身の貼り付けが優先。[isFocusOnTextInput] 参照）。
class PasteImageIntent extends Intent {
  const PasteImageIntent();
}

/// 貼り付けのキー割り当て（#97）。macOS は Cmd+V、それ以外は Ctrl+V。
/// プラットフォームで変わるため `const` の `Shortcuts` マップには入れられず、
/// 呼び出し側（`home_screen.dart`）が実行時に足す。キーを押しっぱなしにした
/// ときのリピートは無視する（`includeRepeats: false`）。
SingleActivator pasteShortcutActivator() =>
    defaultTargetPlatform == TargetPlatform.macOS
        ? const SingleActivator(
            LogicalKeyboardKey.keyV,
            meta: true,
            includeRepeats: false,
          )
        : const SingleActivator(
            LogicalKeyboardKey.keyV,
            control: true,
            includeRepeats: false,
          );

/// 貼り付けボタンのツールチップに出すキー表記（[pasteShortcutActivator] と対）。
/// macOS は「⌘V」、それ以外は「Ctrl+V」。キーの記号なのでロケールで変わらず、
/// ARB には置かない。
String pasteShortcutLabel() =>
    defaultTargetPlatform == TargetPlatform.macOS ? '⌘V' : 'Ctrl+V';

/// フォーカス中のウィジェットが「テキスト入力・ボタン・スイッチ等」のとき、
/// アプリ内ショートカット（`/`・↑↓・←→）を奪うべきでないかを判定する
/// (#63)。`ReleaseClickThroughIntent`（Esc）はこのガードの対象外
/// — クリックスルーからの復帰は常に効く必要があるため。
bool isFocusOnInteractiveControl() => _focusHasAncestor(
      (widget) =>
          widget is EditableText ||
          widget is ButtonStyleButton ||
          widget is IconButton ||
          widget is Switch ||
          widget is SwitchListTile ||
          widget is Checkbox ||
          widget is Radio ||
          widget is Slider ||
          widget is SegmentedButton ||
          widget is RawChip ||
          widget is InkResponse,
    );

/// フォーカス中のウィジェットが**テキスト入力**（[EditableText]）かどうか
/// （#97）。[PasteImageIntent]（Cmd/Ctrl+V）専用のガード。
///
/// [isFocusOnInteractiveControl] よりわざと狭い: `/`・↑↓・←→ はボタンや
/// スライダー自身も使うキーだが、Cmd/Ctrl+V はテキスト入力以外に固有の意味を
/// 持たない。貼り付けボタンを押した直後（フォーカスがボタンに残る）でも
/// キーボードの貼り付けが効くよう、ボタン等では奪う側に回る。
bool isFocusOnTextInput() =>
    _focusHasAncestor((widget) => widget is EditableText);

bool _focusHasAncestor(bool Function(Widget widget) test) {
  final focusedContext = FocusManager.instance.primaryFocus?.context;
  if (focusedContext == null) return false;
  var found = false;
  focusedContext.visitAncestorElements((element) {
    if (test(element.widget)) {
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

/// [isFocusOnTextInput] が true の間は無効化される [CallbackAction]（#97）。
/// [PasteImageIntent] 用。無効の間はキーイベントを消費しないので、入力欄自身の
/// 貼り付け（`DefaultTextEditingShortcuts`）がそのまま働く。
class TextInputAwareCallbackAction<T extends Intent> extends CallbackAction<T> {
  TextInputAwareCallbackAction({required super.onInvoke});

  @override
  bool isEnabled(T intent) => !isFocusOnTextInput();
}
