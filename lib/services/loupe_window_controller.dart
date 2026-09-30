import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show HardwareKeyboard, KeyDownEvent, KeyEvent;
import 'package:flutter/widgets.dart' show Color, Rect, Size;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'loupe_rect_source.dart';

/// ルーペ窓の表示状態。
///
/// - [normal]    : 通常ウィンドウ。縁(フレーム/タイトルバー)を見せ、
///                 ドラッグで移動・リサイズできる。覗き範囲はウィンドウ矩形。
/// - [maximized] : 最大化。画面いっぱいに広げるが **縁は残す**。
///                 ルーペは「枠の向こうにフィルタ済みデスクトップ」が見える体験なので、
///                 最大化でも縁があった方が「どこが覗き窓か」が破綻しない。
/// - [fullscreen]: 全画面。縁を消し、画面全域をフィルタ対象にする没入モード。
enum LoupeWindowMode { normal, maximized, fullscreen }

/// モード遷移を起こすユーザーアクション。
enum LoupeWindowAction { restore, toggleMaximize, toggleFullscreen }

/// アプリの起動モード (#63)。ルーペ窓の透明度・タイトルバー等の見た目に関わる。
/// 最前面固定・クリックスルーはこれとは独立したトグルとして別に持つ
/// （モード切り替えはこれらを自動で変更しない）。
enum AppMode { settings, loupe }

/// ルーペ窓の純粋ロジック(プラットフォーム I/O を含まない)。
///
/// window_manager を直接叩く前段の「決定」だけをここに集約し、unit test 可能にする。
/// 実際の `windowManager.xxx()` 呼び出しは [LoupeWindowController] が担う。
class LoupeWindowPolicy {
  const LoupeWindowPolicy._();

  /// ルーペ窓の最小サイズ。
  ///
  /// 根拠: 従来は 600x400 だったが、ルーペは「画面の一部に小さくかざす」
  /// 使い方が主眼。色覚/視野シミュレーションの差を視認できる下限として
  /// 320x240 (QVGA, 4:3) を採用する。
  /// - 320px あればフィルタの色差・ボケ・視野欠損のパターンは判別できる。
  /// - これ以上小さいとタイトルバー操作領域や枠描画が窮屈になり実用性を失う。
  /// 4:3 にしているのは「覗き窓」の直感的な比率で、特定アスペクト強制ではない
  /// (リサイズで自由に変えられる)。
  ///
  /// 単位の注意: この値は **論理ピクセル**。HiDPI (DPR 2x) のモニタでは
  /// 実効の物理ピクセルは 640x480 相当の見え方になる。物理解像度に応じた見え方の
  /// 調整 (DPR 換算) は #5 DPR スコープで扱う。
  static const Size minimumSize = Size(320, 240);

  /// 起動時の既定サイズ。最小より十分大きく、デスクトップの一角を覗ける程度。
  static const Size defaultSize = Size(800, 600);

  /// 既定: 最前面固定は **OFF**、切替式 (#63)。
  ///
  /// 起動直後は設定モード (通常ウィンドウ) から始まる (#63) ため、フィルタ
  /// 選択 UI をまず操作したい。常に最前面だと設定 UI が他アプリの上に居座って
  /// 操作しづらいので、既定は OFF にし、実際にかざして見たいときにユーザーが
  /// トグル ON する運用にする。
  static const bool defaultAlwaysOnTop = false;

  /// 既定: loupe モード時の透明値。settings モードは常に不透明
  /// ([transparentForMode] 参照)。
  static const bool defaultTransparent = true;

  /// 既定: クリックスルーは **OFF**。
  /// 起動直後はウィンドウを掴んで移動・リサイズしたいので、まずは
  /// イベントを受け取る。下のアプリを操作したいときにユーザーが
  /// トグル ON する運用 (切替式)。
  static const bool defaultClickThrough = false;

  /// 起動時の既定モード。設定窓（通常ウィンドウ・不透明）から始める (#63)。
  static const AppMode defaultAppMode = AppMode.settings;

  /// 指定モードでの透明背景。loupe モードのみ透明 (defaultTransparent を流用)、
  /// settings モードは常に不透明 (フィルタ選択 UI を見やすくするため)。
  static bool transparentForMode(AppMode mode) =>
      mode == AppMode.loupe && defaultTransparent;

  /// あるモードで「縁(フレーム/タイトルバー)を見せるか」を返す純粋関数。
  ///
  /// - normal/maximized : 縁あり (= frameless ではない)
  /// - fullscreen       : 縁なし (= frameless)
  static bool showFrame(LoupeWindowMode mode) {
    switch (mode) {
      case LoupeWindowMode.normal:
      case LoupeWindowMode.maximized:
        return true;
      case LoupeWindowMode.fullscreen:
        return false;
    }
  }

  /// モード遷移の解決。現在モードと要求アクションから次モードを決める。
  ///
  /// トグル系アクションは「同じモードを再要求したら normal に戻る」挙動にする
  /// (最大化中にもう一度 maximize 要求 = 元に戻す、を表現)。
  static LoupeWindowMode resolveMode(
    LoupeWindowMode current,
    LoupeWindowAction action,
  ) {
    switch (action) {
      case LoupeWindowAction.restore:
        return LoupeWindowMode.normal;
      case LoupeWindowAction.toggleMaximize:
        return current == LoupeWindowMode.maximized
            ? LoupeWindowMode.normal
            : LoupeWindowMode.maximized;
      case LoupeWindowAction.toggleFullscreen:
        return current == LoupeWindowMode.fullscreen
            ? LoupeWindowMode.normal
            : LoupeWindowMode.fullscreen;
    }
  }

  /// Linux で、グローバルホットキー（keybinder、X11 依存）が実際には発火しなそうな
  /// セッションかを判定する (#63)。Wayland ネイティブセッションでは hotkey_manager の
  /// 登録が「成功」を返しても実際には発火しないことがある。Wayland セッションの兆候
  /// （`XDG_SESSION_TYPE=wayland` または `WAYLAND_DISPLAY`）が少しでもあれば、
  /// `GDK_BACKEND=x11`（XWayland 経由の互換動作を示唆する値）が明示されていても
  /// 信頼できない側に倒す — 判定を誤って「使える」と過信するより、ヒントから
  /// 除外しすぎる方が安全なため。[environment] は呼び出し側が `Platform.environment`
  /// を渡す想定（テストではフェイクの Map を渡せる）。
  static bool isLikelyWaylandNativeSession(Map<String, String> environment) {
    final sessionType = environment['XDG_SESSION_TYPE'];
    final waylandDisplay = environment['WAYLAND_DISPLAY'];
    return sessionType == 'wayland' ||
        (waylandDisplay != null && waylandDisplay.isNotEmpty);
  }
}

/// window_manager の薄いラッパ。
///
/// マルチモニタ: **第1弾はメインモニタのみ対象**。サブモニタへの移動追従や
/// モニタごとの DPR 換算 (#5) はスコープ外。window_manager はメインモニタの
/// 座標系で動作する前提で扱う。
///
/// プラットフォーム差: `setAsFrameless` / `setIgnoreMouseEvents(forward:)` は
/// Linux/macOS/Windows で挙動差・未対応がある。利用不能でも落ちないよう
/// 全 I/O を try/catch + ログで握る。
class LoupeWindowController extends ChangeNotifier with WindowListener {
  LoupeWindowController({LoupeRectSource rectSource = const ManualLoupeRectSource()})
      : _rectSource = rectSource;

  final LoupeRectSource _rectSource;

  LoupeWindowMode _mode = LoupeWindowMode.normal;
  bool _clickThrough = LoupeWindowPolicy.defaultClickThrough;
  bool _alwaysOnTop = LoupeWindowPolicy.defaultAlwaysOnTop;
  AppMode _appMode = LoupeWindowPolicy.defaultAppMode;
  Size? _currentSize;
  SharedPreferences? _prefs;

  static const String _prefsAppMode = 'loupeWindow.appMode';
  static const String _prefsAlwaysOnTop = 'loupeWindow.alwaysOnTop';
  static const String _prefsClickThrough = 'loupeWindow.clickThrough';

  /// 現在の表示モード。
  LoupeWindowMode get mode => _mode;

  /// クリックスルー(下のアプリへイベントを流す)が有効か。
  bool get clickThrough => _clickThrough;

  /// 最前面固定が有効か。
  bool get alwaysOnTop => _alwaysOnTop;

  /// アプリの起動モード (#63)。
  AppMode get appMode => _appMode;

  /// 現在のウィンドウサイズ (リサイズ追従で更新)。null は未取得。
  Size? get currentSize => _currentSize;

  /// ルーペ矩形の決定元 (#63、#44 向けの差し替え可能な seam) から現在の矩形を
  /// 取得する。#44 実装時にこのコントローラへ対象アプリ追従の `LoupeRectSource`
  /// を注入できる。現状どこからも消費されない（ライブ画面キャプチャ未実装の
  /// ため）が、注入口だけは用意しておく。
  Future<Rect?> currentLoupeRect() => _rectSource.currentRect();

  /// 永続化されたアプリモード・最前面固定・クリックスルーの状態を読み込む
  /// (#63)。`main()` が [initialize] より先に呼ぶ責務を持つ — ここは
  /// `_appMode`/`_alwaysOnTop`/`_clickThrough` を復元するだけで、実際の
  /// window_manager への反映は [initialize] が行う。
  Future<void> load() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    final modeName = prefs.getString(_prefsAppMode);
    if (modeName != null) {
      _appMode = AppMode.values.firstWhere(
        (m) => m.name == modeName,
        orElse: () => LoupeWindowPolicy.defaultAppMode,
      );
    }
    _alwaysOnTop =
        prefs.getBool(_prefsAlwaysOnTop) ?? LoupeWindowPolicy.defaultAlwaysOnTop;
    final storedClickThrough =
        prefs.getBool(_prefsClickThrough) ?? LoupeWindowPolicy.defaultClickThrough;
    if (_appMode == AppMode.settings && storedClickThrough) {
      // 保存値が不変条件（設定窓モードはクリックスルー禁止）と矛盾していた
      // 場合は正しい値へ正規化し、書き直す (#63)。
      _clickThrough = false;
      await _persist();
    } else {
      _clickThrough = storedClickThrough;
    }
  }

  Future<void> _persist() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setString(_prefsAppMode, _appMode.name);
    await prefs.setBool(_prefsAlwaysOnTop, _alwaysOnTop);
    await prefs.setBool(_prefsClickThrough, _clickThrough);
  }

  /// 起動時の初期化。[load] 済みの `_appMode`/`_alwaysOnTop` を実際の
  /// window_manager へ反映する (#63)。`load()` 自体はここでは呼ばない
  /// (`main.dart` の責務。`load()` を先に呼んでおかないと既定値のまま適用される)。
  /// 背景色 (transparent/black) は `main.dart` の `WindowOptions` 構築時に別途
  /// 反映するため、ここでは触らない。
  ///
  /// クリックスルーは適用しない。実際の適用は [restorePersistedClickThrough]
  /// が担う（`main()` がトレイ・ホットキー初期化の後に呼ぶ構成は診断ログの
  /// タイミングを揃えるため変えていないが、ゲート自体はもう無い）。
  Future<void> initialize() async {
    windowManager.addListener(this);
    HardwareKeyboard.instance.addHandler(_handleAnyKeyEvent);
    await _guard('setMinimumSize', () async {
      await windowManager.setMinimumSize(LoupeWindowPolicy.minimumSize);
    });
    await setAlwaysOnTop(_alwaysOnTop);
    // 起動は normal モード = 縁あり。
    await _applyFramePolicy();
  }

  /// 永続化されたクリックスルーを window_manager へ適用する (#63)。
  /// クリックスルーはいつでも ON にしてよい（フォーカス復帰＋キー入力・Esc の
  /// 復帰経路が常にあるため）ので、復帰手段の可用性を待つ必要はもう無い。
  /// main() がトレイ・ホットキー初期化の後に呼ぶ構成は変えていないが
  /// （診断ログのタイミングを揃えるため）、ゲート自体は無い。
  Future<void> restorePersistedClickThrough() async {
    if (_clickThrough) {
      await setClickThrough(true);
    }
  }

  /// 後始末。
  @override
  void dispose() {
    windowManager.removeListener(this);
    HardwareKeyboard.instance.removeHandler(_handleAnyKeyEvent);
    super.dispose();
  }

  /// 起動モードを切り替える (#63)。背景の透明値 (settings=不透明/loupe=透明)
  /// を反映する。settings モードに切り替えるときは、クリックスルーが ON の
  /// ままだと設定 UI が操作不能になるため強制 OFF にする。
  Future<void> setAppMode(AppMode mode) async {
    _appMode = mode;
    await _guard('setBackgroundColor', () async {
      // 色の例外（DESIGN.md）: OS ウィンドウの下地色（透過/不透明黒）。
      // Flutter のテーマの外側にあり、colorScheme のロールを引けない。
      await windowManager.setBackgroundColor(
        LoupeWindowPolicy.transparentForMode(mode)
            ? const Color(0x00000000)
            : const Color(0xFF000000),
      );
    });
    if (mode == AppMode.settings && _clickThrough) {
      await setClickThrough(false);
    }
    await _persist();
    _notify();
  }

  /// 最前面固定のトグル。
  Future<void> setAlwaysOnTop(bool value) async {
    _alwaysOnTop = value;
    await _guard('setAlwaysOnTop', () async {
      await windowManager.setAlwaysOnTop(value);
    });
    await _persist();
    _notify();
  }

  /// クリックスルーのトグル。
  ///
  /// `forward: true` で「自ウィンドウは無視しつつイベントを下へ転送」する。
  ///
  /// プラットフォーム差 (重要): `forward` 引数は **macOS 専用**で、Linux/Windows
  /// では window_manager 側で無視される。つまり Linux では「自ウィンドウはイベントを
  /// 無視する」までは効くが、「下のアプリへ転送する」挙動は forward では保証されない
  /// (コンポジタ/OS 依存)。クリックスルー時に下のアプリが実際に操作できるかは
  /// **Linux 実機での確認が必要（ライブキャプチャ #1 の実装後）**。未対応でも落ちないよう
  /// try/catch で握る。
  Future<void> setClickThrough(bool value) async {
    if (value && _appMode == AppMode.settings) {
      // 安全策 (#63): 設定窓モードは UI 操作が前提の通常ウィンドウなので、
      // クリックスルーを ON にはできない。呼び出し元（UI パネル/トレイ/
      // ホットキー）を問わずここで一括して拒否する。ここに来た時点で true の
      // 余地は無いはずだが、念のため false を確定させて persist/notify する
      // （拒否するだけで状態確定をサボらない）。
      if (_clickThrough) {
        _clickThrough = false;
        await _persist();
        _notify();
      }
      return;
    }
    _clickThrough = value;
    await _guard('setIgnoreMouseEvents', () async {
      await windowManager.setIgnoreMouseEvents(value, forward: true);
    });
    await _persist();
    _notify();
  }

  /// モード遷移アクションを適用する。
  Future<void> applyAction(LoupeWindowAction action) async {
    final next = LoupeWindowPolicy.resolveMode(_mode, action);
    await _setMode(next);
  }

  Future<void> _setMode(LoupeWindowMode next) async {
    if (next == _mode) return;
    final previous = _mode;
    _mode = next;
    await _guard('mode:$previous->$next', () async {
      switch (next) {
        case LoupeWindowMode.normal:
          if (previous == LoupeWindowMode.fullscreen) {
            await windowManager.setFullScreen(false);
          }
          if (previous == LoupeWindowMode.maximized) {
            await windowManager.unmaximize();
          }
          break;
        case LoupeWindowMode.maximized:
          if (previous == LoupeWindowMode.fullscreen) {
            await windowManager.setFullScreen(false);
          }
          await windowManager.maximize();
          break;
        case LoupeWindowMode.fullscreen:
          await windowManager.setFullScreen(true);
          break;
      }
    });
    await _applyFramePolicy();
    _notify();
  }

  /// 現在モードの枠ポリシーをウィンドウに反映する。
  ///
  /// 順序依存の注意 (実機確認): ここでは `_setMode` が `setFullScreen` を
  /// 呼んだ **後** に `setTitleBarStyle` を当てている。プラットフォームによっては
  /// 全画面遷移とタイトルバースタイル変更の順序で「全画面なのにタイトルバーが
  /// 残る/枠が二重に出る」等の差が出ることがある。この順序 (fullscreen → titleBar)
  /// が Linux/Windows/macOS いずれでも破綻しないかは **実機目視で確認が必要 (#11後)**。
  Future<void> _applyFramePolicy() async {
    final showFrame = LoupeWindowPolicy.showFrame(_mode);
    await _guard('frame:$showFrame', () async {
      if (showFrame) {
        // 縁あり: タイトルバーを通常表示。
        await windowManager.setTitleBarStyle(TitleBarStyle.normal);
      } else {
        // 縁なし(全画面): タイトルバー/枠を隠す。
        await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      }
    });
  }

  void _notify() => notifyListeners();

  /// 診断ログ。avoid_print lint を踏まないよう debug ビルド限定で出す。
  void _log(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[LoupeWindowController] $message');
    }
  }

  /// 全 window_manager I/O を握る共通ガード。
  /// プラットフォーム未対応・未初期化でも落とさない。
  Future<void> _guard(String label, Future<void> Function() body) async {
    try {
      await body();
    } catch (e) {
      _log('$label failed: $e');
    }
  }

  // --- WindowListener: リサイズ追従とモード同期 ---

  /// クリックスルー解除が「予約」されているか。フォーカスを得た直後は即座に
  /// 解除せず、実際にユーザーがこのウィンドウを操作し始めた合図（最初の
  /// キー入力）まで待つ ([releaseClickThroughOnFirstKeyPress] 参照)。
  bool _clickThroughReleaseArmed = false;

  @override
  void onWindowFocus() {
    if (_clickThrough) {
      // 復帰経路 (#63): クリックスルー ON のままフォーカスを得ても、ここでは
      // 即座に解除しない。トレイメニューを開いた・OS がユーザー操作を伴わず
      // フォーカスを移しただけ（Windows の SetForegroundWindow 等）のときに
      // 意図せず解除されるのを避けるため、実際に最初のキー入力があるまで
      // 「解除の予約」だけをする。
      _clickThroughReleaseArmed = true;
    }
  }

  @override
  void onWindowBlur() {
    // フォーカスを失ったら予約は取り消す。
    _clickThroughReleaseArmed = false;
  }

  /// フォーカス復帰後の最初のキー入力でクリックスルーを解除する。
  /// [onWindowFocus] で予約されていなければ何もしない。`HardwareKeyboard`
  /// の全キーイベントハンドラ（[initialize] で登録、[dispose] で解除）から
  /// キー入力ごとに呼ばれる。
  void releaseClickThroughOnFirstKeyPress() {
    if (_clickThroughReleaseArmed) {
      _clickThroughReleaseArmed = false;
      unawaited(setClickThrough(false));
    }
  }

  /// [HardwareKeyboard] の全キーイベントハンドラ。keyDown のたびに
  /// [releaseClickThroughOnFirstKeyPress] を呼ぶだけで、イベント自体は消費
  /// しない（false を返し、通常のフォーカスチェーン・IME 等の処理へそのまま
  /// 渡す）。
  bool _handleAnyKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      releaseClickThroughOnFirstKeyPress();
    }
    return false;
  }

  @override
  void onWindowResize() {
    // 中身がウィンドウに貼り付く責務。サイズを保持して UI に伝える。
    () async {
      final size = await _safeGetSize();
      if (size != null) {
        _currentSize = size;
        _notify();
      }
    }();
  }

  @override
  void onWindowMaximize() {
    _mode = LoupeWindowMode.maximized;
    _notify();
  }

  @override
  void onWindowUnmaximize() {
    if (_mode == LoupeWindowMode.maximized) {
      _mode = LoupeWindowMode.normal;
      _notify();
    }
  }

  @override
  void onWindowEnterFullScreen() {
    _mode = LoupeWindowMode.fullscreen;
    _notify();
  }

  @override
  void onWindowLeaveFullScreen() {
    if (_mode == LoupeWindowMode.fullscreen) {
      _mode = LoupeWindowMode.normal;
      _notify();
    }
  }

  Future<Size?> _safeGetSize() async {
    try {
      return await windowManager.getSize();
    } catch (e) {
      _log('getSize failed: $e');
      return null;
    }
  }
}
