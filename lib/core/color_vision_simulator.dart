import 'dart:typed_data';
import '../models/disability_type.dart';

/// Color Vision Deficiency Simulator
///
/// Implements LMS color space transformation for simulating
/// various types of color vision deficiencies
class ColorVisionSimulator {
  // RGB→LMS transformation matrix (Hunt-Pointer-Estevez D65)
  static const List<List<double>> _rgbToLms = [
    [0.31399022, 0.63951294, 0.04649755],
    [0.15537241, 0.75789446, 0.08670142],
    [0.01775239, 0.10944209, 0.87256922],
  ];

  // LMS→RGB transformation matrix (inverse of above)
  static const List<List<double>> _lmsToRgb = [
    [5.47221206, -4.6419601, 0.16963708],
    [-1.1252419, 2.29317094, -0.1678952],
    [0.02980165, -0.19318073, 1.16364789],
  ];

  // Protanopia transformation (L-cone missing)
  static const List<List<double>> _protanopia = [
    [0.0, 2.02344, -2.52581],
    [0.0, 1.0, 0.0],
    [0.0, 0.0, 1.0],
  ];

  // Deuteranopia transformation (M-cone missing)
  static const List<List<double>> _deuteranopia = [
    [1.0, 0.0, 0.0],
    [0.494207, 0.0, 1.24827],
    [0.0, 0.0, 1.0],
  ];

  // Tritanopia transformation (S-cone missing)
  static const List<List<double>> _tritanopia = [
    [1.0, 0.0, 0.0],
    [0.0, 1.0, 0.0],
    [-0.395913, 0.801109, 0.0],
  ];

  // Achromatopsia transformation (all cones missing)
  static const List<List<double>> _achromatopsia = [
    [0.299, 0.587, 0.114],
    [0.299, 0.587, 0.114],
    [0.299, 0.587, 0.114],
  ];

  /// Get transformation matrix for specific CVD type
  static List<List<double>> _getCvdMatrix(ColorVisionType type) {
    switch (type) {
      case ColorVisionType.protanopia:
      case ColorVisionType.protanomaly:
        return _protanopia;
      case ColorVisionType.deuteranopia:
      case ColorVisionType.deuteranomaly:
        return _deuteranopia;
      case ColorVisionType.tritanopia:
      case ColorVisionType.tritanomaly:
        return _tritanopia;
      case ColorVisionType.achromatopsia:
        return _achromatopsia;
      case ColorVisionType.none:
        return [
          [1.0, 0.0, 0.0],
          [0.0, 1.0, 0.0],
          [0.0, 0.0, 1.0],
        ];
    }
  }

  /// Multiply two 3x3 matrices
  static List<List<double>> _multiplyMatrices(
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

  /// Get final RGB→CVD_RGB transformation matrix
  ///
  /// Combines: LMS→RGB × CVD × RGB→LMS
  static List<List<double>> getTransformMatrix(ColorVisionType type) {
    if (type == ColorVisionType.none) {
      return [
        [1.0, 0.0, 0.0],
        [0.0, 1.0, 0.0],
        [0.0, 0.0, 1.0],
      ];
    }

    final cvdMatrix = _getCvdMatrix(type);
    final temp = _multiplyMatrices(cvdMatrix, _rgbToLms);
    return _multiplyMatrices(_lmsToRgb, temp);
  }

  /// Linear interpolation between two values
  static double _lerp(double a, double b, double t) {
    return a + (b - a) * t;
  }

  /// Get ColorMatrix for Flutter/Android (5×4 format)
  ///
  /// Returns a 20-element array suitable for ColorFilter.matrix
  /// Interpolates between identity and full CVD based on intensity
  static List<double> toColorMatrix(ColorVisionType type, double intensity) {
    // Clamp intensity
    final t = intensity.clamp(0.0, 1.0);

    // For anomalous trichromacy, use partial severity
    final effectiveIntensity = type.toString().contains('anomaly') ? t * 0.6 : t;

    final transform = getTransformMatrix(type);

    // Build 5×4 ColorMatrix (20 elements)
    return [
      // Red channel
      _lerp(1.0, transform[0][0], effectiveIntensity),
      _lerp(0.0, transform[0][1], effectiveIntensity),
      _lerp(0.0, transform[0][2], effectiveIntensity),
      0.0,
      0.0,

      // Green channel
      _lerp(0.0, transform[1][0], effectiveIntensity),
      _lerp(1.0, transform[1][1], effectiveIntensity),
      _lerp(0.0, transform[1][2], effectiveIntensity),
      0.0,
      0.0,

      // Blue channel
      _lerp(0.0, transform[2][0], effectiveIntensity),
      _lerp(0.0, transform[2][1], effectiveIntensity),
      _lerp(1.0, transform[2][2], effectiveIntensity),
      0.0,
      0.0,

      // Alpha channel (unchanged)
      0.0,
      0.0,
      0.0,
      1.0,
      0.0,
    ];
  }

  /// Get 5×5 matrix for Windows Magnification API
  static List<List<double>> toMagColorEffect(
    ColorVisionType type,
    double intensity,
  ) {
    final t = intensity.clamp(0.0, 1.0);
    final effectiveIntensity = type.toString().contains('anomaly') ? t * 0.6 : t;
    final transform = getTransformMatrix(type);

    return [
      [
        _lerp(1.0, transform[0][0], effectiveIntensity),
        _lerp(0.0, transform[0][1], effectiveIntensity),
        _lerp(0.0, transform[0][2], effectiveIntensity),
        0.0,
        0.0
      ],
      [
        _lerp(0.0, transform[1][0], effectiveIntensity),
        _lerp(1.0, transform[1][1], effectiveIntensity),
        _lerp(0.0, transform[1][2], effectiveIntensity),
        0.0,
        0.0
      ],
      [
        _lerp(0.0, transform[2][0], effectiveIntensity),
        _lerp(0.0, transform[2][1], effectiveIntensity),
        _lerp(1.0, transform[2][2], effectiveIntensity),
        0.0,
        0.0
      ],
      [0.0, 0.0, 0.0, 1.0, 0.0], // Alpha
      [0.0, 0.0, 0.0, 0.0, 1.0], // Translation
    ];
  }

  /// Transform a single RGB color
  static List<int> transformColor(
    int r,
    int g,
    int b,
    ColorVisionType type,
    double intensity,
  ) {
    final transform = getTransformMatrix(type);
    final t = intensity.clamp(0.0, 1.0);

    // Normalize to 0-1
    final rNorm = r / 255.0;
    final gNorm = g / 255.0;
    final bNorm = b / 255.0;

    // Apply transformation
    final rTransformed = transform[0][0] * rNorm +
        transform[0][1] * gNorm +
        transform[0][2] * bNorm;
    final gTransformed = transform[1][0] * rNorm +
        transform[1][1] * gNorm +
        transform[1][2] * bNorm;
    final bTransformed = transform[2][0] * rNorm +
        transform[2][1] * gNorm +
        transform[2][2] * bNorm;

    // Interpolate with original based on intensity
    final rFinal = _lerp(rNorm, rTransformed, t);
    final gFinal = _lerp(gNorm, gTransformed, t);
    final bFinal = _lerp(bNorm, bTransformed, t);

    // Clamp and convert back to 0-255
    return [
      (rFinal * 255).clamp(0, 255).round(),
      (gFinal * 255).clamp(0, 255).round(),
      (bFinal * 255).clamp(0, 255).round(),
    ];
  }

  /// Generate a lookup table (LUT) for fast color transformation
  ///
  /// Creates a 3D LUT with [lutSize]^3 entries
  /// Default size: 64 (64×64×64 = 262,144 entries)
  static Uint8List generateLUT(ColorVisionType type, {int lutSize = 64}) {
    final lut = Uint8List(lutSize * lutSize * lutSize * 3);
    final step = 255 / (lutSize - 1);

    int index = 0;
    for (int r = 0; r < lutSize; r++) {
      for (int g = 0; g < lutSize; g++) {
        for (int b = 0; b < lutSize; b++) {
          final rgbIn = [
            (r * step).round(),
            (g * step).round(),
            (b * step).round(),
          ];

          final rgbOut = transformColor(
            rgbIn[0],
            rgbIn[1],
            rgbIn[2],
            type,
            1.0,
          );

          lut[index++] = rgbOut[0];
          lut[index++] = rgbOut[1];
          lut[index++] = rgbOut[2];
        }
      }
    }

    return lut;
  }
}
