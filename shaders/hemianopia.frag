// GENERATED FILE - DO NOT EDIT.
//
// Source of truth: sensus-core vision filter "hemianopia"
// (canonical GLSL: sensus shaders/hemianopia.frag, sensus-core v0.5.0).
// Filter-specific provenance (e.g. the Machado 2009 matrix and
// its citation) lives in the sensus source, not here.
//
// Regenerate with: dart run tools/generate_shaders.dart
// (input dump: tools/sensus_shaders.g.json, produced by sensus-core v0.5.0).
//
// scalar uniform order (setFloat index): uStrength, uSide, uResolution_x, uResolution_y
#include <flutter/runtime_effect.glsl>

uniform float uStrength;
uniform float uSide;
uniform float uResolution_x;
uniform float uResolution_y;
uniform sampler2D uTexture;

// 半盲（hemianopia）シミュレーション — 左右半側マスク
// uSide=1.0: 右半分を暗化, uSide=-1.0: 左半分を暗化
// 境界は画像中央 x=0.5 に固定。幅 2% の smoothstep で滑らかに。

out vec4 fragColor;

float srgbToLinear(float c) {
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

float linearToSrgb(float c) {
    return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

void main() {
    vec4 src = texture(uTexture, (FlutterFragCoord().xy / vec2(uResolution_x, uResolution_y)));

    float x = (FlutterFragCoord().xy / vec2(uResolution_x, uResolution_y)).x;
    float split = 0.5;
    float blur_w = 0.02; // UV 単位のぼかし幅（2%）。vision.rs は pixel 単位で w_f * 0.02 と等価。

    float left_fade;
    if (x < split - blur_w) {
        left_fade = 1.0;
    } else if (x > split + blur_w) {
        left_fade = 0.0;
    } else {
        float t = (x - (split - blur_w)) / (2.0 * blur_w);
        left_fade = 1.0 - t * t * (3.0 - 2.0 * t);
    }

    // vision.rs 規約: side=0→左欠損, side=1→右欠損
    // uSide: 1.0=右欠損, -1.0=左欠損 → side = (uSide+1)/2
    float side = (uSide + 1.0) * 0.5;

    // lerp(left_fade, 1-left_fade, side)
    float fade = left_fade + (1.0 - 2.0 * left_fade) * side;
    float mul = 1.0 - fade * uStrength;

    float rl = srgbToLinear(src.r);
    float gl = srgbToLinear(src.g);
    float bl = srgbToLinear(src.b);

    fragColor = vec4(
        linearToSrgb(clamp(rl * mul, 0.0, 1.0)),
        linearToSrgb(clamp(gl * mul, 0.0, 1.0)),
        linearToSrgb(clamp(bl * mul, 0.0, 1.0)),
        src.a
    );
}
