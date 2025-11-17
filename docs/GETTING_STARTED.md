# Getting Started with Universal Experience

このガイドでは、Universal Experienceの開発環境のセットアップから実行までを説明します。

## 前提条件

### 必須ツール

- **Flutter SDK**: 3.2.0以上
  ```bash
  flutter --version
  ```

- **Git**: バージョン管理用

### プラットフォーム別要件

#### Android開発
- Android Studio
- Android SDK (API 23以上)
- Java Development Kit (JDK) 11以上

#### Windows開発
- Visual Studio 2022 (C++ desktop development)
- Windows 10/11 SDK

#### macOS開発
- Xcode 14以上
- CocoaPods

#### Linux開発
- Clang
- CMake 3.10以上
- GTK 3.0 development headers
- pkg-config

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

# プラグインの依存関係
cd plugins/color_vision_filter
flutter pub get
cd ../..
```

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

# Windowsで実行
flutter run -d windows

# Androidで実行
flutter run -d <android-device-id>
```

### リリースビルド

```bash
# Windowsリリースビルド
flutter build windows --release

# Androidリリースビルド
flutter build apk --release

# macOSリリースビルド
flutter build macos --release

# Linuxリリースビルド
flutter build linux --release
```

## プロジェクト構造

```
universal-experience/
├── lib/                    # Dartソースコード
│   ├── main.dart          # アプリエントリーポイント
│   ├── models/            # データモデル
│   ├── services/          # ビジネスロジック
│   ├── ui/                # UIコンポーネント
│   └── core/              # コアアルゴリズム
├── plugins/               # ネイティブプラグイン
│   └── color_vision_filter/
├── android/               # Android固有コード
├── windows/               # Windows固有コード
├── macos/                 # macOS固有コード
├── linux/                 # Linux固有コード
├── docs/                  # ドキュメント
└── test/                  # テスト
```

## 開発ワークフロー

### コードの変更を監視

```bash
flutter run --hot-reload
```

ホットリロードで、コード変更を即座に反映できます。

### 静的解析

```bash
flutter analyze
```

### テストの実行

```bash
# 全テスト実行
flutter test

# 特定のテスト実行
flutter test test/models/disability_type_test.dart
```

### コードフォーマット

```bash
flutter format lib/ test/
```

## トラブルシューティング

### よくある問題

#### 1. "Flutter SDK not found"

```bash
# Flutterのパスを確認
which flutter

# パスを追加（例：bash）
export PATH="$PATH:/path/to/flutter/bin"
```

#### 2. Android依存関係エラー

```bash
cd android
./gradlew clean
cd ..
flutter clean
flutter pub get
```

#### 3. Windows Magnification APIエラー

- Windows SDKがインストールされているか確認
- Visual Studio 2022でC++デスクトップ開発をインストール

#### 4. macOSビルドエラー

```bash
cd macos
pod install
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
