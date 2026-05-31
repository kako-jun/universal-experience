// GENERATED FILE - DO NOT EDIT.
//
// Source of truth: sensus-core vision filter "astigmatism".
// Regenerate with: dart run tools/generate_shaders.dart
// (input: tools/sensus_shaders.g.json).
//
// scalar uniform order (setFloat index): uStrength, uRadiusPx, uAxisDeg, uTexelSize_x, uTexelSize_y, uResolution_x, uResolution_y
#include <flutter/runtime_effect.glsl>

uniform float uStrength;
uniform float uRadiusPx;
uniform float uAxisDeg;
uniform float uTexelSize_x;
uniform float uTexelSize_y;
uniform float uResolution_x;
uniform float uResolution_y;
uniform sampler2D uTexture;

// 楕円カーネルの境界判定 (u²/a²+v²/b²≤1) を CPU(f32) と bit 一致させるため highp 必須。
// mediump だと境界格子点の内外が flip し採用 tap が 1 点ずれる。
precision highp int;

// 1D directional blur — 乱視シミュレーション（純粋 cylinder lens）
//
// CPU 実装 (vision::astigmatism → ellipse_blur) と同一カーネルで畳み込む。
// CPU は「長軸 a = uRadiusPx（ぼかし方向）, 短軸 b = 0.5px（シャープ方向）」の
// filled-ellipse box（楕円内の整数格子点を一様平均, edge replication）である。
// 旧実装は ±uRadiusPx を直線 16-tap でサンプルしていたため、CPU の box 楕円
// とはカーネル形状・重み・端処理が異なり、鋭エッジで ~20dB 乖離していた (#126)。
//
// 本実装は CPU の build_ellipse_spans / ellipse_blur と同じ整数格子点列挙を行う:
//   各 (dx, dy) を回転座標 (u, v) に写し、u²/a² + v²/b² ≤ 1 の点だけ一様加算。
// 端は clamp-to-edge（CPU の edge replication と一致）。texture() は texel 中心を
// nearest fetch するため CPU の整数ピクセル参照と一致する。
//
// 半径上限: 回転した薄楕円の dy 範囲は最大 ±ceil(a) になり得る (軸 90° 付近)。
// よって 2D 窓 [-RMAX, RMAX]² を走査する。RMAX=15 は min(W,H) ≲ 1363 まで
// ceil(uRadiusPx) ≤ RMAX を満たし、CPU と bit 等価。これを超える巨大半径では
// 窓が飽和し近似となる（#97 disk-blur と同じ単一パス制約の扱い）。


out vec4 fragColor;

// CPU build_ellipse_spans の窓上限と一致させる定数（2*RMAX+1 = 31 行/列）。
const int RMAX = 15;
// CPU 短軸 b = MIN_BLUR_RADIUS_PX = 0.5px（シャープ方向, sub-pixel に縮退）。
const float B_RADIUS = 0.5;

float srgbToLinear(float c) {
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

float linearToSrgb(float c) {
    return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

void main() {
    if (uRadiusPx < 0.5) {
        fragColor = texture(uTexture, (FlutterFragCoord().xy / vec2(uResolution_x, uResolution_y)));
        return;
    }

    float rad = uAxisDeg * 3.14159265358979 / 180.0;
    float cosT = cos(rad);
    float sinT = sin(rad);
    // CPU と同じ a2/b2（ゼロ除算回避の下限つき）。
    float a2 = max(uRadiusPx * uRadiusPx, 1e-6);
    float b2 = max(B_RADIUS * B_RADIUS, 1e-6);

    // CPU の r_max = ceil(max(a, b))。窓は RMAX で頭打ち（巨大半径は近似）。
    float aMax = max(uRadiusPx, B_RADIUS);
    int rMax = int(ceil(aMax));
    if (rMax > RMAX) {
        rMax = RMAX;
    }

    vec3 acc = vec3(0.0);
    float n = 0.0;

    // CPU build_ellipse_spans と同一の整数格子点列挙（filled ellipse box）。
    for (int dy = -RMAX; dy <= RMAX; dy++) {
        if (dy < -rMax || dy > rMax) {
            continue;
        }
        for (int dx = -RMAX; dx <= RMAX; dx++) {
            if (dx < -rMax || dx > rMax) {
                continue;
            }
            float fdx = float(dx);
            float fdy = float(dy);
            float u = fdx * cosT + fdy * sinT;
            float v = -fdx * sinT + fdy * cosT;
            if ((u * u) / a2 + (v * v) / b2 <= 1.0) {
                vec2 offset = vec2(fdx, fdy) * vec2(uTexelSize_x, uTexelSize_y);
                vec4 s = texture(uTexture, (FlutterFragCoord().xy / vec2(uResolution_x, uResolution_y)) + offset);
                acc += vec3(srgbToLinear(s.r), srgbToLinear(s.g), srgbToLinear(s.b));
                n += 1.0;
            }
        }
    }

    vec3 blurred = acc / max(n, 1.0);
    fragColor = vec4(
        linearToSrgb(clamp(blurred.r, 0.0, 1.0)),
        linearToSrgb(clamp(blurred.g, 0.0, 1.0)),
        linearToSrgb(clamp(blurred.b, 0.0, 1.0)),
        texture(uTexture, (FlutterFragCoord().xy / vec2(uResolution_x, uResolution_y))).a
    );
}
