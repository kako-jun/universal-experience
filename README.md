# Universal Experience

色覚障害・聴覚障害など、複数の感覚障害をシミュレーションできるアクセシビリティ体験アプリ。

**「すべての感覚を、すべての人に。」**

## 機能

### 色覚障害シミュレーション

- Protanopia（1型色覚・赤色盲）
- Deuteranopia（2型色覚・緑色盲）
- Tritanopia（3型色覚・青黄色盲）
- Achromatopsia（全色盲）
- Protanomaly / Deuteranomaly / Tritanomaly（各異常3色覚。錐体機能の部分低下）

色覚変換アルゴリズムの正本は別 crate
[`sensus-core`](https://crates.io/crates/sensus-core)（Rust）に一元化しており、
ue はそれを flutter_rust_bridge 経由で消費する薄いブリッジです（ue 側で LMS 等の
変換ロジックを再実装する方針は取りません）。フィルタの見え方は sensus 由来の
GPU シェーダ（`lib/rendering/shader_filter.dart`）で計算し、強度調整も可能です。
強度は**色覚タイプごとに個別記憶**します（`FilterService`、#57）。まだ選んだ
ことのないタイプを選ぶと推奨強度（-opia / achromatopsia は 1.0、-omaly は
0.6）が初期値になり、フィルタを切り替えても切替前のタイプの強度は保持されます。

> 色覚 3 型（protanopia/deuteranopia/tritanopia）の中間 strength は、sensus 0.6 の
> Machado 2009 11 段 severity テーブルをグリッド間で区分線形補間した正本値と一致
> します（#59）。`rust/src/color_matrix_gen.rs` が sensus-core の公開関数から 11
> グリッド点を汲み出して `tools/color_matrices.g.json` に書き出し、
> `tools/generate_color_matrices.dart` が `lib/rendering/color_matrices.g.dart`
> （Dart 定数）へ変換、`ShaderFilter.resolveSeverityMatrix()` が sensus と同じ
> 補間式でグリッド間を解決します。手書きの行列値は持ちません。

> 旧バージョンは OS 全体へ system-wide フィルタを適用する独自プラグイン
> （`plugins/color_vision_filter`）と ue 内 LMS 実装を持っていましたが、
> sensus 一元化に伴い撤去しました。ライブ画面（他アプリ含む全画面）への
> 適用は、画面キャプチャ経路の実装後に対応予定です。

> before / after の比較プレビューは、色覚 8 型（protanopia/deuteranopia/
> tritanopia/achromatopsia + 各 -omaly）すべてで実際に GPU 描画できます
> （#59）。後述の advanced カタログ（sensus 全 30 種）・体験プリセットの選択は
> 引き続き `VisionFilterState` に入るだけで、プレビューへの描画には反映されません
> （#60）。

### 視覚 advanced フィルタ（sensus カタログ）

sensus が提供する**計 30 種**（上記の色覚型を含む。屈折／視野欠損／
光・透明度／前庭・めまい／眼精疲労 等）の視覚フィルタをカタログから
カテゴリ別に選択し、パラメータ・強度を調整できます。フィルタ定義の正本は
sensus-core であり、ue はカタログ（`lib/models/vision_filter_catalog.dart`）
から引きます。
※ 選択・パラメータ調整は `VisionFilterState` に反映されますが、プレビューへの
ライブ描画は未配線です（#60）。

### 体験プリセット（複合症状）

複数の感覚にまたがる複合症状を、ワンタップで適用できる 4 つのプリセットを
用意しています:

- メニエール病（meniere）
- 良性発作性頭位めまい症（BPPV）
- 前庭神経炎（vestibular neuritis）
- 迷路炎（labyrinthitis）

各プリセットは視覚フィルタを選択状態にし、緊急度に応じた受診喚起の注記を
表示します。聴覚症状を含む体験（メニエール病・迷路炎）には「聴覚症状も含む」
注記を出しますが、**音声再生は未実装**です。また、プリセットのタップでは
`FilterService` が deactivate され、before/after 両ペインとも原画のままです
（#60）。プリセットの組み合わせ（どの視覚・聴覚フィルタが組になるか）の正本は
sensus-core の `experiences()` です。

### 画像エクスポート（PNG）

フィルタ適用後（after）の画像を、**症状名・強度・日付（ISO・`YYYY-MM-DD`）**
を焼き込んだ PNG として書き出せます。保存後はファイルのフルパスを
クリップボードへコピーします。画像そのもののクリップボード書き込み・
動画エクスポートは非対応です（ライブ描画がある色覚 8 型でエクスポート可能）。

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
- **視覚フィルタのライブ描画拡張** — 色覚 8 型は実描画済み（#59）。advanced
  カタログ（sensus 全 30 種）の GPU 描画配線は #60
- **アプリ内の言語ピッカー UI**

## 対応プラットフォーム

現行で対応（ランナーが存在し、ビルド・実行できる）:

- macOS 13+（deployment target 13.0。Flutter の native assets が macOS 13 を要求する）
- Linux (Ubuntu 20.04+ 目安、GTK 3 ベース)

計画中（ランナー未作成）:

- Android
- Windows

※ iOS は技術的制約により非対応（`docs/adr/2025-11-17-no-ios-support.md`）

## セットアップ

```bash
git clone https://github.com/kako-jun/universal-experience.git
cd universal-experience
flutter pub get
flutter run
```

Rust は `rust/` の `cargo test` / clippy、flutter_rust_bridge の codegen に加え、
`flutter run` / `flutter build macos` / `flutter build linux` でのビルドにも
必要です（`rust_builder/` の cargokit 統合が同梱まで自動で行う、#55。詳細は
`docs/GETTING_STARTED.md`）。

## 技術スタック

- Flutter 3.38.4+（`pubspec.lock` の `sdks` 準拠。`pubspec.yaml` の
  `sdk: '>=3.3.0 <4.0.0'` は flutter_rust_bridge の生成物が要求する下限にすぎない）
- Provider (状態管理)
- Material Design 3
- 多言語化は `flutter_localizations` + ARB（`lib/l10n/app_en.arb` / `app_ja.arb`、ja/en）
- 色覚・複合症状のアルゴリズム正本は [`sensus-core`](https://crates.io/crates/sensus-core)（Rust crate）。
  ue は flutter_rust_bridge 経由で消費（フィルタ・`experiences()` 等。詳細は `docs/sensus-integration.md`）

## ライセンス

MIT
