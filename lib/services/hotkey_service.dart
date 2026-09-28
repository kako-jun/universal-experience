import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'
    show KeyboardKey, LogicalKeyboardKey, PhysicalKeyboardKey;
import 'package:hotkey_manager/hotkey_manager.dart';
import 'dart:io' show Platform;

/// #63 で導入するグローバルホットキー 4 アクション。
enum AppHotkeyAction {
  /// クリックスルーの ON/OFF。
  toggleClickThrough,

  /// 押している間だけ原画を表示 (A/B)。keyUp が届かない環境ではトグル動作にフォールバックする
  /// (HotkeyActions.holdOriginalKeyDown/holdOriginalKeyUp の実装を参照)。
  holdOriginal,

  /// 非常口: 全フィルタ停止 + クリックスルー解除 + 最前面解除 + ウィンドウ表示/前面化。
  emergencyExit,

  /// ルーペ窓の表示/非表示。
  toggleLoupeVisibility,
}

/// [AppHotkeyAction] ごとのハンドラ。[onKeyUp] は holdOriginal だけが使う。
class HotkeyHandlers {
  const HotkeyHandlers({required this.onKeyDown, this.onKeyUp});
  final void Function() onKeyDown;
  final void Function()? onKeyUp;
}

/// hotkey_manager の singleton (`hotKeyManager`) を直接叩かず、テストでフェイクに
/// 差し替えられるようにする薄いゲートウェイ (#63)。実 OS のグローバルホットキー登録は
/// `flutter test` のプラットフォームチャンネルでは動かせないため。
abstract class HotkeyGateway {
  Future<void> register(
    HotKey hotKey, {
    HotKeyHandler? keyDownHandler,
    HotKeyHandler? keyUpHandler,
  });
  Future<void> unregisterAll();
}

class RealHotkeyGateway implements HotkeyGateway {
  const RealHotkeyGateway();
  @override
  Future<void> register(
    HotKey hotKey, {
    HotKeyHandler? keyDownHandler,
    HotKeyHandler? keyUpHandler,
  }) =>
      hotKeyManager.register(
        hotKey,
        keyDownHandler: keyDownHandler,
        keyUpHandler: keyUpHandler,
      );

  @override
  Future<void> unregisterAll() => hotKeyManager.unregisterAll();
}

/// [AppHotkeyAction] ごとの既定キー割り当て (#63)。
/// 主要アプリ（ブラウザ・OS 標準ショートカット等）と衝突しにくいよう、
/// Ctrl+Alt+Shift の 3 修飾を既定にする。
Map<AppHotkeyAction, HotKey> defaultHotkeyBindings() => {
      AppHotkeyAction.toggleClickThrough: HotKey(
        key: LogicalKeyboardKey.keyC, // Click-through
        modifiers: const [
          HotKeyModifier.control,
          HotKeyModifier.alt,
          HotKeyModifier.shift,
        ],
        scope: HotKeyScope.system,
      ),
      AppHotkeyAction.holdOriginal: HotKey(
        key: LogicalKeyboardKey.keyO, // Original
        modifiers: const [
          HotKeyModifier.control,
          HotKeyModifier.alt,
          HotKeyModifier.shift,
        ],
        scope: HotKeyScope.system,
      ),
      AppHotkeyAction.emergencyExit: HotKey(
        key: LogicalKeyboardKey.escape,
        modifiers: const [
          HotKeyModifier.control,
          HotKeyModifier.alt,
          HotKeyModifier.shift,
        ],
        scope: HotKeyScope.system,
      ),
      AppHotkeyAction.toggleLoupeVisibility: HotKey(
        key: LogicalKeyboardKey.keyL, // Loupe
        modifiers: const [
          HotKeyModifier.control,
          HotKeyModifier.alt,
          HotKeyModifier.shift,
        ],
        scope: HotKeyScope.system,
      ),
    };

/// [AppHotkeyAction] の既定キーを人間可読な文字列にする (#63)。
///
/// 「クリックスルーが無効化されているときに、戻り方をヒント表示する」
/// （`WindowModePanel`、`clickThroughDisabledHint` ARB プレースホルダ）用。
/// 実際のキー割当 ([defaultHotkeyBindings]) から導出するので、表示文言と
/// 実際のホットキーがズレない。
String describeHotkey(AppHotkeyAction action) {
  final binding = defaultHotkeyBindings()[action];
  if (binding == null) return '';
  final modifierLabels = {
    HotKeyModifier.control: 'Ctrl',
    HotKeyModifier.alt: 'Alt',
    HotKeyModifier.shift: 'Shift',
    HotKeyModifier.meta: 'Meta',
    HotKeyModifier.capsLock: 'CapsLock',
    HotKeyModifier.fn: 'Fn',
  };
  final parts = <String>[
    for (final m in binding.modifiers ?? const [])
      modifierLabels[m] ?? m.name,
    _keyLabel(binding.key),
  ];
  return parts.join('+');
}

String _keyLabel(KeyboardKey key) {
  if (key == LogicalKeyboardKey.escape) return 'Esc';
  // LogicalKeyboardKey/PhysicalKeyboardKey.debugName for letter keys is e.g.
  // "Key C"; strip the "Key " prefix so the displayed shortcut reads
  // "Ctrl+Alt+Shift+C". `debugName` is only declared on the concrete
  // subclasses, not on the abstract KeyboardKey base, so dispatch by type.
  final String? name = switch (key) {
    LogicalKeyboardKey k => k.debugName,
    PhysicalKeyboardKey k => k.debugName,
    _ => null,
  };
  final resolved = name ?? '?';
  return resolved.startsWith('Key ') ? resolved.substring(4) : resolved;
}

/// UI 表示用のホットキー登録結果サマリ (#63)。main() が [HotkeyService.init] の後に
/// 組み立てて `UniversalExperienceApp` に渡す。`UniversalExperienceApp` 自体は
/// （`TrayService` と同じ理由で。widget_test.dart のコメント参照）`late final` な
/// `HotkeyService` シングルトンを直接参照しない — widget test が main() のデスクトップ
/// 初期化を経由せず `UniversalExperienceApp` を構築できるようにするため。
@immutable
class HotkeyStatus {
  const HotkeyStatus({
    this.registered = const {},
    this.failed = const {},
  });

  final Set<AppHotkeyAction> registered;
  final Set<AppHotkeyAction> failed;

  bool isRegistered(AppHotkeyAction action) => registered.contains(action);
  bool get anyAvailable => registered.isNotEmpty;
}

/// グローバルホットキー登録の副作用層 (#63)。`TrayService` と同じ 2 層構成に倣う:
/// 実処理は [HotkeyActions]（テスト可能な純粋寄りロジック）が持ち、ここは
/// hotkey_manager への登録・失敗のハンドリングだけを担う。
class HotkeyService {
  HotkeyService({HotkeyGateway gateway = const RealHotkeyGateway()})
      : _gateway = gateway;

  final HotkeyGateway _gateway;
  final Set<AppHotkeyAction> _registered = {};
  final Set<AppHotkeyAction> _failed = {};

  /// デスクトップ以外（トレイと同じ判定、tray_service.dart 参照）ではホットキー概念が
  /// 無いため常にスキップする。
  static bool get isSupportedPlatform {
    try {
      return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    } catch (_) {
      return false;
    }
  }

  Set<AppHotkeyAction> get registeredActions => Set.unmodifiable(_registered);
  Set<AppHotkeyAction> get failedActions => Set.unmodifiable(_failed);
  bool isRegistered(AppHotkeyAction action) => _registered.contains(action);

  /// [handlers] に定義されたアクションだけを登録する（未定義のアクションはスキップ）。
  /// 登録失敗（Wayland 等でグローバルホットキーが使えない環境、#63）は個別に catch し、
  /// 他のアクションの登録は続行する。
  Future<void> init(
    Map<AppHotkeyAction, HotkeyHandlers> handlers, {
    Map<AppHotkeyAction, HotKey>? bindings,
  }) async {
    if (!isSupportedPlatform) return;
    // hot-restart 等での二重登録を避けるため、登録済み状態をいったんクリアして
    // から登録し直す（nit）。
    await dispose();
    final effectiveBindings = bindings ?? defaultHotkeyBindings();
    for (final action in AppHotkeyAction.values) {
      final handler = handlers[action];
      final binding = effectiveBindings[action];
      if (handler == null || binding == null) continue;
      try {
        await _gateway.register(
          binding,
          keyDownHandler: (_) => handler.onKeyDown(),
          keyUpHandler:
              handler.onKeyUp == null ? null : (_) => handler.onKeyUp!(),
        );
        _registered.add(action);
      } catch (error) {
        _failed.add(action);
        debugPrint('HotkeyService: failed to register $action: $error');
      }
    }
  }

  Future<void> dispose() async {
    try {
      await _gateway.unregisterAll();
    } catch (_) {
      // 後始末失敗は無視する。
    }
    _registered.clear();
    _failed.clear();
  }
}
