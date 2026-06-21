//! Universal Experience の Rust ライブラリ。
//!
//! 感覚障害シミュレーションのアルゴリズム正本は別 crate `sensus-core`
//! (crates.io 公開) に一元化されている。この crate はその薄いブリッジで、
//! flutter_rust_bridge 経由で Dart 側へ以下を公開する:
//!
//! - vision フィルタの GLSL ソース取得（ビルド時のアセット同期用）
//! - FragmentProgram に `setFloat(i, ..)` する順序の flat な f32 uniform 配列
//! - （将来用）CPU 適用の薄いラッパ
//!
//! GLSL や uniform 計算をここで再実装しないこと。すべて `sensus_core::shaders`
//! を呼ぶだけにして、正本の一元化を保つ。

// flutter_rust_bridge v2.11.1 はマクロ生成コード内で `cfg(frb_expand)` を
// 参照する。rustc 1.80+ はこれに対し `unexpected_cfgs` 警告を出すが、
// これは上流マクロのフィーチャ検出ガードであり無害（ここからは直せない）。
// selona と同じ抑制を入れる。
#![allow(unexpected_cfgs)]

mod frb_generated; /* AUTO INJECTED BY flutter_rust_bridge. This line may not be accurate, and you can change it according to your needs. */

mod api;

// GPU golden テストの参照 PNG 生成・検証（#31）。中身は `#[cfg(test)]` のみで、
// 本体ビルドには何も足さない。
#[cfg(test)]
mod golden_gen;

pub use api::sensus_bridge::*;
