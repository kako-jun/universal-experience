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

システム全体にリアルタイムフィルタを適用、強度調整可能。

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
cd plugins/color_vision_filter && flutter pub get && cd ../..
flutter run
```

## 技術スタック

- Flutter 3.2+
- Provider (状態管理)
- Material Design 3
- LMS色空間変換アルゴリズム

## ライセンス

MIT
