# Changelog

## 未リリース

- 起動時のウィンドウを 1280x800 にし、起動直後から 3 ペイン（選ぶ / 見る / 調整）で表示する（従来は 800x600 で縦並びだった。
  タスクバーなどを除いた作業領域に収まらないときは、ウィンドウ枠ごと収まる大きさで起動する。ルーペ窓モードで起動するときは従来どおり 800x600）。
- 狭い画面の縦並びを、3 ペインの左・中央・右と同じ順（選択 → プレビュー → 調整）にした（従来はプレビュー → 調整 → 選択）。
- 体験プリセットを、左ペインの一番上のドロップダウンにした。選ぶと下のフィルタ・強度・パラメータがまとめて切り替わる
  （従来は一覧の中に 4 行で並んでいた。選択肢は sensus の体験をそのまま並べるので、件数は固定ではない）。
- Linux の Wayland セッション（COSMIC など）で、起動してもウィンドウが描画されず操作できない問題を修正。Wayland セッションでは
  XWayland（X11 バックエンド）を優先して起動する（`GDK_BACKEND=x11` の指定は不要。XWayland が無ければ Wayland にフォールバック。
  `UE_ALLOW_WAYLAND=1` でネイティブ Wayland を強制可能）。

## 0.2.0 — 2026-10-15

- Android 10+（arm64-v8a / armeabi-v7a / x86_64 の universal APK）を対応 OS に追加。フォト/ドキュメントピッカーから画像を選び、
  フィルタ適用後の PNG を `Pictures/Universal Experience` へ書き出せる。
- GitHub Releases で、release keystore により署名した
  `universal-experience-android.apk` を macOS / Linux / Windows の配布物と同じ Release に公開する。
- Android の Rust FFI を cargokit で APK に同梱し、CI で3 ABIすべての Rust native library を含む universal debug APK を検証する。

## 0.1.1

- macOS / Linux / Windows 向けの GitHub Releases 配布と、タグ・Dart・Rust の版一致ゲートを追加。
