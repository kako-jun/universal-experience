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
//!
//! # u32 / uint シードと count の扱い
//!
//! flat 配列の要素はすべて `f32`。`cataract` / `floaters` / `metamorphopsia` /
//! `flickering_stars` の `uSeed`（GLSL では `uint`）や `uCount`（`int`）も f32 に
//! 詰める。FragmentProgram には float uniform しか積まないため、Dart 側で
//! `setFloat(i, value)` した後、シェーダの `uint`/`int` uniform へは Flutter の
//! sampler/float bridge 経由で渡らない点に注意（これらの整数 uniform を使う実描画は
//! #11 の GPU パスで個別に詰める）。本ブリッジが保証するのは「値そのもの」と
//! 「レイアウト（順序）」であり、float の bit 精度は u32 が 2^24 を超えると失われる。
//! seed は基本 0..少数を想定するため実害はないが、層を超える際の前提として明記する。

use sensus_core::shaders;

/// 緑内障の暗点モード。`sensus_core::vision::GlaucomaMode` の FRB 公開ミラー。
///
/// FRB は外部クレートの enum を直接 Dart へ出せないため、ue 側で同型を定義して
/// [`to_sensus`](VisionGlaucomaMode::to_sensus) で変換する。値は
/// `glaucoma.frag` の `uMode`（0..3）に 1 対 1 対応する。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VisionGlaucomaMode {
    /// 中心保存 + 周辺 smoothstep vignetting（既定）。uMode=0。
    Vignette,
    /// 上方弧状暗点（Bjerrum 上方）。uMode=1。
    ArcuateSuperior,
    /// 下方弧状暗点（Bjerrum 下方）。uMode=2。
    ArcuateInferior,
    /// 両弧状暗点（進行例）。uMode=3。
    Biarcuate,
}

impl VisionGlaucomaMode {
    fn to_sensus(self) -> sensus_core::vision::GlaucomaMode {
        use sensus_core::vision::GlaucomaMode as G;
        match self {
            VisionGlaucomaMode::Vignette => G::Vignette,
            VisionGlaucomaMode::ArcuateSuperior => G::ArcuateSuperior,
            VisionGlaucomaMode::ArcuateInferior => G::ArcuateInferior,
            VisionGlaucomaMode::Biarcuate => G::Biarcuate,
        }
    }

    fn from_sensus(mode: sensus_core::vision::GlaucomaMode) -> Self {
        use sensus_core::vision::GlaucomaMode as G;
        match mode {
            G::Vignette => VisionGlaucomaMode::Vignette,
            G::ArcuateSuperior => VisionGlaucomaMode::ArcuateSuperior,
            G::ArcuateInferior => VisionGlaucomaMode::ArcuateInferior,
            G::Biarcuate => VisionGlaucomaMode::Biarcuate,
        }
    }
}

/// Dart 側で扱う vision フィルタ。`sensus_core::Filter` の vision バリアント全種を
/// 網羅する。payload を持つフィルタは Rust enum のフィールド付きバリアントにして
/// あり、FRB が Dart の sealed class 風コードを生成する。
///
/// uniform レイアウトは各 `.frag` の uniform 宣言順（`sampler2D` を除く）に
/// 厳密一致させる。詳細は [`vision_uniforms`] と [`vision_uniform_layout`] を参照。
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum VisionFilter {
    // --- 色覚 (CVD) ---
    /// 1型2色覚（赤）。uniform: uStrength + uMatrix[9]。
    Protanopia,
    /// 2型2色覚（緑）。uniform: uStrength + uMatrix[9]。
    Deuteranopia,
    /// 3型2色覚（青黄）。uniform: uStrength + uMatrix[9]。
    Tritanopia,
    /// 全色盲。uniform: uStrength + RGB luma weights。
    Achromatopsia,
    /// 四色型色覚。uniform: uStrength。
    Tetrachromacy,

    // --- 焦点 / 屈折 ---
    /// 近視（解像度依存の disk blur）。
    Myopia,
    /// 遠視（disk blur）。
    Hyperopia,
    /// 老視（disk blur）。
    Presbyopia,
    /// 乱視。`axis_deg`: シャープ方向の経線角（度数法、医学慣習）。
    Astigmatism { axis_deg: f32 },

    // --- 視野 ---
    /// 緑内障。`mode`: 暗点モード。
    Glaucoma { mode: VisionGlaucomaMode },
    /// 加齢黄斑変性。
    MacularDegeneration,
    /// 半盲。`side`: 0.0 = 左視野消失, 1.0 = 右視野消失。
    Hemianopia { side: f32 },
    /// 視野狭窄（トンネル視）。
    TunnelVision,

    // --- 光 / 透明度 ---
    /// 白内障。`seed`: 散乱グレア生成シード。
    Cataract { seed: u64 },
    /// 飛蚊症。`seed`/`density`/`size`/`gaze_x`/`gaze_y`。
    Floaters {
        seed: u64,
        density: f32,
        size: f32,
        gaze_x: f32,
        gaze_y: f32,
    },
    /// 羞明（解像度依存の bloom）。
    Photophobia,
    /// 夜盲。
    NightBlindness,

    // --- 平衡感覚 / めまい ---
    /// 浮動性めまい（時間依存）。
    Vertigo,
    /// BPPV 回転性めまい（時間依存）。
    BppvRotation,
    /// 前庭神経炎。
    VestibularNeuritis,

    // --- 複視 / 眼振 / 光芒 ---
    /// 複視。`offset_x`/`offset_y`: 幽霊像のずれ（min(W,H) 比のピクセル）, `ghost_strength`: 幽霊像強度。
    Diplopia {
        offset_x: f32,
        offset_y: f32,
        ghost_strength: f32,
    },
    /// 眼振。`amplitude`: 振幅（min(W,H) 比）, `direction_deg`: 揺れ方向（度数法）。
    Nystagmus { amplitude: f32, direction_deg: f32 },
    /// 光芒。`num_rays`/`ray_length_ratio`/`threshold`/`dispersion`。
    Starbursts {
        num_rays: u32,
        ray_length_ratio: f32,
        threshold: f32,
        dispersion: f32,
    },

    // --- 眼精疲労 ---
    /// 眼精疲労。
    EyeStrain,
    /// ドライアイ。
    DryEye,

    // --- 変視症 / コントラスト / ピクセル化 ---
    /// 変視症（歪み）。`freq`: 空間周波数, `seed`: 歪み場シード。
    Metamorphopsia { freq: f32, seed: u64 },
    /// コントラスト感度低下。
    ContrastSensitivity,
    /// ディテールロス（ピクセル化）。`cell_size`: タイルサイズ (px)。
    DetailLoss { cell_size: u32 },

    // --- 閃輝暗点 ---
    /// 閃輝暗点。
    Teichopsia,
    /// 閃輝（光の星）。`seed`: ランダムシード。
    FlickeringStars { seed: u64 },
}

impl VisionFilter {
    /// CPU `apply` 経路用に `sensus_core::Filter` へ変換する。payload は
    /// そのまま転送する。色覚・焦点などパラメータ無しバリアントは引数なしの
    /// sensus バリアントへマップする。
    fn to_sensus(self) -> sensus_core::Filter {
        use sensus_core::Filter as F;
        match self {
            VisionFilter::Protanopia => F::Protanopia,
            VisionFilter::Deuteranopia => F::Deuteranopia,
            VisionFilter::Tritanopia => F::Tritanopia,
            VisionFilter::Achromatopsia => F::Achromatopsia,
            VisionFilter::Tetrachromacy => F::Tetrachromacy,
            VisionFilter::Myopia => F::Myopia,
            VisionFilter::Hyperopia => F::Hyperopia,
            VisionFilter::Presbyopia => F::Presbyopia,
            VisionFilter::Astigmatism { axis_deg } => F::Astigmatism { axis_deg },
            VisionFilter::Glaucoma { mode } => F::Glaucoma {
                mode: mode.to_sensus(),
            },
            VisionFilter::MacularDegeneration => F::MacularDegeneration,
            VisionFilter::Hemianopia { side } => F::Hemianopia { side },
            VisionFilter::TunnelVision => F::TunnelVision,
            VisionFilter::Cataract { seed } => F::Cataract { seed },
            VisionFilter::Floaters {
                seed,
                density,
                size,
                gaze_x,
                gaze_y,
            } => F::Floaters {
                seed,
                density,
                size,
                gaze_x,
                gaze_y,
            },
            VisionFilter::Photophobia => F::Photophobia,
            VisionFilter::NightBlindness => F::NightBlindness,
            VisionFilter::Vertigo => F::Vertigo,
            VisionFilter::BppvRotation => F::BppvRotation,
            VisionFilter::VestibularNeuritis => F::VestibularNeuritis,
            VisionFilter::Diplopia {
                offset_x,
                offset_y,
                ghost_strength,
            } => F::Diplopia {
                offset_x,
                offset_y,
                ghost_strength,
            },
            VisionFilter::Nystagmus {
                amplitude,
                direction_deg,
            } => F::Nystagmus {
                amplitude,
                direction_deg,
            },
            VisionFilter::Starbursts {
                num_rays,
                ray_length_ratio,
                threshold,
                dispersion,
            } => F::Starbursts {
                num_rays,
                ray_length_ratio,
                threshold,
                dispersion,
            },
            VisionFilter::EyeStrain => F::EyeStrain,
            VisionFilter::DryEye => F::DryEye,
            VisionFilter::Metamorphopsia { freq, seed } => F::Metamorphopsia { freq, seed },
            VisionFilter::ContrastSensitivity => F::ContrastSensitivity,
            VisionFilter::DetailLoss { cell_size } => F::DetailLoss { cell_size },
            VisionFilter::Teichopsia => F::Teichopsia,
            VisionFilter::FlickeringStars { seed } => F::FlickeringStars { seed },
        }
    }

    /// `sensus_core::Filter` を Dart 公開ミラーへ逆変換する。`to_sensus` の対称写像。
    ///
    /// sensus の `Filter` は全 vision バリアントなので（聴覚は別 enum `HearingFilter`）、
    /// 本関数は常に `Some` を返す。戻り値を `Option` にしてあるのは、将来 sensus が
    /// non-vision な `Filter` バリアントを足したときに `None` で逃がせるようにするため。
    /// [`Experience`] の `vision: Option<Filter>` をミラーへ写す際に使う。
    fn from_sensus(filter: sensus_core::Filter) -> Option<VisionFilter> {
        use sensus_core::Filter as F;
        let mirror = match filter {
            F::Protanopia => VisionFilter::Protanopia,
            F::Deuteranopia => VisionFilter::Deuteranopia,
            F::Tritanopia => VisionFilter::Tritanopia,
            F::Achromatopsia => VisionFilter::Achromatopsia,
            F::Tetrachromacy => VisionFilter::Tetrachromacy,
            F::Myopia => VisionFilter::Myopia,
            F::Hyperopia => VisionFilter::Hyperopia,
            F::Presbyopia => VisionFilter::Presbyopia,
            F::Astigmatism { axis_deg } => VisionFilter::Astigmatism { axis_deg },
            F::Glaucoma { mode } => VisionFilter::Glaucoma {
                mode: VisionGlaucomaMode::from_sensus(mode),
            },
            F::MacularDegeneration => VisionFilter::MacularDegeneration,
            F::Hemianopia { side } => VisionFilter::Hemianopia { side },
            F::TunnelVision => VisionFilter::TunnelVision,
            F::Cataract { seed } => VisionFilter::Cataract { seed },
            F::Floaters {
                seed,
                density,
                size,
                gaze_x,
                gaze_y,
            } => VisionFilter::Floaters {
                seed,
                density,
                size,
                gaze_x,
                gaze_y,
            },
            F::Photophobia => VisionFilter::Photophobia,
            F::NightBlindness => VisionFilter::NightBlindness,
            F::Vertigo => VisionFilter::Vertigo,
            F::BppvRotation => VisionFilter::BppvRotation,
            F::VestibularNeuritis => VisionFilter::VestibularNeuritis,
            F::Diplopia {
                offset_x,
                offset_y,
                ghost_strength,
            } => VisionFilter::Diplopia {
                offset_x,
                offset_y,
                ghost_strength,
            },
            F::Nystagmus {
                amplitude,
                direction_deg,
            } => VisionFilter::Nystagmus {
                amplitude,
                direction_deg,
            },
            F::Starbursts {
                num_rays,
                ray_length_ratio,
                threshold,
                dispersion,
            } => VisionFilter::Starbursts {
                num_rays,
                ray_length_ratio,
                threshold,
                dispersion,
            },
            F::EyeStrain => VisionFilter::EyeStrain,
            F::DryEye => VisionFilter::DryEye,
            F::Metamorphopsia { freq, seed } => VisionFilter::Metamorphopsia { freq, seed },
            F::ContrastSensitivity => VisionFilter::ContrastSensitivity,
            F::DetailLoss { cell_size } => VisionFilter::DetailLoss { cell_size },
            F::Teichopsia => VisionFilter::Teichopsia,
            F::FlickeringStars { seed } => VisionFilter::FlickeringStars { seed },
        };
        Some(mirror)
    }
}

/// 指定フィルタの GLSL ES 3.00 ソースを返す。
///
/// **用途**: ビルド時に Flutter アセット（または impeller 変換前の中間 `.frag`）
/// へ書き出す同期スクリプト用。実機ランタイムでこの文字列を直接 Flutter の
/// `FragmentProgram` に流し込むことはできない（理由は docs/sensus-integration.md）。
///
/// sensus_core の全 vision フィルタに `*_glsl()` getter が存在するため、本関数は
/// 全 [`VisionFilter`] で非空ソースを返す（shader 非対応フィルタは無い）。
#[flutter_rust_bridge::frb(sync)]
pub fn vision_shader_glsl(filter: VisionFilter) -> String {
    match filter {
        VisionFilter::Protanopia => shaders::protanopia_glsl(),
        VisionFilter::Deuteranopia => shaders::deuteranopia_glsl(),
        VisionFilter::Tritanopia => shaders::tritanopia_glsl(),
        VisionFilter::Achromatopsia => shaders::achromatopsia_glsl(),
        VisionFilter::Tetrachromacy => shaders::tetrachromacy_glsl(),
        VisionFilter::Myopia => shaders::myopia_glsl(),
        VisionFilter::Hyperopia => shaders::hyperopia_glsl(),
        VisionFilter::Presbyopia => shaders::presbyopia_glsl(),
        VisionFilter::Astigmatism { .. } => shaders::astigmatism_glsl(),
        VisionFilter::Glaucoma { .. } => shaders::glaucoma_glsl(),
        VisionFilter::MacularDegeneration => shaders::macular_degeneration_glsl(),
        VisionFilter::Hemianopia { .. } => shaders::hemianopia_glsl(),
        VisionFilter::TunnelVision => shaders::tunnel_vision_glsl(),
        VisionFilter::Cataract { .. } => shaders::cataract_glsl(),
        VisionFilter::Floaters { .. } => shaders::floaters_glsl(),
        VisionFilter::Photophobia => shaders::photophobia_glsl(),
        VisionFilter::NightBlindness => shaders::nyctalopia_glsl(),
        VisionFilter::Vertigo => shaders::vertigo_glsl(),
        VisionFilter::BppvRotation => shaders::bppv_rotation_glsl(),
        VisionFilter::VestibularNeuritis => shaders::vestibular_neuritis_glsl(),
        VisionFilter::Diplopia { .. } => shaders::diplopia_glsl(),
        VisionFilter::Nystagmus { .. } => shaders::nystagmus_glsl(),
        VisionFilter::Starbursts { .. } => shaders::starbursts_glsl(),
        VisionFilter::EyeStrain => shaders::eye_strain_glsl(),
        VisionFilter::DryEye => shaders::dry_eye_glsl(),
        VisionFilter::Metamorphopsia { .. } => shaders::metamorphopsia_glsl(),
        VisionFilter::ContrastSensitivity => shaders::contrast_sensitivity_glsl(),
        VisionFilter::DetailLoss { .. } => shaders::detail_loss_glsl(),
        VisionFilter::Teichopsia => shaders::teichopsia_glsl(),
        VisionFilter::FlickeringStars { .. } => shaders::flickering_stars_glsl(),
    }
    .to_string()
}

/// 指定フィルタの uniform を、FragmentProgram に `setFloat(i, ..)` する順序の
/// flat な `Vec<f32>` にして返す。
///
/// `sampler2D uTexture`（= 入力画像）および `uMask`（floaters のマスク）は
/// `setFloat` の対象外なので含めない。Flutter 側では float uniform を `setFloat(0..)`
/// で順に積み、サンプラは `setImageSampler(..)` で別途渡す。各インデックスの意味は
/// [`vision_uniform_layout`] が返すラベルと一致する（同じ順序、同じ長さ）。
///
/// # 引数
/// - `strength`: 0.0..=1.0（範囲外・NaN は sensus 側 `normalize_strength` で clamp / NaN→0）。
/// - `time`: 秒単位の時間。時間依存フィルタ（Vertigo / BppvRotation）の `uTime` に渡す。
///   それ以外のフィルタでは無視される（sensus の uniforms getter が time を取らないため）。
/// - `width` / `height`: 入力画像のピクセルサイズ。解像度依存フィルタの半径・texel size・
///   resolution・aspect の算出に使う。
///
/// # u32 シード / count / int の扱い
/// GLSL で `uint`/`int` の uniform（`uSeed`, `uCount`）も f32 に詰める。f32 は 2^24 を
/// 超える整数を正確に表せないため、seed が巨大だと精度が落ちる（モジュール doc 参照）。
#[flutter_rust_bridge::frb(sync)]
pub fn vision_uniforms(
    filter: VisionFilter,
    strength: f32,
    time: f32,
    width: u32,
    height: u32,
) -> Vec<f32> {
    // texel_size = 1/dim を計算する際、0 だと +inf が下流（setFloat → シェーダ）へ
    // 流れてしまう。呼び元は実画像サイズを渡す前提だが、防御的に最低 1 にする。
    let width = width.max(1);
    let height = height.max(1);
    let min_dim = width.min(height);
    let texel_x = 1.0 / width as f32;
    let texel_y = 1.0 / height as f32;
    let mut uniforms = match filter {
        VisionFilter::Protanopia => color_matrix_flat(shaders::protanopia_uniforms(strength)),
        VisionFilter::Deuteranopia => color_matrix_flat(shaders::deuteranopia_uniforms(strength)),
        VisionFilter::Tritanopia => color_matrix_flat(shaders::tritanopia_uniforms(strength)),
        VisionFilter::Achromatopsia => {
            let u = shaders::achromatopsia_uniforms(strength);
            vec![u.strength, u.r_weight, u.g_weight, u.b_weight]
        }
        VisionFilter::Tetrachromacy => {
            vec![shaders::tetrachromacy_uniforms(strength).strength]
        }
        VisionFilter::Myopia => {
            let u = shaders::myopia_uniforms(strength, min_dim);
            vec![u.strength, u.radius_px, texel_x, texel_y]
        }
        VisionFilter::Hyperopia => {
            let u = shaders::hyperopia_uniforms(strength, min_dim);
            vec![u.strength, u.radius_px, texel_x, texel_y]
        }
        VisionFilter::Presbyopia => {
            let u = shaders::presbyopia_uniforms(strength, min_dim);
            vec![u.strength, u.radius_px, texel_x, texel_y]
        }
        VisionFilter::Astigmatism { axis_deg } => {
            let u = shaders::astigmatism_uniforms(strength, min_dim, axis_deg);
            vec![u.strength, u.radius_px, u.axis_deg, texel_x, texel_y]
        }
        VisionFilter::Glaucoma { mode } => {
            let u = shaders::glaucoma_uniforms(strength, width, height, mode.to_sensus());
            vec![u.strength, u.aspect, u.mode as f32]
        }
        VisionFilter::MacularDegeneration => {
            let u = shaders::macular_degeneration_uniforms(strength, width, height);
            vec![u.strength, u.aspect]
        }
        VisionFilter::Hemianopia { side } => {
            // 公開 API 規約: 0.0=左欠損, 1.0=右欠損。frag の uSide は 1.0=右, -1.0=左。
            // shaders::hemianopia_uniforms は GLSL 内部値をそのまま渡すため、ここで変換する。
            let glsl_side = if side >= 0.5 { 1.0 } else { -1.0 };
            let u = shaders::hemianopia_uniforms(strength, glsl_side);
            vec![u.strength, u.side]
        }
        VisionFilter::TunnelVision => {
            let u = shaders::tunnel_vision_uniforms(strength, width, height);
            vec![u.strength, u.aspect]
        }
        VisionFilter::Cataract { seed } => {
            let u = shaders::cataract_uniforms(strength, seed);
            // frag: uStrength, uint uSeed, vec2 uResolution
            vec![u.strength, u.seed as f32, width as f32, height as f32]
        }
        VisionFilter::Floaters { .. } => {
            // frag: uStrength のみ（マスクは uMask テクスチャで別途渡す）。
            vec![shaders::floaters_uniforms(strength).strength]
        }
        VisionFilter::Photophobia => {
            let u = shaders::photophobia_uniforms(strength, width, height);
            // photophobia.frag は uStrength を持たない。strength は radius_px に
            // 畳み込まれているため、uniform は radius + texel のみ。
            vec![u.radius_px, u.texel_size[0], u.texel_size[1]]
        }
        VisionFilter::NightBlindness => {
            vec![shaders::nyctalopia_uniforms(strength).strength]
        }
        VisionFilter::Vertigo => {
            let u = shaders::vertigo_uniforms(strength, time, width, height);
            vec![
                u.strength,
                u.time,
                u.aspect,
                u.radius_px,
                u.texel_size[0],
                u.texel_size[1],
            ]
        }
        VisionFilter::BppvRotation => {
            let u = shaders::bppv_rotation_uniforms(strength, time, width, height);
            vec![u.strength, u.time, u.aspect]
        }
        VisionFilter::VestibularNeuritis => {
            let u = shaders::vestibular_neuritis_uniforms(strength, width, height);
            vec![
                u.strength,
                u.radius_px,
                u.shift_texel,
                u.texel_size[0],
                u.texel_size[1],
            ]
        }
        VisionFilter::Diplopia {
            offset_x,
            offset_y,
            ghost_strength,
        } => {
            // offset は min(W,H) 比。CPU vision::diplopia と同じくピクセルへ展開してから
            // テクセル化する（diplopia_uniforms が px → texel 変換を担う）。
            let offset_x_px = offset_x * min_dim as f32;
            let offset_y_px = offset_y * min_dim as f32;
            let u = shaders::diplopia_uniforms(
                strength,
                offset_x_px,
                offset_y_px,
                ghost_strength,
                width,
                height,
            );
            vec![
                u.strength,
                u.offset_x_texel,
                u.offset_y_texel,
                u.ghost_strength,
            ]
        }
        VisionFilter::Nystagmus {
            amplitude,
            direction_deg,
        } => {
            let u = shaders::nystagmus_uniforms(strength, amplitude, direction_deg, min_dim);
            vec![u.strength, u.radius_px, u.direction_deg, texel_x, texel_y]
        }
        VisionFilter::Starbursts {
            num_rays,
            ray_length_ratio,
            threshold,
            dispersion,
        } => {
            let u = shaders::starbursts_uniforms(
                strength,
                threshold,
                dispersion,
                num_rays,
                ray_length_ratio,
                width,
                height,
            );
            // frag 順: uStrength, uThreshold, uDispersion, uNumRays, uRayLengthPx, uTexelSize
            vec![
                u.strength,
                u.threshold,
                u.dispersion,
                u.num_rays,
                u.ray_length_px,
                u.texel_size[0],
                u.texel_size[1],
            ]
        }
        VisionFilter::EyeStrain => {
            let u = shaders::eye_strain_uniforms(strength, width, height);
            vec![u.strength, u.radius_px, u.texel_size[0], u.texel_size[1]]
        }
        VisionFilter::DryEye => {
            let u = shaders::dry_eye_uniforms(strength, width, height);
            vec![u.strength, u.texel_size[0], u.texel_size[1]]
        }
        VisionFilter::Metamorphopsia { freq, seed } => {
            let u = shaders::metamorphopsia_uniforms(strength, freq, seed, width, height);
            vec![
                u.strength,
                u.freq,
                u.seed as f32,
                u.texel_size[0],
                u.texel_size[1],
            ]
        }
        VisionFilter::ContrastSensitivity => {
            vec![shaders::contrast_sensitivity_uniforms(strength).strength]
        }
        VisionFilter::DetailLoss { .. } => {
            // detail_loss.frag: uStrength, vec2 uResolution。
            // cell_size は CPU 実装（detail_loss_with_cell_size）専用で、GLSL は
            // strength からタイルサイズを内部算出するため uniform には乗らない。
            let u = shaders::detail_loss_uniforms(strength);
            vec![u.strength, width as f32, height as f32]
        }
        VisionFilter::Teichopsia => {
            let u = shaders::teichopsia_uniforms(strength, width, height);
            vec![u.strength, u.aspect]
        }
        VisionFilter::FlickeringStars { seed } => {
            let u = shaders::flickering_stars_uniforms(strength, seed);
            // frag 順: uStrength, uint uSeed, int uCount, vec2 uResolution
            vec![
                u.strength,
                u.seed as f32,
                u.count as f32,
                width as f32,
                height as f32,
            ]
        }
    };
    // 防御境界: payload 数値（axis_deg / freq / offset 等）に NaN/Inf が紛れ込んでも、
    // Dart→FragmentProgram の setFloat に非有限値を渡さない。strength は sensus 側で
    // normalize 済みだが、payload 由来の値はここが Dart への最後の関門。非有限は 0.0 に潰す
    // （半径・係数いずれも 0 は「効果なし」側で安全）。呼び元は有限値を渡す前提。
    for v in uniforms.iter_mut() {
        if !v.is_finite() {
            *v = 0.0;
        }
    }
    uniforms
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
        VisionFilter::Tetrachromacy
        | VisionFilter::NightBlindness
        | VisionFilter::ContrastSensitivity => &["uStrength"],
        VisionFilter::Floaters { .. } => &["uStrength"],
        VisionFilter::Myopia | VisionFilter::Hyperopia | VisionFilter::Presbyopia => {
            &["uStrength", "uRadiusPx", "uTexelSize.x", "uTexelSize.y"]
        }
        VisionFilter::Astigmatism { .. } => &[
            "uStrength",
            "uRadiusPx",
            "uAxisDeg",
            "uTexelSize.x",
            "uTexelSize.y",
        ],
        VisionFilter::Glaucoma { .. } => &["uStrength", "uAspect", "uMode"],
        VisionFilter::MacularDegeneration
        | VisionFilter::TunnelVision
        | VisionFilter::Teichopsia => &["uStrength", "uAspect"],
        VisionFilter::Hemianopia { .. } => &["uStrength", "uSide"],
        VisionFilter::Cataract { .. } => &["uStrength", "uSeed", "uResolution.x", "uResolution.y"],
        VisionFilter::Photophobia => &["uRadiusPx", "uTexelSize.x", "uTexelSize.y"],
        VisionFilter::Vertigo => &[
            "uStrength",
            "uTime",
            "uAspect",
            "uRadiusPx",
            "uTexelSize.x",
            "uTexelSize.y",
        ],
        VisionFilter::BppvRotation => &["uStrength", "uTime", "uAspect"],
        VisionFilter::VestibularNeuritis => &[
            "uStrength",
            "uRadiusPx",
            "uShiftTexel",
            "uTexelSize.x",
            "uTexelSize.y",
        ],
        VisionFilter::Diplopia { .. } => &["uStrength", "uOffsetX", "uOffsetY", "uGhostStrength"],
        VisionFilter::Nystagmus { .. } => &[
            "uStrength",
            "uRadiusPx",
            "uDirectionDeg",
            "uTexelSize.x",
            "uTexelSize.y",
        ],
        VisionFilter::Starbursts { .. } => &[
            "uStrength",
            "uThreshold",
            "uDispersion",
            "uNumRays",
            "uRayLengthPx",
            "uTexelSize.x",
            "uTexelSize.y",
        ],
        VisionFilter::EyeStrain => &["uStrength", "uRadiusPx", "uTexelSize.x", "uTexelSize.y"],
        VisionFilter::DryEye => &["uStrength", "uTexelSize.x", "uTexelSize.y"],
        VisionFilter::Metamorphopsia { .. } => &[
            "uStrength",
            "uFreq",
            "uSeed",
            "uTexelSize.x",
            "uTexelSize.y",
        ],
        VisionFilter::DetailLoss { .. } => &["uStrength", "uResolution.x", "uResolution.y"],
        VisionFilter::FlickeringStars { .. } => &[
            "uStrength",
            "uSeed",
            "uCount",
            "uResolution.x",
            "uResolution.y",
        ],
    };
    labels.iter().map(|s| s.to_string()).collect()
}

/// sensus-core の CPU `apply` を薄く公開する。全 [`VisionFilter`] に対応する
/// （sensus の `apply` は網羅 match なので payload 付きフィルタも CPU で適用可能）。
///
/// GPU（FragmentProgram）経路が主だが、テストや GPU 非対応環境のフォールバックに使う。
/// 生 RGBA8（`width * height * 4` バイト）を入力し、同じレイアウトの RGBA8 を返す。
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

    let out =
        sensus_core::apply(filter.to_sensus(), dynimg, strength).map_err(|e| e.to_string())?;
    Ok(out.to_rgba8().into_raw())
}

// =============================================================================
// 体験（Experience）— 視覚 + 聴覚 + 緊急度の正準記述子
// =============================================================================
//
// sensus-core の `Experience` / `Urgency` / `HearingFilter` を Dart へ公開する。
// 文言（体験名・緊急度メッセージ・聴覚症状の説明）は **一切持たせない**。`id` と
// 分類（enum バリアント）だけを出し、文言は ue 側 i18n（#18）が `id`・urgency 種別・
// HearingFilter バリアントをキーに解決する。これにより、文言の正本は ue（多言語）、
// 症状の組み合わせ（三徴候の正準化）の正本は sensus-core、と責務が分かれる。
//
// HearingFilter は **型として公開するだけ**で、音声再生は本層のスコープ外（#19 の
// 聴覚モード設計に委ねる）。ここでは Experience の `hearing` データ（どの聴覚フィルタが
// 組になるか）と 14 バリアントの識別子を Dart に渡すところまでを担う。

/// 受診喚起の緊急度分類。`sensus_core::Urgency` の FRB 公開ミラー。
///
/// 文言は持たない（分類のみ）。⚠️/🚨 等の表示文言は Dart 側 i18n が
/// このバリアントをキーに出し分ける。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Urgency {
    /// 緊急性の注記なし。
    None,
    /// 早期受診が望ましい。
    EarlyConsultation,
    /// 即救急（脳卒中等のサインの可能性）。
    Emergency,
}

impl Urgency {
    fn from_sensus(urgency: sensus_core::Urgency) -> Self {
        use sensus_core::Urgency as U;
        match urgency {
            U::None => Urgency::None,
            U::EarlyConsultation => Urgency::EarlyConsultation,
            U::Emergency => Urgency::Emergency,
        }
    }
}

/// 聴覚フィルタの種類。`sensus_core::HearingFilter` の FRB 公開ミラー（14 バリアント）。
///
/// **型として公開するだけ**で、音声再生（`apply_hearing` 相当）は本層のスコープ外
/// （聴覚モード設計 #19 に委ねる）。payload 付きバリアントは sensus と同じフィールド名・
/// 型（`{ freq_hz: f32 }` 等）でミラーする。症状の説明文言は持たず、Dart 側 i18n が
/// バリアントをキーに解決する。
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum HearingFilter {
    /// 難聴: 高音域カット。
    HearingLoss,
    /// 突発性難聴: 特定周波数帯の急激な損失。
    SuddenHearingLoss { freq_hz: f32 },
    /// 騒音性難聴: 4 kHz 付近の損失。
    NoiseInducedHearingLoss,
    /// 耳鳴り: 指定周波数の正弦波を常時ミックス。
    Tinnitus { freq_hz: f32 },
    /// 音響過敏: 音量を異常に増幅。
    Hyperacusis,
    /// ミソフォニア: `freq_hz` 中心のトリガー帯域を過剰増幅 + 歪み。
    Misophonia { freq_hz: f32 },
    /// 変音: 音を歪んだ・金属的な質感に加工。
    Paracusis,
    /// 音楽音痴: 音程の違いを識別しにくくする。
    Amusia,
    /// ジスメロディア: 音楽を不快・歪んだ音に変換。
    Dysmelodia,
    /// 音程シフト: 半音単位で全体音程をシフト。
    PitchShift { semitones: f32 },
    /// ダイプラクシス: 左右耳で異なる音程を知覚。
    Diplacusis,
    /// APD（聴覚情報処理障害）: 時間分解能低下 + 雑音付加。
    AuditoryProcessingDisorder,
    /// メニエール病の聴覚側: 低音域難聴 + 低い唸る耳鳴り。
    Meniere,
    /// 迷路炎の聴覚側: 高音域感音難聴 + 高音の耳鳴り。
    Labyrinthitis,
}

impl HearingFilter {
    fn from_sensus(filter: sensus_core::HearingFilter) -> Self {
        use sensus_core::HearingFilter as H;
        match filter {
            H::HearingLoss => HearingFilter::HearingLoss,
            H::SuddenHearingLoss { freq_hz } => HearingFilter::SuddenHearingLoss { freq_hz },
            H::NoiseInducedHearingLoss => HearingFilter::NoiseInducedHearingLoss,
            H::Tinnitus { freq_hz } => HearingFilter::Tinnitus { freq_hz },
            H::Hyperacusis => HearingFilter::Hyperacusis,
            H::Misophonia { freq_hz } => HearingFilter::Misophonia { freq_hz },
            H::Paracusis => HearingFilter::Paracusis,
            H::Amusia => HearingFilter::Amusia,
            H::Dysmelodia => HearingFilter::Dysmelodia,
            H::PitchShift { semitones } => HearingFilter::PitchShift { semitones },
            H::Diplacusis => HearingFilter::Diplacusis,
            H::AuditoryProcessingDisorder => HearingFilter::AuditoryProcessingDisorder,
            H::Meniere => HearingFilter::Meniere,
            H::Labyrinthitis => HearingFilter::Labyrinthitis,
        }
    }
}

/// 視覚 + 聴覚にまたがる「複合体験」の Dart 公開ミラー。`sensus_core::Experience` 由来。
///
/// sensus は pure・別バッファ（画像 / 音声）のため、メニエール病のような「回転性めまい
/// （視覚）＋ 難聴・耳鳴り（聴覚）」の複合症状を 1 バッファで表せない。`Experience` は
/// 「どの視覚フィルタとどの聴覚フィルタを組にすれば仕様どおりの複合体験になるか」の
/// 正準化を sensus から受け取る。Dart 側は三徴候の組み合わせをハードコードせず、
/// [`experiences`] から取得する。
///
/// `id` は安定した英語識別子（i18n キー）。文言（体験名・説明）は持たず、Dart 側 i18n が
/// `id` をキーに解決する。
#[derive(Debug, Clone, PartialEq)]
pub struct Experience {
    /// 安定した識別子（i18n キー等に使う英語 ID）。sensus は `&'static str` だが
    /// FRB は `String` で出す。
    pub id: String,
    /// 視覚側フィルタ（視覚要素が無い体験では `None`）。
    pub vision: Option<VisionFilter>,
    /// 聴覚側フィルタ（聴覚要素が無い体験では `None`）。
    pub hearing: Option<HearingFilter>,
    /// 受診喚起の緊急度。
    pub urgency: Urgency,
}

impl Experience {
    fn from_sensus(exp: &sensus_core::Experience) -> Self {
        Experience {
            id: exp.id.to_string(),
            vision: exp.vision.and_then(VisionFilter::from_sensus),
            hearing: exp.hearing.clone().map(HearingFilter::from_sensus),
            urgency: Urgency::from_sensus(exp.urgency),
        }
    }
}

/// sensus-core が正準化した複合体験のプリセット 4 種を Dart へ返す。
///
/// 順序固定: meniere / bppv / vestibular_neuritis / labyrinthitis。各体験の視覚・聴覚
/// フィルタと緊急度は sensus の `Experience::MENIERE` 等の const をミラーへ変換したもの。
/// 文言は含まない（`id`・分類のみ）。体験名・緊急度メッセージ・聴覚症状の説明は
/// Dart 側 i18n（#18）が解決する。
#[flutter_rust_bridge::frb(sync)]
pub fn experiences() -> Vec<Experience> {
    [
        &sensus_core::Experience::MENIERE,
        &sensus_core::Experience::BPPV,
        &sensus_core::Experience::VESTIBULAR_NEURITIS,
        &sensus_core::Experience::LABYRINTHITIS,
    ]
    .into_iter()
    .map(Experience::from_sensus)
    .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 全 vision バリアントを 1 ループで列挙するためのヘルパ。バリアントが増えたら
    /// ここに追加するだけで全網羅テストが拾う。payload 付きは代表値を入れる。
    // 新しい VisionFilter variant を追加したらこの配列にも足すこと（網羅テスト用）。
    // 本体の `vision_uniforms`/`vision_shader_glsl`/`to_sensus` は網羅 match なので、
    // variant 追加自体はコンパイルエラーで気付ける。
    const ALL_FILTERS: [VisionFilter; 30] = [
        VisionFilter::Protanopia,
        VisionFilter::Deuteranopia,
        VisionFilter::Tritanopia,
        VisionFilter::Achromatopsia,
        VisionFilter::Tetrachromacy,
        VisionFilter::Myopia,
        VisionFilter::Hyperopia,
        VisionFilter::Presbyopia,
        VisionFilter::Astigmatism { axis_deg: 45.0 },
        VisionFilter::Glaucoma {
            mode: VisionGlaucomaMode::Biarcuate,
        },
        VisionFilter::MacularDegeneration,
        VisionFilter::Hemianopia { side: 1.0 },
        VisionFilter::TunnelVision,
        VisionFilter::Cataract { seed: 7 },
        VisionFilter::Floaters {
            seed: 7,
            density: 1.0,
            size: 2.0,
            gaze_x: 0.5,
            gaze_y: 0.5,
        },
        VisionFilter::Photophobia,
        VisionFilter::NightBlindness,
        VisionFilter::Vertigo,
        VisionFilter::BppvRotation,
        VisionFilter::VestibularNeuritis,
        VisionFilter::Diplopia {
            offset_x: 0.01,
            offset_y: 0.0,
            ghost_strength: 0.5,
        },
        VisionFilter::Nystagmus {
            amplitude: 0.02,
            direction_deg: 0.0,
        },
        VisionFilter::Starbursts {
            num_rays: 6,
            ray_length_ratio: 0.1,
            threshold: 0.8,
            dispersion: 0.3,
        },
        VisionFilter::EyeStrain,
        VisionFilter::DryEye,
        VisionFilter::Metamorphopsia { freq: 8.0, seed: 3 },
        VisionFilter::ContrastSensitivity,
        VisionFilter::DetailLoss { cell_size: 8 },
        VisionFilter::Teichopsia,
        VisionFilter::FlickeringStars { seed: 5 },
    ];

    #[test]
    fn glsl_sources_are_non_empty_all_filters() {
        for f in ALL_FILTERS {
            assert!(!vision_shader_glsl(f).is_empty(), "{f:?}: empty GLSL");
        }
    }

    /// 最重要不変条件: 全バリアントで uniforms の長さが layout の長さと一致する。
    /// ズレると Dart 側 setFloat(i, ..) のインデックスが壊れる。
    #[test]
    fn all_filters_uniforms_len_matches_layout() {
        for f in ALL_FILTERS {
            let u = vision_uniforms(f, 0.5, 0.3, 256, 128);
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

    /// strength の境界・異常値を渡しても panic せず、長さ不変・有限値が返る
    /// （clamp / NaN→0 は sensus 側 normalize_strength に委譲）。
    #[test]
    fn strength_extremes_do_not_panic() {
        for f in ALL_FILTERS {
            let layout_len = vision_uniform_layout(f).len();
            for s in [0.0_f32, 1.0, -5.0, 100.0, f32::NAN, f32::INFINITY] {
                let u = vision_uniforms(f, s, 0.0, 256, 128);
                assert_eq!(u.len(), layout_len, "{f:?} s={s}: length changed");
                for (i, v) in u.iter().enumerate() {
                    assert!(v.is_finite(), "{f:?} s={s}: uniform[{i}] not finite ({v})");
                }
            }
        }
    }

    /// width/height が 0 でも texel_size が +inf にならず有限値が返る
    /// （`width.max(1)` ガードの回帰。0 除算で inf が下流に流れるのを防ぐ）。
    #[test]
    fn zero_dimensions_produce_finite_uniforms() {
        for f in ALL_FILTERS {
            for (w, h) in [(0u32, 0u32), (0, 128), (256, 0)] {
                let u = vision_uniforms(f, 1.0, 0.5, w, h);
                for (i, v) in u.iter().enumerate() {
                    assert!(
                        v.is_finite(),
                        "{f:?} {w}x{h}: uniform[{i}] not finite ({v})"
                    );
                }
            }
        }
    }

    /// payload 数値に NaN/Inf が紛れても、出力 uniform は全て有限（境界ガードの回帰）。
    #[test]
    fn non_finite_payloads_are_sanitized() {
        let nan = f32::NAN;
        let inf = f32::INFINITY;
        let cases = [
            VisionFilter::Astigmatism { axis_deg: nan },
            VisionFilter::Hemianopia { side: inf },
            VisionFilter::Diplopia {
                offset_x: nan,
                offset_y: inf,
                ghost_strength: nan,
            },
            VisionFilter::Nystagmus {
                amplitude: inf,
                direction_deg: nan,
            },
            VisionFilter::Starbursts {
                num_rays: 6,
                ray_length_ratio: nan,
                threshold: inf,
                dispersion: nan,
            },
            VisionFilter::Metamorphopsia { freq: inf, seed: 0 },
            VisionFilter::Floaters {
                seed: 0,
                density: nan,
                size: inf,
                gaze_x: nan,
                gaze_y: inf,
            },
        ];
        for f in cases {
            // time にも異常値を入れて二重に確認
            let u = vision_uniforms(f, nan, inf, 128, 64);
            for (i, v) in u.iter().enumerate() {
                assert!(v.is_finite(), "{f:?}: uniform[{i}] not finite ({v})");
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

    #[test]
    fn cpu_apply_rejects_wrong_buffer_len() {
        let r = apply_vision_cpu_rgba8(VisionFilter::Protanopia, vec![0u8; 10], 4, 4, 1.0);
        assert!(r.is_err());
    }

    // --- フィルタ別レイアウト・値の回帰 ---

    #[test]
    fn color_matrix_layout_matches_uniforms_len() {
        for f in [
            VisionFilter::Protanopia,
            VisionFilter::Deuteranopia,
            VisionFilter::Tritanopia,
        ] {
            let u = vision_uniforms(f, 1.0, 0.0, 100, 100);
            assert_eq!(u.len(), 10);
        }
    }

    #[test]
    fn achromatopsia_bt709_weights() {
        let u = vision_uniforms(VisionFilter::Achromatopsia, 1.0, 0.0, 100, 100);
        assert_eq!(u.len(), 4);
        assert!((u[1] - 0.2126).abs() < 1e-6);
    }

    #[test]
    fn myopia_uniforms_include_texel_size() {
        let u = vision_uniforms(VisionFilter::Myopia, 1.0, 0.0, 200, 100);
        assert_eq!(u.len(), 4);
        assert!((u[2] - 1.0 / 200.0).abs() < 1e-6);
        assert!((u[3] - 1.0 / 100.0).abs() < 1e-6);
    }

    #[test]
    fn photophobia_has_no_strength_uniform() {
        let u = vision_uniforms(VisionFilter::Photophobia, 1.0, 0.0, 200, 100);
        let l = vision_uniform_layout(VisionFilter::Photophobia);
        assert_eq!(u.len(), 3);
        assert_eq!(l[0], "uRadiusPx");
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
            let a = vision_uniforms(f, 0.7, 0.0, 100, 100);
            let b = vision_uniforms(f, 0.7, 0.0, 999, 333);
            assert_eq!(
                a, b,
                "{f:?}: color filter uniforms must not depend on resolution"
            );
        }
    }

    /// 時間依存フィルタは uTime を反映する（time を変えると uniform が変わる）。
    #[test]
    fn time_dependent_filters_track_time() {
        for f in [VisionFilter::Vertigo, VisionFilter::BppvRotation] {
            let l = vision_uniform_layout(f);
            assert!(
                l.iter().any(|s| s == "uTime"),
                "{f:?}: layout must contain uTime"
            );
            let a = vision_uniforms(f, 1.0, 0.0, 256, 128);
            let b = vision_uniforms(f, 1.0, 1.5, 256, 128);
            assert_ne!(a, b, "{f:?}: changing time must change uniforms");
            // uTime はそのまま透過する
            let idx = l.iter().position(|s| s == "uTime").unwrap();
            assert!((b[idx] - 1.5).abs() < 1e-6);
        }
    }

    /// 時間非依存フィルタは time を無視する（time を変えても uniform 不変）。
    #[test]
    fn time_independent_filters_ignore_time() {
        for f in [
            VisionFilter::Protanopia,
            VisionFilter::Myopia,
            VisionFilter::Nystagmus {
                amplitude: 0.02,
                direction_deg: 0.0,
            },
            VisionFilter::Glaucoma {
                mode: VisionGlaucomaMode::Vignette,
            },
        ] {
            let a = vision_uniforms(f, 0.7, 0.0, 256, 128);
            let b = vision_uniforms(f, 0.7, 9.9, 256, 128);
            assert_eq!(a, b, "{f:?}: must ignore time");
        }
    }

    /// Glaucoma の uMode が VisionGlaucomaMode と 1 対 1 対応する。
    #[test]
    fn glaucoma_mode_maps_to_glsl_mode() {
        let cases = [
            (VisionGlaucomaMode::Vignette, 0.0),
            (VisionGlaucomaMode::ArcuateSuperior, 1.0),
            (VisionGlaucomaMode::ArcuateInferior, 2.0),
            (VisionGlaucomaMode::Biarcuate, 3.0),
        ];
        for (mode, expected) in cases {
            let u = vision_uniforms(VisionFilter::Glaucoma { mode }, 1.0, 0.0, 64, 64);
            // layout: [uStrength, uAspect, uMode]
            assert_eq!(u[2], expected, "{mode:?}");
        }
    }

    /// Hemianopia: 公開 side(0=左,1=右) → frag uSide(-1=左,1=右) の変換。
    #[test]
    fn hemianopia_side_conversion() {
        let right = vision_uniforms(VisionFilter::Hemianopia { side: 1.0 }, 1.0, 0.0, 64, 64);
        let left = vision_uniforms(VisionFilter::Hemianopia { side: 0.0 }, 1.0, 0.0, 64, 64);
        // layout: [uStrength, uSide]
        assert_eq!(right[1], 1.0, "side=1.0(右) → uSide=1.0");
        assert_eq!(left[1], -1.0, "side=0.0(左) → uSide=-1.0");
    }

    /// Cataract: seed が flat 配列に乗り、resolution が width/height で来る。
    #[test]
    fn cataract_seed_and_resolution() {
        let u = vision_uniforms(VisionFilter::Cataract { seed: 42 }, 1.0, 0.0, 200, 100);
        // layout: [uStrength, uSeed, uResolution.x, uResolution.y]
        assert_eq!(u.len(), 4);
        assert_eq!(u[1], 42.0);
        assert_eq!(u[2], 200.0);
        assert_eq!(u[3], 100.0);
    }

    /// FlickeringStars: seed と count(=strength*200) が乗る。
    #[test]
    fn flickering_stars_count_from_strength() {
        let u = vision_uniforms(
            VisionFilter::FlickeringStars { seed: 1 },
            0.5,
            0.0,
            100,
            100,
        );
        // layout: [uStrength, uSeed, uCount, uResolution.x, uResolution.y]
        assert_eq!(u.len(), 5);
        assert_eq!(u[1], 1.0); // seed
        assert_eq!(u[2], 100.0); // count = 0.5 * 200
    }

    /// Starbursts: num_rays / ray_length_px / texel が乗る（7 要素）。
    #[test]
    fn starbursts_layout_seven() {
        let f = VisionFilter::Starbursts {
            num_rays: 8,
            ray_length_ratio: 0.1,
            threshold: 0.8,
            dispersion: 0.3,
        };
        let u = vision_uniforms(f, 1.0, 0.0, 200, 100);
        assert_eq!(u.len(), 7);
        assert_eq!(u[3], 8.0); // uNumRays
                               // ray_length_px = (0.1 * min(200,100)) as u32 = 10
        assert_eq!(u[4], 10.0);
    }

    // --- Experience / Urgency / HearingFilter ミラーのマッピング検証 ---

    /// experiences() は sensus の 4 プリセットを順序固定で返す。
    #[test]
    fn experiences_returns_four_presets_in_order() {
        let xs = experiences();
        assert_eq!(xs.len(), 4);
        let ids: Vec<&str> = xs.iter().map(|e| e.id.as_str()).collect();
        assert_eq!(
            ids,
            vec!["meniere", "bppv", "vestibular_neuritis", "labyrinthitis"]
        );
    }

    /// meniere = 回転性めまい（視覚 Vertigo）+ 聴覚 Meniere + 早期受診。
    #[test]
    fn meniere_maps_vision_hearing_urgency() {
        let xs = experiences();
        let m = xs.iter().find(|e| e.id == "meniere").unwrap();
        assert_eq!(m.vision, Some(VisionFilter::Vertigo));
        assert_eq!(m.hearing, Some(HearingFilter::Meniere));
        assert_eq!(m.urgency, Urgency::EarlyConsultation);
    }

    /// bppv = 純粋な前庭性めまい（聴覚症状なし）+ 緊急度なし。
    #[test]
    fn bppv_has_no_hearing_and_no_urgency() {
        let xs = experiences();
        let b = xs.iter().find(|e| e.id == "bppv").unwrap();
        assert_eq!(b.vision, Some(VisionFilter::BppvRotation));
        assert_eq!(b.hearing, None);
        assert_eq!(b.urgency, Urgency::None);
    }

    /// vestibular_neuritis = 聴力温存（hearing None）+ 突然発症で救急。
    #[test]
    fn vestibular_neuritis_is_emergency_with_no_hearing() {
        let xs = experiences();
        let v = xs.iter().find(|e| e.id == "vestibular_neuritis").unwrap();
        assert_eq!(v.vision, Some(VisionFilter::VestibularNeuritis));
        assert_eq!(v.hearing, None);
        assert_eq!(v.urgency, Urgency::Emergency);
    }

    /// labyrinthitis = 回転性めまい（視覚 Vertigo）+ 聴覚 Labyrinthitis + 早期受診。
    #[test]
    fn labyrinthitis_maps_vision_hearing_urgency() {
        let xs = experiences();
        let l = xs.iter().find(|e| e.id == "labyrinthitis").unwrap();
        assert_eq!(l.vision, Some(VisionFilter::Vertigo));
        assert_eq!(l.hearing, Some(HearingFilter::Labyrinthitis));
        assert_eq!(l.urgency, Urgency::EarlyConsultation);
    }

    /// Urgency ミラーが sensus の 3 バリアントと 1 対 1 対応する。
    #[test]
    fn urgency_from_sensus_covers_all_variants() {
        use sensus_core::Urgency as U;
        assert_eq!(Urgency::from_sensus(U::None), Urgency::None);
        assert_eq!(
            Urgency::from_sensus(U::EarlyConsultation),
            Urgency::EarlyConsultation
        );
        assert_eq!(Urgency::from_sensus(U::Emergency), Urgency::Emergency);
    }

    /// HearingFilter ミラーが payload を保持して写す（代表バリアント）。
    #[test]
    fn hearing_filter_from_sensus_preserves_payload() {
        use sensus_core::HearingFilter as H;
        assert_eq!(
            HearingFilter::from_sensus(H::Tinnitus { freq_hz: 4000.0 }),
            HearingFilter::Tinnitus { freq_hz: 4000.0 }
        );
        assert_eq!(
            HearingFilter::from_sensus(H::PitchShift { semitones: -2.0 }),
            HearingFilter::PitchShift { semitones: -2.0 }
        );
        assert_eq!(
            HearingFilter::from_sensus(H::HearingLoss),
            HearingFilter::HearingLoss
        );
        assert_eq!(
            HearingFilter::from_sensus(H::Meniere),
            HearingFilter::Meniere
        );
    }

    /// VisionFilter::from_sensus は to_sensus の逆写像（payload 付き含む代表ラウンドトリップ）。
    #[test]
    fn vision_filter_from_sensus_roundtrips_to_sensus() {
        for f in ALL_FILTERS {
            let back = VisionFilter::from_sensus(f.to_sensus());
            assert_eq!(back, Some(f), "{f:?}: from_sensus(to_sensus) mismatch");
        }
    }
}
