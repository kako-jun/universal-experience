// GENERATED FILE - DO NOT EDIT.
//
// Source of truth: sensus-core vision filter "tetrachromacy"
// (canonical GLSL: sensus shaders/tetrachromacy.frag, sensus-core v0.5.0).
// Filter-specific provenance (e.g. the Machado 2009 matrix and
// its citation) lives in the sensus source, not here.
//
// Regenerate with: dart run tools/generate_shaders.dart
// (input dump: tools/sensus_shaders.g.json, produced by sensus-core v0.5.0).
//
// scalar uniform order (setFloat index): uStrength, uResolution_x, uResolution_y
#include <flutter/runtime_effect.glsl>

uniform float uStrength;
uniform float uResolution_x;
uniform float uResolution_y;
uniform sampler2D uTexture;

// 四色型色覚（Tetrachromacy）シミュレーション。
// LMS 変換 + 赤-緑 opponent channel 誇張。
// CPU 実装 vision::tetrachromacy に対応。
//
// メタメリックペア候補領域（|delta| < 0.05）の Cb/Cr 誇張は、
// GPU では閾値判定が難しいため全領域に opponent channel 誇張を適用する簡略版。

out vec4 fragColor;

float srgbToLinear(float c) {
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}
float linearToSrgb(float c) {
    return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

void main() {
    vec4 orig = texture(uTexture, (FlutterFragCoord().xy / vec2(uResolution_x, uResolution_y)));
    float r = srgbToLinear(orig.r);
    float g = srgbToLinear(orig.g);
    float b = srgbToLinear(orig.b);

    // Machado 2009 linear sRGB → LMS 変換行列の第1-2行
    float lCone = 0.4002 * r + 0.7076 * g + (-0.0808) * b;
    float mCone = (-0.2263) * r + 1.1653 * g + 0.0457 * b;

    float delta = mCone - lCone;

    float rg = r - g;
    const float K_RG = 0.5;

    float nr, ng, nb;

    if (abs(delta) < 0.05) {
        // メタメリックペア候補: Cb/Cr 誇張
        float luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        float cb = b - luma;
        float cr = r - luma;
        float scale = uStrength * 2.0;
        nr = clamp(luma + cr * scale, 0.0, 1.0);
        ng = clamp(luma, 0.0, 1.0);
        nb = clamp(luma + cb * scale, 0.0, 1.0);
    } else {
        // 全領域: 赤-緑 opponent channel 誇張
        nr = clamp(r + uStrength * rg * K_RG, 0.0, 1.0);
        ng = clamp(g - uStrength * rg * K_RG, 0.0, 1.0);
        nb = b;
    }

    fragColor = vec4(
        linearToSrgb(nr),
        linearToSrgb(ng),
        linearToSrgb(nb),
        orig.a
    );
}
