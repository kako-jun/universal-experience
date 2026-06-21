import 'dart:async';
import 'dart:ui' as ui;

/// FragmentProgram (Impeller GPU シェーダ) で sensus 由来の視覚フィルタを
/// `ui.Image` に適用するヘルパ。
///
/// MVP では protanopia 1 枚のみ。配線は #11 のゴール:
///   FragmentProgram.fromAsset → fragmentShader() → setFloat で uniform を積む
///   → setImageSampler(0, src) → PictureRecorder.drawRect(Paint..shader) → toImage。
///
/// uniform 順序は shaders/protanopia.frag の宣言順に厳密一致させる:
///   [uStrength, uM0..uM8, uSize.x, uSize.y]  (float 12 本) + setImageSampler(0, src)。
class ShaderFilter {
  ShaderFilter._();

  static const String _protanopiaAsset = 'shaders/protanopia.frag';

  /// protanopia の Machado 2009 severity=1.0 行列 (行優先 3x3)。
  ///
  /// 値は sensus_core `PROTANOPIA_MATRIX` / 元 .frag コメントと同値。
  /// MVP ではここにハードコードするが、将来は rust bridge の
  /// `visionUniforms(VisionFilter.protanopia, ...)` から取得して二重実装を避ける。
  // TODO(#11 後続): bridge の visionUniforms から取得し、本ハードコードを撤去する。
  static const List<double> _protanopiaMatrix = <double>[
    0.152286, 1.052583, -0.204868, //
    0.114503, 0.786281, 0.099216, //
    -0.003882, -0.048116, 1.051998, //
  ];

  // 解決済み値ではなく Future をキャッシュする。並行呼び出し (スライダ連打で
  // applyProtanopiaGpu が並列発火) でも fromAsset は 1 回だけになる。
  static Future<ui.FragmentProgram>? _protanopiaProgram;

  /// protanopia の FragmentProgram をロード (キャッシュ)。
  static Future<ui.FragmentProgram> _loadProtanopia() {
    return _protanopiaProgram ??= ui.FragmentProgram.fromAsset(_protanopiaAsset);
  }

  /// protanopia フィルタを GPU で [src] に適用し、新しい [ui.Image] を返す。
  ///
  /// [strength] は 0.0..=1.0 (0.0=原画, 1.0=完全適用)。sensus の `normalize_strength`
  /// と同じく、範囲外は clamp し NaN は 0.0 (原画) として扱う。
  static Future<ui.Image> applyProtanopiaGpu(
    ui.Image src,
    double strength,
  ) async {
    final ui.FragmentProgram program = await _loadProtanopia();
    final ui.FragmentShader shader = program.fragmentShader();

    // sensus の normalize_strength 相当 (NaN→0, 0..=1 clamp)。非有限 uniform が
    // GPU に流れて画面が壊れるのを防ぐ。
    final double s = strength.isNaN ? 0.0 : strength.clamp(0.0, 1.0);

    final double w = src.width.toDouble();
    final double h = src.height.toDouble();

    // shaders/protanopia.frag の宣言順に setFloat する:
    //   0:uStrength, 1..9:uM0..uM8, 10:uSize.x, 11:uSize.y
    shader.setFloat(0, s);
    for (int i = 0; i < 9; i++) {
      shader.setFloat(1 + i, _protanopiaMatrix[i]);
    }
    shader.setFloat(10, w);
    shader.setFloat(11, h);
    shader.setImageSampler(0, src);

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    final ui.Paint paint = ui.Paint()..shader = shader;
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, w, h),
      paint,
    );
    final ui.Picture picture = recorder.endRecording();
    try {
      final ui.Image out = await picture.toImage(src.width, src.height);
      return out;
    } finally {
      picture.dispose();
      shader.dispose();
    }
  }

  // ロード済み FragmentProgram を asset パスでキャッシュ（並行ロードの重複を避ける）。
  static final Map<String, Future<ui.FragmentProgram>> _programCache =
      <String, Future<ui.FragmentProgram>>{};

  static Future<ui.FragmentProgram> _loadProgram(String asset) {
    return _programCache[asset] ??= ui.FragmentProgram.fromAsset(asset);
  }

  /// 色変換系フィルタ（色行列 / luma 重み）を GPU で [src] に適用する汎用経路。
  ///
  /// protanopia/deuteranopia/tritanopia/achromatopsia のように **解像度を最後の
  /// 2 uniform に持つ** `.frag`（`[..scalars.., uResolution_x, uResolution_y]`）を対象に、
  /// [scalarUniforms]（= 正本 `vision_uniforms()` が返す末尾の解像度を含まない flat 配列、
  /// 例: `[uStrength, uMatrix0..8]` や `[uStrength, uRWeight, uGWeight, uBWeight]`）を
  /// `setFloat(0..)` で積み、続けて `setFloat(n, w)` / `setFloat(n+1, h)` を積んで
  /// `setImageSampler(0, src)` する。
  ///
  /// 色行列・luma 重みを Dart 側に**書かない**こと（正本は sensus_core）。本メソッドは
  /// golden テストが正本由来の uniforms（`test/golden/color_uniforms.json`）を流し込む
  /// ためのもので、ハードコードを増やさない。空間・時間依存フィルタ（blur/glaucoma/
  /// vertigo 等）はこのレイアウト前提（末尾が解像度）と適用モデルが異なるため対象外。
  static Future<ui.Image> applyColorFilterGpu(
    ui.Image src,
    String shaderAsset,
    List<double> scalarUniforms,
  ) async {
    final ui.FragmentProgram program = await _loadProgram(shaderAsset);
    final ui.FragmentShader shader = program.fragmentShader();

    final double w = src.width.toDouble();
    final double h = src.height.toDouble();

    for (int i = 0; i < scalarUniforms.length; i++) {
      final double v = scalarUniforms[i];
      // 非有限 uniform が GPU に流れて描画が壊れるのを防ぐ（NaN/Inf→0.0）。
      shader.setFloat(i, v.isFinite ? v : 0.0);
    }
    shader.setFloat(scalarUniforms.length, w);
    shader.setFloat(scalarUniforms.length + 1, h);
    shader.setImageSampler(0, src);

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    final ui.Paint paint = ui.Paint()..shader = shader;
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, w, h), paint);
    final ui.Picture picture = recorder.endRecording();
    try {
      return await picture.toImage(src.width, src.height);
    } finally {
      picture.dispose();
      shader.dispose();
    }
  }
}
