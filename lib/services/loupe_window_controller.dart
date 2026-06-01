import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Size, VoidCallback;
import 'package:window_manager/window_manager.dart';

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
  /// 単位の注意 (nit): この値は **論理ピクセル**。HiDPI (DPR 2x) のモニタでは
  /// 実効の物理ピクセルは 640x480 相当の見え方になる。物理解像度に応じた見え方の
  /// 調整 (DPR 換算) は #5 DPR スコープで扱う。
  static const Size minimumSize = Size(320, 240);

  /// 起動時の既定サイズ。最小より十分大きく、デスクトップの一角を覗ける程度。
  static const Size defaultSize = Size(800, 600);

  /// 既定: ルーペ窓は常に最前面に出し続ける。
  /// 下のアプリより手前にいないと「かざして見る」体験が成立しないため。
  static const bool defaultAlwaysOnTop = true;

  /// 既定: 背景は完全透過。枠の外は透け、枠(レンズ)の中だけ描画する。
  static const bool defaultTransparent = true;

  /// 既定: クリックスルーは **OFF**。
  /// 起動直後はウィンドウを掴んで移動・リサイズしたいので、まずは
  /// イベントを受け取る。下のアプリを操作したいときにユーザーが
  /// トグル ON する運用 (切替式)。
  static const bool defaultClickThrough = false;

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
class LoupeWindowController with WindowListener {
  LoupeWindowController();

  LoupeWindowMode _mode = LoupeWindowMode.normal;
  bool _clickThrough = LoupeWindowPolicy.defaultClickThrough;
  bool _alwaysOnTop = LoupeWindowPolicy.defaultAlwaysOnTop;
  Size? _currentSize;

  /// 現在の表示モード。
  LoupeWindowMode get mode => _mode;

  /// クリックスルー(下のアプリへイベントを流す)が有効か。
  bool get clickThrough => _clickThrough;

  /// 最前面固定が有効か。
  bool get alwaysOnTop => _alwaysOnTop;

  /// 現在のウィンドウサイズ (リサイズ追従で更新)。null は未取得。
  Size? get currentSize => _currentSize;

  /// リサイズなどで状態が変わったら呼ばれるコールバック (UI 再描画用)。
  VoidCallback? onChanged;

  // TODO(#14/#16): アプリモード切替を導入する。
  // 現状は起動直後から「透明・最前面」を常時適用しているが、フィルタ選択 UI (#16)
  // を操作するときは「常に最前面・背景透明」だと操作しづらい (UI が透けて背後の
  // アプリと重なる / 他ウィンドウへ移れない)。
  // 将来は次の2モードを切り替える想定:
  //   - 設定モード (settings): 通常ウィンドウ。透明 OFF・最前面 OFF。フィルタ選択など
  //     UI 操作に集中する。起動既定はこちらが望ましい。
  //   - ルーペモード (loupe): 透明 ON・最前面 ON。実際に画面へかざして見る。
  // 実装時は LoupeWindowController に setSettingsMode(bool)/setLoupeMode(bool) の口を
  // 用意し、main の起動既定を「設定モード=通常ウィンドウ」にする。
  // 本 PR (#14) ではスコープ外のため起動既定 (透明・最前面 ON) は現状維持。
  // 詳細は docs/ARCHITECTURE.md「フォロー事項: アプリモード切替」を参照。

  /// 起動時の初期化。最小サイズ・最前面・枠ポリシーを適用する。
  /// (透過は WindowOptions.backgroundColor 側で設定済み。)
  Future<void> initialize() async {
    windowManager.addListener(this);
    await _guard('setMinimumSize', () async {
      await windowManager.setMinimumSize(LoupeWindowPolicy.minimumSize);
    });
    if (LoupeWindowPolicy.defaultAlwaysOnTop) {
      await setAlwaysOnTop(true);
    }
    // 起動は normal モード = 縁あり。
    await _applyFramePolicy();
  }

  /// 後始末。
  void dispose() {
    windowManager.removeListener(this);
  }

  /// 最前面固定のトグル。
  Future<void> setAlwaysOnTop(bool value) async {
    _alwaysOnTop = value;
    await _guard('setAlwaysOnTop', () async {
      await windowManager.setAlwaysOnTop(value);
    });
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
  /// **Linux 実機での確認が必要 (#11 描画統合後)**。未対応でも落ちないよう
  /// try/catch で握る。
  Future<void> setClickThrough(bool value) async {
    _clickThrough = value;
    await _guard('setIgnoreMouseEvents', () async {
      await windowManager.setIgnoreMouseEvents(value, forward: true);
    });
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
  /// 順序依存の注意 (nit/実機確認): ここでは `_setMode` が `setFullScreen` を
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

  void _notify() => onChanged?.call();

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
