// GENERATED FILE - DO NOT EDIT.
//
// Source of truth: sensus-core vision filter "eye_strain"
// (canonical GLSL: sensus shaders/eye_strain.frag, sensus-core v0.5.0).
// Filter-specific provenance (e.g. the Machado 2009 matrix and
// its citation) lives in the sensus source, not here.
//
// Regenerate with: dart run tools/generate_shaders.dart
// (input dump: tools/sensus_shaders.g.json, produced by sensus-core v0.5.0).
//
// scalar uniform order (setFloat index): uStrength, uRadiusPx, uTexelSize_x, uTexelSize_y, uResolution_x, uResolution_y
#include <flutter/runtime_effect.glsl>

uniform float uStrength;
uniform float uRadiusPx;
uniform float uTexelSize_x;
uniform float uTexelSize_y;
uniform float uResolution_x;
uniform float uResolution_y;
uniform sampler2D uTexture;

// 眼精疲労（Eye strain）シミュレーション。
// CPU 実装 vision::eye_strain に対応。処理順序は CPU と同一:
//   1. linear sRGB 空間でコントラスト圧縮
//   2. vignette（周辺減光）
//   3. 微小 disk（pillbox）blur（半径 = strength * 1.5 px）
//
// CPU は手順 1+2 を済ませたバッファに対し「均一重み disk blur（edge replication）」を
// 厳密適用する。GPU は単一パスで処理するため、各 tap で 1+2 を再計算してから
// disk 状に平均する。厳密 pillbox は単一パスで畳み込めない（半径が大きいとループ
// 展開不可）ため、photophobia.frag と同じ Fibonacci lattice 16 tap で円盤を近似
// サンプリングする。等価性は PSNR で担保する
// （shader_equivalence の simulate_eye_strain_glsl は本シェーダと同一の式を持つ）。
// 乖離上限: 32x32 で strength=0.5 → PSNR ≈ 40 dB、strength=1.0 → ≈ 42 dB
// （いずれも許容下限 30 dB を満たす）。


out vec4 fragColor;

// blur が視認できない最小半径（CPU の MIN_BLUR_RADIUS_PX と一致）
const float kMinRadiusPx = 0.5;

// sRGB -> linear
float srgbToLinear(float c) {
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}
// linear -> sRGB
float linearToSrgb(float c) {
    return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

// 指定 uv で「コントラスト圧縮 + vignette」を済ませた linear sRGB を返す。
// CPU の Step 1 と 1:1 対応。vignette は uv のテクスチャ座標（中心 0.5）から算出する。
vec3 processedAt(vec2 uv) {
    vec3 s = texture(uTexture, uv).rgb;
    vec3 lin = vec3(srgbToLinear(s.r), srgbToLinear(s.g), srgbToLinear(s.b));
    // contrast compression in linear space
    vec3 compressed = vec3(0.5) + (lin - vec3(0.5)) * (1.0 - uStrength * 0.15);
    // vignette
    vec2 nuv = uv * 2.0 - 1.0;
    float d = dot(nuv, nuv);
    float t = clamp((d - 0.3) / (1.2 - 0.3), 0.0, 1.0);
    float sm = t * t * (3.0 - 2.0 * t);
    float vignette = 1.0 - uStrength * 0.3 * sm;
    return clamp(compressed * vignette, 0.0, 1.0);
}

void main() {
    vec4 c = texture(uTexture, (FlutterFragCoord().xy / vec2(uResolution_x, uResolution_y)));

    vec3 result;
    if (uRadiusPx < kMinRadiusPx) {
        // CPU: 半径が小さすぎる場合は blur なし（contrast+vignette のみ）
        result = processedAt((FlutterFragCoord().xy / vec2(uResolution_x, uResolution_y)));
    } else {
        // disk（pillbox）状に近傍を平均する近似。
        // Fibonacci lattice 16 tap で円盤内を均等サンプリングし平均する。
        const int N = 16;
        const float PHI = 2.399963229728653; // 黄金角 ≈ 137.508°
        vec3 acc = vec3(0.0);
        for (int i = 0; i < N; i++) {
            float ft = float(i) / float(N);
            float r = sqrt(ft) * uRadiusPx;
            float theta = float(i) * PHI;
            vec2 offset = vec2(cos(theta), sin(theta)) * r * vec2(uTexelSize_x, uTexelSize_y);
            acc += processedAt((FlutterFragCoord().xy / vec2(uResolution_x, uResolution_y)) + offset);
        }
        result = acc / float(N);
    }

    // encode back to sRGB
    fragColor = vec4(linearToSrgb(result.r), linearToSrgb(result.g), linearToSrgb(result.b), c.a);
}
