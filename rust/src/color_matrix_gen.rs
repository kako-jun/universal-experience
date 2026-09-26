//! `tools/color_matrices.g.json` の**一回限りの再生成器**（#59、#34 解消）。
//!
//! sensus 0.6 の色覚 3 型（protanopia / deuteranopia / tritanopia）は、Machado 2009
//! の 11 段 severity テーブル（`vision::color::{PROTANOMALY,DEUTERANOMALY,TRITANOMALY}_TABLE`）
//! を `strength` でグリッド間**区分線形補間**した行列を返す（sensus#165）。この
//! テーブル自体は `pub(crate)`（sensus-core 内部限定）で ue からは直接参照できないが、
//! 公開関数 `sensus_core::shaders::{protanopia,deuteranopia,tritanopia}_uniforms(strength)`
//! はグリッド点ちょうど（`strength = i/10.0`, i=0..=10）では**未補間のテーブル値そのもの**
//! を返す（[`tests::grid_strength_round_trips_exactly`] が、この前提となる f32 演算の
//! 性質 — `(i as f32 / 10.0) * 10.0 == i as f32` が i=0..=10 で厳密に成り立つこと — を
//! 検証する）。本モジュールはこの性質を使い、11 グリッド点を公開 API 経由で汲み出して
//! `tools/color_matrices.g.json` に書き出す。手書きの行列値は一切持たない。
//!
//! achromatopsia は severity テーブルを持たず、BT.709 photopic luminance の固定係数
//! （`shaders::achromatopsia_uniforms` の `r_weight`/`g_weight`/`b_weight`。strength に
//! 依存しない）をシェーダが直接使う方式のため、グリッドではなく単一の重み 3 つを書き出す。
//!
//! -omaly（protanomaly 等）は sensus 側で対応する -opia と同一の [`VisionFilter`] に
//! マップされ、severity（strength）を下げて弱め表現するだけなので、専用テーブルは無い
//! （`lib/services/filter_service.dart` の `kAnomalyDefaultSeverity` 参照）。
//!
//! 再生成の実行: `cargo test -- --ignored gen_color_matrices`
//! ドリフト検出（CI 常時実行）: [`tests::generated_json_matches_committed_file`]

#[cfg(test)]
mod tests {
    use sensus_core::shaders;
    use std::fs;
    use std::path::{Path, PathBuf};

    /// `ue/rust/` からの相対パスで `ue/tools/` を指す。
    fn tools_dir() -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("tools")
    }

    /// `Cargo.lock` から `sensus-core` の固定バージョンを読み取る（`shader_dump_gen.rs`
    /// と同じ理由・同じ実装。両モジュールとも依存を増やさず文字列探索で済ませる）。
    fn locked_sensus_core_version() -> String {
        let lock_path = Path::new(env!("CARGO_MANIFEST_DIR")).join("Cargo.lock");
        let text = fs::read_to_string(&lock_path)
            .unwrap_or_else(|e| panic!("failed to read {}: {e}", lock_path.display()));
        let name_idx = text
            .find("name = \"sensus-core\"")
            .unwrap_or_else(|| panic!("sensus-core not found in {}", lock_path.display()));
        let after = &text[name_idx..];
        let version_idx = after
            .find("version = \"")
            .unwrap_or_else(|| panic!("version field not found after sensus-core in Cargo.lock"));
        let rest = &after[version_idx + "version = \"".len()..];
        let end = rest
            .find('"')
            .unwrap_or_else(|| panic!("unterminated version string in Cargo.lock"));
        rest[..end].to_string()
    }

    /// grid 点ぴったりの `strength` を計算する。i=0..=10 に対し `i as f32 / 10.0` を
    /// 返すだけだが、この値が [`grid_strength_round_trips_exactly`] の性質を満たす
    /// ことが「補間なしでテーブル値そのものが取れる」前提になる。
    fn grid_strength(i: u32) -> f32 {
        i as f32 / 10.0
    }

    /// 本モジュールの中核となる数値的前提: `strength = i/10.0`（f32 演算）に対し
    /// `strength * 10.0 == i as f32` が厳密に成り立つこと（i=0..=10）。
    ///
    /// sensus-core の `resolve_severity_matrix`（`pub(crate)` で ue からは呼べない）は
    /// 内部で `scaled = strength * 10.0; i0 = scaled.floor(); frac = scaled - i0;` を計算し、
    /// `frac <= 0.0` のときテーブル値をそのまま返す（補間しない）。この性質が崩れると、
    /// [`dump_targets`] が汲み出す「グリッド点」が実は隣接グリッドとのわずかな補間
    /// （frac が 0 にほぼ等しいが非ゼロ）になり、テーブル値そのものではなくなる。
    /// f32 の IEEE 754 演算は決定的なので、この事実はプラットフォーム非依存で常に成り立つ
    /// （numpy float32 で独立検証済み。本テストは Rust 側でも壊れていないことを守る）。
    #[test]
    fn grid_strength_round_trips_exactly() {
        for i in 0..=10u32 {
            let strength = grid_strength(i);
            let scaled = strength * 10.0;
            assert_eq!(
                scaled, i as f32,
                "grid point {i} (strength={strength}) does not round-trip exactly in f32 \
                 arithmetic — dump_targets() would capture an interpolated value, not the \
                 exact Machado table entry"
            );
        }
    }

    /// f32 を JSON 数値として書く。`{:?}` は shortest round-trip 表現（Dart 側で
    /// double として読み戻しても実用上ビット同等）。`golden_gen.rs`/`shader_dump_gen.rs`
    /// と同じ流儀。
    fn f32_json(v: f32) -> String {
        format!("{v:?}")
    }

    fn matrix9_json(matrix: &[f32; 9]) -> String {
        let body = matrix
            .iter()
            .map(|v| f32_json(*v))
            .collect::<Vec<_>>()
            .join(", ");
        format!("[{body}]")
    }

    /// 1 色覚型分の 11 グリッド点（`[uMatrix0..8]`、行優先）を JSON 配列にする。
    fn grid_json(matrices: [[f32; 9]; 11]) -> String {
        let rows = matrices
            .iter()
            .map(|m| format!("      {}", matrix9_json(m)))
            .collect::<Vec<_>>()
            .join(",\n");
        format!("[\n{rows}\n    ]")
    }

    fn protanopia_grid() -> [[f32; 9]; 11] {
        std::array::from_fn(|i| shaders::protanopia_uniforms(grid_strength(i as u32)).matrix)
    }

    fn deuteranopia_grid() -> [[f32; 9]; 11] {
        std::array::from_fn(|i| shaders::deuteranopia_uniforms(grid_strength(i as u32)).matrix)
    }

    fn tritanopia_grid() -> [[f32; 9]; 11] {
        std::array::from_fn(|i| shaders::tritanopia_uniforms(grid_strength(i as u32)).matrix)
    }

    /// [`build_dump_json`] から `tools/color_matrices.g.json` と同じ文字列を組み立てる。
    fn build_dump_json() -> String {
        let version = locked_sensus_core_version();
        // strength は achromatopsia の重みに影響しない（`achromatopsia_uniforms` 参照）。
        let luma = shaders::achromatopsia_uniforms(0.0);
        format!(
            "{{\n  \"schema\": \"sensus-color-matrices/v1\",\n  \"sensus_core_version\": \"{version}\",\n  \
             \"protanopia_grid\": {},\n  \"deuteranopia_grid\": {},\n  \"tritanopia_grid\": {},\n  \
             \"achromatopsia_weights\": {{ \"r\": {}, \"g\": {}, \"b\": {} }}\n}}\n",
            grid_json(protanopia_grid()),
            grid_json(deuteranopia_grid()),
            grid_json(tritanopia_grid()),
            f32_json(luma.r_weight),
            f32_json(luma.g_weight),
            f32_json(luma.b_weight),
        )
    }

    /// `tools/color_matrices.g.json` を再生成する。既定では実行しない（`#[ignore]`）。
    #[test]
    #[ignore = "one-shot generator; run with --ignored to regenerate tools/color_matrices.g.json"]
    fn gen_color_matrices() {
        let json = build_dump_json();
        let out = tools_dir().join("color_matrices.g.json");
        fs::write(&out, &json).unwrap_or_else(|e| panic!("failed to write {}: {e}", out.display()));
        eprintln!("wrote {}", out.display());
    }

    /// ドリフト検出: [`build_dump_json`] が今 commit されている
    /// `tools/color_matrices.g.json` と byte 一致することを常時（非 ignore）検証する。
    #[test]
    fn generated_json_matches_committed_file() {
        let committed_path = tools_dir().join("color_matrices.g.json");
        let committed = fs::read_to_string(&committed_path).unwrap_or_else(|e| {
            panic!("failed to read committed {}: {e}", committed_path.display())
        });
        let generated = build_dump_json();
        assert_eq!(
            generated, committed,
            "tools/color_matrices.g.json is stale. Run `cargo test -- --ignored \
             gen_color_matrices` from rust/, then `dart run tools/generate_color_matrices.dart` \
             from the repo root, and commit both results."
        );
    }

    /// severity=1.0（グリッド末尾）が sensus_core 公開のディクロマシー定数
    /// （strength=1.0 描画・既存 golden の前提）と食い違っていないことの簡易防御。
    /// golden_gen.rs 側の `protanopia_ref_matches_sensus_core` が画素レベルで守っている
    /// のと同じ不変条件を行列レベルでも確認する（回帰があれば golden よりこちらが先に
    /// 落ちる）。
    ///
    /// **#86 レビュー nit**: [`protanopia_grid`] 等は内部で
    /// `shaders::protanopia_uniforms(1.0).matrix` を呼ぶだけなので、
    /// `protanopia_grid()[10]` を期待値にすると「同じ計算を自分自身と比べる」だけの
    /// 無意味な assert になっていた。sensus-core が独立に公開している定数
    /// `shaders::{PROTANOPIA,DEUTERANOPIA,TRITANOPIA}_MATRIX`（severity=1.0 の
    /// 正解値そのもの）と直接比較する。
    #[test]
    fn severity_1_0_grid_point_matches_sensus_core_dichromacy_constants() {
        let cases: [(&str, [f32; 9], [f32; 9]); 3] = [
            (
                "Protanopia",
                protanopia_grid()[10],
                shaders::PROTANOPIA_MATRIX,
            ),
            (
                "Deuteranopia",
                deuteranopia_grid()[10],
                shaders::DEUTERANOPIA_MATRIX,
            ),
            (
                "Tritanopia",
                tritanopia_grid()[10],
                shaders::TRITANOPIA_MATRIX,
            ),
        ];
        for (name, grid_10, constant) in cases {
            assert_eq!(
                grid_10, constant,
                "{name} severity=1.0 grid point does not match sensus_core's own \
                 published dichromacy constant"
            );
        }
    }
}
