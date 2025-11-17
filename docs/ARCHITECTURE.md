# Architecture Design

## システムアーキテクチャ

Universal Experienceは、Flutterベースのクロスプラットフォームアプリケーションとして設計されています。

## レイヤー構造

```
┌─────────────────────────────────────────┐
│     Flutter UI Layer (Dart)             │
│  - Screens, Widgets, Theme              │
│  - User Interaction                     │
└─────────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────────┐
│  Business Logic Layer (Dart)            │
│  - FilterService (State Management)     │
│  - Models (DisabilityType, etc.)        │
└─────────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────────┐
│  Platform Channel Layer                 │
│  - Method Channel Interface             │
│  - Platform-specific Plugin API         │
└─────────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────────┐
│  Native Implementation Layer            │
│  - Android: Kotlin/Java                 │
│  - Windows: C++/C#                      │
│  - macOS: Swift/Objective-C             │
│  - Linux: C++                           │
└─────────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────────┐
│  OS System APIs                         │
│  - Graphics/Compositing APIs            │
│  - Accessibility Services               │
└─────────────────────────────────────────┘
```

## コンポーネント詳細

### 1. Flutter UI Layer

**責務**: ユーザーインターフェースの提供

**主要コンポーネント**:
- `HomeScreen`: メイン画面
- `FilterSelector`: フィルタタイプ選択UI
- `IntensitySlider`: 強度調整UI
- `AppTheme`: アプリ全体のテーマ定義

### 2. Business Logic Layer

**責務**: アプリケーションロジックと状態管理

**主要コンポーネント**:
- `FilterService`: フィルタの状態管理とプラットフォームへの指示
- `DisabilityType`: 障害タイプの定義
- `ColorVisionType`: 色覚障害タイプの詳細定義

### 3. Platform Channel Layer

**責務**: Dart ↔ ネイティブコード間の通信

**メソッド**:
```dart
// フィルタの適用
await ColorVisionFilter.apply(String type, double intensity)

// フィルタの強度変更
await ColorVisionFilter.setIntensity(double intensity)

// フィルタの解除
await ColorVisionFilter.remove()

// フィルタの状態取得
Map<String, dynamic> state = await ColorVisionFilter.getState()
```

### 4. Native Implementation Layer

各プラットフォーム固有の実装を提供します。

## プラットフォーム別実装戦略

### Android

**アプローチ**: Accessibility Service + Overlay

```
1. AccessibilityService登録
2. SurfaceViewでオーバーレイ作成
3. Canvas/Shaderで色変換処理
4. リアルタイム画面キャプチャ & フィルタ適用
```

**主要API**:
- `AccessibilityService`
- `WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY`
- `Canvas`, `Paint`, `ColorMatrix`

**課題**:
- パフォーマンス最適化
- バッテリー消費の管理

### Windows

**アプローチ**: Magnification API / DirectComposition

```
1. Magnification APIでシステム全体の色変換
2. ColorEffectで変換行列を設定
3. または DirectComposition で画面合成時にフィルタ
```

**主要API**:
- `MagSetFullscreenColorEffect`
- `MagInitialize`, `MagUninitialize`
- DirectComposition (Windows 8+)

**利点**:
- システムレベルの統合
- 高パフォーマンス

### macOS

**アプローチ**: Core Graphics Filters

```
1. CGDisplaySetDisplayFilters
2. Quartz FilterでLMS変換実装
3. システム全体に適用
```

**主要API**:
- `CGDisplaySetDisplayFilters`
- Core Image Filters
- Accessibility Inspector (開発用)

**注意**:
- macOS 10.14以降でAPI変更
- サンドボックス制限への対応

### Linux

**アプローチ**: Compositor連携

```
1. Wayland: wl_output filters
2. X11: XRandR gamma correction
3. または compton/picom compositorプラグイン
```

**主要API**:
- Wayland Protocol Extensions
- XRandR (X11)
- Compositor-specific plugin APIs

**課題**:
- ディスプレイサーバーの多様性
- 各環境での互換性確保

## データフロー

### フィルタ適用フロー

```
User Action (UI)
      ↓
FilterService.applyFilter()
      ↓
State Update (Provider)
      ↓
Platform Channel Call
      ↓
Native Plugin Handler
      ↓
OS-Specific Filter Application
      ↓
Visual Feedback to User
```

### 状態管理フロー

```
FilterService (ChangeNotifier)
      ↓
Consumer<FilterService> (UI)
      ↓
UI Rebuild on notifyListeners()
```

## セキュリティ考慮事項

1. **権限管理**:
   - Android: SYSTEM_ALERT_WINDOW, BIND_ACCESSIBILITY_SERVICE
   - macOS: Accessibility permissions
   - Linux: Compositor access

2. **サンドボックス**:
   - macOS App Sandboxでの制限事項
   - Windows UWP vs. Win32

3. **プライバシー**:
   - 画面キャプチャ時のデータ保護
   - 一時ファイルの暗号化

## パフォーマンス最適化

1. **リアルタイム処理**:
   - GPU アクセラレーション活用
   - シェーダーでの色変換
   - フレームレート維持 (60fps目標)

2. **リソース管理**:
   - メモリ使用量の監視
   - バッテリー消費の最適化
   - CPU使用率の制限

3. **起動時間**:
   - 遅延初期化
   - バックグラウンド起動

## 拡張性設計

### Phase 2: 聴覚障害対応

```
新規サービス: AudioFilterService
新規プラグイン: audio_filter
Platform APIs:
- Android: AudioEffect
- Windows: WASAPI
- macOS: Core Audio
- Linux: PulseAudio/ALSA
```

### Phase 3: その他の障害

```
モジュール化されたプラグインシステム
- vision_field_filter (視野欠損)
- blur_filter (視覚ぼやけ)
- tremor_simulator (振戦シミュレーション)
```

## テスト戦略

1. **ユニットテスト**:
   - モデル、サービスのロジックテスト
   - 色変換アルゴリズムの精度検証

2. **ウィジェットテスト**:
   - UI コンポーネントの動作確認
   - 状態変化の検証

3. **統合テスト**:
   - プラットフォームチャネルの通信テスト
   - エンドツーエンドフロー

4. **プラットフォームテスト**:
   - 各OS固有機能の動作確認
   - パフォーマンステスト

## デプロイメント

```
Development → Staging → Production

Channels:
- main: 安定版
- beta: ベータ版
- dev: 開発版
```

## 今後の技術的課題

1. ✅ 色覚フィルタアルゴリズムの実装
2. ⬜ プラットフォーム別ネイティブプラグイン開発
3. ⬜ システム常駐機能の実装
4. ⬜ パフォーマンス最適化
5. ⬜ CI/CDパイプライン構築
6. ⬜ 自動テストの拡充
