# Universal Experience

色覚障害・聴覚障害など、複数の感覚障害をシミュレーションできるアクセシビリティ体験アプリ。

**「すべての感覚を、すべての人に。」**

## 機能

### 色覚障害シミュレーション

- Protanopia（1型色覚・赤色盲）
- Deuteranopia（2型色覚・緑色盲）
- Tritanopia（3型色覚・青黄色盲）
- Achromatopsia（全色盲）
- Protanomaly / Deuteranomaly / Tritanomaly（各2色覚）

色覚変換アルゴリズムの正本は別 crate
[`sensus-core`](https://crates.io/crates/sensus-core)（Rust）に一元化しており、
ue はそれを flutter_rust_bridge 経由で消費する薄いブリッジです（ue は LMS 等の
変換ロジックを再実装しません）。フィルタの見え方は sensus 由来の GPU シェーダ
（`lib/rendering/shader_filter.dart`）で計算し、強度調整も可能です。

> 旧バージョンは OS 全体へ system-wide フィルタを適用する独自プラグイン
> （`plugins/color_vision_filter`）と ue 内 LMS 実装を持っていましたが、
> sensus 一元化に伴い撤去しました。ライブ画面（他アプリ含む全画面）への
> 適用は、画面キャプチャ経路の実装後に対応予定です。

### 計画中

- 聴覚障害シミュレーション（高音/低音カット、ノイズ追加）
- 視野欠損シミュレーション
- 視覚ぼやけ効果

## 対応プラットフォーム

- Android 6.0+
- Windows 10/11
- macOS 10.14+
- Linux (Ubuntu 20.04+)

※ iOS は技術的制約により非対応

## セットアップ

```bash
git clone https://github.com/kako-jun/universal-experience.git
cd universal-experience
flutter pub get
flutter run
```

## 技術スタック

- Flutter 3.2+
- Provider (状態管理)
- Material Design 3
- 色覚アルゴリズムは [`sensus-core`](https://crates.io/crates/sensus-core)（Rust crate）が正本。
  ue は flutter_rust_bridge 経由で消費（詳細は `docs/sensus-integration.md`）

## ライセンス

MIT
