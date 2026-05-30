//! sensus-core への薄いブリッジ。
//!
//! Dart 側（FragmentProgram）が必要とするのは次の 2 つ:
//!
//! 1. **シェーダ本体（GLSL ソース）** — ビルド時に Flutter アセットへ同期する用途。
//!    ランタイムにここで取得して文字列を Flutter へ渡すわけではない（stable の
//!    `FragmentProgram` は `fromSource` を持たないため）。同期スクリプトが
//!    `vision_shader_glsl()` を呼んで `.frag` を吐く、という使い方を想定する。
//! 2. **uniform 値** — フィルタごとの `sensus_core::shaders::*_uniforms()` を呼び、
//!    FragmentProgram に `setFloat(i, value)` する順序の flat な `Vec<f32>` にして返す。
//!    どのインデックスが何かは [`vision_uniform_layout`] が返すラベルで Dart から分かる。
//!
//! アルゴリズム（行列値・半径式・色係数）は一切ここで持たない。すべて
//! `sensus_core::shaders` の戻り値をそのまま展開するだけにして、正本を一元化する。

use sensus_core::shaders;

/// Dart 側で扱う vision フィルタ（MVP サブセット）。
///
/// sensus_core::Filter のうち、本 Issue (#7, sensus 連携 1/3) でブリッジを
/// 通すものだけを列挙する。MVP は色覚 4 種 + 解像度依存の 2 例。全フィルタ網羅は
/// 後続フェーズで `sensus_core::Filter` 全バリアントへ拡張する。
///
/// パラメータは MVP では `strength` 中心とし、解像度依存フィルタは
/// [`vision_uniforms`] へ `width`/`height` を、ランダム系は `seed` を渡す。
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum VisionFilter {
    /// 1型2色覚（赤）。uniform: uStrength + uMatrix[9]。
    Protanopia,
    /// 2型2色覚（緑）。uniform: uStrength + uMatrix[9]。
    Deuteranopia,
    /// 3型2色覚（青黄）。uniform: uStrength + uMatrix[9]。
    Tritanopia,
    /// 全色盲。uniform: uStrength + RGB luma weights。
    Achromatopsia,
    /// 近視（解像度依存の disk blur）。uniform: uStrength + uRadiusPx + uTexelSize。
    Myopia,
    /// 羞明（解像度依存の bloom）。uniform: uRadiusPx + uTexelSize（uStrength なし）。
    Photophobia,
}

/// 指定フィルタの GLSL ES 3.00 ソースを返す。
///
/// **用途**: ビルド時に Flutter アセット（または impeller 変換前の中間 `.frag`）
/// へ書き出す同期スクリプト用。実機ランタイムでこの文字列を直接 Flutter の
/// `FragmentProgram` に流し込むことはできない（理由は docs/sensus-integration.md）。
#[flutter_rust_bridge::frb(sync)]
pub fn vision_shader_glsl(filter: VisionFilter) -> String {
    match filter {
        VisionFilter::Protanopia => shaders::protanopia_glsl(),
        VisionFilter::Deuteranopia => shaders::deuteranopia_glsl(),
        VisionFilter::Tritanopia => shaders::tritanopia_glsl(),
        VisionFilter::Achromatopsia => shaders::achromatopsia_glsl(),
        VisionFilter::Myopia => shaders::myopia_glsl(),
        VisionFilter::Photophobia => shaders::photophobia_glsl(),
    }
    .to_string()
}

/// 指定フィルタの uniform を、FragmentProgram に `setFloat(i, ..)` する順序の
/// flat な `Vec<f32>` にして返す。
///
/// `sampler2D uTexture`（= 入力画像）は `setFloat` の対象外なので含めない。
/// Flutter 側では float uniform を `setFloat(0..)` で順に積み、サンプラは
/// `setImageSampler(0, ..)` で別途渡す。各インデックスの意味は
/// [`vision_uniform_layout`] が返すラベルと一致する（同じ順序）。
///
/// # 引数
/// - `strength`: 0.0..=1.0（範囲外は sensus 側で clamp される）。
/// - `width` / `height`: 入力画像のピクセルサイズ。解像度依存フィルタ
///   （Myopia / Photophobia）の半径・texel size 算出に使う。色覚 4 種では未使用。
/// - `seed`: ランダム系フィルタ用シード。MVP のフィルタでは未使用だが、後続で
///   Cataract / Floaters 等を足すときに使う（署名を安定させるため今から受ける）。
///
/// # 各フィルタの返却レイアウト
/// - Protanopia / Deuteranopia / Tritanopia:
///   `[uStrength, uMatrix0, uMatrix1, .., uMatrix8]`（計 10 要素）
/// - Achromatopsia: `[uStrength, uRWeight, uGWeight, uBWeight]`（計 4 要素）
/// - Myopia: `[uStrength, uRadiusPx, uTexelSizeX, uTexelSizeY]`（計 4 要素）
/// - Photophobia: `[uRadiusPx, uTexelSizeX, uTexelSizeY]`（計 3 要素。
///   photophobia.frag は `uStrength` を持たない — strength は半径へ畳み込み済み）
#[flutter_rust_bridge::frb(sync)]
pub fn vision_uniforms(
    filter: VisionFilter,
    strength: f32,
    width: u32,
    height: u32,
    _seed: u64,
) -> Vec<f32> {
    match filter {
        VisionFilter::Protanopia => {
            let u = shaders::protanopia_uniforms(strength);
            color_matrix_flat(u)
        }
        VisionFilter::Deuteranopia => {
            let u = shaders::deuteranopia_uniforms(strength);
            color_matrix_flat(u)
        }
        VisionFilter::Tritanopia => {
            let u = shaders::tritanopia_uniforms(strength);
            color_matrix_flat(u)
        }
        VisionFilter::Achromatopsia => {
            let u = shaders::achromatopsia_uniforms(strength);
            vec![u.strength, u.r_weight, u.g_weight, u.b_weight]
        }
        VisionFilter::Myopia => {
            let u = shaders::myopia_uniforms(strength, width.min(height));
            vec![
                u.strength,
                u.radius_px,
                1.0 / width as f32,
                1.0 / height as f32,
            ]
        }
        VisionFilter::Photophobia => {
            let u = shaders::photophobia_uniforms(strength, width, height);
            // photophobia.frag は uStrength を持たない。strength は radius_px に
            // 畳み込まれているため、uniform は radius + texel のみ。
            vec![u.radius_px, u.texel_size[0], u.texel_size[1]]
        }
    }
}

/// `ColorMatrixUniforms` を `[uStrength, uMatrix0..8]` の flat 配列へ展開する。
fn color_matrix_flat(u: shaders::ColorMatrixUniforms) -> Vec<f32> {
    let mut v = Vec::with_capacity(10);
    v.push(u.strength);
    v.extend_from_slice(&u.matrix);
    v
}

/// 指定フィルタの uniform レイアウト（各 `setFloat` インデックスのラベル）を返す。
///
/// 返る `Vec<String>` の長さと順序は [`vision_uniforms`] の `Vec<f32>` と一致する。
/// Dart 側はこのラベル列で「インデックス i は何の値か」を機械的に確認できる
/// （`.frag` の uniform 宣言順と突き合わせる用途）。
#[flutter_rust_bridge::frb(sync)]
pub fn vision_uniform_layout(filter: VisionFilter) -> Vec<String> {
    let labels: &[&str] = match filter {
        VisionFilter::Protanopia | VisionFilter::Deuteranopia | VisionFilter::Tritanopia => &[
            "uStrength",
            "uMatrix[0]",
            "uMatrix[1]",
            "uMatrix[2]",
            "uMatrix[3]",
            "uMatrix[4]",
            "uMatrix[5]",
            "uMatrix[6]",
            "uMatrix[7]",
            "uMatrix[8]",
        ],
        VisionFilter::Achromatopsia => &["uStrength", "uRWeight", "uGWeight", "uBWeight"],
        VisionFilter::Myopia => &["uStrength", "uRadiusPx", "uTexelSize.x", "uTexelSize.y"],
        VisionFilter::Photophobia => &["uRadiusPx", "uTexelSize.x", "uTexelSize.y"],
    };
    labels.iter().map(|s| s.to_string()).collect()
}

/// （将来用）sensus-core の CPU `apply` を 1 つだけ薄く公開する。
///
/// GPU（FragmentProgram）経路が主のため MVP では未使用だが、テストや
/// GPU 非対応環境のフォールバックに備えて残す。生 RGBA8（`width * height * 4`
/// バイト）を入力し、同じレイアウトの RGBA8 を返す。
///
/// 注意: これは sensus の `image::DynamicImage` 経路を通すため GPU 経路より遅い。
/// 大きな画像をリアルタイム処理する用途には使わないこと。
#[flutter_rust_bridge::frb(sync)]
pub fn apply_vision_cpu_rgba8(
    filter: VisionFilter,
    rgba8: Vec<u8>,
    width: u32,
    height: u32,
    strength: f32,
) -> Result<Vec<u8>, String> {
    use sensus_core::Filter;

    let expected = (width as usize) * (height as usize) * 4;
    if rgba8.len() != expected {
        return Err(format!(
            "rgba8 length {} != width*height*4 ({})",
            rgba8.len(),
            expected
        ));
    }

    let img = image::RgbaImage::from_raw(width, height, rgba8)
        .ok_or_else(|| "failed to build RgbaImage from raw buffer".to_string())?;
    let dynimg = image::DynamicImage::ImageRgba8(img);

    let f = match filter {
        VisionFilter::Protanopia => Filter::Protanopia,
        VisionFilter::Deuteranopia => Filter::Deuteranopia,
        VisionFilter::Tritanopia => Filter::Tritanopia,
        VisionFilter::Achromatopsia => Filter::Achromatopsia,
        VisionFilter::Myopia => Filter::Myopia,
        VisionFilter::Photophobia => Filter::Photophobia,
    };

    let out = sensus_core::apply(f, dynimg, strength).map_err(|e| e.to_string())?;
    Ok(out.to_rgba8().into_raw())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn glsl_sources_are_non_empty() {
        for f in [
            VisionFilter::Protanopia,
            VisionFilter::Deuteranopia,
            VisionFilter::Tritanopia,
            VisionFilter::Achromatopsia,
            VisionFilter::Myopia,
            VisionFilter::Photophobia,
        ] {
            assert!(!vision_shader_glsl(f).is_empty());
        }
    }

    #[test]
    fn color_matrix_layout_matches_uniforms_len() {
        for f in [
            VisionFilter::Protanopia,
            VisionFilter::Deuteranopia,
            VisionFilter::Tritanopia,
        ] {
            let u = vision_uniforms(f, 1.0, 100, 100, 0);
            let l = vision_uniform_layout(f);
            assert_eq!(u.len(), 10);
            assert_eq!(u.len(), l.len());
        }
    }

    #[test]
    fn achromatopsia_layout_matches() {
        let u = vision_uniforms(VisionFilter::Achromatopsia, 1.0, 100, 100, 0);
        let l = vision_uniform_layout(VisionFilter::Achromatopsia);
        assert_eq!(u.len(), 4);
        assert_eq!(u.len(), l.len());
        // BT.709 luma weights が sensus からそのまま来ること
        assert!((u[1] - 0.2126).abs() < 1e-6);
    }

    #[test]
    fn myopia_uniforms_include_texel_size() {
        let u = vision_uniforms(VisionFilter::Myopia, 1.0, 200, 100, 0);
        let l = vision_uniform_layout(VisionFilter::Myopia);
        assert_eq!(u.len(), 4);
        assert_eq!(u.len(), l.len());
        // texel size = 1/width, 1/height
        assert!((u[2] - 1.0 / 200.0).abs() < 1e-6);
        assert!((u[3] - 1.0 / 100.0).abs() < 1e-6);
    }

    #[test]
    fn photophobia_has_no_strength_uniform() {
        let u = vision_uniforms(VisionFilter::Photophobia, 1.0, 200, 100, 0);
        let l = vision_uniform_layout(VisionFilter::Photophobia);
        assert_eq!(u.len(), 3);
        assert_eq!(u.len(), l.len());
        assert_eq!(l[0], "uRadiusPx");
    }

    #[test]
    fn cpu_apply_rejects_wrong_buffer_len() {
        let r = apply_vision_cpu_rgba8(VisionFilter::Protanopia, vec![0u8; 10], 4, 4, 1.0);
        assert!(r.is_err());
    }

    #[test]
    fn cpu_apply_roundtrips_size() {
        let w = 4u32;
        let h = 4u32;
        let buf = vec![128u8; (w * h * 4) as usize];
        let out = apply_vision_cpu_rgba8(VisionFilter::Protanopia, buf, w, h, 1.0).unwrap();
        assert_eq!(out.len(), (w * h * 4) as usize);
    }

    /// 全フィルタを 1 ループで列挙するためのヘルパ。バリアントが増えたら
    /// ここに追加するだけで全網羅テストが拾う。
    const ALL_FILTERS: [VisionFilter; 6] = [
        VisionFilter::Protanopia,
        VisionFilter::Deuteranopia,
        VisionFilter::Tritanopia,
        VisionFilter::Achromatopsia,
        VisionFilter::Myopia,
        VisionFilter::Photophobia,
    ];

    /// 最重要不変条件: 全バリアントで uniforms の長さが layout の長さと一致する。
    /// ズレると Dart 側 setFloat(i, ..) のインデックスが壊れる。
    #[test]
    fn all_filters_uniforms_len_matches_layout() {
        for f in ALL_FILTERS {
            let u = vision_uniforms(f, 0.5, 256, 128, 0);
            let l = vision_uniform_layout(f);
            assert_eq!(
                u.len(),
                l.len(),
                "{f:?}: uniforms len {} != layout len {}",
                u.len(),
                l.len()
            );
            assert!(!l.is_empty(), "{f:?}: layout must not be empty");
        }
    }

    /// 全バリアントで layout が非空ラベルを返す（空文字のプレースホルダ混入を防ぐ）。
    #[test]
    fn all_filters_layout_labels_non_empty() {
        for f in ALL_FILTERS {
            for (i, label) in vision_uniform_layout(f).iter().enumerate() {
                assert!(!label.is_empty(), "{f:?}: layout[{i}] is empty");
            }
        }
    }

    /// 解像度依存フィルタ（Myopia）: width/height を変えると texel size と
    /// 半径が変わる。解像度に依存しない色覚フィルタは値が変わらないことも確認。
    #[test]
    fn myopia_uniforms_track_resolution() {
        let small = vision_uniforms(VisionFilter::Myopia, 1.0, 100, 100, 0);
        let large = vision_uniforms(VisionFilter::Myopia, 1.0, 400, 400, 0);
        // texel size = 1/dim なので解像度で変わる。
        assert!((small[2] - 1.0 / 100.0).abs() < 1e-6);
        assert!((large[2] - 1.0 / 400.0).abs() < 1e-6);
        assert_ne!(small[2], large[2]);
        // radius_px は min(width,height) に比例するので大きい画像ほど大きい。
        assert!(large[1] > small[1]);
    }

    /// 解像度依存フィルタ（Photophobia）: 解像度で radius と texel が変わる。
    #[test]
    fn photophobia_uniforms_track_resolution() {
        let small = vision_uniforms(VisionFilter::Photophobia, 1.0, 100, 100, 0);
        let large = vision_uniforms(VisionFilter::Photophobia, 1.0, 400, 400, 0);
        // layout: [uRadiusPx, uTexelSize.x, uTexelSize.y]
        assert!((small[1] - 1.0 / 100.0).abs() < 1e-6);
        assert!((large[1] - 1.0 / 400.0).abs() < 1e-6);
        assert!(large[0] > small[0]); // radius_px が解像度で増える
    }

    /// 色覚フィルタは解像度に依存しない（width/height を変えても uniform 不変）。
    #[test]
    fn color_matrix_uniforms_ignore_resolution() {
        for f in [
            VisionFilter::Protanopia,
            VisionFilter::Deuteranopia,
            VisionFilter::Tritanopia,
            VisionFilter::Achromatopsia,
        ] {
            let a = vision_uniforms(f, 0.7, 100, 100, 0);
            let b = vision_uniforms(f, 0.7, 999, 333, 0);
            assert_eq!(
                a, b,
                "{f:?}: color filter uniforms must not depend on resolution"
            );
        }
    }

    /// Photophobia は uStrength uniform を持たないが、strength は radius_px に
    /// 畳み込まれている。strength を上げると radius_px が増えることの回帰。
    #[test]
    fn photophobia_strength_folds_into_radius() {
        let weak = vision_uniforms(VisionFilter::Photophobia, 0.1, 200, 200, 0);
        let strong = vision_uniforms(VisionFilter::Photophobia, 0.9, 200, 200, 0);
        // index 0 = uRadiusPx
        assert!(strong[0] > weak[0]);
        // strength=0 なら bloom 半径は 0。
        let zero = vision_uniforms(VisionFilter::Photophobia, 0.0, 200, 200, 0);
        assert!(zero[0].abs() < 1e-6);
    }

    /// strength の境界・異常値を渡しても panic せず、長さ不変・有限値が返る
    /// （clamp / NaN→0 は sensus 側 normalize_strength に委譲）。
    #[test]
    fn strength_extremes_do_not_panic() {
        for f in ALL_FILTERS {
            let layout_len = vision_uniform_layout(f).len();
            for s in [0.0_f32, 1.0, -5.0, 100.0, f32::NAN, f32::INFINITY] {
                let u = vision_uniforms(f, s, 256, 128, 0);
                assert_eq!(u.len(), layout_len, "{f:?} s={s}: length changed");
                for (i, v) in u.iter().enumerate() {
                    assert!(v.is_finite(), "{f:?} s={s}: uniform[{i}] not finite ({v})");
                }
            }
        }
    }

    /// 全バリアントで CPU apply が入力と同サイズの RGBA を返す（非正方・矩形含む）。
    #[test]
    fn cpu_apply_roundtrips_size_all_filters_non_square() {
        let w = 8u32;
        let h = 5u32;
        let len = (w * h * 4) as usize;
        for f in ALL_FILTERS {
            let buf = vec![64u8; len];
            let out = apply_vision_cpu_rgba8(f, buf, w, h, 0.6).unwrap();
            assert_eq!(out.len(), len, "{f:?}: output size mismatch");
        }
    }
}
