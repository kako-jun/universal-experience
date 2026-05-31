// GENERATED FILE - DO NOT EDIT.
//
// Source of truth: sensus-core vision filter "macular_degeneration"
// (canonical GLSL: sensus shaders/macular_degeneration.frag, sensus-core v0.5.0).
// Filter-specific provenance (e.g. the Machado 2009 matrix and
// its citation) lives in the sensus source, not here.
//
// Regenerate with: dart run tools/generate_shaders.dart
// (input dump: tools/sensus_shaders.g.json, produced by sensus-core v0.5.0).
//
// scalar uniform order (setFloat index): uStrength, uAspect, uResolution_x, uResolution_y
#include <flutter/runtime_effect.glsl>

uniform float uStrength;
uniform float uAspect;
uniform float uResolution_x;
uniform float uResolution_y;
uniform sampler2D uTexture;

// 黄斑変性（macular degeneration）シミュレーション — 中心暗化（foveal smoothstep マスク）
// 中心部を暗化・脱色する。strength=1.0 で最強の中心視野欠損。

out vec4 fragColor;

float srgbToLinear(float c) {
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

float linearToSrgb(float c) {
    return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

void main() {
    vec4 src = texture(uTexture, (FlutterFragCoord().xy / vec2(uResolution_x, uResolution_y)));

    // UV 座標を aspect 補正してから距離計算する。
    // Rust 実装（pixel 座標）との一致: dx/max_r = uv_x*aspect / corner
    vec2 uv = (FlutterFragCoord().xy / vec2(uResolution_x, uResolution_y)) - vec2(0.5, 0.5);
    vec2 uvA = vec2(uv.x * uAspect, uv.y);
    float cornerDist = sqrt(0.5 * uAspect * 0.5 * uAspect + 0.5 * 0.5);
    float d = length(uvA) / cornerDist;

    // vision.rs と同じ定数
    float inner_r = uStrength * 0.25;
    float outer_r = uStrength * 0.4;

    float u_t = clamp((d - inner_r) / max(outer_r - inner_r, 1e-5), 0.0, 1.0);
    float t = 1.0 - u_t * u_t * (3.0 - 2.0 * u_t); // 1 - smoothstep（中心ほど強い）

    float rl = srgbToLinear(src.r);
    float gl = srgbToLinear(src.g);
    float bl = srgbToLinear(src.b);

    // BT.709 輝度
    float lum = 0.2126 * rl + 0.7152 * gl + 0.0722 * bl;
    float darkened = lum * (1.0 - uStrength * 0.95);

    float out_r = mix(rl, darkened, t);
    float out_g = mix(gl, darkened, t);
    float out_b = mix(bl, darkened, t);

    fragColor = vec4(
        linearToSrgb(clamp(out_r, 0.0, 1.0)),
        linearToSrgb(clamp(out_g, 0.0, 1.0)),
        linearToSrgb(clamp(out_b, 0.0, 1.0)),
        src.a
    );
}
