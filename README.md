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
変換ロジックを再実装する方針は取りません）。フィルタの見え方は sensus の CPU
`apply()`（`lib/rendering/cpu_vision_renderer.dart`）で計算し、強度調整も可能です。
強度は**色覚タイプごとに個別記憶**します（`FilterService`、#57）。まだ選んだ
ことのないタイプを選ぶと推奨強度（-opia / achromatopsia は 1.0、-omaly は
0.6）が初期値になり、フィルタを切り替えても切替前のタイプの強度は保持されます。

> 色覚 3 型（protanopia/deuteranopia/tritanopia）の中間 strength は、sensus 0.6 の
> Machado 2009 11 段 severity テーブルをグリッド間で区分線形補間した正本値と一致
> します。現行のプレビュー描画経路（sensus の CPU `apply()`、#85）は sensus-core の
> 公開関数をそのまま呼ぶため、この一致は自動的に保証されます。GPU 経路
> （`ShaderFilter`。ライブ画面キャプチャ向けに残置、現状 production 未使用）は
> sensus と別に Dart 側で行列を再現する必要があり、`rust/src/color_matrix_gen.rs`
> が sensus-core の公開関数から 11 グリッド点を汲み出して `tools/color_matrices.g.json`
> に書き出し、`tools/generate_color_matrices.dart` が `lib/rendering/
> color_matrices.g.dart`（Dart 定数）へ変換、`ShaderFilter.resolveSeverityMatrix()`
> が sensus と同じ補間式でグリッド間を解決します（#59）。手書きの行列値は持ちません。

> 旧バージョンは OS 全体へ system-wide フィルタを適用する独自プラグイン
> （`plugins/color_vision_filter`）と ue 内 LMS 実装を持っていましたが、
> sensus 一元化に伴い撤去しました。ライブ画面（他アプリ含む全画面）への
> 適用は、画面キャプチャ経路の実装後に対応予定です。

> before / after の比較プレビューは、sensus が公開する全 30 種すべてで実際に
> 描画できます（色覚のクイック選択・advanced カタログ・体験プリセットは、この
> 同じ 30 種への 3 つの選び方に過ぎません — 重複カウントではありません）。描画は sensus
> の CPU `apply()` 経由（#85）で、固定の正準サイズ（1024px）で描画してから
> 表示側で拡大縮小します。GPU シェーダは将来のライブ画面キャプチャ機能向けに
> 残してありますが、現状はどこからも呼ばれていません。プレビューの描画対象は
> `VisionFilterState` の現在の選択（色覚のクイック選択・advanced カタログ・
> 体験プリセットのいずれで選んでも一本化される）を唯一の正本にします（#60）。
> vertigo / bppv_rotation のような時間依存フィルタは、プレビューでは動きのない
> 静止フレームになります（その旨は注記します）。
>
> 色覚のクイック選択・advanced カタログ・体験プリセットは選択の起源として
> 区別され（`lib/services/color_vision_selection.dart`）、色覚のクイック選択が
> 起点のときだけプレビューの強度は色覚タイプごとの記憶（#57）を使います
> （それ以外は advanced の strength スライダー自体の値）。advanced/プリセットを
> 見ている間は色覚のクイック選択チップを点灯させず、advanced 側の strength
> スライダーも色覚クイック選択中は出しません（動かしても反映されない
> スライダーを見せないため）。-omaly（protanomaly 等）を選んだときは、
> 見出し・export の caption・ファイル名にも -omaly の名前を正しく出します。

### 視覚 advanced フィルタ（sensus カタログ）

sensus が提供する**計 30 種**（上記の色覚型を含む。屈折／視野欠損／
光・透明度／前庭・めまい／眼精疲労 等）の視覚フィルタをカタログから
カテゴリ別に選択し、パラメータ・強度を調整できます。フィルタ定義の正本は
sensus-core であり、ue はカタログ（`lib/models/vision_filter_catalog.dart`）
から引きます。選択・パラメータ調整は `VisionFilterState` に反映され、
プレビューにもそのまま反映されます（#60）。

### 体験プリセット（複合症状）

複数の感覚にまたがる複合症状を、ワンタップで適用できる 4 つのプリセットを
用意しています:

- メニエール病（meniere）
- 良性発作性頭位めまい症（BPPV）
- 前庭神経炎（vestibular neuritis）
- 迷路炎（labyrinthitis）

各プリセットは視覚フィルタを選択状態にし、before/after プレビューに反映します
（#60）。緊急度に応じた受診喚起の注記も表示します。聴覚症状を含む体験
（メニエール病・迷路炎）には「聴覚症状も含む」注記を出しますが、
**音声再生は未実装**です。プリセットの選択は体験 id（`meniere` 等）で保持する
ため、メニエール病と迷路炎（どちらも内部的には同じ vertigo フィルタ）を同時に
選択中と誤表示することはありません。また、プリセットのタップは色覚のクイック
選択（`FilterService`）を変更しません — 両者は独立に状態を保持します。
プリセットの組み合わせ（どの視覚・聴覚フィルタが組になるか）の正本は
sensus-core の `experiences()` です。

### 画像エクスポート（PNG）

フィルタ適用後（after）の画像を、**症状名・強度・日付（ISO・`YYYY-MM-DD`）**
を焼き込んだ PNG として書き出せます。プレビューが描画できるフィルタ（sensus
全 30 種 + 原画表示）はすべてエクスポート可能です。保存後はファイルのフルパスを
クリップボードへコピーします。画像そのもののクリップボード書き込み・
動画エクスポートは非対応です。

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
- **ライブ画面キャプチャ** — 他アプリを含む全画面への適用（プロダクトの目標方式。
  Issue #1）。現状は合成したデモ画像に対してのみフィルタを適用する。対象アプリを
  指定して自動追従させるモードの設計判断は
  `docs/adr/2026-09-26-loupe-as-single-render-unit.md` 参照
- **アプリ内の言語ピッカー UI**

## やらないこと（非目標）

- ue は診断・スクリーニング・色覚検査を行いません（体験プリセットの受診喚起は
  一般的な案内であり、診断ではありません）。
- 色の補正（Daltonization）は、現時点ではしません（シミュレーション専用です）。
- 画像や画面を端末の外に送りません。テレメトリも持ちません。
- 動画のエクスポートはしません。
- 運動障害と認知障害は、sensus に正本ができるまで扱いません。

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
