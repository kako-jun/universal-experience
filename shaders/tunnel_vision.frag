// GENERATED FILE - DO NOT EDIT.
//
// Source of truth: sensus-core vision filter "tunnel_vision"
// (canonical GLSL: sensus shaders/tunnel_vision.frag, sensus-core v0.5.0).
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

// トンネル視野（tunnel vision）シミュレーション — 急峻なビネット
// glaucoma より inner_r/outer_r の差が小さく、急激な境界が特徴。


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

    // vision.rs と同じ定数: tunnel_vision は急峻（outer - inner = 0.05）
    float inner_r = (1.0 - uStrength) * 0.5;
    float outer_r = min(inner_r + 0.05, 1.0);

    float t = clamp((d - inner_r) / max(outer_r - inner_r, 1e-5), 0.0, 1.0);
    float fade = t * t * (3.0 - 2.0 * t); // smoothstep
    float mul = 1.0 - uStrength * fade;

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
