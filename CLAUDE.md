# Universal Experience 開発者向けドキュメント

感覚障害シミュレーションアプリ。「決定版」を目指し、乱立するシミュレータを統一する。

## コンセプト

### 3つの「ユニバーサル」

1. **Universal Global**: 世界共通のアプリ
2. **Universal Standard**: 科学的に正確なアルゴリズム
3. **Universal Coverage**: 複数の障害タイプに対応

## プロジェクト構造

```
lib/
├── main.dart
├── core/
│   └── color_vision_simulator.dart  # LMS変換アルゴリズム
├── models/
│   └── disability_type.dart         # 障害タイプ定義
├── services/
│   └── filter_service.dart          # フィルタ適用サービス
└── ui/
    ├── screens/home_screen.dart
    ├── widgets/
    │   ├── filter_selector.dart
    │   └── intensity_slider.dart
    └── theme/app_theme.dart

plugins/color_vision_filter/
├── lib/                    # Dart API
├── android/                # Kotlin実装
├── windows/                # C++実装
├── macos/                  # Swift実装（計画中）
└── linux/                  # C++実装（計画中）

docs/
├── ARCHITECTURE.md
├── COLOR_ALGORITHM.md
├── GETTING_STARTED.md
└── PLATFORM_APIS.md
```

## アーキテクチャ

```
Flutter UI (Presentation)
    ↓
Services / State (Provider)
    ↓
Platform Channel
    ↓
Native Plugin (Android/Windows/macOS/Linux)
    ↓
OS System APIs
```

## 色覚アルゴリズム

### LMS色空間変換

```
RGB → LMS → CVD Simulation → LMS → RGB
```

- 人間の視覚システムに基づく科学的手法
- 事前計算された変換行列で高速処理
- 強度補間による柔軟な調整

### 対応色覚異常

| タイプ | 有病率（男性） |
|--------|--------------|
| Deuteranopia | 5% |
| Protanopia | 1% |
| Deuteranomaly | 5% |
| Protanomaly | 1% |
| Tritanopia | 0.001% |

## プラットフォーム実装

### Android

- AccessibilityService + Overlay
- ColorMatrix + ColorMatrixColorFilter

### Windows

- Magnification API
- MAGCOLOREFFECT (5x5 matrix)

### macOS (計画中)

- CGSetDisplayTransferByTable (Public API)
- Private API回避でApp Store対応

### Linux (計画中)

- Wayland: GNOME Shell Extension / KWin Effects
- X11: XRandR fallback

## 設計判断

### Flutter採用

- クロスプラットフォーム効率
- ネイティブ並みの性能
- 活発なエコシステム

### Provider選定

- Flutterチーム推奨
- シンプルで学習コスト低
- 将来的にRiverpod移行可能

### iOS非対応

Appleのサンドボックス制約により、システム全体へのフィルタ適用が技術的に困難。

## ビルド

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

## ロードマップ

- **Phase 1**: 色覚障害シミュレーション（80%完成）
- **Phase 2**: 聴覚障害シミュレーション
- **Phase 3**: 視野欠損、視覚ぼやけ、運動障害
