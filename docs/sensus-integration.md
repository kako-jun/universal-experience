# sensus 連携 — シェーダ方言調査と統合方針

感覚障害シミュレーションのアルゴリズム正本は別 crate
[`sensus-core`](https://crates.io/crates/sensus-core)（Rust, crates.io 公開, v0.5.0）に
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
> dumper（`dump_shaders.rs`）が `CARGO_PKG_VERSION` を埋める。
> `generate_shaders.dart` は (a) `schema` が既知値か、(b)
> `sensus_core_version` のメジャーが `rust/Cargo.toml` の `sensus-core = "0.5"`
> と一致するか、(c) 各エントリが `name`/`glsl`/`layout` を持つか、を検証して
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
- `visionUniforms(filter, strength, width, height, seed)` → `Float32List`
  （`setFloat(0..)` する順序の flat 配列。sensus の `*_uniforms()` を呼ぶだけ）
- `visionUniformLayout(filter)` → `List<String>`（各インデックスの uniform 名。
  `.frag` の宣言順と突き合わせる検証用。`visionUniforms` と同じ長さ・順序）
- `applyVisionCpuRgba8(...)` → `Uint8List`（将来用の CPU フォールバック。MVP 未使用）

#### uniform レイアウト（MVP の 6 フィルタ）

`setFloat(i, value)` の順序。`sampler2D uTexture` は `setImageSampler(0, ..)` で
別途渡すため、この float 配列には含まない。

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

- `rust/` crate を追加（selona と同構成、`flutter_rust_bridge = "=2.11.1"`、
  `sensus-core = "0.5"` 依存）。`cargo build` / `cargo fmt` / `cargo clippy` 通過。
- ブリッジ API（上記 4 関数 + `VisionFilter` enum 6 種）を実装。`cargo test` 16 件通過。
- FRB codegen 実行、`lib/src/rust/` に Dart バインディング生成。`flutter analyze`
  エラー 0（生成 web 版が inline-class を使うため Dart SDK 下限を 3.3 に引き上げ）。
- 本ドキュメントで方言の結論と統合方針を確定。

## 4. 次フェーズ（2/3）に残したこと

1. **GLSL → Impeller サブセット変換**（§2.1 案A）。**#12 で実装済み**:
   `tools/generate_shaders.dart` が repo 直下 `shaders/<name>.frag`（`assets/shaders/`
   ではない）へ 20 フィルタを生成し、`pubspec` の `shaders:` を列挙、`impellerc`
   を通すところまで完了（`flutter build linux --debug` で全 .frag コンパイル実証）。
2. **Flutter 側のレンダリング配線**: `FragmentProgram.fromAsset` でロード →
   `FragmentShader` に `visionUniforms()` の `Float32List` を `setFloat` で積む →
   `setImageSampler(0, snapshot)` → `CustomPainter` 等で適用。
3. **実機検証**: Linux/Android/Windows いずれかで実際に 1 フィルタを画面適用し、
   sensus の CPU 出力（または既知の見え方）と目視一致を確認する（CLAUDE.md の
   完了判定: 実機 golden path）。本フェーズは環境（ネイティブツールチェーン未導入）
   のため `flutter run` 未実施。
4. **フィルタ網羅の拡張**: `VisionFilter` を `sensus_core::Filter` の全バリアントへ
   広げる（cataract/floaters の seed、glaucoma の mode、astigmatism の axis_deg、
   時間依存の vertigo/bppv など、payload を FRB へ反映）。
5. 既存 `lib/core/color_vision_simulator.dart`（ue 内の LMS 実装）の撤去は
   **別 Issue（3/3）**。→ **#13 で撤去済み**（下記 §5）。

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
