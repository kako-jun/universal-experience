# ADR: ビルド時 impellerc 変換（FragmentProgram）

- **決定日**: 2026-05-31（変換を実装した #12 / PR #24 の commit 日 `ab24277`。
  方針（案A）の確定は同時期の sensus 連携 1/3 #7/#8 の `docs/sensus-integration.md`）
- **記録日**: 2026-06-21（ADR 化）
- **ステータス**: Accepted

## 文脈（問題）

sensus-core の `.frag`（`sensus_core::shaders::*_glsl()` が返すシェーダ）は
**GLSL ES 3.00** で書かれている:

- `#version 300 es` 宣言を持つ
- 入出力に `in vec2 vTexCoord` / `out vec4 fragColor` を使う
- 配列 uniform を使う（例: `uniform float uMatrix[9]`）

一方、Flutter stable の `FragmentProgram` は **Impeller GLSL サブセット**を要求し、
かつ**ビルド時コンパイル方式**である:

- `#version` 宣言を書かない／`#include <flutter/runtime_effect.glsl>` + `FlutterFragCoord()`
- `in`/`out` の代わりに限定的な `uniform` 入力と `out vec4 fragColor`
- 配列 uniform の扱いに制約
- ランタイムの `FragmentProgram.fromSource`（任意文字列の即時コンパイル）は **stable に無い**。
  `pubspec.yaml` の `shaders:` に `.frag` を列挙し、ビルド時に `impellerc` がコンパイルする。

したがって、sensus の `.frag` をそのまま Flutter の `shaders:` に列挙しても `impellerc` は
通らない（方言が違う）。さらにランタイム文字列注入の経路が無いので、sensus から
シェーダ文字列を取得して実行時に流し込む素朴な統合もできない。**変換が必須**で、
その変換を **どこで持つか** を決める必要があった。

## 決定

**ビルド時に ue 側で GLSL ES 3.00 → Impeller サブセットへ機械変換する（案A）。**
変換結果を `.frag` として吐き、`impellerc` でビルド時コンパイルする。

- 純粋変換関数: `tools/shader_codegen.dart`、CLI: `tools/generate_shaders.dart`。
- 入力: sensus-core の dumper（`crates/core/examples/dump_shaders.rs`）出力を vendor した
  `tools/sensus_shaders.g.json`。
- 生成先: repo 直下 `shaders/<name>.frag`。`pubspec.yaml` の `shaders:` を
  アルファベット順に自動列挙する。
- ドリフト検証: `dart run tools/generate_shaders.dart --check`、テスト:
  `test/shader_codegen_test.dart`。
- uniform 値は実行時に変わる（strength / 解像度 / seed 依存）ため、シェーダ本体は
  ビルド時に確定し、uniform は sensus の `*_uniforms()` を Rust で計算して FRB で渡す
  （→ ADR `2026-05-31-flutter-rust-split.md`）。

変換規則の要点: `#version`/`precision` 除去 + `#include <flutter/runtime_effect.glsl>`、
`in vec2 vTexCoord` 廃止して `FlutterFragCoord()` / 合成 `uResolution` から算出、
配列 `uMatrix[k]`→`uMatrixk`、`vec2 uXxx`→`uXxx_x`/`uXxx_y`。トークン置換は厳密な
識別子境界で行う。未知の配列 uniform は変換器が **throw** して握りつぶさない。

## 代替案

1. **案B: sensus 側に Flutter 用バリアントを出させる** — sensus に
   `*_glsl_flutter()`（Impeller サブセット版）を追加してもらい、ue はそれを同期するだけ。
   長所: ue が変換器を持たない／各フィルタの正しい変換を正本リポが保証。
   短所: sensus に Flutter 依存の出力責務が増える（sensus は本来 I/O 無しの純ロジック）。
   → 当面は採らず、変換ルールが汎用的に固まった段階でコストを見て還元を検討する。
2. **実行時変換 / ランタイム文字列注入** — sensus から GLSL 文字列を取得して実行時に
   `FragmentProgram` へ流す。却下: Flutter stable に `FragmentProgram.fromSource` の
   経路が無く、実現不可能。

## 根拠

- **シェーダ本体は静的**（フィルタ種別で固定）なので、ビルド時に確定できる。一方
  uniform は実行時に変わるので Rust（正本）で計算して渡す、という役割分担が自然。
- **sensus 側を変更しなくてよい**（案A の長所）。ue が変換ルールを所有し、正本リポに
  Flutter 依存を持ち込まない。
- まず案A で 1 枚（protanopia）を手で移植して golden path を通し、ルールが安定してから
  機械化する、という漸進的な進め方が取れた。色覚 4 種は uniform レイアウトが単純
  （行列 or luma weights）で最初の検証に向く。

## 結果・トレードオフ

- `tools/generate_shaders.dart` が repo 直下 `shaders/<name>.frag` へ 20 フィルタを
  生成し、`pubspec` の `shaders:` を列挙、`impellerc` を通すところまで完了
  （`flutter build linux --debug` で全 `.frag` コンパイルを実証）。
- **トレードオフ（変換器の保守）**: 変換ルールは ue が保守する。dump の鮮度検証（#24）で
  `sensus_shaders.g.json` の `schema` / `sensus_core_version` メジャー整合を検証し、
  不一致なら停止する。再生成手順は `tools/sensus_shaders.README.md`。
- **対象外のフィルタが残る**: 第2サンプラ（floaters/depth_aware_blur）・`int`/`uint`
  （glaucoma, cataract 等）・`uTime`（vertigo, bppv）系は host 側対応待ち。
  dry_eye / starbursts は GLSL の loop index が実行時値と比較され Impeller SkSL が
  拒否するため、sensus 側で定数ループ境界に直すまで対象外（codegen で握りつぶさない）。
- 実機での 1 フィルタ画面適用の目視確認は、ネイティブツールチェーン未導入のため
  当時未実施で残課題（`docs/sensus-integration.md` §4-3）。

## 関連 Issue・PR・docs

- Issue #12 / PR #24（シェーダ同期 codegen, commit `ab24277`, 2026-05-31）
- 前提: Issue #7/#8（sensus 連携 1/3, 方言調査）／関連 #24（dump 鮮度検証）
- `docs/sensus-integration.md` §1（方言の結論）・§2.1（案A/案B と推奨）・§4（残課題）
- `tools/shader_codegen.dart` / `tools/generate_shaders.dart` / `tools/sensus_shaders.g.json` /
  `tools/sensus_shaders.README.md` / `test/shader_codegen_test.dart` / `shaders/*.frag`
