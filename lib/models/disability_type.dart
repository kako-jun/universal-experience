/// Enumeration of supported disability simulation types
enum DisabilityType {
  /// Color vision deficiencies
  colorVision,

  /// Hearing impairments (future)
  hearing,

  /// Visual field defects (future)
  visualField,

  /// Motor impairments (future)
  motor,
}

/// Enumeration of color vision deficiency types
enum ColorVisionType {
  /// No filter applied (normal vision)
  none('Normal Vision', 'none'),

  /// Red-green color blindness (missing L-cones)
  protanopia('Protanopia', 'protanopia'),

  /// Red-green color blindness (missing M-cones)
  deuteranopia('Deuteranopia', 'deuteranopia'),

  /// Blue-yellow color blindness (missing S-cones)
  tritanopia('Tritanopia', 'tritanopia'),

  /// Complete color blindness (no cone function)
  achromatopsia('Achromatopsia', 'achromatopsia'),

  /// Partial red-green deficiency (weak L-cones)
  protanomaly('Protanomaly', 'protanomaly'),

  /// Partial red-green deficiency (weak M-cones)
  deuteranomaly('Deuteranomaly', 'deuteranomaly'),

  /// Partial blue-yellow deficiency (weak S-cones)
  tritanomaly('Tritanomaly', 'tritanomaly');

  const ColorVisionType(this.displayName, this.id);

  final String displayName;
  final String id;

  /// Get description of the color vision type
  String get description {
    switch (this) {
      case ColorVisionType.none:
        return 'Normal color vision with no simulation applied';
      case ColorVisionType.protanopia:
        return 'Red-green color blindness caused by absence of L-cones (red receptors)';
      case ColorVisionType.deuteranopia:
        return 'Red-green color blindness caused by absence of M-cones (green receptors)';
      case ColorVisionType.tritanopia:
        return 'Blue-yellow color blindness caused by absence of S-cones (blue receptors)';
      case ColorVisionType.achromatopsia:
        return 'Complete color blindness with no functional cone cells';
      case ColorVisionType.protanomaly:
        return 'Partial red-green deficiency with weakened L-cones';
      case ColorVisionType.deuteranomaly:
        return 'Partial red-green deficiency with weakened M-cones (most common form)';
      case ColorVisionType.tritanomaly:
        return 'Partial blue-yellow deficiency with weakened S-cones';
    }
  }

  /// Approximate prevalence in population
  String get prevalence {
    switch (this) {
      case ColorVisionType.none:
        return '~92% of males, ~99.5% of females';
      case ColorVisionType.protanopia:
        return '~1% of males, ~0.01% of females';
      case ColorVisionType.deuteranopia:
        return '~1% of males, ~0.01% of females';
      case ColorVisionType.tritanopia:
        return '~0.001% (very rare)';
      case ColorVisionType.achromatopsia:
        return '~0.003% (extremely rare)';
      case ColorVisionType.protanomaly:
        return '~1% of males, rare in females';
      case ColorVisionType.deuteranomaly:
        return '~5% of males, ~0.4% of females';
      case ColorVisionType.tritanomaly:
        return '~0.01% (rare)';
    }
  }
}
