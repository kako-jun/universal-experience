# Architecture Design

> **現状（#13 反映）**: 本ドキュメントが「Platform Channel Layer」「Native
> Implementation Layer」「OS-Specific Filter Application」として記述する
> system-wide フィルタ機構（`color_vision_filter` プラグイン／`ColorVisionFilter.apply`
> 等）は **撤去済み**。色覚アルゴリズムの正本は sensus-core crate（Rust）に一元化し、
> ue は flutter_rust_bridge 経由で消費する（`lib/src/rust/`、詳細は
> `docs/sensus-integration.md`）。フィルタ適用は sensus 由来の GPU シェーダ
> （`lib/rendering/shader_filter.dart`）が担い、`FilterService` は選択状態のみを
> 保持する。他アプリ含む全画面への適用は画面キャプチャ経路（#1/#3/#4）の実装後。
> 以下の Platform Channel / Native 実装の節は当初設計の歴史的記述として残す。

## ルーペ窓挙動 (#14)

ルーペ窓のウィンドウ設定の責務。実装は `lib/services/loupe_window_controller.dart`
(window_manager ラッパ + 純粋ロジック `LoupeWindowPolicy`) と `lib/main.dart` の配線。
画面キャプチャ (#3/#4/#5)・ライブ適用・描画 (#11)・フィルタ UI (#16)・トレイ (#15) は本節のスコープ外。

### 最小サイズ

- **320x240 (QVGA, 4:3)**。従来の 600x400 から引き下げた。
- 根拠: ルーペは「画面の一部に小さくかざす」使い方が主眼。320px あれば
  色覚/視野/コントラストのフィルタ差は判別できる下限。これ以下だと枠操作
  領域が窮屈で実用性を失う。4:3 は覗き窓の直感的比率 (アスペクト強制ではなく、
  リサイズで自由に変えられる)。

### 状態遷移と枠ポリシー

状態は enum `LoupeWindowMode { normal, maximized, fullscreen }`。

| モード | 縁(フレーム/タイトルバー) | 用途 |
|---|---|---|
| normal | あり | 通常。掴んで移動・リサイズ |
| maximized | **あり** | 画面いっぱいでも縁を残す |
| fullscreen | なし | 没入。画面全域をフィルタ |

- 最大化で **縁を残す**のが要点。ルーペは「枠の向こうにフィルタ済みデスクトップ」
  が見える体験なので、最大化で縁が消えると「どこが覗き窓か」が破綻する。
  全画面だけは没入用に縁を消す。
- 遷移は `LoupeWindowPolicy.resolveMode` (純粋関数) で解決。toggle 系は
  同じモード再要求で normal に戻る。実 I/O は window_manager の
  `maximize`/`unmaximize`/`setFullScreen` + `setTitleBarStyle` で反映。

### リサイズ追従

`WindowListener.onWindowResize` でサイズを取得し state 更新 -> `onChanged`
コールバックで UI に伝える (中身がウィンドウに貼り付く責務)。

### 透過・最前面・クリックスルー (既定方針)

- **透明背景**: 既定 ON。枠の外は完全透過、枠の中だけ描画 (VIP-Sim / Sim Daltonism 型, #6)。
  `WindowOptions.backgroundColor = transparent`。
- **最前面**: 既定 ON (`setAlwaysOnTop(true)`)。下のアプリより手前にいないと
  「かざして見る」が成立しない。
- **クリックスルー**: 既定 **OFF**、切替式。起動直後は窓を掴んで移動・リサイズ
  したいのでイベントを受け取り、下のアプリを操作したいときユーザーが ON する。
  実装は `setIgnoreMouseEvents(true, forward: true)`。
- フレームレス/クリックスルー forward 引数はプラットフォーム差・未対応があるため、
  全 window_manager I/O は try/catch + ログで握り、未対応でも落とさない。

### マルチモニタ

- **第1弾はメインモニタのみ対象**。サブモニタへの移動追従や、モニタごとの
  DPR 換算 (#5) はスコープ外。window_manager のメインモニタ座標系で動作する前提。

### 実機目視について

透過・クリックスルー・最大化時の縁などの GUI 目視確認は、Wayland/grim 制約と
#11 描画統合前のため本実装段階では未実施。`flutter analyze` / `flutter test` /
`flutter build linux --debug` で静的・ビルド確認のみ。実機目視は #11 描画統合後に行う。

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
