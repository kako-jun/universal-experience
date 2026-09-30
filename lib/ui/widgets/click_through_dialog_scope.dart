import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:provider/provider.dart';

import '../../services/app_shortcuts.dart';
import '../../services/loupe_window_controller.dart';

/// クリックスルー（#63）を持つアプリのダイアログの中身を包む共有部品。
///
/// クリックスルーの OFF→ON でダイアログを閉じ、ON の間は Esc を
/// [ReleaseClickThroughIntent]（解除）にする。ON になるとクリックが窓を素通りして
/// 「閉じる」を押せず、最初の Esc もダイアログを閉じるだけで解除まで 2 回かかる
/// ため、起動モード（`showWindowModeDialog`）と言語（`showLanguageDialog`）の
/// 両ダイアログが使う。
class ClickThroughDialogScope extends StatefulWidget {
  const ClickThroughDialogScope({super.key, required this.child});

  final Widget child;

  @override
  State<ClickThroughDialogScope> createState() =>
      ClickThroughDialogScopeState();
}

class ClickThroughDialogScopeState extends State<ClickThroughDialogScope> {
  LoupeWindowController? _loupe;
  bool _wasClickThrough = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final loupe = context.read<LoupeWindowController>();
    if (identical(loupe, _loupe)) return;
    _loupe?.removeListener(_onChanged);
    _loupe = loupe;
    _wasClickThrough = loupe.clickThrough;
    loupe.addListener(_onChanged);
  }

  void _onChanged() {
    final on = _loupe?.clickThrough ?? false;
    if (on && !_wasClickThrough && mounted) _closeThisDialog();
    _wasClickThrough = on;
  }

  /// このダイアログのルートだけを閉じる。最上位のルートを無条件に pop すると、
  /// 別のルート（別のダイアログなど）が上に載っているときにそちらを閉じてしまう。
  void _closeThisDialog() {
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    final navigator = Navigator.of(context);
    if (route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
  }

  @override
  void dispose() {
    _loupe?.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): ReleaseClickThroughIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ReleaseClickThroughIntent: ReleaseClickThroughAction(_loupe!),
        },
        // ダイアログの中にフォーカスを置く（キーイベントはフォーカスのある
        // ノードから祖先へ流れるので、上の Shortcuts に届かせるため）。
        child: Focus(autofocus: true, child: widget.child),
      ),
    );
  }
}

/// ON の間だけ有効な Esc の解除アクション。OFF のときは無効になり、Esc は
/// ダイアログの標準の閉じる動作へ流れる。
class ReleaseClickThroughAction extends Action<ReleaseClickThroughIntent> {
  ReleaseClickThroughAction(this._loupe);

  final LoupeWindowController _loupe;

  @override
  bool isEnabled(ReleaseClickThroughIntent intent) => _loupe.clickThrough;

  @override
  Object? invoke(ReleaseClickThroughIntent intent) {
    _loupe.setClickThrough(false);
    return null;
  }
}
