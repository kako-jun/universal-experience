// GENERATED FILE - DO NOT EDIT.
//
// Source of truth: sensus-core vision filter "photophobia"
// (canonical GLSL: sensus shaders/photophobia.frag, sensus-core v0.5.0).
// Filter-specific provenance (e.g. the Machado 2009 matrix and
// its citation) lives in the sensus source, not here.
//
// Regenerate with: dart run tools/generate_shaders.dart
// (input dump: tools/sensus_shaders.g.json, produced by sensus-core v0.5.0).
//
// scalar uniform order (setFloat index): uRadiusPx, uTexelSize_x, uTexelSize_y, uResolution_x, uResolution_y
#include <flutter/runtime_effect.glsl>

uniform float uRadiusPx;
uniform float uTexelSize_x;
uniform float uTexelSize_y;
uniform float uResolution_x;
uniform float uResolution_y;
uniform sampler2D uTexture;

// 光過敏（Photophobia）シミュレーション。
// 高輝度領域を抽出し、disk（pillbox）状に近傍へ滲ませる bloom。
// CPU 実装 vision::photophobia に対応。
//
// CPU は highlight レイヤに「均一重み disk blur（半径 r, edge replication）」を
// 厳密適用する。GPU は単一パスで厳密 pillbox を畳み込めない（半径が大きいと
// ループ展開不可）ため、Fibonacci lattice 16 tap で円盤を近似サンプリングする。
// 16tap lattice 近似サンプリング自体は myopia.frag / hyperopia.frag と同じだが、
// それらが画像そのものをぼかすのに対し本シェーダは highlight レイヤをぼかして
// 元画像に加算合成する点が異なる。等価性は PSNR で担保する
// （shader_equivalence の sim_photophobia_glsl は本シェーダと同一の式を持つ）。
// 乖離上限: strength=1.0 / 32x32 で PSNR ≈ 42.7 dB（許容下限 30 dB を満たす）。

// 注: strength は uRadiusPx の算出にのみ使う（CPU 実装と同じく highlight 振幅は
//     strength 非依存）。そのため uStrength uniform は持たない。

out vec4 fragColor;

// highlight 抽出のしきい値（CPU の PHOTOPHOBIA_THRESHOLD と一致）
const float kThreshold = 0.5;
// bloom が視認できない最小半径（CPU の MIN_BLUR_RADIUS_PX と一致）
const float kMinRadiusPx = 0.5;

float srgbToLinear(float c) {
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}
float linearToSrgb(float c) {
    return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

// 指定 uv の highlight レイヤ（linear sRGB）を返す。
// luma > しきい値 の超過分でマスクし、linear RGB に乗じる。
vec3 highlightAt(vec2 uv) {
    vec3 s = texture(uTexture, uv).rgb;
    vec3 lin = vec3(srgbToLinear(s.r), srgbToLinear(s.g), srgbToLinear(s.b));
    float luma = 0.2126 * lin.r + 0.7152 * lin.g + 0.0722 * lin.b;
    float mask = luma > kThreshold
        ? (luma - kThreshold) / (1.0 - kThreshold)
        : 0.0;
    return lin * mask;
}

// highlight レイヤを disk（pillbox）状にぼかす近似。
// Fibonacci lattice 16 tap で円盤内を均等サンプリングし平均する。
vec3 bloomSpread(vec2 uv, float radius) {
    if (radius < kMinRadiusPx) {
        // CPU: 半径が小さすぎる場合は bloom なし
        return vec3(0.0);
    }
    const int N = 16;
    const float PHI = 2.399963229728653; // 黄金角 ≈ 137.508°
    vec3 acc = vec3(0.0);
    for (int i = 0; i < N; i++) {
        float t = float(i) / float(N);
        float r = sqrt(t) * radius;
        float theta = float(i) * PHI;
        vec2 offset = vec2(cos(theta), sin(theta)) * r * vec2(uTexelSize_x, uTexelSize_y);
        acc += highlightAt(uv + offset);
    }
    return acc / float(N);
}

void main() {
    vec4 orig = texture(uTexture, (FlutterFragCoord().xy / vec2(uResolution_x, uResolution_y)));
    vec3 lin = vec3(
        srgbToLinear(orig.r),
        srgbToLinear(orig.g),
        srgbToLinear(orig.b)
    );

    vec3 bloom = bloomSpread((FlutterFragCoord().xy / vec2(uResolution_x, uResolution_y)), uRadiusPx);

    fragColor = vec4(
        linearToSrgb(clamp(lin.r + bloom.r, 0.0, 1.0)),
        linearToSrgb(clamp(lin.g + bloom.g, 0.0, 1.0)),
        linearToSrgb(clamp(lin.b + bloom.b, 0.0, 1.0)),
        orig.a
    );
}
