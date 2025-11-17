# Platform-Specific APIs Research

各プラットフォームでのシステム全体への色覚フィルタ適用のための技術調査結果。

## Android Implementation

### アプローチ: AccessibilityService + Overlay

#### 主要API

**AccessibilityService**
- `android.accessibilityservice.AccessibilityService`
- システム全体のイベントを監視し、オーバーレイを描画可能

**Window Overlay**
```kotlin
// WindowManager.LayoutParams設定
val params = WindowManager.LayoutParams(
    WindowManager.LayoutParams.MATCH_PARENT,
    WindowManager.LayoutParams.MATCH_PARENT,
    WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
    PixelFormat.TRANSLUCENT
)
```

**Color Filter Application**
```kotlin
// ColorMatrixを使用した色変換
val colorMatrix = ColorMatrix()
// LMS変換行列を設定
colorMatrix.set(lmsMatrix)

val paint = Paint()
paint.colorFilter = ColorMatrixColorFilter(colorMatrix)
```

#### 実装戦略

1. **AccessibilityServiceの登録**
   - `AndroidManifest.xml`でサービス宣言
   - `accessibility_service_config.xml`で設定定義
   - 必要な権限: `BIND_ACCESSIBILITY_SERVICE`

2. **オーバーレイビューの作成**
   - `TYPE_ACCESSIBILITY_OVERLAY`を使用（`SYSTEM_ALERT_WINDOW`権限不要）
   - 透明な`SurfaceView`または`View`を全画面に配置
   - ハードウェアアクセラレーションを有効化

3. **リアルタイム描画**
   - `onDraw()`で`ColorMatrix`を適用
   - GPUアクセラレーション活用でパフォーマンス維持
   - 60fps目標

#### 利点
- ユーザー操作を阻害しない（`FLAG_NOT_TOUCHABLE`）
- システムアラート権限不要
- Android 6.0 (API 23)以上で動作

#### 課題
- バッテリー消費の最適化が必要
- 一部アプリ（セキュアコンテンツ）で機能しない可能性
- リアルタイム処理のパフォーマンス調整

---

## Windows Implementation

### アプローチ: Magnification API

#### 主要API

**Magnification API**
- `MagInitialize()`: API初期化
- `MagSetFullscreenColorEffect()`: システム全体に色変換適用
- `MagGetColorEffect()`: 現在の色変換取得
- `MagUninitialize()`: API終了

**Color Effect Structure**
```cpp
typedef struct tagMAGCOLOREFFECT {
    float transform[5][5];
} MAGCOLOREFFECT;
```

5×5の色変換行列：
```
[ R' ]   [ m11 m12 m13 m14 m15 ]   [ R ]
[ G' ]   [ m21 m22 m23 m24 m25 ]   [ G ]
[ B' ] = [ m31 m32 m33 m34 m35 ] × [ B ]
[ A' ]   [ m41 m42 m43 m44 m45 ]   [ A ]
[ 1  ]   [ m51 m52 m53 m54 m55 ]   [ 1 ]
```

#### 実装戦略

1. **初期化**
```cpp
BOOL success = MagInitialize();
if (!success) {
    // エラーハンドリング
}
```

2. **色変換行列の適用**
```cpp
MAGCOLOREFFECT colorEffect;
// LMS変換行列を設定
// ... 行列計算 ...

BOOL result = MagSetFullscreenColorEffect(&colorEffect);
```

3. **解除**
```cpp
// 単位行列を適用してリセット
MAGCOLOREFFECT identityMatrix = {
    1.0f, 0.0f, 0.0f, 0.0f, 0.0f,
    0.0f, 1.0f, 0.0f, 0.0f, 0.0f,
    0.0f, 0.0f, 1.0f, 0.0f, 0.0f,
    0.0f, 0.0f, 0.0f, 1.0f, 0.0f,
    0.0f, 0.0f, 0.0f, 0.0f, 1.0f
};
MagSetFullscreenColorEffect(&identityMatrix);
MagUninitialize();
```

#### システム要件
- Windows Vista以降
- WDDM (Windows Display Driver Model)対応ビデオカード
- 管理者権限不要

#### 利点
- システムレベルの統合
- 高パフォーマンス（ハードウェアアクセラレーション）
- フルスクリーン全体に適用
- バッテリー消費が少ない

#### 課題
- 古いグラフィックドライバでは非対応の可能性
- 一部のゲームやフルスクリーンアプリで無効

---

## macOS Implementation

### アプローチ: CoreGraphics Private APIs / Display Filters

#### 主要API（警告: 一部はPrivate API）

**公開API**
- `CGSetDisplayTransferByTable()`: ガンマテーブル操作

**非公開API（使用注意）**
- `CGDisplayUsesForceToGray()`
- `CGDisplayForceToGray()`
- `CGDisplayUsesInvertedPolarity()`
- `CGDisplaySetInvertedPolarity()`

#### 実装戦略（推奨）

macOSでは、Private APIの使用はApp Store配布で却下される可能性があるため、公開APIを使用します：

**1. ガンマテーブル方式**
```swift
func applyColorFilter(type: ColorVisionType) {
    let tableSize: UInt32 = 256
    var redTable = [CGGammaValue](repeating: 0, count: Int(tableSize))
    var greenTable = [CGGammaValue](repeating: 0, count: Int(tableSize))
    var blueTable = [CGGammaValue](repeating: 0, count: Int(tableSize))

    // LMS変換に基づいてガンマテーブルを計算
    for i in 0..<Int(tableSize) {
        let normalized = CGGammaValue(i) / CGGammaValue(tableSize - 1)
        // ... LMS変換計算 ...
        redTable[i] = transformedRed
        greenTable[i] = transformedGreen
        blueTable[i] = transformedBlue
    }

    CGSetDisplayTransferByTable(
        CGMainDisplayID(),
        tableSize,
        &redTable,
        &greenTable,
        &blueTable
    )
}
```

**2. 設定ファイル方式（代替）**
- `~/Library/Preferences/com.apple.CoreGraphics.plist`
- `~/Library/Preferences/com.apple.universalaccess.plist`
- ただし、これらの直接操作は非推奨

#### システム要件
- macOS 10.14 (Mojave)以降
- アクセシビリティ権限が必要な場合がある

#### 利点
- 公開APIのみで実装可能
- システム全体に適用

#### 課題
- Private APIは将来的に動作保証なし（特にApple Siliconで問題報告あり）
- ガンマテーブル方式は精度に限界がある
- サンドボックスアプリでの制限

#### 代替アプローチ
1. ユーザーに「システム設定」でカラーフィルタを有効にするよう案内
2. アプリ内プレビュー機能のみ提供
3. Helper Toolとしてインストール（権限昇格）

---

## Linux Implementation

### アプローチ: Display Server別対応

Linuxは複数のディスプレイサーバーが存在するため、それぞれに対応が必要：

#### Wayland対応

**Compositor連携**
- Waylandでは、compositorがすべての描画を管理
- compositor pluginまたはprotocol extensionが必要

**実装例（GNOME Shell Extension）**
```javascript
// GNOME Shell Extension
const { Clutter, St } = imports.gi;

function applyColorFilter() {
    let effect = new Clutter.ColorizeEffect();
    // または Clutter.DesaturateEffect, カスタムShaderEffect

    global.stage.add_effect(effect);
}
```

**KWin Effects（KDE Plasma）**
```cpp
// KWin Script
effects.windowAdded.connect(function(window) {
    window.colorize = true;
    // カラーエフェクト適用
});
```

#### X11対応

**XRandR Gamma Correction**
```cpp
#include <X11/extensions/Xrandr.h>

void applyGamma(Display* display) {
    Window root = DefaultRootWindow(display);
    XRRScreenResources* resources = XRRGetScreenResources(display, root);

    for (int i = 0; i < resources->ncrtc; i++) {
        XRRCrtcInfo* crtc_info = XRRGetCrtcInfo(display, resources,
                                                 resources->crtcs[i]);

        int size = XRRGetCrtcGammaSize(display, resources->crtcs[i]);
        XRRCrtcGamma* gamma = XRRAllocGamma(size);

        // ガンマ値を計算
        for (int j = 0; j < size; j++) {
            // LMS変換に基づく計算
            gamma->red[j] = /* ... */;
            gamma->green[j] = /* ... */;
            gamma->blue[j] = /* ... */;
        }

        XRRSetCrtcGamma(display, resources->crtcs[i], gamma);
        XRRFreeGamma(gamma);
    }
}
```

#### Compositor Plugins

**Compton/Picom**
- GLXバックエンドでカスタムシェーダー適用可能
- 設定ファイルでフィルタ指定

#### 利点
- オープンソースで柔軟なカスタマイズ
- 各環境に最適化可能

#### 課題
- ディスプレイサーバー・デスクトップ環境の多様性
- 環境ごとの実装が必要
- 互換性テストの負荷

#### 推奨戦略
1. **第一優先**: Wayland GNOME/KDE対応（主要シェア）
2. **第二優先**: X11 XRandR対応（レガシーサポート）
3. **将来**: その他環境への段階的対応

---

## 権限管理まとめ

| Platform | 必要な権限 | ユーザー操作 |
|----------|-----------|------------|
| Android | `BIND_ACCESSIBILITY_SERVICE` | 初回設定で有効化必要 |
| Windows | なし | 不要 |
| macOS | アクセシビリティ権限（場合による） | 初回許可が必要な場合あり |
| Linux | ディスプレイサーバー依存 | 環境による |

---

## パフォーマンス考慮事項

### Android
- ハードウェアアクセラレーション必須
- バッテリー最適化の除外リスト追加を推奨

### Windows
- WDDM対応ドライバー必須
- ほぼゼロオーバーヘッド

### macOS
- ガンマテーブル更新は軽量
- システム統合によりオーバーヘッド最小

### Linux
- Compositorの性能に依存
- GLXシェーダーは高速

---

## セキュリティ考慮事項

### Android
- AccessibilityServiceは強力な権限
- Google Playでの審査が厳格
- 使用目的の明確な説明が必要

### Windows
- Magnification APIは安全
- マルウェアでの悪用例は少ない

### macOS
- Private API使用はApp Store却下リスク
- 公開API推奨

### Linux
- オープンソースで透明性確保
- Compositorプラグインは信頼が重要

---

## 次のステップ

1. ✅ API調査完了
2. ⬜ プラットフォーム別プロトタイプ実装
3. ⬜ パフォーマンステスト
4. ⬜ 権限フロー設計
5. ⬜ エラーハンドリング戦略
