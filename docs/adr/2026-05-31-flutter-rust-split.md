# ADR: Flutter + Rust の分割

- **決定日**: 2026-05-31（Rust ブリッジを追加した #7/#8 の commit 日 `ee1b942`。
  Flutter を UI に採る方針自体は 2025-11-17 の初期実装に遡る）
- **記録日**: 2026-06-21（ADR 化）
- **ステータス**: Accepted

## 文脈（問題）

ue の色覚シミュレーションのアルゴリズム正本を sensus-core crate（Rust）に一元化する
方針（→ ADR `2026-05-31-sensus-core-consolidation.md`）が立った。sensus-core は
Rust の crate であり、ue の UI は Flutter（Dart）で書かれている。

このとき「UI と コアアルゴリズムをどの言語・どの層で持つか」を決める必要があった。
sensus-core を ue から消費するには、Rust のロジックを Dart から呼ぶ橋が要る。

## 決定

**UI を Flutter（Dart）、コアを Rust** に分割する。

- **UI = Flutter**: 画面・ウィジェット・状態管理（Provider）・ルーペ窓・トレイなど
  プレゼンテーションと操作。
- **コア = Rust**: 感覚障害シミュレーションのアルゴリズム（sensus-core crate）。
  ue は `rust/` crate を持ち、`rust/src/api/sensus_bridge.rs` が
  [flutter_rust_bridge (FRB)](https://crates.io/crates/flutter_rust_bridge) 経由で
  sensus-core の機能を Dart へ公開する。
- 生成された Dart バインディングは `lib/src/rust/`。FRB は selona と同一バージョン
  `=2.11.1` に固定し、`sensus-core = "0.5"` に依存する。

ブリッジが公開する主な API（`sensus_bridge.rs`）:

- `visionShaderGlsl(filter)` — GLSL ソース（ビルド時シェーダ同期用）
- `visionUniforms(filter, strength, width, height, seed)` — `setFloat` 順の flat 配列
- `visionUniformLayout(filter)` — 各インデックスの uniform 名（検証用）
- `applyVisionCpuRgba8(...)` — CPU フォールバック（将来用）

uniform 値（半径式・aspect 補正・texel size 等）は sensus の `*_uniforms()` を
正本のまま Rust で計算し、FRB で Dart に渡す。

## 代替案

1. **全 Dart で書く** — アルゴリズムも Dart で実装する。却下: アルゴリズムの正本を
   ue が抱え直すことになり、sensus-core への一元化（二重化排除）と矛盾する。
   Rust の sensus-core を再実装する保守コストも発生する。
2. **全 Rust で書く** — UI も Rust（egui 等）で書く。却下: クロスプラットフォームの
   UI・既存の Flutter エコシステム（window_manager / tray_manager / provider 等の
   デスクトップ周辺）を捨てることになる。ue は元々 Flutter アプリとして始まっている。
3. **Rust を別プロセス/FFI 手書き** — FRB を使わず手書き FFI や別プロセス IPC で繋ぐ。
   却下: FRB は型安全なバインディングを codegen でき、selona で同構成の実績がある。
   手書き FFI は境界の保守が重い。

## 根拠

- **正本（Rust の sensus-core）をそのまま消費できる**。Dart へ再実装せず、UI と
  アルゴリズムをそれぞれ得意な言語に置ける。
- **FRB の実績**: selona と同構成（`flutter_rust_bridge = "=2.11.1"`）で、codegen に
  よる型安全なブリッジが既に動いている。バージョンを固定して codegen のドリフトを防ぐ。
- **二重実装を避ける唯一の形**: uniform の計算（半径式・aspect・texel size 等）を
  sensus 正本のまま Rust で行い FRB で渡すことで、ue 側に計算ロジックを複製しない。

## 結果・トレードオフ

- ue は `rust/` crate（`cargo build` / `fmt` / `clippy` / `test` 通過）と
  `lib/src/rust/`（FRB 生成）を持つ二言語構成になった。
- ビルドにネイティブツールチェーン（Rust + 各 OS のリンク）が必要になる。
- FRB 生成コードが web 版で inline-class を使うため、Dart SDK 下限を 3.3 に引き上げた。
- **トレードオフ**: FRB のバージョン固定・codegen 再実行・dump の鮮度検証
  （`sensus_shaders.g.json` の version 整合）という保守が増える。これは
  `docs/sensus-integration.md` と codegen テストで担保する。

## 関連 Issue・PR・docs

- Issue #7 / PR #8（sensus 連携 1/3: Rust ブリッジ + シェーダ方言調査, commit `ee1b942`, 2026-05-31）
- `docs/sensus-integration.md` §2.2（uniform の役割分担）・§3（このフェーズで完了したこと）
- `rust/Cargo.toml`（`flutter_rust_bridge = "=2.11.1"`, `sensus-core = "0.5"`）
- `rust/src/api/sensus_bridge.rs` / `lib/src/rust/`（生成 Dart バインディング）
