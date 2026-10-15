# Changelog

## 0.2.0 — 2026-10-15

- Android 10+（arm64-v8a / armeabi-v7a / x86_64 の universal APK）を対応 OS に追加。フォト/ドキュメントピッカーから画像を選び、
  フィルタ適用後の PNG を `Pictures/Universal Experience` へ書き出せる。
- GitHub Releases で、release keystore により署名した
  `universal-experience-android.apk` を macOS / Linux / Windows の配布物と同じ Release に公開する。
- Android の Rust FFI を cargokit で APK に同梱し、CI で3 ABIすべての Rust native library を含む universal debug APK を検証する。

## 0.1.1

- macOS / Linux / Windows 向けの GitHub Releases 配布と、タグ・Dart・Rust の版一致ゲートを追加。
