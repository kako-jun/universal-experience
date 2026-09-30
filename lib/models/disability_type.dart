// 色覚タイプの安定識別子 [ColorVisionType]。ファイル名は歴史的経緯で
// `disability_type.dart` のまま（障害種別の enum は使われなかったため撤去した）。
// import の一斉書き換えが必要になるので、改名は別の機会に行う。

/// Enumeration of color vision deficiency types
///
/// 規律2（定義と表示文言を混ぜない）に従い、この enum は安定識別子 [id] のみを
/// 持つ。表示名・説明文・有病率などのローカライズ文言は
/// `lib/l10n/l10n_extensions.dart`（`colorVisionTypeName` 等）が解決する。
enum ColorVisionType {
  /// No filter applied (normal vision)
  none('none'),

  /// Red-green color blindness (missing L-cones)
  protanopia('protanopia'),

  /// Red-green color blindness (missing M-cones)
  deuteranopia('deuteranopia'),

  /// Blue-yellow color blindness (missing S-cones)
  tritanopia('tritanopia'),

  /// Complete color blindness (no cone function)
  achromatopsia('achromatopsia'),

  /// Partial red-green deficiency (weak L-cones)
  protanomaly('protanomaly'),

  /// Partial red-green deficiency (weak M-cones)
  deuteranomaly('deuteranomaly'),

  /// Partial blue-yellow deficiency (weak S-cones)
  tritanomaly('tritanomaly');

  const ColorVisionType(this.id);

  final String id;
}
