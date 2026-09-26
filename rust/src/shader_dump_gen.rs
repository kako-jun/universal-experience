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
//!
//! 実行: `cargo test -- --ignored gen_shader_dump`

#[cfg(test)]
mod tests {
    use crate::{vision_shader_glsl, vision_uniform_layout, VisionFieldLossMode, VisionFilter};
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

    /// `tools/sensus_shaders.g.json` を再生成する。
    ///
    /// 対象は host wiring（単一 `uTexture` サンプラ + scalar uniform）に合う 20 種
    /// （`tools/sensus_shaders.README.md` Scope 節、`generate_shaders.dart` の
    /// `_excludedFilters` と同期）。既定では実行しない（`#[ignore]`）。
    #[test]
    #[ignore = "one-shot generator; run with --ignored to regenerate tools/sensus_shaders.g.json"]
    fn gen_shader_dump() {
        let darken = VisionFieldLossMode::Darken;
        let entries = [
            entry("protanopia", VisionFilter::Protanopia),
            entry("deuteranopia", VisionFilter::Deuteranopia),
            entry("tritanopia", VisionFilter::Tritanopia),
            entry("achromatopsia", VisionFilter::Achromatopsia),
            entry("tetrachromacy", VisionFilter::Tetrachromacy),
            entry("myopia", VisionFilter::Myopia),
            entry("hyperopia", VisionFilter::Hyperopia),
            entry("presbyopia", VisionFilter::Presbyopia),
            entry("astigmatism", VisionFilter::Astigmatism { axis_deg: 90.0 }),
            entry(
                "diplopia",
                VisionFilter::Diplopia {
                    offset_x: 0.05,
                    offset_y: 0.0,
                    ghost_strength: 0.5,
                },
            ),
            entry(
                "nystagmus",
                VisionFilter::Nystagmus {
                    amplitude: 0.1,
                    direction_deg: 0.0,
                },
            ),
            entry("eye_strain", VisionFilter::EyeStrain),
            entry("teichopsia", VisionFilter::Teichopsia),
            entry("photophobia", VisionFilter::Photophobia),
            entry("nyctalopia", VisionFilter::NightBlindness),
            entry(
                "macular_degeneration",
                VisionFilter::MacularDegeneration {
                    field_loss_mode: darken,
                },
            ),
            entry(
                "tunnel_vision",
                VisionFilter::TunnelVision {
                    field_loss_mode: darken,
                },
            ),
            entry(
                "hemianopia",
                VisionFilter::Hemianopia {
                    side: 0.0,
                    field_loss_mode: darken,
                },
            ),
            entry("vestibular_neuritis", VisionFilter::VestibularNeuritis),
            entry("contrast_sensitivity", VisionFilter::ContrastSensitivity),
        ];
        let body = entries.join(",\n");
        let version = locked_sensus_core_version();
        let json = format!(
            "{{\n  \"schema\": \"sensus-shader-dump/v1\",\n  \"sensus_core_version\": \"{version}\",\n  \"shaders\": [\n{body}\n  ]\n}}\n"
        );
        let out = tools_dir().join("sensus_shaders.g.json");
        fs::write(&out, &json).unwrap_or_else(|e| panic!("failed to write {}: {e}", out.display()));
        eprintln!(
            "wrote {} ({} filters, sensus-core {version})",
            out.display(),
            entries.len()
        );
    }
}
