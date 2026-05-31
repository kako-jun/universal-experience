// GENERATED FILE - DO NOT EDIT.
//
// Source of truth: sensus-core vision filter "diplopia"
// (canonical GLSL: sensus shaders/diplopia.frag, sensus-core v0.5.0).
// Filter-specific provenance (e.g. the Machado 2009 matrix and
// its citation) lives in the sensus source, not here.
//
// Regenerate with: dart run tools/generate_shaders.dart
// (input dump: tools/sensus_shaders.g.json, produced by sensus-core v0.5.0).
//
// scalar uniform order (setFloat index): uStrength, uOffsetX, uOffsetY, uGhostStrength, uResolution_x, uResolution_y
#include <flutter/runtime_effect.glsl>

uniform float uStrength;
uniform float uOffsetX;
uniform float uOffsetY;
uniform float uGhostStrength;
uniform float uResolution_x;
uniform float uResolution_y;
uniform sampler2D uTexture;

out vec4 fragColor;

float srgbToLinear(float c) {
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}
float linearToSrgb(float c) {
    return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

void main() {
    vec4 orig = texture(uTexture, (FlutterFragCoord().xy / vec2(uResolution_x, uResolution_y)));
    vec2 ghostUV = clamp((FlutterFragCoord().xy / vec2(uResolution_x, uResolution_y)) - vec2(uOffsetX, uOffsetY), 0.0, 1.0);
    vec4 ghost = texture(uTexture, ghostUV);

    float alpha = clamp(uGhostStrength * uStrength, 0.0, 1.0);

    vec3 o = vec3(srgbToLinear(orig.r), srgbToLinear(orig.g), srgbToLinear(orig.b));
    vec3 g = vec3(srgbToLinear(ghost.r), srgbToLinear(ghost.g), srgbToLinear(ghost.b));
    // out = orig * (1 - alpha) + ghost * alpha（alpha blend、輝度保存）
    vec3 blended = o * (1.0 - alpha) + g * alpha;

    fragColor = vec4(
        linearToSrgb(clamp(blended.r, 0.0, 1.0)),
        linearToSrgb(clamp(blended.g, 0.0, 1.0)),
        linearToSrgb(clamp(blended.b, 0.0, 1.0)),
        orig.a
    );
}
