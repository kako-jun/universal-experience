// GENERATED FILE - DO NOT EDIT.
//
// Source of truth: sensus-core vision filter "vestibular_neuritis"
// (canonical GLSL: sensus shaders/vestibular_neuritis.frag, sensus-core v0.5.0).
// Filter-specific provenance (e.g. the Machado 2009 matrix and
// its citation) lives in the sensus source, not here.
//
// Regenerate with: dart run tools/generate_shaders.dart
// (input dump: tools/sensus_shaders.g.json, produced by sensus-core v0.5.0).
//
// scalar uniform order (setFloat index): uStrength, uRadiusPx, uShiftTexel, uTexelSize_x, uTexelSize_y, uResolution_x, uResolution_y
#include <flutter/runtime_effect.glsl>

uniform float uStrength;
uniform float uRadiusPx;
uniform float uShiftTexel;
uniform float uTexelSize_x;
uniform float uTexelSize_y;
uniform float uResolution_x;
uniform float uResolution_y;
uniform sampler2D uTexture;

// 前庭神経炎（Vestibular Neuritis）シミュレーション。
// 水平シフト + 1D 水平 blur（motion blur）。
// CPU 実装 vision::vestibular_neuritis に対応。
//
// GPU 版は 16-tap 水平 blur で motion blur を再現。
// シフト量: strength * 0.05 (テクセル単位)


out vec4 fragColor;

float srgbToLinear(float c) {
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}
float linearToSrgb(float c) {
    return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

void main() {
    // 水平シフト
    vec2 shiftedUV = vec2(clamp((FlutterFragCoord().xy / vec2(uResolution_x, uResolution_y)).x - uShiftTexel, 0.0, 1.0), (FlutterFragCoord().xy / vec2(uResolution_x, uResolution_y)).y);

    if (uRadiusPx < 0.5) {
        fragColor = texture(uTexture, shiftedUV);
        return;
    }

    // 16-tap 水平 1D blur
    const int N = 16;
    vec3 acc = vec3(0.0);
    for (int i = 0; i < N; i++) {
        float t = (float(i) / float(N - 1)) * 2.0 - 1.0;
        float offsetU = t * uRadiusPx * vec2(uTexelSize_x, uTexelSize_y).x;
        vec4 s = texture(uTexture, vec2(clamp(shiftedUV.x + offsetU, 0.0, 1.0), shiftedUV.y));
        acc += vec3(srgbToLinear(s.r), srgbToLinear(s.g), srgbToLinear(s.b));
    }
    vec3 blurred = acc / float(N);

    fragColor = vec4(
        linearToSrgb(clamp(blurred.r, 0.0, 1.0)),
        linearToSrgb(clamp(blurred.g, 0.0, 1.0)),
        linearToSrgb(clamp(blurred.b, 0.0, 1.0)),
        texture(uTexture, shiftedUV).a
    );
}
