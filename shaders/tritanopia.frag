// GENERATED FILE - DO NOT EDIT.
//
// Source of truth: sensus-core vision filter "tritanopia".
// Regenerate with: dart run tools/generate_shaders.dart
// (input: tools/sensus_shaders.g.json).
//
// scalar uniform order (setFloat index): uStrength, uMatrix0, uMatrix1, uMatrix2, uMatrix3, uMatrix4, uMatrix5, uMatrix6, uMatrix7, uMatrix8, uResolution_x, uResolution_y
#include <flutter/runtime_effect.glsl>

uniform float uStrength;
uniform float uMatrix0;
uniform float uMatrix1;
uniform float uMatrix2;
uniform float uMatrix3;
uniform float uMatrix4;
uniform float uMatrix5;
uniform float uMatrix6;
uniform float uMatrix7;
uniform float uMatrix8;
uniform float uResolution_x;
uniform float uResolution_y;
uniform sampler2D uTexture;

// Machado 2009 severity=1.0 行列（linear sRGB → simulated linear sRGB）
// 出典: https://www.inf.ufrgs.br/~oliveira/pubs_files/CVD_Simulation/CVD_Simulation.html


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

    float sr = uMatrix0 * r + uMatrix1 * g + uMatrix2 * b;
    float sg = uMatrix3 * r + uMatrix4 * g + uMatrix5 * b;
    float sb = uMatrix6 * r + uMatrix7 * g + uMatrix8 * b;

    float nr = r + (sr - r) * uStrength;
    float ng = g + (sg - g) * uStrength;
    float nb = b + (sb - b) * uStrength;

    fragColor = vec4(
        linearToSrgb(clamp(nr, 0.0, 1.0)),
        linearToSrgb(clamp(ng, 0.0, 1.0)),
        linearToSrgb(clamp(nb, 0.0, 1.0)),
        tex.a
    );
}
