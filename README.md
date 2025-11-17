# Universal Experience

**すべての感覚を、すべての人に。**

Universal Experienceは、色覚障害、聴覚障害など、複数の感覚障害をシミュレーションできる包括的なアクセシビリティ体験アプリケーションです。世界中の人々が障害を理解し、共感を深めることを目的としています。

## 🌟 コンセプト

- **決定版シミュレータ**: 乱立する障害体験アプリを統一する「ユニバーsal」な存在
- **グローバル対応**: 世界共通のUI・体験を提供
- **アクセシビリティ啓発**: 障害者への理解と配慮を推進
- **マルチプラットフォーム**: Android、Windows、macOS、Linuxをサポート

## ✨ 主要機能

### Phase 1: 色覚障害シミュレーション（開発中）

- **対応タイプ**:
  - Protanopia（1型色覚・赤色盲）
  - Deuteranopia（2型色覚・緑色盲）
  - Tritanopia（3型色覚・青黄色盲）
  - Achromatopsia（全色盲）
  - Protanomaly（1型2色覚）
  - Deuteranomaly（2型2色覚）
  - Tritanomaly（3型2色覚）

- **機能**:
  - システム全体へのリアルタイムフィルタ適用
  - 強度調整（0-100%）
  - 各タイプの詳細説明と有病率表示

### Phase 2: 聴覚障害シミュレーション（計画中）

- 高音・低音カット
- 環境ノイズ追加
- システム音声フィルタ

### Phase 3: その他の障害体験（計画中）

- 視野欠損シミュレーション
- 視覚ぼやけ効果
- 運動障害シミュレーション

## 🛠️ 技術構成

### アーキテクチャ

```
Flutter (UI & Common Logic)
    ↓
Native Plugins (Platform-specific)
    ↓
OS APIs (System-wide filters)
```

### プラットフォーム別実装

- **Android**: Accessibility Service + SurfaceView Overlay
- **Windows**: DirectComposition / GDI Hook
- **macOS**: CoreGraphics Filters
- **Linux**: Wayland / X11 Compositor Filters

### 技術スタック

- **フレームワーク**: Flutter 3.2+
- **状態管理**: Provider
- **UI**: Material Design 3
- **アルゴリズム**: LMS色空間変換 + Daltonization

## 📦 プロジェクト構造

```
universal-experience/
├── lib/                    # Flutter application
│   ├── main.dart
│   ├── models/            # Data models
│   ├── services/          # Business logic
│   ├── ui/                # UI components
│   │   ├── screens/
│   │   ├── widgets/
│   │   └── theme/
│   └── utils/             # Utilities
├── plugins/               # Platform plugins
│   └── color_vision_filter/
│       ├── lib/           # Dart interface
│       ├── android/       # Android implementation
│       ├── windows/       # Windows implementation
│       ├── macos/         # macOS implementation
│       └── linux/         # Linux implementation
├── docs/                  # Documentation
├── test/                  # Tests
└── assets/                # Resources
```

## 🚀 セットアップ

### 前提条件

- Flutter SDK 3.2.0以上
- 各プラットフォームの開発環境:
  - Android: Android Studio + Android SDK
  - Windows: Visual Studio 2022
  - macOS: Xcode
  - Linux: Clang, CMake, GTK development headers

### インストール

```bash
# リポジトリのクローン
git clone https://github.com/kako-jun/universal-experience.git
cd universal-experience

# 依存関係のインストール
flutter pub get

# プラグインのビルド
cd plugins/color_vision_filter
flutter pub get
cd ../..

# アプリの実行
flutter run
```

## 🎯 開発ロードマップ

- [x] **Phase 1.1**: プロジェクト構造設計
- [ ] **Phase 1.2**: 色覚障害アルゴリズム実装
- [ ] **Phase 1.3**: プラットフォーム別ネイティブプラグイン
- [ ] **Phase 1.4**: システム常駐機能
- [ ] **Phase 2**: 聴覚障害シミュレーション
- [ ] **Phase 3**: その他の障害体験機能

## 🤝 コントリビューション

Universal Experienceは、より多くの人にアクセシビリティの重要性を伝えるプロジェクトです。コントリビューションを歓迎します！

## 📄 ライセンス

MIT License

## 🌐 サポートプラットフォーム

- ✅ Android 6.0 (API 23) 以上
- ✅ Windows 10/11
- ✅ macOS 10.14 (Mojave) 以上
- ✅ Linux (Ubuntu 20.04+, Fedora 34+)
- ❌ iOS (Apple制約により非対応)

## 📞 連絡先

質問や提案がある場合は、Issueを作成してください。

---

**Universal Experience** - すべての感覚を、すべての人に。
