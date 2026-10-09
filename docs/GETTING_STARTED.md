# Getting Started with Universal Experience

このガイドでは、Universal Experienceの開発環境のセットアップから実行までを説明します。

## 前提条件

### 必須ツール

- **Flutter SDK**: **3.41.4**。`pubspec.yaml` の `environment.flutter` がローカル開発と
  CI の唯一の定義元です。インストール済み SDK が一致することを確認してください。
  この指定は SDK を自動でインストール・切替しないため、ローカルでは自分で同じ版を選びます。
  ```bash
  flutter --version
  ```

- **Git**: バージョン管理用

- **Rust toolchain**（`rustc` / `cargo`, stable channel、**rustup 経由でのインストールが必須**）:
  `rust/` crate（flutter_rust_bridge 経由で sensus-core を公開する）に必要。
  `cargo test` / clippy だけでなく、`rust_builder/`（cargokit 統合、#55）が
  `flutter run` / `flutter build macos` / `flutter build linux` のたびに
  `cargo build` を呼んで native lib をビルド・同梱するため、通常のアプリ実行にも
  要ります。cargokit は toolchain の解決に `rustup` コマンドを直接呼ぶため
  （`rustup toolchain list` 等）、Homebrew 等で `cargo`/`rustc` だけ単独導入した
  環境では動きません。[rustup.rs](https://rustup.rs/) 経由で入れてください
  ```bash
  rustup --version
  rustc --version
  cargo --version
  ```

### プラットフォーム別要件

現行のランナーは macOS / Linux / Windows です。Windows は x64 debug bundle の
CI ビルドを対象とし、実機の操作確認が残っています。Android はランナー未作成です。

#### macOS開発（現行対応）
- 最新の安定版 Xcode（macOS 13 以上をターゲットにできるもの。Flutter の native assets が
  macOS 13 を要求する）
- CocoaPods

#### Linux開発（現行対応）
- Clang
- CMake 3.10以上
- GTK 3.0 development headers
- pkg-config
- libayatana-appindicator3 development headers（タスクトレイ、#15）
- libkeybinder-3.0 development headers（グローバルホットキー、#63）

ビルド時は `-dev` パッケージ、実行時はそれぞれの共有ライブラリ本体が必要。Ubuntu では
`sudo apt-get install libayatana-appindicator3-dev libkeybinder-3.0-dev`。実行時の共有
ライブラリは通常 `-dev` パッケージの依存で一緒に入る。

#### Android開発（計画中）
- Android Studio
- Android SDK (API 23以上)
- Java Development Kit (JDK) 11以上

#### Windows開発（debug runner）
- Visual Studio 2022 (C++ desktop development)
- Windows 10/11 SDK
- Visual Studio の「C++ によるデスクトップ開発」ワークロード
- Rust は `x86_64-pc-windows-msvc` ターゲットを使用（rustup 経由）

## セットアップ手順

### 1. リポジトリのクローン

```bash
git clone https://github.com/kako-jun/universal-experience.git
cd universal-experience
```

### 2. 依存関係のインストール

```bash
# メインアプリの依存関係
flutter pub get
```

### Flutter SDK を更新する場合

`pubspec.yaml` の `environment.flutter` だけを変更します。CI は全ワークフローでこの値を
読むため、ワークフローごとのバージョン更新は不要です。更新後は `flutter pub get`、
`flutter analyze`、`flutter test` と対象プラットフォームのビルドを実行し、必要なら
`pubspec.lock` と生成物を同じ変更に含めてください。FRB の生成物も
`tools/check_frb_drift.sh` で検証します。

> 旧バージョンには `plugins/color_vision_filter` という自作プラグインがあり、
> ここで別途 `flutter pub get` が必要でしたが、#13 でプラグインを撤去し色変換
> アルゴリズムを sensus crate に一元化したため、その手順はもう不要です。

### 3. プラットフォームの確認

サポートされているプラットフォームを確認：

```bash
flutter devices
```

## アプリの実行

### デバッグモードで実行

```bash
# デフォルトデバイスで実行
flutter run

# 特定のデバイスで実行
flutter run -d <device-id>
```

Windows では `flutter run -d windows` を使います。Android はランナー未作成です。

### リリースビルド

```bash
# macOSリリースビルド
flutter build macos --release

# Linuxリリースビルド
flutter build linux --release
```

`vX.Y.Z` タグを push すると Release workflow が既存のデスクトップ対応 OS の
配布物を検証し、同じ GitHub Release に公開します。

- Windows x64: `universal-experience-windows-x64.zip`。展開後は DLL と `data/` を
  同じ場所に保ち、`universal_experience.exe` を起動します。
- macOS: `universal-experience-macos.dmg`。アプリを Applications へ
  ドラッグします（未署名）。
- Linux x64: `universal-experience-linux-x64.tar.gz`。展開後は `lib/` と `data/` を
  同じ場所に保ち、`universal_experience` を起動します。

Windows x64 ホストでは `flutter build windows --release`、macOS では
`flutter build macos --release`、Linux では `flutter build linux --release` で
各配布用 bundle をビルドできます。
実機では画面表示・フィルタ選択・サンプル切替・トレイ・ホットキー・クリップボード・
PNG書き出しを確認します。アプリは未署名で、インストーラ形式ではありません。
Android はランナー未作成です。

## プロジェクト構造

```
universal-experience/
├── lib/                    # Dartソースコード
│   ├── main.dart          # アプリエントリーポイント
│   ├── l10n/              # 多言語化（ARB: app_en.arb / app_ja.arb と生成物。ja/en）
│   ├── models/            # データモデル
│   ├── services/          # ビジネスロジック（VisionFilterState = 選択状態の唯一の正本、export_service.dart 等）
│   ├── rendering/         # GPU シェーダ描画（sensus 由来の FragmentProgram）
│   ├── src/rust/          # flutter_rust_bridge 生成コード（sensus-core 連携、experiences() 等）
│   └── ui/                # UIコンポーネント
├── rust/                  # sensus-core を FRB で公開する Rust crate（Dart バインディング lib/src/rust/ の生成元）
├── rust_builder/          # cargokit 統合（#55）。flutter build/run 時に rust/ をビルドし同梱する FFI plugin
├── tools/                 # シェーダ codegen（sensus の .frag → Impeller サブセット変換）、FRB 生成物のドリフト検証（check_frb_drift.sh）、サンプル画像の生成（generate_samples.dart）と OFL フォントのアトラス（fonts/）
├── shaders/               # 変換済み .frag（ビルド時 impellerc がコンパイル）
├── macos/                 # macOS固有コード（現行対応）
├── linux/                 # Linux固有コード（現行対応）
├── windows/               # Windows固有コード（x64 debug runner）
├── docs/                  # ドキュメント
└── test/                  # テスト
```

Android 固有ディレクトリ（`android/`）はランナー未作成のため存在しません。

## 開発ワークフロー

### コードの変更を監視

`flutter run` で起動したセッションに `r`（hot reload）/ `R`（hot restart）を
入力すると、コード変更を即座に反映できます（`flutter run --hot-reload` という
コマンドラインオプションはありません）。

### 静的解析

```bash
flutter analyze
```

### テストの実行

```bash
# 全テスト実行
flutter test

# 特定のテスト実行
flutter test test/vision_filter_state_test.dart
```

### FRB 生成物のドリフト検証

`rust/src/api/` を変えたら `flutter_rust_bridge_codegen generate` を実行して `lib/src/rust/`
と `rust/src/frb_generated.rs` の差分をコミットする。同期しているかは次で確認でき、
CI の `check` job でも同じスクリプトを実行する（#88）。差分があれば非 0 で終了し、
実行後に作業ツリーは元の内容へ戻る。

```bash
tools/check_frb_drift.sh
```

前提は次の 2 つのインストール（版は CI と揃える。cargo-expand は
`.github/workflows/ci.yml` の `CARGO_EXPAND_VERSION`、codegen は `rust/Cargo.toml` の
`flutter_rust_bridge = "=X.Y.Z"` が正。下記は 2026-09 時点の値）。

```bash
cargo install cargo-expand --version 1.0.126 --locked
cargo install flutter_rust_bridge_codegen --version 2.11.1 --locked
```

### サンプル画像・フォントアトラスの同期検証

`assets/samples/*.png` は `tools/generate_samples.dart` の生成物、`tools/fonts/` は
`tools/generate_font_atlases.py` の生成物で、どちらもコミットしてある。スクリプトや
アトラスを変えたら再生成して差分をコミットする（アトラスを変えたら PNG も）。

```bash
dart run tools/generate_samples.dart
# フォントの文字集合を変えたときだけ（ネットワークが要る）:
uv run --with pillow==12.3.0 python3 tools/generate_font_atlases.py
```

再生成し忘れは CI が落とす（#115）。`samples-sync` ワークフロー（`.github/workflows/samples-sync.yml`）は
生成結果と `assets/samples` が一致しなければ失敗し、`font-atlas-sync`
ワークフロー（`.github/workflows/font-atlas-sync.yml`）は `tools/fonts` について同じ検証をする。
どちらも対象ファイルを変えた push/PR と手動実行（`workflow_dispatch`）でだけ起動する（通常の PR の CI 時間は増えない）。

### コードフォーマット

```bash
dart format lib/ test/
```

（`flutter format` は廃止されたコマンドです。）

## トラブルシューティング

### よくある問題

#### 1. "Flutter SDK not found"

```bash
# Flutterのパスを確認
which flutter

# パスを追加（例：bash）
export PATH="$PATH:/path/to/flutter/bin"
```

#### 2. macOSビルドエラー

```bash
cd macos
pod install
cd ..
```

#### 3. Rust ビルドエラー（`cargokit`, `cargo build failed` 等）

`rust_builder/`（cargokit 統合、#55）が `flutter build` / `flutter run` の
たびに裏で `cargo build` を実行します。Rust toolchain が入っていない、
rustup 経由で入れていない、または `rust/` の `cargo build` 自体が失敗する
環境ではここで落ちます。

```bash
# rustup 経由で入っているか確認する（cargokit は rustup を直接呼ぶ）
rustup --version

# rust/ 単体でビルドが通るか確認する
cd rust
cargo build
cd ..
```

### ログの確認

```bash
# 詳細ログで実行
flutter run -v

# デバッグログ出力
flutter logs
```

## 次のステップ

- [アーキテクチャドキュメント](ARCHITECTURE.md)を読む
- [プラットフォームAPI調査](PLATFORM_APIS.md)を確認
- [色覚アルゴリズム](COLOR_ALGORITHM.md)を理解する
- コントリビューション方法を確認

## ヘルプ

問題が発生した場合：

1. [GitHub Issues](https://github.com/kako-jun/universal-experience/issues)を確認
2. 新しいIssueを作成
3. Discussionsで質問

---

Happy Coding! 🚀
