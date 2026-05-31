// GENERATED FILE - DO NOT EDIT.
//
// Source of truth: sensus-core vision filter "teichopsia".
// Regenerate with: dart run tools/generate_shaders.dart
// (input: tools/sensus_shaders.g.json).
//
// scalar uniform order (setFloat index): uStrength, uAspect, uResolution_x, uResolution_y
#include <flutter/runtime_effect.glsl>

uniform float uStrength;
uniform float uAspect;
uniform float uResolution_x;
uniform float uResolution_y;
uniform sampler2D uTexture;

out vec4 fragColor;

#define PI 3.14159265358979323846

// sRGB -> linear
float srgb_to_linear(float c) {
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}
// linear -> sRGB
float linear_to_srgb(float c) {
    return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

void main() {
    vec4 c = texture(uTexture, (FlutterFragCoord().xy / vec2(uResolution_x, uResolution_y)));
    vec3 lin = vec3(srgb_to_linear(c.r), srgb_to_linear(c.g), srgb_to_linear(c.b));

    // 正規化 UV (-0.5..0.5) に aspect 補正を適用して円形距離計算
    // uy / aspect（aspect = width/height）: UV 空間ではなくピクセル空間で円形になるよう補正。
    // 横長画像（width > height, aspect > 1）の場合 uy が縮小され、UV 空間では横長楕円だが
    // ピクセル座標に変換すると正円になる。CPU 実装（vision::teichopsia）と同一の補正方式。
    vec2 uv = (FlutterFragCoord().xy / vec2(uResolution_x, uResolution_y)) - vec2(0.5);
    vec2 uvA = vec2(uv.x, uv.y / uAspect);
    float dist = length(uvA);

    vec3 result = lin;

    if (dist < 0.2) {
        // scotoma: 内側を暗化
        float dark = 1.0 - uStrength * 0.7 * (1.0 - dist / 0.2);
        result = lin * dark;
    } else if (dist <= 0.5) {
        // ジグザグリング: saw wave
        float angle = atan(uvA.y, uvA.x);
        float saw = fract(angle / PI * 8.0);
        float ring_t = (dist - 0.2) / 0.3;
        float fade = clamp(ring_t * (1.0 - ring_t) * 4.0, 0.0, 1.0);
        float brightness = saw * uStrength * fade * 0.6;
        result = clamp(lin + vec3(brightness), 0.0, 1.0);
    }

    fragColor = vec4(linear_to_srgb(result.r), linear_to_srgb(result.g), linear_to_srgb(result.b), c.a);
}
