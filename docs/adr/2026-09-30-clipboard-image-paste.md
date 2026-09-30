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
3. **ファイルを先に見る**。`ClipboardImageReader.read()` は `Pasteboard.files` を先に読み、
   各パスを 2 段で見る。(a) **ローカルに何かしら実在するか**（`FileSystemEntity.type` が `notFound`
   でない。ファイルでもフォルダでも `.app` でも真。判定は `resolveClipboardContent` に
   `existsLocally` として注入するので純粋関数のまま）、(b) 画像拡張子（png/jpg/jpeg/gif/bmp/webp）か。
   実在するもののうち画像のものがあれば先頭の 1 枚を `ClipboardImageFile` として返し、選択・ドロップと
   同じ `loadUserImageFile`（50MB の事前判定付き）に回す。実在するものはあるが画像が 1 枚も無い
   （HEIC 等の非対応形式・フォルダ・`.app`・拡張子なしのファイル）ときは、画像データ取得へ進まず
   `ClipboardUnsupportedFiles`（「コピーしたファイルは読み込めない形式」）にする。Finder はフォルダや
   アプリのアイコンも一緒に載せるため、ここで画像データへ進むとアイコンが原画になってしまう。
   画像データへ進むのは、ローカルに**実在しない**パス（URL 等）しか無いとき（またはパスが無いとき）だけ。
   macOS の上流実装は
   `files()` が options なしの `readObjects(NSURL)` で http(s) URL も返し得るため、ブラウザの
   「イメージをコピー」で URL と画像データが両方載る場合に、実在しない URL に引っ張られて画像が
   貼り付けられなくなる退行を避ける（どのブラウザが URL を載せるかは実機未確認）。
   ファイラでファイルをコピーすると、OS がファイルのアイコン画像も一緒に載せることがある
   （macOS の Finder はファイル URL とアイコンの TIFF）。先に画像データを見ると、画像ファイルの
   中身ではなくアイコンを貼り付けてしまうため。判定は純粋関数 `resolveClipboardContent` に切り出して
   テストする。
4. 画像データのバイト列は、ファイル選択と同じ `decodeUserImageBytes`（長辺 2048px に縮小しながら
   デコード）を経て `ImageSourceState.setUserImage` に渡す。原画の正本は増やさない。
   サイズ上限は 50MB（ファイルと同じ）で、デコード前に判定する。
5. 入口は「貼り付け」ボタンと `Cmd+V`（macOS）/ `Ctrl+V`。キー操作はテキスト入力にフォーカスが
   あるときだけ奪わない（DESIGN.md §6.3）。キーの押しっぱなし（リピート）は無視し
   （`includeRepeats: false`）、貼り付けの実行中に再度呼ばれても無視する（in-flight ガード、
   例外でも解除）。
6. 失敗は SnackBar で 5 種に分けて示す（画像なし / 大きすぎる / 読めない形式 / 非対応ファイルのみ /
   読み取り失敗）。失敗しても現在の原画は変えない。読み取りには 30 秒のタイムアウトを付け、
   `TimeoutException` は読み取り失敗として扱う（返事をしないクリップボード所有者で in-flight ガードが
   残らないように）。

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

- **ライセンス**: `pasteboard` は Apache-2.0。MIT の本アプリで使用でき、配布物のライセンス表示は
  Flutter の `LicenseRegistry`（`showLicensePage`）が pub パッケージの LICENSE を集めるので含まれる。
- **既知の上流問題（Linux のメモリリーク）**: `pasteboard` 0.5.0 の Linux 実装
  （`linux/pasteboard_plugin.cc`、`clipboard_request_image_callback`）は、
  `gdk_pixbuf_save_to_buffer` が確保した `buffer` を Flutter へ渡した後に `g_free` せず、
  エラー時の `GError` も `g_error_free` しない。画像を貼り付けるたびに PNG 1 枚分のメモリが
  解放されない（プロセス終了まで残る）。同じく `gtk_clipboard_request_uris_callback`（ファイルのコピー
  取得）も `g_file_get_path` の戻り値を `g_free` していない（パス 1 本ごとの小さなリーク）。当アプリ側では回避できない（プラグイン内部の確保のため）。
  上流への起票は第三者への公開行為なので行っていない（起票用の文案は Issue #97 のコメントにある。起票するかは
  kako-jun の判断）。macOS の実装は Swift で、同種の手動解放の漏れはコード上にない。
- **ブラウザの画像コピーで載るクリップボードの中身は実機未確認**: どのブラウザ・OS の組み合わせで
  http(s) URL がファイル一覧に載るかは確認していない。実在判定で無視する設計にしてあるが、挙動は
  実機で確認が要る。
- **ファイルのコピー経路は実機未確認**: `Pasteboard.files` が Finder（macOS）・Nautilus 等（Linux）で
  実際にどう返るか（macOS は Finder が載せるアイコンの TIFF を避けられるか、Linux は URI のみの
  クリップボードからパスを取れるか）は、コード上の想定であり実機で確認していない。実機確認が要る。
- **macOS のプライバシー警告は実機未確認**（確認ダイアログが同期的に読み取りを止める場合、
  許可待ちとタイムアウトが衝突しうるため、`clipboardReadTimeout` は 30 秒にした。実機確認の対象）: 新しい macOS には、他アプリのクリップボードを
  プログラムが読むときに確認を出す仕組み（「他のアプリからのペーストを許可」）がある。本アプリの
  貼り付けボタン・Cmd+V で警告が出るか、出た場合の文言と挙動は実機でしか確認できない。
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
