//! `tools/sensus_shaders.g.json` の**一回限りの再生成器**（#56）。
//!
//! sensus 側の shader dumper（`dump_shaders.rs`、README 参照）はこのリポジトリの
//! 管理外（別リポジトリ）にあり、ue の worktree からは書けない。本モジュールは
//! その代わりに、**ue/rust が既にリンクしている sensus-core（Cargo.lock 固定版）**
//! から `shaders::*_glsl()` / [`crate::vision_uniform_layout`] を直接呼び、
//! `tools/sensus_shaders.g.json` と完全互換の JSON を書き出す。GLSL/layout の値は
//! 正本（sensus-core）由来のままで、ue 側では一切再実装しない。
//!
//! 対象フィルタ・除外理由は `tools/generate_shaders.dart` の `_excludedFilters` /
//! `tools/sensus_shaders.README.md` と同期させること（本モジュールはその 20 種を
//! 手で列挙する。除外理由はそちら任せで、本モジュールは対象選定の正本ではない）。
//! この同期は [`tests::dump_targets_and_excluded_stems_cover_all_variants`]
//! （非 ignore）が検証する。
//!
//! 再生成の実行: `cargo test -- --ignored gen_shader_dump`
//! ドリフト検出（CI 常時実行）: [`tests::generated_json_matches_committed_file`]

// lib.rs の `#[cfg(test)] mod shader_dump_gen;` が既にこのファイル全体を
// test 限定にしているため、ここでの `#[cfg(test)]` は付けない（N5: 二重ゲート
// の解消）。
mod tests {
    use crate::{vision_shader_glsl, vision_uniform_layout, VisionFieldLossMode, VisionFilter};
    use std::collections::HashSet;
    use std::fs;
    use std::path::{Path, PathBuf};

    /// `ue/rust/` からの相対パスで `ue/tools/` を指す。
    fn tools_dir() -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("tools")
    }

    /// `Cargo.lock` から `sensus-core` の固定バージョンを読み取る。
    ///
    /// ハードコードすると Cargo.toml の bump 後に再生成し忘れてもドリフトに
    /// 気付けないため、Cargo.lock（実際にビルドで使われているバージョン）を都度
    /// 読む。`[[package]]` ブロックの `name = "sensus-core"` の直後の `version` 行を
    /// 素朴に探す（Cargo.lock は TOML だが、ここでは依存を増やさず文字列探索で足りる）。
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

    /// `vision_uniform_layout()` のラベル（`uMatrix[0]` / `uTexelSize.x` 形式）を
    /// dump JSON の flat 形式（`uMatrix0` / `uTexelSize_x`）へ変換する。
    /// 変換規則は `tools/sensus_shaders.README.md` の layout 節と同じ。
    fn flatten_label(label: &str) -> String {
        if let Some(bracket) = label.find('[') {
            let base = &label[..bracket];
            let digits: String = label[bracket..]
                .chars()
                .filter(char::is_ascii_digit)
                .collect();
            format!("{base}{digits}")
        } else if let Some(dot) = label.find('.') {
            let base = &label[..dot];
            let suffix = &label[dot + 1..];
            format!("{base}_{suffix}")
        } else {
            label.to_string()
        }
    }

    fn json_escape(s: &str) -> String {
        let mut out = String::with_capacity(s.len() + 16);
        for c in s.chars() {
            match c {
                '"' => out.push_str("\\\""),
                '\\' => out.push_str("\\\\"),
                '\n' => out.push_str("\\n"),
                '\r' => out.push_str("\\r"),
                '\t' => out.push_str("\\t"),
                c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
                c => out.push(c),
            }
        }
        out
    }

    /// 1 フィルタ分の JSON エントリ（`{ "name", "glsl", "layout" }`）を組み立てる。
    /// `filter` の payload 値は layout・GLSL いずれにも影響しないため（値依存ではなく
    /// 構造依存）、ダミー値で構わない。
    fn entry(name: &str, filter: VisionFilter) -> String {
        let glsl = vision_shader_glsl(filter);
        let mut layout: Vec<String> = vision_uniform_layout(filter)
            .iter()
            .map(|l| flatten_label(l))
            .collect();
        // Impeller は vTexCoord varying を持たないため、host 側で
        // FlutterFragCoord()/uResolution から UV を導出する。全エントリ共通で
        // 末尾に付与する（README 参照）。
        layout.push("uResolution_x".to_string());
        layout.push("uResolution_y".to_string());
        let layout_json = layout
            .iter()
            .map(|l| format!("\"{}\"", json_escape(l)))
            .collect::<Vec<_>>()
            .join(", ");
        format!(
            "    {{\n      \"name\": \"{name}\",\n      \"glsl\": \"{glsl}\",\n      \"layout\": [{layout_json}]\n    }}",
            name = json_escape(name),
            glsl = json_escape(&glsl),
        )
    }

    /// ダンプ対象 20 種（`(dump 名, ダミー payload 付き VisionFilter)`）。
    ///
    /// host wiring（単一 `uTexture` サンプラ + scalar uniform）に合う種類だけを
    /// 手で列挙する（`tools/sensus_shaders.README.md` Scope 節、
    /// `generate_shaders.dart` の `_excludedFilters` と同期させること）。
    /// [`gen_shader_dump`] と [`generated_json_matches_committed_file`]
    /// の両方がこの 1 箇所を共有する。
    fn dump_targets() -> Vec<(&'static str, VisionFilter)> {
        let darken = VisionFieldLossMode::Darken;
        vec![
            ("protanopia", VisionFilter::Protanopia),
            ("deuteranopia", VisionFilter::Deuteranopia),
            ("tritanopia", VisionFilter::Tritanopia),
            ("achromatopsia", VisionFilter::Achromatopsia),
            ("tetrachromacy", VisionFilter::Tetrachromacy),
            ("myopia", VisionFilter::Myopia),
            ("hyperopia", VisionFilter::Hyperopia),
            ("presbyopia", VisionFilter::Presbyopia),
            ("astigmatism", VisionFilter::Astigmatism { axis_deg: 90.0 }),
            (
                "diplopia",
                VisionFilter::Diplopia {
                    offset_x: 0.05,
                    offset_y: 0.0,
                    ghost_strength: 0.5,
                },
            ),
            (
                "nystagmus",
                VisionFilter::Nystagmus {
                    amplitude: 0.1,
                    direction_deg: 0.0,
                },
            ),
            ("eye_strain", VisionFilter::EyeStrain),
            ("teichopsia", VisionFilter::Teichopsia),
            ("photophobia", VisionFilter::Photophobia),
            ("nyctalopia", VisionFilter::NightBlindness),
            (
                "macular_degeneration",
                VisionFilter::MacularDegeneration {
                    field_loss_mode: darken,
                },
            ),
            (
                "tunnel_vision",
                VisionFilter::TunnelVision {
                    field_loss_mode: darken,
                },
            ),
            (
                "hemianopia",
                VisionFilter::Hemianopia {
                    side: 0.0,
                    field_loss_mode: darken,
                },
            ),
            ("vestibular_neuritis", VisionFilter::VestibularNeuritis),
            ("contrast_sensitivity", VisionFilter::ContrastSensitivity),
        ]
    }

    /// [`dump_targets`] から `tools/sensus_shaders.g.json` と同じ文字列を組み立てる。
    /// `sensus_core_version` は常に [`locked_sensus_core_version`] から取る
    /// （呼び出し側でハードコードしない）。
    fn build_dump_json() -> String {
        let entries: Vec<String> = dump_targets()
            .into_iter()
            .map(|(name, filter)| entry(name, filter))
            .collect();
        let body = entries.join(",\n");
        let version = locked_sensus_core_version();
        format!(
            "{{\n  \"schema\": \"sensus-shader-dump/v1\",\n  \"sensus_core_version\": \"{version}\",\n  \"shaders\": [\n{body}\n  ]\n}}\n"
        )
    }

    /// `tools/sensus_shaders.g.json` を再生成する。
    ///
    /// 対象は host wiring（単一 `uTexture` サンプラ + scalar uniform）に合う 20 種
    /// （`tools/sensus_shaders.README.md` Scope 節、`generate_shaders.dart` の
    /// `_excludedFilters` と同期）。既定では実行しない（`#[ignore]`）。
    #[test]
    #[ignore = "one-shot generator; run with --ignored to regenerate tools/sensus_shaders.g.json"]
    fn gen_shader_dump() {
        let json = build_dump_json();
        let out = tools_dir().join("sensus_shaders.g.json");
        fs::write(&out, &json).unwrap_or_else(|e| panic!("failed to write {}: {e}", out.display()));
        eprintln!("wrote {} ({} filters)", out.display(), dump_targets().len());
    }

    /// ドリフト検出（レビュー S2）: [`build_dump_json`] が今 commit されている
    /// `tools/sensus_shaders.g.json` と byte 一致することを常時（非 ignore）検証する。
    /// sensus-core を更新したのにダンプを再生成し忘れると、このテストが CI で落ちる。
    #[test]
    fn generated_json_matches_committed_file() {
        let committed_path = tools_dir().join("sensus_shaders.g.json");
        let committed = fs::read_to_string(&committed_path).unwrap_or_else(|e| {
            panic!("failed to read committed {}: {e}", committed_path.display())
        });
        let generated = build_dump_json();
        assert_eq!(
            generated, committed,
            "tools/sensus_shaders.g.json is stale. Run `cargo test -- --ignored \
             gen_shader_dump` from rust/ and commit the result."
        );
    }

    /// [`dump_targets`] の 20 種と、`tools/generate_shaders.dart` の
    /// `_excludedFilters`（ここに手でミラーする）が、重複なく sensus-core の
    /// 全 30 `VisionFilter` を覆っていることを検証する（レビュー S2）。
    ///
    /// `depth_aware_blur` だけは対応する `VisionFilter` variant が存在しない
    /// sensus 内部シェーダ（第2サンプラ `uDepth`）なので、variant の網羅対象
    /// からは別扱いする。
    #[test]
    fn dump_targets_and_excluded_stems_cover_all_variants() {
        use crate::api::sensus_bridge::tests::ALL_FILTERS;

        // tools/generate_shaders.dart の `_excludedFilters` のキーのうち、
        // 実在する VisionFilter variant に対応する 10 種（depth_aware_blur を除く）。
        const EXCLUDED_VARIANTS: [&str; 10] = [
            "dry_eye",
            "starbursts",
            "glaucoma",
            "cataract",
            "flickering_stars",
            "metamorphopsia",
            "vertigo",
            "bppv_rotation",
            "floaters",
            "detail_loss",
        ];
        // 対応する VisionFilter variant が無い、sensus 内部シェーダ。
        const EXCLUDED_NON_VARIANT: [&str; 1] = ["depth_aware_blur"];

        let dumped_names: HashSet<&str> = dump_targets().iter().map(|(name, _)| *name).collect();
        assert_eq!(
            dumped_names.len(),
            20,
            "dump_targets() の対象数が20から変わった"
        );

        for name in &dumped_names {
            assert!(
                !EXCLUDED_VARIANTS.contains(name),
                "{name} is listed as both dumped and excluded"
            );
        }

        let mut covered: HashSet<&str> = dumped_names.clone();
        covered.extend(EXCLUDED_VARIANTS);

        let all_variant_stems: HashSet<&str> = ALL_FILTERS.iter().map(canonical_stem).collect();
        assert_eq!(
            all_variant_stems.len(),
            30,
            "ALL_FILTERS の variant 数が30から変わった"
        );

        assert_eq!(
            covered, all_variant_stems,
            "dump_targets() + _excludedFilters(ミラー) が VisionFilter 全30種と \
             一致しない。新しい variant を追加したら dump_targets() / \
             tools/generate_shaders.dart の _excludedFilters / このテストの \
             いずれかを更新すること"
        );

        for name in EXCLUDED_NON_VARIANT {
            assert!(
                !all_variant_stems.contains(name),
                "{name} に対応する VisionFilter variant が追加された場合は \
                 この特別扱いを外すこと"
            );
        }
    }

    /// [`VisionFilter`] variant → dump/shader の canonical stem 名。
    ///
    /// [`dump_targets`] が使う名前と一致させる（`night_blindness` variant だけ
    /// sensus 側のシェーダ stem が `nyctalopia` という例外的なエイリアスを持つ）。
    /// payload の値は無視する（`{ .. }`）。
    fn canonical_stem(f: &VisionFilter) -> &'static str {
        match f {
            VisionFilter::Protanopia => "protanopia",
            VisionFilter::Deuteranopia => "deuteranopia",
            VisionFilter::Tritanopia => "tritanopia",
            VisionFilter::Achromatopsia => "achromatopsia",
            VisionFilter::Tetrachromacy => "tetrachromacy",
            VisionFilter::Myopia => "myopia",
            VisionFilter::Hyperopia => "hyperopia",
            VisionFilter::Presbyopia => "presbyopia",
            VisionFilter::Astigmatism { .. } => "astigmatism",
            VisionFilter::Glaucoma { .. } => "glaucoma",
            VisionFilter::MacularDegeneration { .. } => "macular_degeneration",
            VisionFilter::Hemianopia { .. } => "hemianopia",
            VisionFilter::TunnelVision { .. } => "tunnel_vision",
            VisionFilter::Cataract { .. } => "cataract",
            VisionFilter::Floaters { .. } => "floaters",
            VisionFilter::Photophobia => "photophobia",
            // sensus 側のシェーダ stem は nyctalopia（旧称）。
            VisionFilter::NightBlindness => "nyctalopia",
            VisionFilter::Vertigo => "vertigo",
            VisionFilter::BppvRotation => "bppv_rotation",
            VisionFilter::VestibularNeuritis => "vestibular_neuritis",
            VisionFilter::Diplopia { .. } => "diplopia",
            VisionFilter::Nystagmus { .. } => "nystagmus",
            VisionFilter::Starbursts { .. } => "starbursts",
            VisionFilter::EyeStrain => "eye_strain",
            VisionFilter::DryEye => "dry_eye",
            VisionFilter::Metamorphopsia { .. } => "metamorphopsia",
            VisionFilter::ContrastSensitivity => "contrast_sensitivity",
            VisionFilter::DetailLoss { .. } => "detail_loss",
            VisionFilter::Teichopsia => "teichopsia",
            VisionFilter::FlickeringStars { .. } => "flickering_stars",
        }
    }
}
