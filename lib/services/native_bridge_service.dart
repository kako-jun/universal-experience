import 'dart:developer' as developer;

import '../src/rust/frb_generated.dart';

/// Rust ブリッジ（sensus-core、#55）の bootstrap。
///
/// `main()` と `integration_test/` の両方から同じ経路で初期化できるよう
/// `RustLib.init()` 呼び出しをここに切り出している。`RustLib.instance.initialized`
/// を見て二重初期化を素通りさせる（`RustLib.init()` を直接 2 回呼ぶと
/// `StateError('Should not initialize flutter_rust_bridge twice')` になるため、
/// bootstrap としてはこちらを仕様とする）。
///
/// 失敗時（native lib が同梱されていない・壊れている等）は例外を投げず、
/// ログに残して `false` を返す。呼び出し元（`main()`）はこれを見て
/// エラー画面（`AppLocalizations.nativeBridgeInitFailed`）を出す。
Future<bool> initNativeBridge() async {
  if (RustLib.instance.initialized) {
    return true;
  }
  try {
    await RustLib.init();
    return true;
  } catch (error, stackTrace) {
    developer.log(
      'Rust ネイティブライブラリの初期化に失敗しました (#55)',
      name: 'NativeBridgeService',
      error: error,
      stackTrace: stackTrace,
      level: 1000, // SEVERE
    );
    return false;
  }
}
