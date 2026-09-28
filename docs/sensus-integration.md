# sensus 連携 — シェーダ方言調査と統合方針

感覚障害シミュレーションのアルゴリズム正本は別 crate
[`sensus-core`](https://crates.io/crates/sensus-core)（Rust, crates.io 公開, v0.6.0）に
一元化する。universal-experience（ue）は GLSL や行列・半径式を**再実装しない**。

このドキュメントは Issue #7（sensus 連携 1/3）のスコープのうち「シェーダ方言の
結論」と「次フェーズ（2/3）の設計」を確定するもの。Rust ブリッジの実装は
`rust/src/api/sensus_bridge.rs`、生成された Dart バインディングは
`lib/src/rust/` にある。

---

## 1. sensus の `.frag` は Flutter FragmentProgram でそのまま使えない

### 1.1 sensus 側の方言: GLSL ES 3.00

`sensus_core::shaders::*_glsl()` が返す `.frag` は **GLSL ES 3.00** で書かれている。
具体的には:

- `#version 300 es` 宣言を持つ
- 入出力に `in vec2 vTexCoord` / `out vec4 fragColor` を使う
- テクスチャは `uniform sampler2D uTexture`
- 配列 uniform を使う（例: `uniform float uMatrix[9]`）

（実例は `protanopia.frag` 等。`srgbToLinear` / `linearToSrgb` を持ち、
linear sRGB 空間で行列を適用して `uStrength` で線形補間する。）

### 1.2 Flutter 側の方言: Impeller GLSL サブセット

Flutter stable の `FragmentProgram` は次の制約を持つ:

- **ビルド時コンパイル方式**。ランタイムの `FragmentProgram.fromSource`（任意の
  文字列をその場でコンパイル）は stable には**無い**。`pubspec.yaml` の
  `flutter:` `shaders:` に `.frag` を列挙し、ビルド時に `impellerc` が
  コンパイルする。
- **Impeller GLSL サブセット**を要求する:
  - `#version` 宣言を**書かない**
  - 座標は `#include <flutter/runtime_effect.glsl>` を入れて `FlutterFragCoord()` を使う
  - `in`/`out` の代わりに `uniform` 入力と `out vec4 fragColor` の限定的な形
  - 配列 uniform の扱いに制約がある
  - サンプラは `uniform sampler2D`（テクスチャ入力は `setImageSampler` で渡す）

### 1.3 結論

sensus の `.frag`（GLSL ES 3.00, `#version 300 es` + `in/out` + 配列 uniform）を
**そのまま** Flutter の `shaders:` に列挙しても `impellerc` は通らない。
方言が異なるため、**変換が必須**。さらにランタイム文字列注入の経路が無いので、
sensus からシェーダ文字列を取得して実行時に流し込む、という素朴な統合もできない。

---

## 2. 採るべき方式: ビルド時にアセットへ同期 + Impeller サブセットへ変換

役割分担は次の 2 系統に分ける:

| 要素 | 担当 | 経路 |
|---|---|---|
| **シェーダ本体（GLSL）** | アセット | ビルド時に `.frag` を Flutter アセットへ同期し、`impellerc` でコンパイル |
| **uniform 値** | FRB（Rust→Dart） | 実行時に `vision_uniforms()` を呼び `Float32List` を取得、`setFloat(i, ..)` で積む |

理由: シェーダ本体は静的（フィルタ種別で固定）なのでビルド時に確定できる。
一方 uniform は `strength` / 画像解像度 / seed に依存して**実行時に**変わるため、
sensus の `*_uniforms()` 計算（半径式・aspect 補正・texel size 等）を正本のまま
Rust で計算して FRB で渡すのが、二重実装を避ける唯一の方法。

### 2.1 シェーダ同期: 変換をどこでやるか（次フェーズの判断ポイント）

> **#12 で実装済み（案A）**。変換器は ue 側に持つ。純粋変換関数は
> `tools/shader_codegen.dart`、CLI は `tools/generate_shaders.dart`。入力は
> sensus-core の dumper（`crates/core/examples/dump_shaders.rs`）出力を vendor した
> `tools/sensus_shaders.g.json`。生成先は **repo 直下 `shaders/<name>.frag`**
> （#11・host・pubspec が稼働中のパス。`assets/shaders/` ではない）。`pubspec.yaml`
> の `shaders:` をアルファベット順に自動列挙する（`assets:` は触らない）。ドリフト
> 検証は `dart run tools/generate_shaders.dart --check`、テストは
> `test/shader_codegen_test.dart`。
>
> スコープは host（`lib/rendering/shader_filter.dart`）の uniform モデルに合う
> フィルタ（単一 `uTexture` サンプラ + scalar `float`/`vec2` uniform）の 20 種。
> 第2サンプラ（floaters/`uMask`, depth_aware_blur/`uDepth`）・`int`/`uint`
> （glaucoma, cataract, flickering_stars, metamorphopsia）・`uTime`
> （vertigo, bppv_rotation）を要するフィルタは host 側対応待ちで対象外。
> ここで「対象外」とは **shader codegen による live GPU 描画が未対応**という
> 意味に限られる。これらの視覚フィルタ自体はカタログ（#16）や体験プリセット
> （#19、vertigo / bppv_rotation 等を含む）から**選択・配線できる**（適用＝
> 選択状態の確定）。live 描画の有無とプリセットからの選択可否は別の話であり、
> 両者は矛盾しない。
> さらに dry_eye / starbursts は GLSL の loop index が実行時値（radius,
> iRayLen/numRays）と比較されており Impeller SkSL が拒否する（"loop index must be
> compared with a constant expression"）ため、sensus 側で定数ループ境界に書き直す
> までは対象外（codegen で握りつぶさない）。
> 変換規則: `#version`/`precision` 除去 + `#include <flutter/runtime_effect.glsl>`、
> `in vec2 vTexCoord` 廃止して body の `vTexCoord` を `FlutterFragCoord()` / 合成
> `uResolution` から算出、配列 `uMatrix[k]`→`uMatrixk`、`vec2 uXxx`→`uXxx_x`/`uXxx_y`。
> トークン置換は厳密な識別子境界で行い、`uTexelSize` が `uTexelSizeScale` の
> ような長い識別子を部分一致で壊さない。`uMatr[k]` 以外の未知配列 uniform
> （`uniform float uKernel[5]` 等）は変換器が **throw** して握りつぶさない。
>
> **dump の鮮度検証（#24）**: `sensus_shaders.g.json` は配列ではなく
> `{ "schema", "sensus_core_version", "shaders": [...] }` のオブジェクト。
> `rust/src/shader_dump_gen.rs` が `Cargo.lock` の sensus-core バージョンを埋める。
> `generate_shaders.dart` は (a) `schema` が既知値か、(b)
> `sensus_core_version` が `rust/Cargo.toml` の `sensus-core = "0.6"` と
> 一致するか（メジャーが 0 の間はマイナーまで一致必須。Cargo の 0.x semver
> 慣習では `^0.6` が `>=0.6.0, <0.7.0` を意味するため、メジャーだけの一致だと
> 0.5.x 由来の古い dump を誤って通してしまう）、(c) 各エントリが
> `name`/`glsl`/`layout` を持つか、を検証して
> 不一致なら停止する。sensus 更新時の再生成手順とバージョン確認は
> `tools/sensus_shaders.README.md` を参照。生成 `.frag` のヘッダには sensus
> version・入力 dump パス・正本（`sensus shaders/<name>.frag`）への参照を残す。

> → ADR: 本節の案A/案B の判断は `docs/adr/2026-05-31-buildtime-impellerc-conversion.md` に昇格。

GLSL ES 3.00 → Impeller サブセットの変換を**どちらで持つか**の選択肢:

- **案A: ue 側ビルドで変換する**
  `vision_shader_glsl()` で取得した `#version 300 es` ソースを、ビルド時スクリプト
  （Dart or シェルの codegen ステップ）で機械変換し、`assets/shaders/*.frag` として
  吐いてから `impellerc` に渡す。
  - 長所: sensus 側を変更しなくてよい。ue が変換ルールを所有する。
  - 短所: 変換器を ue が保守する。`in/out`→Impeller、`#version` 除去、
    `FlutterFragCoord()` 化、配列 uniform の展開などを正しくやる必要がある。

- **案B: sensus 側に Flutter 用バリアントを別途出させる**
  sensus に `*_glsl_flutter()`（Impeller サブセット版）を追加してもらい、ue は
  それをそのまま同期するだけにする。
  - 長所: ue に変換器を持たない。各フィルタの正しい変換は正本リポが保証。
  - 短所: sensus に Flutter 依存の出力責務が増える（sensus は本来 I/O 無しの純ロジック）。

**推奨**: まず**案A**で 1 枚（protanopia）を手で Impeller サブセットへ移植して
golden path（実機 1 フィルタ表示）を通し、変換ルールが安定したら機械化する。
変換ルールが汎用的に固まった段階で、コストを見て案B（sensus へ還元）を検討する。
色覚 4 種は uniform レイアウトが単純（行列 or luma weights）なので最初の検証に向く。

### 2.2 uniform の役割分担（このフェーズで実装済み）

`rust/src/api/sensus_bridge.rs` が次を FRB で公開する（生成 Dart は `lib/src/rust/`）:

- `visionShaderGlsl(filter)` → `String`（GLSL ソース。**ビルド時同期スクリプト用**。
  実行時にこの文字列を `FragmentProgram` へ流すわけではない）
- `visionUniforms(filter, strength, time, width, height)` → `Float32List`
  （`setFloat(0..)` する順序の flat 配列。sensus の `*_uniforms()` を呼ぶだけ。
  `time` は秒単位で、時間依存フィルタ（Vertigo / BppvRotation）の `uTime` に渡す。
  それ以外のフィルタでは無視される）
- `visionUniformLayout(filter)` → `List<String>`（各インデックスの uniform 名。
  `.frag` の宣言順と突き合わせる検証用。`visionUniforms` と同じ長さ・順序）
- `applyVisionCpuRgba8(...)` → `Future<Uint8List>`（**プレビュー（静止画）描画の
  正本経路**、#85。`#[frb(sync)]` を外して非同期公開しており、Rust 側スレッド
  プールで実行されるため Dart 側の `await` は UI スレッドを塞がない。
  `lib/rendering/cpu_vision_renderer.dart` の `CpuVisionRenderer` が薄くラップし、
  `ui.Image` ⇄ raw RGBA8 の往復を行う）

#### 複合体験（Experience）API（#10）

視覚 + 聴覚 + 緊急度にまたがる「複合体験」の正準記述子を FRB で公開する
（生成 Dart は `lib/src/rust/api/sensus_bridge.dart`）。メニエール病のような
「回転性めまい（視覚）＋ 難聴・耳鳴り（聴覚）」は sensus の pure・別バッファ
設計（画像／音声）では 1 バッファに収まらないため、「どの視覚フィルタとどの
聴覚フィルタを組にすれば仕様どおりの複合体験になるか」の正準化を sensus から
受け取る。

- `experiences()` → `List<Experience>`（`frb(sync)`）。順序固定で 4 複合体験
  `meniere` / `bppv` / `vestibular_neuritis` / `labyrinthitis` を返す。
- `Experience`（ミラー型）— `id`（安定した英語識別子＝i18n キー）、
  `vision: VisionFilter?`、`hearing: HearingFilter?`、`urgency: Urgency`。
- `Urgency`（ミラー enum）— `None` / `EarlyConsultation` / `Emergency`。
- `HearingFilter`（ミラー型・14 バリアント）— `HearingLoss` /
  `SuddenHearingLoss { freq_hz }` / `Tinnitus { freq_hz }` / `Meniere` /
  `Labyrinthitis` 等。payload 付きバリアントは sensus と同じフィールド名・型。

文言は **一切持たない**（`id` と分類＝enum バリアントのみ）。体験名・受診喚起
メッセージ・聴覚症状の説明といった表示文言の正本は ue 側 i18n（#18）にあり、
`id` / `Urgency` 種別 / `HearingFilter` バリアントをキーに解決する。症状の
組み合わせの正本は sensus-core。`HearingFilter` は **型として公開するだけ**で、
音声再生（`apply_hearing` 相当）は本層のスコープ外であり**未実装**（聴覚モード
設計に委ねる）。`experiences()` をワンタップ適用 UI として消費するのが体験
プリセット集（#19、`lib/ui/widgets/experience_presets.dart`）。

#### uniform レイアウト（ドキュメント化済みの一部フィルタ）

`setFloat(i, value)` の順序。`sampler2D uTexture` は `setImageSampler(0, ..)` で
別途渡すため、この float 配列には含まない。

> 以下の表は代表例のドキュメントであり網羅ではない。シェーダ codegen（§2.1）は
> 20 フィルタを `.frag` に変換済みで、うち色覚 4 型（protanopia/deuteranopia/
> tritanopia/achromatopsia、+各 -omaly は base の -opia を再利用）は
> `ShaderFilter` 経由で GPU 描画できる（#59）。**UI の before/after プレビュー
> （`before_after_view.dart`）はこの GPU 経路を呼ばない**: #85 で sensus の CPU
> `apply()`（`CpuVisionRenderer`）に置き換え済みで、GPU 経路は将来のライブ画面
> キャプチャ（#1/#3/#4、ルーペ窓での実描画を想定）向けに残置してあるが、その
> 機能自体が未実装のため現状 production コードからは呼ばれない。この節の
> uniform レイアウトは、その将来のライブ描画実装時・GPU golden テスト向けの
> 参照情報として残す。
> myopia 等の advanced フィルタも `ShaderFilter.applyColorFilterGpu` の汎用経路
> 自体は使えるが、ライブ描画（ルーペ）への配線自体がまだ存在しない（#60 の
> プレビュー結線とは別スコープ）。各フィルタの正確なレイアウトは実装時に必ず
> `visionUniformLayout()` で確認すること（ここに書き写した値を信用しない）。

| フィルタ | flat 配列 | 要素数 |
|---|---|---|
| Protanopia / Deuteranopia / Tritanopia | `[uStrength, uMatrix0..uMatrix8]` | 10 |
| Achromatopsia | `[uStrength, uRWeight, uGWeight, uBWeight]` | 4 |
| Myopia | `[uStrength, uRadiusPx, uTexelSize.x, uTexelSize.y]` | 4 |
| Photophobia | `[uRadiusPx, uTexelSize.x, uTexelSize.y]` | 3 |

> **注意（photophobia）**: `photophobia.frag` は `uStrength` を**持たない**。
> strength は bloom 半径（`radius_px = strength * 0.05 * min(W,H)`）へ畳み込み済み。
> フィルタごとに uniform 構造体が異なるので、Dart 側は必ず `visionUniformLayout()`
> で要素の意味を確認してから `.frag` の uniform 宣言順へマップすること。

---

## 3. このフェーズ（1/3）で完了したこと

- `rust/` crate を追加（別の flutter_rust_bridge プロジェクトと同構成、
  `flutter_rust_bridge = "=2.11.1"`、`sensus-core = "0.5"` 依存）。
  `cargo build` / `cargo fmt` / `cargo clippy` 通過。
- ブリッジ API（上記 4 関数 + `VisionFilter` enum 6 種）を実装。`cargo test` 16 件通過。
- FRB codegen 実行、`lib/src/rust/` に Dart バインディング生成。`flutter analyze`
  エラー 0（生成 web 版が inline-class を使うため Dart SDK 下限を 3.3 に引き上げ）。
- 本ドキュメントで方言の結論と統合方針を確定。

## 4. 次フェーズ（2/3）に残したこと — 完了状況

1. 完了（#12）: **GLSL → Impeller サブセット変換**（§2.1 案A）。
   `tools/generate_shaders.dart` が repo 直下 `shaders/<name>.frag`（`assets/shaders/`
   ではない）へ 20 フィルタを生成し、`pubspec` の `shaders:` を列挙、`impellerc`
   を通すところまで完了（`flutter build linux --debug` で全 .frag コンパイル実証）。
2. 完了（#11 で着手、#34/#59 で色覚 4 型に拡張して完了）: **Flutter 側の
   レンダリング配線**。`FragmentProgram.fromAsset` でロード →
   `FragmentShader` に uniform を `setFloat` で積む → `setImageSampler(0,
   snapshot)` → `toImage` → `_UiImagePainter`（`before_after_view.dart`）で
   描画、を実装。当初 protanopia のみだったハードコード行列（`_protanopiaMatrix`）
   は撤去し、sensus 由来の Machado テーブル生成物（§8）を使う形に置き換えた。
   汎用 `applyColorFilterGpu` を通じて色覚 4 型（+各 -omaly）全部が home 画面へ
   配線済み。
3. 未完了: **実機検証**。macOS/Linux で実際に画面へ 1 フィルタを適用し、
   sensus の CPU 出力（または既知の見え方）と目視一致を確認する（CLAUDE.md の
   完了判定: 実機 golden path）。現状は `flutter test`（ヘッドレス）の GPU golden
   テスト（PSNR/maxDiff 一致）で代替しており、実機での目視確認は未実施。
4. 部分: **フィルタ網羅の拡張**。`VisionFilter`/カタログは
   `sensus_core::Filter` の全 30 種を選択・パラメータ調整できる状態まで広がった
   （#16）が、プレビューの GPU 描画が配線されているのは上記のとおり一部のみ。
   payload 付きフィルタ（cataract/floaters の seed、glaucoma の mode、astigmatism
   の axis_deg、時間依存の vertigo/bppv 等）の描画配線は個別 Issue（#59 等）で継続中。
5. 完了（#13）: 既存 `lib/core/color_vision_simulator.dart`（ue 内の LMS 実装）の
   撤去。詳細は下記 §5。

---

## 5. 重複ロジック撤去（3/3）— #13 で完了

> → ADR: この一元化判断は `docs/adr/2026-05-31-sensus-core-consolidation.md` に昇格。

ue が二重に持っていた色覚ロジックを撤去し、アルゴリズム正本を sensus に一本化した。

- **削除**: `lib/core/color_vision_simulator.dart`（ue 内 LMS 実装）。
- **削除**: `plugins/color_vision_filter/`（OS 全体 system-wide フィルタを適用する
  独自ネイティブプラグイン）と `pubspec.yaml` の `color_vision_filter` path 依存。
- **`FilterService` の一本化**: plugin 呼び出し（apply/setIntensity/remove/getState）と
  permission 概念、`colorMatrix` getter（simulator 依存）を撤去。現在は純粋な
  選択状態モデル（`currentFilter` / `intensity` / `isActive`）で、選択・強度変更で
  `notifyListeners` するだけ。`ColorVisionType` → sensus `VisionFilter` の
  マッピング（`VisionFilter? get sensusFilter`）を追加した。none→null、
  protanopia/deuteranopia/tritanopia/achromatopsia→対応する `VisionFilter`、
  -anomaly 系は sensus が severity を `strength` で表すため base の -opia へマップ
  （anomaly は強度 < 1 相当）。
- **UI**: `filter_selector` / `intensity_slider` は `ColorVisionType` のまま動く
  （FilterService の公開 API を維持）。home_screen は system-wide 適用前提の文言を
  外し、「ライブ画面への適用は画面キャプチャ経路（#1/#3/#4）実装後」と明記した。
- **テスト**: `test/filter_service_test.dart` を追加（選択状態の遷移・clamp・
  sensusFilter マッピング）。protanopia golden は維持。
- **残課題（このフェーズ外）**: ライブ画面キャプチャ経路（#1/#3/#4）、
  `ColorVisionType` の全面 sensus `VisionFilter` 化や category/param パネル（#16）。

---

## 6. GPU golden テスト — 参照の再現可能な生成（#31）

色覚（色変換系）フィルタの GPU 出力が sensus と数値一致することを守る golden テスト。
当初は protanopia 1 種のみ（参照 PNG は sensus CLI 由来）だったが、CLI が同梱されず
参照を再生成できなかった。そこで **正本そのもの（`sensus_core::apply()` / `vision_uniforms()`）**
から参照を生成する経路を rust 側に置いた。

- **生成元**: `rust/src/golden_gen.rs`（`#[cfg(test)]` のみ。本体 cdylib には何も載らない。
  PNG 入出力は dev-dependency の `image`+`png` feature）。
- **生成手順（参照 PNG と uniforms を再生成するとき）**:

  ```sh
  cd rust && cargo test -- --ignored gen_color_golden_refs
  ```

  → `test/golden/<filter>_ref.png`（参照 RGBA, CPU 正本経路）と
  `test/golden/color_uniforms.json`（GPU 経路用の正本 uniform。色行列 / luma 重みを
  Dart に再実装しないための生成物）を書き出す。
- **方法論の保証**: `rust/src/golden_gen.rs` の `protanopia_ref_matches_sensus_core`
  テスト（既定で実行）が、commit 済み `protanopia_ref.png`（CLI 由来）と
  `sensus_core::apply(Protanopia)` がビット一致することを検証する。これにより
  「rust apply を参照源に使う」生成経路が CLI 参照と等価であることを CI で守る（捏造防止）。
- **Dart 側**: `test/vision_filter_golden_test.dart` が `color_uniforms.json` の正本 uniform を
  `ShaderFilter.applyColorFilterGpu()` に流し、各 `.frag` を FragmentProgram で GPU 描画して
  参照 PNG とトレランス内一致（PSNR≥30dB / maxDiff≤8）を assert する。現状 deuteranopia /
  tritanopia / achromatopsia をカバー（protanopia は従来の `protanopia_golden_test.dart`）。
- **対象外**: 空間・時間依存フィルタ（myopia/glaucoma/vertigo 等）は GPU/CPU のカーネル・
  サンプリング差でピクセル等価にならないため、この PSNR golden 方式の対象にしない。
  別途の検証方式（uniform レイアウト一致は既存の `shader_codegen_test.dart` が担保）。

---

## 7. sensus 0.6.0 への更新（#56）

`sensus-core` を 0.5.0 → 0.6.0 に上げた。API・挙動への影響:

- **Machado 段階（severity）テーブル（sensus#165、#51 注記6）**: `protanopia_uniforms` /
  `deuteranopia_uniforms` / `tritanopia_uniforms` が、strength を severity として
  11 段テーブル（`vision::color::{PROTANOMALY,DEUTERANOMALY,TRITANOMALY}_TABLE`）から
  補間した**解決済み行列**を返すようになった（severity=0.0 で単位行列、1.0 で従来の
  severity=1.0 行列と同値）。対応して `protanopia.frag`（他2色も同様）は
  シェーダ内の `uStrength` ブレンドを廃止し、`uMatrix` を直接適用するだけになった。
  #51 注記6が予告していたとおり中間 severity の出力が変わった。
  **試した上で見送ったこと**: `shader_filter.dart` の `_protanopiaMatrix` ハードコード
  （severity=1.0 固定 + 線形ブレンド。#34 の指摘対象）を撤去し
  `ShaderFilter.applyProtanopiaGpu` が `visionUniforms(VisionFilter.protanopia(), ...)`
  から解決済み行列を取得する形に一度書き換えたが、`ShaderFilter` はネイティブ
  ブリッジ未初期化のプレーンな `flutter test`（`before_after_view_test.dart` /
  `protanopia_golden_test.dart` が直接 exercise する）からも呼ばれ、`RustLib.init()`
  は `initNativeBridge()` 経由で `main()` / `integration_test/`（`-d macos`、
  cargokit のネイティブ lib ビルドを経由）からしか呼ばれないため、プレーンな
  `flutter test` では bridge 呼び出しが必ず失敗することを実測で確認した（CI の
  `check` ジョブも `flutter build macos --debug` より前に `flutter test` を走らせる
  順序）。そのため本 PR では **Dart 側での単位行列↔severity=1.0 行列の線形補間を
  維持**し、コメントで sensus 正本の Machado テーブルと中間 strength が一致しない
  ことを明記するに留めた（`_protanopiaMatrix` の doc コメント参照）。
  ブリッジ経由の解決値を使う本格対応（テスト側でネイティブ lib を用意する試験
  基盤の整備を含む）、中間 strength 用の golden 追加、deuteranopia / tritanopia /
  achromatopsia の**プレビュー UI 配線**、protanomaly/deuteranomaly/tritanomaly の
  severity 反映は #59 のスコープ。
- **DetailLoss の strength=0（sensus#167→#175、#51 注記2）**: #51 注記2「DetailLoss が
  strength を無視する」は sensus#167 で解消済みと report されていたが、0.6.0
  （sensus#175）で「`strength=0.0` でも pixelation がかかり crate 横断の
  『strength=0=原画』不変条件に違反する」バグとして再修正された。`rust/src/api/sensus_bridge.rs`
  に `detail_loss_strength_zero_is_identity`（byte-identical を assert）/
  `detail_loss_strength_one_changes_pixels`（対照）を追加して回帰させている。
- **FieldLossMode（Darken/Blur、sensus#171）**: `glaucoma` / `macular_degeneration` /
  `hemianopia` / `tunnel_vision` の 4 フィルタに `field_loss_mode` payload が追加された。
  `VisionFieldLossMode`（`darken`/`blur`）として FRB 公開し、bridge の型・写像は
  持つ。**GPU（FragmentProgram）経路は常に Darken 相当**: `shaders::glaucoma_uniforms`
  等の署名は `field_loss_mode` を取らないため（GLSL 側が Blur 未対応）、この4フィルタの
  GPU 描画は選択に関わらず Darken の見た目になる。`Blur` を実際に反映できるのは
  `apply_vision_cpu_rgba8`（CPU 経路）のみ。この理由から `vision_filter_catalog.dart`
  には**あえてパラメータとして公開していない**（UI で選ばせても GPU 描画に反映され
  ないため、#56）。`VisionFilterState.build()` は常に
  `VisionFieldLossMode.darken` で構築する。GPU 描画が Blur に対応するか、カタログが
  CPU 専用パラメータを表現できるようになったら再検討する。
- **シェーダダンプの再生成経路**: `tools/sensus_shaders.g.json` は `rust/src/shader_dump_gen.rs`
  （`#[cfg(test)] #[ignore]` の一回限りジェネレータ、`cd rust && cargo test -- --ignored
  gen_shader_dump`）で再生成する。ue/rust が既にリンクしている sensus-core 0.6.0 から
  `vision_shader_glsl()` / `vision_uniform_layout()` を直接呼んで同じスキーマの JSON を
  書き出す形にしており、GLSL/layout の値は正本（sensus-core）由来のまま再実装していない。
  対象フィルタの一覧は `tools/generate_shaders.dart` の `_excludedFilters` と手で同期させて
  おり、同じ `shader_dump_gen.rs` の非 ignore テスト
  （`dump_targets_and_excluded_stems_cover_all_variants` / `generated_json_matches_committed_file`）
  が両者の同期および生成 JSON と commit 済み `tools/sensus_shaders.g.json` の一致を
  `cargo test` で常時検証する。Dart 側は `dart run tools/generate_shaders.dart --check`
  （CI の `check` ジョブに独立ステップとして追加、`test/shader_codegen_test.dart` も内部で
  同じ `--check` を回す）が `shaders/*.frag` / `pubspec.yaml` の同期を検証する。詳細は
  `tools/sensus_shaders.README.md` の Regenerating 節を参照。

---

## 8. 色覚 3 型の Machado テーブル一元化・プレビュー UI 配線（#59、#34 解消）

§7 が見送った項目（ブリッジ経由の解決値取得、中間 strength 用 golden、
deuteranopia/tritanopia/achromatopsia のプレビュー UI 配線、-omaly の severity
反映）
を本 Issue でまとめて解消した。採った方式は §7 で候補に挙げた (a)（実行時に
`visionUniforms()` を呼ぶ）ではなく (b)（テーブルを生成物として書き出し、Dart
側で同じ補間をかける）。(a) を選ばなかった理由は §7 と同じ: `ShaderFilter` は
ネイティブブリッジ未初期化のプレーンな `flutter test` からも呼ばれ、そこでは
`RustLib.init()` が失敗する。(b) はブリッジ初期化なしに正本と f32 の丸め誤差
（1ulp）以内で一致させられる（Dart 側は f32 由来の値を f64 リテラルとして
読み込んで演算するため、独立の丸め経路を通る分だけ完全なビット一致ではない）。

- **Machado 11 段テーブルの汲み出し**: sensus-core の `PROTANOMALY_TABLE` 等は
  `pub(crate)` で crate 外から直接参照できない。`rust/src/color_matrix_gen.rs` は、
  公開関数 `sensus_core::shaders::{protanopia,deuteranopia,tritanopia}_uniforms
  (strength)` をグリッド点ちょうど（`strength = i/10.0`, i=0..=10）で呼ぶことで、
  内部の `resolve_severity_matrix` が補間せずテーブル値をそのまま返す性質を利用し、
  11 グリッド点を手書きなしで取り出す。`(i as f32 / 10.0) * 10.0 == i as f32` が
  i=0..=10 で厳密に成り立つ（f32 演算として決定的）ことを
  `grid_strength_round_trips_exactly` テストで固定している。achromatopsia は
  severity テーブルを持たず、strength に依存しない固定重み（`achromatopsia_uniforms`
  の `r_weight`/`g_weight`/`b_weight`）を同じ JSON に同梱する。
- **生成パイプライン**: `cargo test -- --ignored gen_color_matrices`
  （`rust/src/color_matrix_gen.rs`）が `tools/color_matrices.g.json` を書き出し、
  `dart run tools/generate_color_matrices.dart` がそれを
  `lib/rendering/color_matrices.g.dart`（Dart 定数、11 グリッド点 ×3 型 +
  achromatopsia の重み 3 つ）へ変換する。`tools/generate_shaders.dart` と同じ
  JSON→生成物パイプラインの形に揃えてある。両段階とも常時ドリフト検出テストを
  持つ（rust 側 `generated_json_matches_committed_file`、Dart 側
  `test/color_matrix_codegen_test.dart` + CI の "Verify color matrix codegen has
  no drift" ステップ）。JSON ではなく Dart 定数ファイルにしたのは、実行時の
  `rootBundle` 非同期ロードやブリッジ初期化を避けるため（§7 と同じ制約）。
- **Dart 側の補間**: `ShaderFilter.resolveSeverityMatrix(grid, strength)` が
  sensus の `resolve_severity_matrix` と同じ式（`scaled = strength*10`、
  `i0 = floor(scaled)`、グリッド区間内だけを要素ごとに線形補間）を再現する。
  `_protanopiaMatrix` ハードコード（severity=1.0 固定 + 単位行列への全域線形
  ブレンド）は撤去した（#34 解消）。`applyDeuteranopiaGpu` / `applyTritanopiaGpu`
  / `applyAchromatopsiaGpu` を新設し、色覚 4 型すべてが同じ `applyColorFilterGpu`
  汎用経路を通る。
- **完了条件の検証**: `test/color_matrix_interpolation_test.dart` が、rust
  `golden_gen::gen_color_matrix_strength_fixture` が sensus_core の
  `vision_uniforms()` から直接汲み出した strength=0/0.125/0.25/0.5/0.75/0.875/1.0
  の fixture（`test/golden/color_matrix_strengths.g.json`）と
  `resolveSeverityMatrix()` の出力を f32 の丸め誤差（1ulp）以内で突き合わせる。
  0.25/0.75 はグリッド区間のちょうど中間（frac=0.5）にあたり、グリッド点だけでは
  検出できない「補間の式そのもの」の一致を確認できる。0.125/0.875（frac=0.25/0.75、
  2進で正確な 1/8・7/8）は、frac=0.5 だけでは検出できない lo/hi 取り違えバグを
  捕まえる（`lerp(lo, hi, 0.5)` は lo/hi を入れ替えても同じ値になるため。#86
  レビュー should-1、`rust/src/golden_gen.rs` のコメントで実際に取り違えて
  再現・確認済み）。`test/protanopia_golden_test.dart` の strength=0.5 期待値も、
  この生成物由来のグリッド + `resolveSeverityMatrix` を使うよう更新した
  （手書きの `_lerpProtanopiaMatrix` を撤去）。
- **高レベル API 自体の golden（#86 レビュー should-4）**:
  `test/vision_filter_golden_test.dart` は `applyColorFilterGpu` に JSON 由来の
  生 uniform を直接流し込む経路のテストで、`before_after_view.dart` が実際に
  呼ぶ `applyDeuteranopiaGpu`/`applyTritanopiaGpu`/`applyAchromatopsiaGpu`
  そのものは golden で検証されていなかった。`test/color_matrix_wrapper_golden_test.dart`
  を追加し、strength=1.0 を各参照 PNG と（maxDiff≤2）、deuteranopia の
  strength=0.5 を `resolveSeverityMatrix` 経由の CPU 期待値と
  （`protanopia_golden_test.dart` と同じ形で）突き合わせる。
- **プレビュー UI 配線**: `before_after_view.dart` の `renderAfter` を色覚 7 型
  （-opia 4 種 + -omaly 3 種。none は原画をそのまま返すだけで元から対応済み）
  全部に広げた。-omaly は base の -opia と同じレンダラを、`recommendedStrength`
  （0.6）で呼ぶだけ（専用テーブルは不要）。この GPU 経路自体は静止画プレビュー用の
  暫定実装で、後に #85 で sensus の CPU `apply()` に置き換わった（§9 参照。GPU は
  将来のライブ画面キャプチャ（#1/#3/#4）向けに残るが、現状 production からは
  呼ばれない）。
- **YAGNI 撤去（#86 レビュー should-3）**: 上記の結果、`canRender`（常に `true`
  を返すだけになっていた）・「描画は近日対応」のプレースホルダ
  （`_ComingSoonPlaceholder` / ARB の `previewComingSoon`）・`home_screen.dart`
  の `previewUnsupportedNote` 分岐は、どの `ColorVisionType` からも到達しない
  死んだコードになったため撤去した。将来また未実装の型が増えたときは、その時点
  で改めて必要な形（コード自体が変わっているはず）で作る。

## 9. プレビューを CPU `apply()` に統一（#85）

- **背景**: ブリッジには `apply_vision_cpu_rgba8`（sensus の `apply()`）が #10
  時点から存在していたが、UI からは一度も呼ばれておらず、テストでしか使われて
  いなかった。プレビューは §8 の GPU 経路（色覚 7 型のみ）に限定され、advanced
  カタログの残り 23 種は「プレビューには反映されない」状態だった。
- **変更**: `apply_vision_cpu_rgba8` の `#[frb(sync)]` を外して非同期公開にし
  （Rust 側スレッドプールで実行、Dart 側の `await` が UI スレッドを塞がない）、
  `lib/rendering/cpu_vision_renderer.dart` に `CpuVisionRenderer` を新設した。
  `before_after_view.dart` の `renderAfter` は
  `FilterService`（`visionFilterForColorVisionType`、単一の対応表）で
  `ColorVisionType` を `VisionFilter` へ写像し、`CpuVisionRenderer.applier`
  （production からも直接呼ぶ seam。`sampleImageGenerator`/
  `afterImageRenderer` と同じパターンだが、production コード自身が参照するため
  `@visibleForTesting` は付けていない、#85 レビュー N1）へ委譲する形に置き換えた。
  レンダラ自体は任意の `VisionFilter`（payload 込み）を受け取れるため、advanced
  カタログ 30 種すべてを描画できる。
  **#60 での追補**: advanced カタログ・体験プリセットの UI 結線を終えた際、
  `renderAfter`（延いては `before_after_view.dart` 全体）から `ColorVisionType`
  → `VisionFilter` の写像を撤去した。マッピングは呼び出し側
  （`home_screen.dart`）が `VisionFilterState.build()` で行い、`renderAfter` は
  組み立て済みの `VisionFilter?` をそのまま `CpuVisionRenderer.applier` へ渡す
  だけになっている。`FilterService.sensusFilter`
  （`visionFilterForColorVisionType`）自体は変わらず健在だが、色覚のクイック
  選択を `VisionFilterState` へ書き込む入力としてのみ使われる
  （`lib/services/color_vision_selection.dart` の `selectColorVision`）。
  **#60 レビュー1巡目での追補（M1）**: 当初は home_screen.dart の listener が
  `FilterService` の変化を `VisionFilterState` へミラーしていたが、
  「`currentFilter` が変わったときだけ」反映する差分検知のせいで、
  advanced/プリセットを経由したあとに同じ色覚型を再選択しても反映されない
  穴があった。ミラーはやめ、`FilterSelector`・トレイ・`main.dart` の起動時
  復元のいずれも `selectColorVision`/`deactivateColorVision`
  （`lib/services/color_vision_selection.dart`）を直接呼んで、その場で
  `FilterService` と `VisionFilterState` の両方を更新する形にした。
  `VisionFilterState` はこれに伴い `filterService` と同じくトップレベル
  singleton（`main.dart` の `visionFilterState`）に昇格した。
- **alpha の扱い（レビュー S1、初版の誤り）**: Flutter の `ui.Image` は
  premultiplied alpha で GPU テクスチャを保持するが、sensus（`image` crate）は
  straight alpha を前提にした画素処理を行う。初版はこの違いを踏まえず
  `ImageByteFormat.rawRgba`（premultiplied を返す）で読み、
  `decodeImageFromPixels` に straight のまま書き込んでいたため、alpha<255 の
  ピクセルで色がずれる欠陥があった。修正: 入力は
  `ImageByteFormat.rawStraightRgba` で straight を読み、出力は
  `CpuVisionRenderer.premultiplyStraightRgba8`（`round(straight × alpha / 255)`）
  で premultiplied に変換してから `ui.Image` を組み立てる。変換は
  sensus_core/`apply_vision_cpu_rgba8` 側ではなく Dart 側（Flutter 固有の
  premultiplied 前提が閉じたレイヤー）で行う。`test/cpu_vision_renderer_test.dart`
  が既知の透過ピクセル（alpha=128）を含む往復と `premultiplyStraightRgba8` の
  変換式そのものを検証する。
- **デコードのハング（レビュー S2、初版の欠陥）**: 初版は `ui.decodeImageFromPixels`
  （コールバック API）で出力バイト列から `ui.Image` を組み立てていたが、この API
  はデコードに失敗した場合にコールバックが一度も呼ばれず `Future` が永久に
  解決しないことがある。`CpuVisionRenderer.rgba8ToImage` を
  `ImmutableBuffer.fromUint8List` → `ImageDescriptor.raw` →
  `instantiateCodec` → `getNextFrame` の await 連鎖に書き換え、失敗が普通の
  例外として `Future` の rejection で伝わるようにした（`buffer`/`descriptor`/
  `codec` は `finally` で必ず dispose する）。これにより既存の `_rebuild` の
  try/catch・失敗表示（#58）にそのまま乗る。`test/cpu_vision_renderer_test.dart`
  が、サイズの合わないバッファを渡すと（ハングせず）例外になることを検証する。
- **実行の集約（レビュー S3）**: CPU `apply()` は GPU シェーダより重いため、
  スライダーの連続操作で `_rebuild` を何本も同時に実行すると実ブリッジ呼び出しが
  積み上がる。`_BeforeAfterViewState._scheduleRebuild` を新設し、`_rebuild` が
  実行中なら新しい要求は「最新の1件」だけを `_pendingRebuildSampleSize` に
  記録して待たせ、完了時にそれを走らせる（同時に走るジョブは常に1本）。
  `_rebuild` 自体の世代管理・dispose・失敗表示（#58）は変更していない。
  `test/before_after_view_test.dart` が、連続更新で中間の要求が集約される
  ことと、同時に実行される `afterImageRenderer` が1本を超えないことを検証する。
- **正準サイズでの描画（レビュー S4）**: 旧 GPU 時代（#58）はプレビューをペインの
  論理サイズ × `devicePixelRatio` に自動で追従させ、リサイズをデバウンスして
  いた。CPU プレビューではこれをやめ、常に固定の正準サイズ
  （`BeforeAfterView.canonicalSampleSize` = 1024）で描画し、表示側で
  `FilterQuality.medium` によるスケーリングに任せる。理由: (1) `DetailLoss`
  の `cellSize` のように絶対ピクセル数でパラメータを取るフィルタは、画像
  サイズが変わるたびに見え方自体が変わってしまう、(2) disk blur 系
  （myopia/hyperopia/presbyopia/astigmatism）は半径を
  `strength × 比率 × min(width, height)` で決めており、比率最小の
  astigmatism/presbyopia（1.1%）では画像が小さいと半径が 1px 未満に退化して
  楕円カーネルが中心 1 点だけになり完全な no-op になる（sensus-core の
  `build_ellipse_spans` の `<=1.0` 判定）。1024 ならこの比率でも半径 11px 超と
  余裕があるが、sensus 側の比率定数や canonical サイズ自体を変えるとこの余裕は
  変わる点に注意（`integration_test/cpu_preview_all_filters_test.dart` の
  コメント参照）。ペインサイズ連動の auto-sizing（#58）とそのテスト群は
  丸ごと撤去した。トレードオフ（レビュー N11）: HiDPI で大きなペイン
  （物理ピクセル数が 1024 を超える）では逆に 1024px の画像を拡大表示する
  ことになり、`FilterQuality.medium` でも旧 auto-sizing 時代よりわずかに
  ぼやける。
- **GPU の位置づけ**: `ShaderFilter`（§8）は削除せず、将来のライブ画面キャプチャ
  （#1/#3/#4、ルーペ窓での実描画を想定）向けに残した。ただしその機能自体が
  未実装のため、**現状 production コードから呼ばれることはない**。GPU と CPU
  の等価性は `test/vision_filter_golden_test.dart` 等の既存 GPU golden テストが
  （production の呼び出しとは独立に）引き続き担保する。
- **数値一致の調査（依頼事項）**: 色覚型について CPU 出力と既存 GPU golden の
  差を調べた。
  - CPU（`apply_vision_cpu_rgba8`）自体は golden 参照 PNG の生成に使われた経路
    そのもの（`rust/src/golden_gen.rs`）なので、strength=1.0 では参照 PNG と
    **バイト完全一致**する（`cargo test` の
    `golden_gen::tests::protanopia_ref_matches_sensus_core` が実測確認する。
    `integration_test/cpu_preview_all_filters_test.dart` から実ブリッジ経由で
    同じ比較をする案は一度実装したが、デスクトップ integration_test 実行時の
    カレントディレクトリがリポジトリルートと一致せず golden ファイルを
    読めなかったため撤去した。ファイル末尾のコメント参照）。
  - `CpuVisionRenderer` が追加する Dart 側の往復変換（straight RGBA8 ⇄
    premultiplied RGBA8）は、alpha==255（このアプリの実運用画像はほぼ全て
    不透明）では premultiply が恒等変換になるためゼロ誤差、alpha<255 でも
    8bit 整数の丸め誤差 1 以内に収まる。`test/cpu_vision_renderer_test.dart` が
    golden 参照 PNG（alpha==255）でのバイト完全一致と、既知の透過ピクセル
    （alpha=128）での丸め誤差 1 以内の往復を実測で固定した。
  - 既存の GPU vs golden 比較（`test/vision_filter_golden_test.dart`）は
    maxDiff≤8（PSNR≥30dB）を許容しており、依頼の目安（2/255）より緩い。この差は
    GPU シェーダ内部の `srgbToLinear`/`linearToSrgb`（pow 演算）に伴う GPU/CPU
    丸め差であり、本 Issue が変更した範囲（プレビューの描画経路の切替）とは
    無関係かつ既存（#31/#59 由来）のまま。**プレビューは CPU 出力そのものに
    なった**ため、この GPU/CPU 差はプレビューの見え方には一切影響しない
    （GPU 経路は現状どこからも呼ばれないため、この差が実際に見えることもない。
    将来ライブ画面キャプチャで GPU 経路が使われる際は従来どおり maxDiff≤8 の
    差が生じうる）。
