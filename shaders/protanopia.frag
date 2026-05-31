// protanopia.frag — sensus protanopia の Impeller (Flutter FragmentProgram) 移植版
//
// 正本: /home/ariori/repos/2026/sensus/crates/core/src/shaders/protanopia.frag
//       (GLSL ES 3.00, `#version 300 es` + `in vec2 vTexCoord` + `uniform float uMatrix[9]`)
//
// Impeller GLSL サブセットへの手変換ルール (docs/sensus-integration.md §2.1 案A):
//   - `#version 300 es` / `precision ...` 行を削除。
//   - `#include <flutter/runtime_effect.glsl>` を先頭に追加。
//   - 座標は `in vec2 vTexCoord` を廃し、`uSize` + `FlutterFragCoord()` から UV を求める。
//   - 配列 uniform `uniform float uMatrix[9]` は Impeller で不安定なため、個別 float
//     `uM0..uM8` へ展開する (行優先: row0col0, row0col1, ...)。
//   - srgb<->linear 変換 / linear 空間での行列適用 / uStrength 線形補間 / clamp は
//     sensus と完全に同一 (見た目一致のため)。
//   - `out vec4 fragColor;` は維持。
//
// ★ uniform 宣言順 = Dart で setFloat する順 = [uStrength, uM0..uM8, uSize.x, uSize.y]。
//   Impeller は float uniform を宣言順に setFloat(0..11) で受け取る (計 12 float)。
//   sampler `uTexture` は setImageSampler(0, ..) で別途渡す。
//   lib/rendering/shader_filter.dart はこの順序に厳密一致させること。

#include <flutter/runtime_effect.glsl>

uniform float uStrength; // setFloat(0)

// Machado 2009 severity=1.0 行列 (linear sRGB → simulated linear sRGB) を行優先で展開。
// 出典: https://www.inf.ufrgs.br/~oliveira/pubs_files/CVD_Simulation/CVD_Simulation.html
uniform float uM0; // setFloat(1)  row0col0
uniform float uM1; // setFloat(2)  row0col1
uniform float uM2; // setFloat(3)  row0col2
uniform float uM3; // setFloat(4)  row1col0
uniform float uM4; // setFloat(5)  row1col1
uniform float uM5; // setFloat(6)  row1col2
uniform float uM6; // setFloat(7)  row2col0
uniform float uM7; // setFloat(8)  row2col1
uniform float uM8; // setFloat(9)  row2col2

uniform vec2 uSize; // setFloat(10)=uSize.x, setFloat(11)=uSize.y (描画矩形のピクセルサイズ)

uniform sampler2D uTexture; // setImageSampler(0, ..)

out vec4 fragColor;

float srgbToLinear(float c) {
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

float linearToSrgb(float c) {
    return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;

    vec4 tex = texture(uTexture, uv);
    float r = srgbToLinear(tex.r);
    float g = srgbToLinear(tex.g);
    float b = srgbToLinear(tex.b);

    float sr = uM0 * r + uM1 * g + uM2 * b;
    float sg = uM3 * r + uM4 * g + uM5 * b;
    float sb = uM6 * r + uM7 * g + uM8 * b;

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
