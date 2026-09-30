# ADR: PNG エクスポートは保存ダイアログを使わず Downloads へ直接保存する

- **決定日**: 2026-09-30（Issue #64。PR #102）
- **記録日**: 2026-09-30（ADR 化）
- **ステータス**: Accepted（実機 macOS / Windows での確認待ち。「結果・トレードオフ」参照）

## 文脈（問題）

PNG エクスポート（#43）は `getDownloadsDirectory()` へ書いていたが、次の問題があった。

- macOS のサンドボックスに Downloads の entitlement が無く、書き込みがサンドボックスに拒否された。
  取得できるパスもコンテナ内（`~/Library/Containers/<bundle>/Data/Downloads`）で、SnackBar に出るパスは
  ユーザーが辿らない場所だった。
- ファイル名が日付までで、同じ日の 2 回目は無言で上書きされた。

## 決定

1. **保存ダイアログ（`file_selector` の `getSaveLocation`）ではなく、Downloads へ直接保存する。**
   `com.apple.security.files.downloads.read-write` を `DebugProfile.entitlements` と `Release.entitlements`
   の両方に追加する。
2. **ファイル名に時刻を入れ（`ue-<症状 id>-<強度>pct-<日付>_<HHMMSS>.png`）、それでも同名があれば連番
   （`-2`, `-3` …）にして決して上書きしない。** 存在確認と作成は `File.create(exclusive: true)` の 1 操作で
   行う。
3. **ユーザーに見せる・Finder に渡すパスは `resolveSymbolicLinks` で実パスにする。** サンドボックスの
   コンテナ内 `Data/Downloads` は実 `~/Downloads` へのシンボリックリンクなので、正規化しないと
   SnackBar・クリップボード・「フォルダで表示」がコンテナ側のパスになる。
4. **成功 SnackBar に保存先のフルパスと「フォルダで表示」を出す。** 新規依存は足さず、OS ごとのコマンド
   （macOS `/usr/bin/open -R`、Windows `explorer /select,`、Linux `xdg-open`）を呼ぶ。開けなければ失敗を
   SnackBar で知らせる。

## 代替案

- **保存ダイアログ（`getSaveLocation`）**: 保存先が確実に見え、上書きも OS が確認する。しかし書き出しの
  たびに選択が要り、アイコン 1 タップで出せる現行の使い勝手が落ちる。user-selected の read-write
  entitlement へ変える必要もあった。Issue も第一案として Downloads entitlement を挙げていた。
- **ドキュメントフォルダ固定**: 追加の entitlement は要らないが、コンテナ内に入ってユーザーに見えない
  のは同じ。
- **`url_launcher` 等でフォルダを開く**: 新規依存が要る。OS コマンドで足りる。

## 根拠

- 書き出しはプレビューを見ながら何度も試す操作で、毎回のダイアログは邪魔になる。保存先が固定で、
  ファイル名で衝突しなければ、ダイアログの利点（保存先が見える・上書き確認）は SnackBar のフルパスと
  「フォルダで表示」・非上書きで代替できる。
- 純関数（`exportFilename` / `numberedFilename` / `revealCommandFor`）と I/O を分け、書き込みは一時
  ディレクトリで単体テストできる。

## 結果・トレードオフ

- 実機 macOS で、(a) `~/Downloads` にファイルが出る、(b) SnackBar が `/Users/<name>/Downloads/…` を出す、
  (c) サンドボックス下で `open -R` が Finder で対象を選択する、は未確認（開発環境がヘッドレス）。(c) が
  失敗する場合は `NSWorkspace activateFileViewerSelecting` のメソッドチャネル呼び出しへ替える。
  失敗は SnackBar でユーザーに伝わる。
- Windows で、パスにスペースやカンマを含むときの `explorer /select,` の解釈は未確認。Linux は含む
  フォルダを開くだけで、ファイルの選択はしない。
- 保存先を変えたい利用者向けの設定は無い（必要になれば別 Issue で保存ダイアログを選べるようにする）。

## 関連 Issue・PR・docs

- Issue #64、PR #102（本決定）、Issue #43（PNG エクスポート）
- `lib/services/export_service.dart`、`macos/Runner/*.entitlements`
- `docs/ARCHITECTURE.md`（ExportService）、README「画像エクスポート（PNG）」
