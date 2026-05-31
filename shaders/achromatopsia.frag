// GENERATED FILE - DO NOT EDIT.
//
// Source of truth: sensus-core vision filter "achromatopsia"
// (canonical GLSL: sensus shaders/achromatopsia.frag, sensus-core v0.5.0).
// Filter-specific provenance (e.g. the Machado 2009 matrix and
// its citation) lives in the sensus source, not here.
//
// Regenerate with: dart run tools/generate_shaders.dart
// (input dump: tools/sensus_shaders.g.json, produced by sensus-core v0.5.0).
//
// scalar uniform order (setFloat index): uStrength, uRWeight, uGWeight, uBWeight, uResolution_x, uResolution_y
#include <flutter/runtime_effect.glsl>

uniform float uStrength;
uniform float uRWeight;
uniform float uGWeight;
uniform float uBWeight;
uniform float uResolution_x;
uniform float uResolution_y;
uniform sampler2D uTexture;

// BT.709 photopic luminance によるグレースケール化（全色盲シミュレーション）
// 係数: R=0.2126, G=0.7152, B=0.0722

out vec4 fragColor;

float srgbToLinear(float c) {
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

float linearToSrgb(float c) {
    return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

void main() {
    vec4 tex = texture(uTexture, (FlutterFragCoord().xy / vec2(uResolution_x, uResolution_y)));
    float r = srgbToLinear(tex.r);
    float g = srgbToLinear(tex.g);
    float b = srgbToLinear(tex.b);

    float y = uRWeight * r + uGWeight * g + uBWeight * b;

    float nr = r + (y - r) * uStrength;
    float ng = g + (y - g) * uStrength;
    float nb = b + (y - b) * uStrength;

    fragColor = vec4(
        linearToSrgb(clamp(nr, 0.0, 1.0)),
        linearToSrgb(clamp(ng, 0.0, 1.0)),
        linearToSrgb(clamp(nb, 0.0, 1.0)),
        tex.a
    );
}
