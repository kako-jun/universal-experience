# 設計方針と技術的決定事項

## 🏗️ アーキテクチャ設計

### レイヤードアーキテクチャ採用

```
┌─────────────────────────────────┐
│   Presentation Layer            │
│   (Flutter UI)                  │
├─────────────────────────────────┤
│   Business Logic Layer          │
│   (Services, State Management)  │
├─────────────────────────────────┤
│   Platform Channel Layer        │
│   (Method Channel Interface)    │
├─────────────────────────────────┤
│   Native Implementation Layer   │
│   (Platform-specific code)      │
├─────────────────────────────────┤
│   OS System APIs                │
│   (Graphics, Accessibility)     │
└─────────────────────────────────┘
```

**理由**:
- 関心の分離（Separation of Concerns）
- プラットフォーム固有コードの隔離
- テスタビリティの向上
- 保守性の確保

### Flutter採用の決定

**選定理由**:
1. **クロスプラットフォーム**: 単一コードベースで複数OS対応
2. **パフォーマンス**: ネイティブに近い性能
3. **Material Design 3**: 最新のUIコンポーネント
4. **ホットリロード**: 高速な開発サイクル
5. **コミュニティ**: 活発なエコシステム

**代替案との比較**:
- React Native: パフォーマンスでFlutterが優位
- Electron: デスクトップ特化だがモバイル非対応
- ネイティブ個別開発: 開発コスト大、保守性低

### 状態管理: Provider

**選定理由**:
- Flutterチーム推奨
- シンプルで学習コスト低
- 十分なパフォーマンス
- InheritedWidgetベースで安定

**代替案**:
- Riverpod: より高機能だが、現段階では過剰
- BLoC: 学習コストが高い
- GetX: 将来的な保守性に懸念

**拡張計画**: 必要に応じてRiverpodへ移行可能な設計

## 🎨 UI/UX設計

### Material Design 3 採用

**理由**:
- モダンで洗練されたデザイン
- アクセシビリティのベストプラクティス
- Dynamic Colorサポート
- クロスプラットフォーム一貫性

### テーマ戦略

```dart
// Light & Dark Theme
- システム設定に追従
- 高コントラストモード対応（将来）
- カラーブラインドネス配慮
```

### レスポンシブデザイン

```
Mobile:  < 600dp
Tablet:  600-840dp
Desktop: > 840dp
```

- ConstrainedBox で最大幅制限（800dp）
- 柔軟なレイアウト（Column, Wrap）
- デスクトップでのウィンドウサイズ最適化

## 🔬 色覚アルゴリズム設計

### LMS色空間変換の採用

**選定理由**:
1. **科学的正確性**: 人間の視覚システムに基づく
2. **医学的検証**: 研究論文で広く使用
3. **計算効率**: 行列演算で高速処理

### 変換パイプライン

```
RGB → LMS → CVD Simulation → LMS → RGB
```

**最適化**:
- 事前計算された変換行列
- 強度補間による柔軟性
- GPU アクセラレーション（将来）

### サポート色覚異常タイプ

| タイプ | 実装優先度 | 理由 |
|--------|----------|------|
| Deuteranopia | 最高 | 最も一般的（男性5%） |
| Protanopia | 高 | 一般的（男性1%） |
| Deuteranomaly | 高 | 非常に一般的 |
| Protanomaly | 中 | 比較的一般的 |
| Tritanopia | 中 | 稀だが重要 |
| Tritanomaly | 低 | 非常に稀 |
| Achromatopsia | 低 | 極めて稀だが完全性のため |

## 🖥️ プラットフォーム別実装戦略

### Android

**アプローチ**: AccessibilityService + Overlay

**技術スタック**:
- Language: Kotlin
- Min SDK: 23 (Android 6.0)
- Target SDK: 34 (Android 14)

**主要API**:
```kotlin
WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY
ColorMatrix + ColorMatrixColorFilter
Paint.setColorFilter()
```

**課題と対策**:
| 課題 | 対策 |
|------|------|
| バッテリー消費 | ハードウェアアクセラレーション、最適化 |
| セキュアコンテンツ | 制限事項として明記 |
| 権限取得 | 丁寧なオンボーディング |

### Windows

**アプローチ**: Magnification API

**技術スタック**:
- Language: C++
- Min Version: Windows 10
- SDK: Windows SDK 10.0.19041.0+

**主要API**:
```cpp
MagInitialize()
MagSetFullscreenColorEffect(&effect)
MAGCOLOREFFECT (5x5 matrix)
```

**利点**:
- システムレベル統合
- 高パフォーマンス
- 管理者権限不要
- バッテリー効率良好

### macOS

**アプローチ**: CoreGraphics Filters

**技術スタック**:
- Language: Swift
- Min Version: macOS 10.14 (Mojave)

**実装方針**:
```swift
// 公開APIのみ使用（App Store対応）
CGSetDisplayTransferByTable()

// Private API回避
// - CGDisplayForceToGray() ❌
// - CGDisplaySetInvertedPolarity() ❌
```

**課題**:
- Private API の誘惑に負けない
- ガンマテーブルの精度限界
- Apple Silicon対応の検証

### Linux

**アプローチ**: Compositor連携

**優先順位**:
1. Wayland (GNOME/KDE) - 主要環境
2. X11 (XRandR) - レガシーサポート
3. その他 - コミュニティ貢献に依存

**技術的選択**:
```bash
# GNOME Shell Extension
JavaScript + GJS

# KWin Effects
C++ + Qt

# X11 Fallback
C + XRandR
```

## 🔌 プラグインアーキテクチャ

### Federated Plugin Pattern

```
universal_experience (main app)
    ↓ depends on
color_vision_filter (plugin)
    ├── lib/ (Dart interface)
    ├── android/
    ├── windows/
    ├── macos/
    └── linux/
```

**利点**:
- モジュール性の向上
- 将来の拡張性（hearing_filter, etc.）
- 独立したテスト
- 再利用可能性

### Method Channel設計

```dart
// Dartサイド
MethodChannel('color_vision_filter')

// メソッド
- apply(type, intensity) → bool
- setIntensity(intensity) → bool
- remove() → bool
- getState() → Map
- hasPermission() → bool
- requestPermission() → bool
```

**設計原則**:
- 非同期処理（Future）
- エラーハンドリング必須
- 状態同期機能

## 📦 依存関係管理

### 最小依存の原則

**採用パッケージ**:
```yaml
provider: 状態管理（Flutter推奨）
window_manager: デスクトップウィンドウ制御
tray_manager: システムトレイ（将来）
path_provider: ファイルパス取得
shared_preferences: 設定保存
```

**意図的に避けたパッケージ**:
- 大規模状態管理ライブラリ（過剰）
- UI フレームワーク（Material Designで十分）
- HTTP クライアント（現時点で不要）

## 🔒 セキュリティ設計

### 権限最小化

**Android**:
```xml
<uses-permission android:name="android.permission.BIND_ACCESSIBILITY_SERVICE" />
<!-- SYSTEM_ALERT_WINDOW は AccessibilityService で不要 -->
```

**Windows**:
- 管理者権限不要
- Magnification API は標準権限

**macOS**:
- アクセシビリティ権限のみ
- Sandboxing 対応

### データプライバシー

**原則**:
- 画面データの一時保存なし
- ネットワーク通信なし（v1.0）
- 個人情報収集なし
- ローカル設定のみ

## ⚡ パフォーマンス設計

### 目標指標

```
フレームレート: 60fps維持
起動時間: <2秒
メモリ使用: <100MB
CPU使用率: <5% (アイドル時)
バッテリー影響: <5%増
```

### 最適化戦略

1. **事前計算**:
   - 変換行列の事前生成
   - LUT (Look-Up Table) 活用可能性

2. **ハードウェアアクセラレーション**:
   - Android: View.LAYER_TYPE_HARDWARE
   - Windows: WDDM対応
   - GPU シェーダー（将来）

3. **レイジーローディング**:
   - 必要時のみフィルタ適用
   - バックグラウンドでの最適化

## 📝 コーディング規約

### Dart Style Guide

```dart
// Flutter公式ガイドに準拠
- Effective Dart
- flutter_lints パッケージ使用
- prefer_const_constructors
- prefer_single_quotes
```

### ドキュメンテーション

```dart
/// DartDoc形式
///
/// [parameter] - パラメータ説明
/// Returns: 戻り値説明
```

### ファイル構造

```
lib/
├── main.dart               # エントリーポイント
├── models/                 # データモデル
├── services/               # ビジネスロジック
├── ui/
│   ├── screens/           # 画面
│   ├── widgets/           # 再利用可能ウィジェット
│   └── theme/             # テーマ定義
├── core/                   # コアアルゴリズム
└── utils/                  # ユーティリティ
```

## 🧪 テスト戦略

### テストピラミッド

```
         ╱ E2E Tests (5%)
       ╱─────────────
     ╱ Widget Tests (20%)
   ╱───────────────────────
 ╱ Unit Tests (75%)
```

### カバレッジ目標

- Unit Tests: 80%+
- Widget Tests: 60%+
- Integration Tests: 主要フロー

### CI/CD計画

```yaml
# GitHub Actions (予定)
- flutter analyze
- flutter test
- flutter build (all platforms)
- dartdoc generation
```

## 🔄 バージョニング戦略

### Semantic Versioning

```
MAJOR.MINOR.PATCH

例: 0.1.0 → 1.0.0 → 1.1.0 → 2.0.0
```

**ルール**:
- MAJOR: 破壊的変更
- MINOR: 機能追加（後方互換）
- PATCH: バグフィックス

### リリースサイクル

```
v0.x.x: Alpha/Beta (内部テスト)
v1.0.0: 最初の安定版（Phase 1完成）
v1.x.x: Phase 1の改善
v2.0.0: Phase 2リリース（聴覚障害）
v3.0.0: Phase 3リリース（その他障害）
```

## 🌐 国際化 (i18n) 計画

### Phase 1対応言語

```
1. 日本語 (ja)
2. 英語 (en)
```

### 将来の拡張

```
優先度高:
- 中国語簡体字 (zh-CN)
- 韓国語 (ko)
- スペイン語 (es)

優先度中:
- フランス語 (fr)
- ドイツ語 (de)
- ポルトガル語 (pt)
```

### 実装方針

```dart
// flutter_localizations 使用
// ARB ファイル形式
lib/l10n/
├── app_en.arb
├── app_ja.arb
└── app_zh.arb
```

## 📊 分析とモニタリング

### Phase 1: 分析なし

**理由**:
- プライバシー優先
- オフライン完結
- ローカルログのみ

### Phase 2以降: オプトイン

**検討事項**:
- クラッシュレポート（匿名）
- 使用統計（集計のみ）
- パフォーマンス指標

**原則**:
- 完全オプトイン
- 透明性の確保
- データ最小化

## 🔮 技術的負債管理

### 意図的な負債

1. **macOS/Linux実装の延期**
   - 理由: リソース集中（Android/Windows優先）
   - 返済計画: Phase 1完成後

2. **システムトレイ機能の延期**
   - 理由: コア機能優先
   - 返済計画: v1.1.0

3. **テストカバレッジ**
   - 現状: コアロジックのみ
   - 目標: 段階的に80%+

### 回避する負債

- ❌ Private API使用（macOS）
- ❌ ハードコーディング
- ❌ グローバル状態の乱用
- ❌ プラットフォーム間の重複コード

---

**これらの設計決定は、プロジェクトの成功と長期的な保守性を確保するための基盤です。**
