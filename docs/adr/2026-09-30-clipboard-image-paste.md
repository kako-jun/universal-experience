# ADR: クリップボードの画像貼り付けに `pasteboard` を使う

- **決定日**: 2026-09-30（Issue #97）
- **記録日**: 2026-09-30（ADR 化）
- **ステータス**: Accepted

## 文脈（問題）

プレビューの原画は、ファイル選択とドラッグ＆ドロップ（#78）でユーザー画像に差し替えられる。
スクリーンショットや他アプリでコピーした画像をそのまま試したい場面では、いったんファイルに
保存する手間が要る。クリップボードの画像を直接読み込めるようにしたい。

Flutter 標準の `Clipboard` はテキストしか扱えないため、画像の取得には外部パッケージが要る。
対象は macOS / Linux のデスクトップ（GTK 3）。ビルドの重さは CI・ローカル（ディスクが小さい
環境がある）に直接効く。

## 決定

1. クリップボード画像の取得に **`pasteboard ^0.5.0`** を使う。ネイティブ側は macOS が
   NSPasteboard、Linux が GtkClipboard、Windows がクリップボードの DIB で、いずれも PNG の
   バイト列を返す（画像が無ければ `null`）。
2. 取得は `ClipboardImageReader`（interface、`lib/services/clipboard_image_reader.dart`）の
   背後に置く。既存の `pickImageFile`（#78）と同じ seam パターンで、テストは
   `clipboardImageReader` をフェイクに差し替える。プラグインは素の `flutter test` では動かない。
3. 読み込んだバイト列は、ファイル選択と同じ `decodeUserImageBytes`（長辺 2048px に縮小しながら
   デコード）を経て `ImageSourceState.setUserImage` に渡す。原画の正本は増やさない。
   サイズ上限は 50MB（ファイルと同じ）で、デコード前に判定する。
4. 入口は「貼り付け」ボタンと `Cmd+V`（macOS）/ `Ctrl+V`。キー操作はテキスト入力にフォーカスが
   あるときだけ奪わない（DESIGN.md §6.3）。
5. 失敗は SnackBar で 4 種に分けて示す（画像なし / 大きすぎる / 読めない形式 / 読み取り失敗）。
   失敗しても現在の原画は変えない。

## 代替案

- **`super_clipboard`**: 機能は最も広い（複数形式、ファイルの参照、ドラッグ）が、
  `super_native_extensions`（Rust + cargokit + irondash）を追加でビルドする。本アプリは
  すでに sensus-core の Rust ビルドを抱えており、CI・ローカルのビルド時間とディスクをこれ以上
  増やしたくない。必要なのは「画像 1 枚のバイト列」だけで、機能が過剰。
- **自前のプラットフォームチャネル（Swift / C）**: 依存は増えないが、macOS と Linux の
  2 実装を自分で保守することになる。`pasteboard` が同じことを標準 API だけで行っている。
- **ペーストを対応せず、ファイル選択・ドラッグ＆ドロップだけにする**: 実装は不要だが、
  スクリーンショットを試すたびにファイル保存が要る手間が残る。
- **`Cmd/Ctrl+V` を `/` や矢印キーと同じ「操作部品にフォーカスがある間は奪わない」ガードにする**:
  「貼り付け」ボタンを押した直後はフォーカスがボタンに残り、キーボードの貼り付けが効かなくなる。
  ボタンやスライダーは貼り付けに固有の意味を持たないので、ガードはテキスト入力（`EditableText`）
  だけにした。

## 根拠

- 追加されるネイティブ依存が各 OS の標準クリップボード API だけで、Rust ビルドが増えない。
- seam の背後に置くので、依存の差し替え（将来 `super_clipboard` へ移る等）が
  `ClipboardImageReader` の実装 1 つで済む。
- 画像はメモリ上でデコードするだけで、ディスク保存も外部送信もしない（#78 の方針と同じ）。

## 結果・トレードオフ

- `pasteboard` は PNG を返すため、元のクリップボードの形式（JPEG 等）は保たれず、
  一度 PNG に変換された分だけバイト数が増えうる。上限 50MB は変換後のバイト列に対して判定する。
- Linux では GTK のクリップボード経由のため、Wayland のみの環境での挙動はヘッドレス開発環境では
  実機確認できていない。macOS の `Podfile.lock` は CI / 実機ビルド時の `pod install` で更新される。
- 実クリップボードを読む経路は自動テストでは踏めない（seam のフェイクで代替）。実機の golden path
  （コピー → Cmd/Ctrl+V → プレビューに反映）は手元のデスクトップで確認する。

## 関連 Issue・PR・docs

- Issue #97、#78（ユーザー画像の読み込み）、#63/#72（アプリ内キー操作）
- `lib/services/clipboard_image_reader.dart`、`lib/ui/widgets/image_source_picker.dart`
  （`pasteUserImageFromClipboard`）、`lib/services/app_shortcuts.dart`
- DESIGN.md §6.3、`docs/ARCHITECTURE.md`（ImageSourceState / アプリ内キー操作）
