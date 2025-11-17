# Color Vision Deficiency Simulation Algorithm

色覚障害シミュレーションのための技術的詳細とアルゴリズム実装方針。

## 概要

色覚障害（CVD: Color Vision Deficiency）のシミュレーションは、LMS色空間での変換に基づいています。

## LMS色空間とは

**LMS色空間**は、人間の目にある3種類の錐体細胞の応答を表現する色空間です：

- **L (Long)**: 長波長（赤）に反応する錐体
- **M (Medium)**: 中波長（緑）に反応する錐体
- **S (Short)**: 短波長（青）に反応する錐体

色覚異常を持つ人は、これらの錐体のいずれかが欠損または機能低下しています。

## 色覚異常のタイプ

### 2色覚（Dichromacy）- 完全欠損

| タイプ | 欠損錐体 | 有病率 |
|--------|---------|-------|
| **Protanopia** (1型色覚) | L錐体欠損 | 男性 ~1%, 女性 ~0.01% |
| **Deuteranopia** (2型色覚) | M錐体欠損 | 男性 ~1%, 女性 ~0.01% |
| **Tritanopia** (3型色覚) | S錐体欠損 | ~0.001% |
| **Achromatopsia** (全色盲) | 全錐体欠損 | ~0.003% |

### 異常3色覚（Anomalous Trichromacy）- 機能低下

| タイプ | 異常錐体 | 有病率 |
|--------|---------|-------|
| **Protanomaly** (1型2色覚) | L錐体弱化 | 男性 ~1% |
| **Deuteranomaly** (2型2色覚) | M錐体弱化 | 男性 ~5%, 女性 ~0.4% |
| **Tritanomaly** (3型2色覚) | S錐体弱化 | ~0.01% |

## アルゴリズム: RGB → LMS → 色覚異常シミュレーション → RGB

### ステップ1: RGB → LMS変換

sRGB色空間からLMS色空間への変換：

```
[ L ]       [ L_r  L_g  L_b ]   [ R ]
[ M ] = T × [ M_r  M_g  M_b ] × [ G ]
[ S ]       [ S_r  S_g  S_b ]   [ B ]
```

**Hunt-Pointer-Estevez変換行列（D65白色点）**:
```
T_RGB→LMS = [
    [ 0.31399022,  0.63951294,  0.04649755 ],
    [ 0.15537241,  0.75789446,  0.08670142 ],
    [ 0.01775239,  0.10944209,  0.87256922 ]
]
```

または**Brettel変換行列**も一般的：
```
T_RGB→LMS = [
    [ 17.8824,  43.5161,  4.11935 ],
    [ 3.45565,  27.1554,  3.86714 ],
    [ 0.02996,  0.18431,  1.46709 ]
]
```

### ステップ2: 色覚異常シミュレーション

各錐体欠損に対する変換行列：

#### Protanopia (L錐体欠損)

LとMの錐体信号から、欠損したL信号を推定：

```
T_protanopia = [
    [ 0.0,  2.02344, -2.52581 ],
    [ 0.0,  1.0,      0.0     ],
    [ 0.0,  0.0,      1.0     ]
]
```

#### Deuteranopia (M錐体欠損)

```
T_deuteranopia = [
    [ 1.0,      0.0,  0.0     ],
    [ 0.494207, 0.0,  1.24827 ],
    [ 0.0,      0.0,  1.0     ]
]
```

#### Tritanopia (S錐体欠損)

```
T_tritanopia = [
    [ 1.0,  0.0,      0.0     ],
    [ 0.0,  1.0,      0.0     ],
    [ -0.395913, 0.801109, 0.0 ]
]
```

#### Achromatopsia (全色盲)

全ての色情報を輝度に変換：

```
T_achromatopsia = [
    [ 0.299,  0.587,  0.114 ],
    [ 0.299,  0.587,  0.114 ],
    [ 0.299,  0.587,  0.114 ]
]
```

### ステップ3: LMS → RGB変換

LMS色空間からsRGBへ戻す：

```
T_LMS→RGB = T_RGB→LMS^(-1)
```

**逆変換行列例**:
```
T_LMS→RGB = [
    [  5.47221206, -4.6419601,   0.16963708 ],
    [ -1.1252419,   2.29317094, -0.1678952  ],
    [  0.02980165, -0.19318073,  1.16364789 ]
]
```

### 完全な変換行列

RGB → 色覚異常RGB の直接変換：

```
T_final = T_LMS→RGB × T_cvd × T_RGB→LMS
```

## 実装例

### Dart/Flutter実装

```dart
class ColorVisionSimulator {
  // RGB→LMS変換行列 (Hunt-Pointer-Estevez)
  static const List<List<double>> rgbToLms = [
    [0.31399022, 0.63951294, 0.04649755],
    [0.15537241, 0.75789446, 0.08670142],
    [0.01775239, 0.10944209, 0.87256922],
  ];

  // LMS→RGB変換行列
  static const List<List<double>> lmsToRgb = [
    [5.47221206, -4.6419601, 0.16963708],
    [-1.1252419, 2.29317094, -0.1678952],
    [0.02980165, -0.19318073, 1.16364789],
  ];

  // Protanopia変換行列
  static const List<List<double>> protanopia = [
    [0.0, 2.02344, -2.52581],
    [0.0, 1.0, 0.0],
    [0.0, 0.0, 1.0],
  ];

  // Deuteranopia変換行列
  static const List<List<double>> deuteranopia = [
    [1.0, 0.0, 0.0],
    [0.494207, 0.0, 1.24827],
    [0.0, 0.0, 1.0],
  ];

  // Tritanopia変換行列
  static const List<List<double>> tritanopia = [
    [1.0, 0.0, 0.0],
    [0.0, 1.0, 0.0],
    [-0.395913, 0.801109, 0.0],
  ];

  /// 行列の乗算
  static List<List<double>> multiplyMatrices(
    List<List<double>> a,
    List<List<double>> b,
  ) {
    final result = List.generate(3, (_) => List<double>.filled(3, 0.0));

    for (int i = 0; i < 3; i++) {
      for (int j = 0; j < 3; j++) {
        for (int k = 0; k < 3; k++) {
          result[i][j] += a[i][k] * b[k][j];
        }
      }
    }

    return result;
  }

  /// 最終的な変換行列を計算
  static List<List<double>> getTransformMatrix(String type) {
    List<List<double>> cvdMatrix;

    switch (type) {
      case 'protanopia':
        cvdMatrix = protanopia;
        break;
      case 'deuteranopia':
        cvdMatrix = deuteranopia;
        break;
      case 'tritanopia':
        cvdMatrix = tritanopia;
        break;
      default:
        // 単位行列（変換なし）
        return [
          [1.0, 0.0, 0.0],
          [0.0, 1.0, 0.0],
          [0.0, 0.0, 1.0],
        ];
    }

    // T_final = T_LMS→RGB × T_cvd × T_RGB→LMS
    final temp = multiplyMatrices(cvdMatrix, rgbToLms);
    return multiplyMatrices(lmsToRgb, temp);
  }

  /// ColorMatrixに変換（Android/Flutter用）
  static List<double> toColorMatrix(String type, double intensity) {
    final transform = getTransformMatrix(type);

    // 5×4行列に変換（ColorMatrix形式）
    // 強度に応じて補間
    return [
      lerp(1.0, transform[0][0], intensity), lerp(0.0, transform[0][1], intensity), lerp(0.0, transform[0][2], intensity), 0.0, 0.0,
      lerp(0.0, transform[1][0], intensity), lerp(1.0, transform[1][1], intensity), lerp(0.0, transform[1][2], intensity), 0.0, 0.0,
      lerp(0.0, transform[2][0], intensity), lerp(0.0, transform[2][1], intensity), lerp(1.0, transform[2][2], intensity), 0.0, 0.0,
      0.0, 0.0, 0.0, 1.0, 0.0,
    ];
  }

  static double lerp(double a, double b, double t) {
    return a + (b - a) * t;
  }
}
```

### Android実装（Kotlin）

```kotlin
class ColorVisionFilter {
    companion object {
        fun getColorMatrix(type: String, intensity: Float): ColorMatrix {
            val transform = getTransformMatrix(type)

            // 強度補間
            val matrix = FloatArray(20) {
                when {
                    it < 5 -> when (it % 5) {
                        0 -> lerp(1f, transform[0][0], intensity)
                        1 -> lerp(0f, transform[0][1], intensity)
                        2 -> lerp(0f, transform[0][2], intensity)
                        else -> 0f
                    }
                    it < 10 -> when (it % 5) {
                        0 -> lerp(0f, transform[1][0], intensity)
                        1 -> lerp(1f, transform[1][1], intensity)
                        2 -> lerp(0f, transform[1][2], intensity)
                        else -> 0f
                    }
                    it < 15 -> when (it % 5) {
                        0 -> lerp(0f, transform[2][0], intensity)
                        1 -> lerp(0f, transform[2][1], intensity)
                        2 -> lerp(1f, transform[2][2], intensity)
                        else -> 0f
                    }
                    else -> if (it % 5 == 3) 1f else 0f
                }
            }

            return ColorMatrix(matrix)
        }

        private fun lerp(a: Float, b: Float, t: Float): Float {
            return a + (b - a) * t
        }
    }
}
```

### Windows実装（C++）

```cpp
#include <magnification.h>

MAGCOLOREFFECT CreateColorVisionEffect(const char* type, float intensity) {
    MAGCOLOREFFECT effect = {};
    float transform[3][3];

    GetTransformMatrix(type, transform);

    // 強度補間して5×5行列に変換
    for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 3; j++) {
            float identity = (i == j) ? 1.0f : 0.0f;
            effect.transform[i][j] =
                identity + (transform[i][j] - identity) * intensity;
        }
        effect.transform[i][3] = 0.0f;
        effect.transform[i][4] = 0.0f;
    }

    // Alpha行
    effect.transform[3][0] = 0.0f;
    effect.transform[3][1] = 0.0f;
    effect.transform[3][2] = 0.0f;
    effect.transform[3][3] = 1.0f;
    effect.transform[3][4] = 0.0f;

    // 最終行
    effect.transform[4][0] = 0.0f;
    effect.transform[4][1] = 0.0f;
    effect.transform[4][2] = 0.0f;
    effect.transform[4][3] = 0.0f;
    effect.transform[4][4] = 1.0f;

    return effect;
}
```

## Daltonization（色覚補正）

Daltonizationは、色覚異常の人でも色の区別がしやすくなるように画像を補正する技術です。

### 基本アルゴリズム

1. **オリジナル画像を色覚異常シミュレーション**
2. **差分を計算**: `error = original - simulated`
3. **エラーを強調**: 区別しにくい色の差を強調
4. **補正画像を生成**: `corrected = original + error_enhancement`

### 実装例

```dart
class Daltonizer {
  /// Daltonization適用
  static List<double> daltonize(String cvdType) {
    // シミュレーション行列
    final simMatrix = ColorVisionSimulator.getTransformMatrix(cvdType);

    // エラー補正行列
    // 失われた情報を他のチャンネルにシフト
    final errorMatrix = [
      [0.0, 0.0, 0.0],
      [0.7, 1.0, 0.0],
      [0.7, 0.0, 1.0],
    ];

    // 最終補正行列
    final correctionMatrix = List.generate(3, (i) =>
      List.generate(3, (j) =>
        simMatrix[i][j] + errorMatrix[i][j]
      )
    );

    return flattenMatrix(correctionMatrix);
  }
}
```

## Anomalous Trichromacy（異常3色覚）実装

部分的な機能低下をシミュレート：

```dart
static List<List<double>> getAnomalyMatrix(String type, double severity) {
  final dichromacyMatrix = getTransformMatrix(type.replaceAll('anomaly', 'anopia'));
  final normalMatrix = [
    [1.0, 0.0, 0.0],
    [0.0, 1.0, 0.0],
    [0.0, 0.0, 1.0],
  ];

  // 正常視と2色覚の間で補間
  return interpolateMatrices(normalMatrix, dichromacyMatrix, severity);
}
```

## 検証とテスト

### Ishihara色覚検査プレート

実装の正確性を検証するため、石原式色覚検査表を使用：

- Protanopia: 特定の数字が見えなくなる
- Deuteranopia: 異なるパターンが見える
- 正常視: すべての数字が見える

### リファレンス実装

- **DaltonLens**: https://daltonlens.org
- **Coblis**: Color Blindness Simulator
- **Adobe Photoshop**: 校正設定の色覚異常シミュレーション

## パフォーマンス最適化

### GPUアクセラレーション

```glsl
// GLSL Shader例
uniform mat3 cvdTransform;

void main() {
    vec3 rgb = texture2D(inputTexture, texCoord).rgb;
    vec3 cvdRgb = cvdTransform * rgb;
    gl_FragColor = vec4(clamp(cvdRgb, 0.0, 1.0), 1.0);
}
```

### ルックアップテーブル（LUT）

事前計算したLUTで高速化：

```dart
class ColorLUT {
  static const int lutSize = 64; // 64×64×64 LUT

  static Uint8List generateLUT(String cvdType) {
    final lut = Uint8List(lutSize * lutSize * lutSize * 3);
    final matrix = ColorVisionSimulator.getTransformMatrix(cvdType);

    // 全RGB組み合わせを事前計算
    // ...

    return lut;
  }
}
```

## 今後の改善

1. ✅ 基本的なLMS変換実装
2. ⬜ Brettelアルゴリズムの実装（より正確）
3. ⬜ 個人差を考慮した調整機能
4. ⬜ Daltonization（補正）機能
5. ⬜ リアルタイムGPU最適化
6. ⬜ 医学的検証データとの比較

## 参考文献

1. **Viénot et al. (1999)** - "Digital video colourmaps for checking the legibility of displays by dichromats"
2. **Brettel et al. (1997)** - "Computerized simulation of color appearance for dichromats"
3. **DaltonLens Documentation** - https://daltonlens.org
4. **Daltonize.org** - http://www.daltonize.org
5. **Machado et al. (2009)** - "A Physiologically-based Model for Simulation of Color Vision Deficiency"
