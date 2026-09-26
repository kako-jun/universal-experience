# Getting Started with Universal Experience

このガイドでは、Universal Experienceの開発環境のセットアップから実行までを説明します。

## 前提条件

### 必須ツール

- **Flutter SDK**: 3.38.4以上（`pubspec.lock` の `sdks` 準拠。`pubspec.yaml` の
  `sdk: '>=3.3.0 <4.0.0'` は flutter_rust_bridge の生成物が要求する下限にすぎない）
  ```bash
  flutter --version
  ```

- **Git**: バージョン管理用

- **Rust toolchain**（`rustc` / `cargo`, stable channel）: `rust/` crate
  （flutter_rust_bridge 経由で sensus-core を公開する）に必要。`cargo test` /
  clippy だけでなく、`rust_builder/`（cargokit 統合、#55）が `flutter run` /
  `flutter build macos` / `flutter build linux` のたびに `cargo build` を
  呼んで native lib をビルド・同梱するため、通常のアプリ実行にも要ります
  ```bash
  rustc --version
  cargo --version
  ```

### プラットフォーム別要件

現行でランナーがあり実際にビルド・実行できるのは macOS / Linux のみです。
Android / Windows は計画中で、ランナーディレクトリ自体がまだありません。

#### macOS開発（現行対応）
- 最新の安定版 Xcode（macOS 13 以上をターゲットにできるもの。Flutter の native assets が
  macOS 13 を要求する）
- CocoaPods

#### Linux開発（現行対応）
- Clang
- CMake 3.10以上
- GTK 3.0 development headers
- pkg-config

#### Android開発（計画中）
- Android Studio
- Android SDK (API 23以上)
- Java Development Kit (JDK) 11以上

#### Windows開発（計画中）
- Visual Studio 2022 (C++ desktop development)
- Windows 10/11 SDK

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

Windows / Android 向けの `-d windows` / `-d <android-device-id>` は、対応する
ランナーディレクトリ自体がまだ無いため現状使えません（計画中）。

### リリースビルド

```bash
# macOSリリースビルド
flutter build macos --release

# Linuxリリースビルド
flutter build linux --release
```

Windows / Android のビルド（`flutter build windows` / `flutter build apk`）は
ランナー未作成のため現状動きません（計画中）。

## プロジェクト構造

```
universal-experience/
├── lib/                    # Dartソースコード
│   ├── main.dart          # アプリエントリーポイント
│   ├── l10n/              # 多言語化（ARB: app_en.arb / app_ja.arb と生成物。ja/en）
│   ├── models/            # データモデル
│   ├── services/          # ビジネスロジック（FilterService = sensus への薄いブリッジ、export_service.dart 等）
│   ├── rendering/         # GPU シェーダ描画（sensus 由来の FragmentProgram）
│   ├── src/rust/          # flutter_rust_bridge 生成コード（sensus-core 連携、experiences() 等）
│   └── ui/                # UIコンポーネント
├── rust/                  # sensus-core を FRB で公開する Rust crate（Dart バインディング lib/src/rust/ の生成元）
├── rust_builder/          # cargokit 統合（#55）。flutter build/run 時に rust/ をビルドし同梱する FFI plugin
├── tools/                 # シェーダ codegen（sensus の .frag → Impeller サブセット変換）
├── shaders/               # 変換済み .frag（ビルド時 impellerc がコンパイル）
├── macos/                 # macOS固有コード（現行対応）
├── linux/                 # Linux固有コード（現行対応）
├── docs/                  # ドキュメント
└── test/                  # テスト
```

Android / Windows 固有ディレクトリ（`android/` / `windows/`）はランナー自体が
まだ無いため存在しません（計画中）。

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
flutter test test/filter_service_test.dart
```

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
たびに裏で `cargo build` を実行します。Rust toolchain が入っていない、または
`rust/` の `cargo build` 自体が失敗する環境ではここで落ちます。

```bash
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
