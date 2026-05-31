// GENERATED FILE - DO NOT EDIT.
//
// Source of truth: sensus-core vision filter "nyctalopia"
// (canonical GLSL: sensus shaders/nyctalopia.frag, sensus-core v0.5.0).
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

// 夜盲（Nyctalopia）シミュレーション。
// 暗化 + 脱色（グレースケール寄り）+ Purkinje shift。
// CPU 実装 vision::nyctalopia と同じ式:
//   dark_factor = 1.0 - uStrength * 0.7
//   desat       = uStrength * 0.8
//   y_phot      = 0.2126 R + 0.7152 G + 0.0722 B  (BT.709)
//   y_scot      = 0.0610 R + 0.3751 G + 0.6038 B  (Vos 1978)
//   y           = lerp(y_phot, y_scot, strength)
//   desaturated = orig + (y - orig) * desat
//   Purkinje:   R' = R * (1 - s*0.2), B' = B * (1 + s*0.1)
//   output      = desaturated_with_purkinje * dark_factor
//
// 出典: Vos (1978) "Colorimetric and photometric properties of a 2° fundamental
// observer" Color Research & Application 3(3): 125–128


out vec4 fragColor;

float srgbToLinear(float c) {
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}
float linearToSrgb(float c) {
    return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

void main() {
    vec4 orig = texture(uTexture, (FlutterFragCoord().xy / vec2(uResolution_x, uResolution_y)));
    float rl = srgbToLinear(orig.r);
    float gl = srgbToLinear(orig.g);
    float bl = srgbToLinear(orig.b);

    // photopic luminance（BT.709）
    float yPhot = 0.2126 * rl + 0.7152 * gl + 0.0722 * bl;
    // scotopic luminance（Vos 1978）
    float yScot = 0.0610 * rl + 0.3751 * gl + 0.6038 * bl;
    // blend
    float y = mix(yPhot, yScot, uStrength);

    float darkFactor = 1.0 - uStrength * 0.7;
    float desat = uStrength * 0.8;

    // 脱色（ブレンドした luma に寄せる）
    float dr = rl + (y - rl) * desat;
    float dg = gl + (y - gl) * desat;
    float db = bl + (y - bl) * desat;

    // Purkinje shift: 赤チャネル微減・青チャネル微増
    float pr = dr * (1.0 - uStrength * 0.2);
    float pb = db * (1.0 + uStrength * 0.1);

    float fr = clamp(pr * darkFactor, 0.0, 1.0);
    float fg = clamp(dg * darkFactor, 0.0, 1.0);
    float fb = clamp(pb * darkFactor, 0.0, 1.0);

    fragColor = vec4(
        linearToSrgb(fr),
        linearToSrgb(fg),
        linearToSrgb(fb),
        orig.a
    );
}
