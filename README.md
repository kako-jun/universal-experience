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
ue はそれを flutter_rust_bridge 経由で消費する薄いブリッジです（ue 側で LMS 等の
変換ロジックを再実装する方針は取りません）。フィルタの見え方は sensus 由来の
GPU シェーダ（`lib/rendering/shader_filter.dart`）で計算し、強度調整も可能です。

> ただし現状、一部の uniform（シェーダへ渡す変換行列）は
> `lib/rendering/shader_filter.dart` に暫定的にハードコードされています
> （`TODO(#11後続)`）。これらは #11 後続で flutter_rust_bridge 経由の
> sensus-core 取得値へ置き換え、二重実装を解消する予定です。

> 旧バージョンは OS 全体へ system-wide フィルタを適用する独自プラグイン
> （`plugins/color_vision_filter`）と ue 内 LMS 実装を持っていましたが、
> sensus 一元化に伴い撤去しました。ライブ画面（他アプリ含む全画面）への
> 適用は、画面キャプチャ経路の実装後に対応予定です。

> 現状、before / after の比較プレビューで実際に描画できるのは
> protanopia / protanomaly のみです（protanomaly は protanopia の変換を
> 弱い強度で再利用）。それ以外の色覚 7 型・後述の advanced フィルタは、
> カタログから選択・パラメータ調整はできますが、ライブ描画は「coming soon」
> プレースホルダ表示で、GPU 描画配線は #11 後続で順次対応します。

### 視覚 advanced フィルタ（sensus カタログ）

sensus が提供する**計 30 種**（上記の色覚型を含む。屈折／視野欠損／
光・透明度／前庭・めまい／眼精疲労 等）の視覚フィルタをカタログから
カテゴリ別に選択し、パラメータ・強度を調整できます。フィルタ定義の正本は
sensus-core であり、ue はカタログ（`lib/models/vision_filter_catalog.dart`）
から引きます。
※ ライブ描画は上記の制約どおり一部のみ。

### 体験プリセット（複合症状）

複数の感覚にまたがる複合症状を、ワンタップで適用できる 4 つのプリセットを
用意しています:

- メニエール病（meniere）
- 良性発作性頭位めまい症（BPPV）
- 前庭神経炎（vestibular neuritis）
- 迷路炎（labyrinthitis）

各プリセットは視覚フィルタを選択状態にし、緊急度に応じた受診喚起の注記を
表示します。聴覚症状を含む体験（メニエール病・迷路炎）には「聴覚症状も含む」
注記を出しますが、**音声再生は未実装**で、現状は視覚フィルタの適用と注記の
表示にとどまります。プリセットの組み合わせ（どの視覚・聴覚フィルタが組に
なるか）の正本は sensus-core の `experiences()` です。

### 画像エクスポート（PNG）

フィルタ適用後（after）の画像を、**症状名・強度・日付（ISO・`YYYY-MM-DD`）**
を焼き込んだ PNG として書き出せます。保存後はファイルのフルパスを
クリップボードへコピーします。画像そのもののクリップボード書き込み・
動画エクスポートは非対応です（ライブ描画がある protanopia / protanomaly で
エクスポート可能）。

> 焼き込み機構は受診喚起の注記にも対応していますが、現状エクスポートできる
> 色覚特性は緊急度 none のため、受診喚起は焼き込まれません（advanced フィルタの
> live エクスポートに広げた際に出る拡張ポイント）。

### 多言語（i18n）

UI は **日本語 / 英語** に対応しています（`flutter_localizations` + ARB）。
既定ではシステムのロケールに追従し、非対応ロケールでは英語へフォールバック
します。言語の明示切替は `SettingsService.locale` に永続化する仕組みを
備えていますが、アプリ内の言語ピッカー UI は今後の予定です。

### 計画中

- **聴覚障害シミュレーションの音声再生** — 聴覚フィルタの型（14 種）は
  sensus から FRB で公開済みだが、実際に音を加工・再生する経路は未実装
- **ライブ画面キャプチャ** — 他アプリを含む全画面への適用。現状は合成した
  デモ画像に対してのみフィルタを適用する
- **視覚フィルタのライブ描画拡張** — 現在 protanopia / protanomaly のみ
  実描画。残りの色覚型・advanced フィルタの GPU 描画配線
- **アプリ内の言語ピッカー UI**

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
- 多言語化は `flutter_localizations` + ARB（`lib/l10n/app_en.arb` / `app_ja.arb`、ja/en）
- 色覚・複合症状のアルゴリズム正本は [`sensus-core`](https://crates.io/crates/sensus-core)（Rust crate）。
  ue は flutter_rust_bridge 経由で消費（フィルタ・`experiences()` 等。詳細は `docs/sensus-integration.md`）

## ライセンス

MIT
