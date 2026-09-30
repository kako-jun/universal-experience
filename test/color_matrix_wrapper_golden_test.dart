import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/rendering/color_matrices.g.dart';
import 'package:universal_experience/rendering/shader_filter.dart';

/// `ShaderFilter.applyDeuteranopiaGpu` / `applyTritanopiaGpu` /
/// `applyAchromatopsiaGpu` の GPU golden テスト。
///
/// `test/vision_filter_golden_test.dart` は同じ参照 PNG を使うが、
/// `ShaderFilter.applyColorFilterGpu` に JSON 由来の生の uniform を直接流し込む
/// 経路（`color_matrices.g.dart` のグリッド + `resolveSeverityMatrix` を経由しない）
/// のテストで、`before_after_view.dart` が実際に呼ぶ高レベル API
/// （`applyDeuteranopiaGpu` 等）そのものは golden で検証されていなかった。
/// 本ファイルはそのギャップを塞ぐ。
///
/// 参照 PNG（`test/golden/{deuteranopia,tritanopia,achromatopsia}_ref.png`）は
/// `rust/src/golden_gen.rs`（sensus_core 正本の CPU 経路）由来（`protanopia_golden_test.dart`
/// / `vision_filter_golden_test.dart` と同じ）。

Future<ui.Image> _decodeFile(String path) async {
  final Uint8List bytes = await File(path).readAsBytes();
  final ui.Codec codec = await ui.instantiateImageCodec(bytes);
  final ui.FrameInfo frame = await codec.getNextFrame();
  return frame.image;
}

Future<Uint8List> _rgba(ui.Image img) async {
  final ByteData? bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  return bd!.buffer.asUint8List();
}

double _srgbToLinear(double c) {
  return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double _linearToSrgb(double c) {
  return c <= 0.0031308
      ? c * 12.92
      : 1.055 * math.pow(c, 1.0 / 2.4).toDouble() - 0.055;
}

int _clampByte(double v) => (v * 255.0).round().clamp(0, 255);

/// `shaders/<name>.frag` と同じ計算（srgb→linear→3x3行列→clamp→linear→srgb）を
/// Dart で素朴に再現し、期待出力 RGBA を計算する。`protanopia_golden_test.dart` の
/// 同名ヘルパと同じ、テスト専用の独立リファレンス実装。
Uint8List _applyColorMatrixSrgb(Uint8List rgba, List<double> matrixRowMajor) {
  final out = Uint8List(rgba.length);
  for (int i = 0; i + 3 < rgba.length; i += 4) {
    final double r = _srgbToLinear(rgba[i] / 255.0);
    final double g = _srgbToLinear(rgba[i + 1] / 255.0);
    final double b = _srgbToLinear(rgba[i + 2] / 255.0);

    final double sr = matrixRowMajor[0] * r +
        matrixRowMajor[1] * g +
        matrixRowMajor[2] * b;
    final double sg = matrixRowMajor[3] * r +
        matrixRowMajor[4] * g +
        matrixRowMajor[5] * b;
    final double sb = matrixRowMajor[6] * r +
        matrixRowMajor[7] * g +
        matrixRowMajor[8] * b;

    out[i] = _clampByte(_linearToSrgb(sr.clamp(0.0, 1.0)));
    out[i + 1] = _clampByte(_linearToSrgb(sg.clamp(0.0, 1.0)));
    out[i + 2] = _clampByte(_linearToSrgb(sb.clamp(0.0, 1.0)));
    out[i + 3] = rgba[i + 3];
  }
  return out;
}

int _maxChannelDiff(Uint8List a, Uint8List b) {
  int maxDiff = 0;
  for (int i = 0; i + 3 < a.length; i += 4) {
    for (int c = 0; c < 3; c++) {
      final int d = (a[i + c] - b[i + c]).abs();
      if (d > maxDiff) maxDiff = d;
    }
  }
  return maxDiff;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('applyDeuteranopiaGpu(1.0) が deuteranopia_ref.png と一致する（maxDiff<=2）',
      () async {
    final ui.Image src = await _decodeFile('test/golden/protanopia_input.png');
    final ui.Image ref = await _decodeFile('test/golden/deuteranopia_ref.png');

    final ui.Image out = await ShaderFilter.applyDeuteranopiaGpu(src, 1.0);
    final int maxDiff = _maxChannelDiff(await _rgba(out), await _rgba(ref));

    expect(maxDiff, lessThanOrEqualTo(2),
        reason: 'applyDeuteranopiaGpu(1.0) が参照から $maxDiff/255 乖離している');

    src.dispose();
    ref.dispose();
    out.dispose();
  });

  test('applyTritanopiaGpu(1.0) が tritanopia_ref.png と一致する（maxDiff<=2）',
      () async {
    final ui.Image src = await _decodeFile('test/golden/protanopia_input.png');
    final ui.Image ref = await _decodeFile('test/golden/tritanopia_ref.png');

    final ui.Image out = await ShaderFilter.applyTritanopiaGpu(src, 1.0);
    final int maxDiff = _maxChannelDiff(await _rgba(out), await _rgba(ref));

    expect(maxDiff, lessThanOrEqualTo(2),
        reason: 'applyTritanopiaGpu(1.0) が参照から $maxDiff/255 乖離している');

    src.dispose();
    ref.dispose();
    out.dispose();
  });

  test(
      'applyAchromatopsiaGpu(1.0) が achromatopsia_ref.png と一致する（maxDiff<=2）',
      () async {
    final ui.Image src = await _decodeFile('test/golden/protanopia_input.png');
    final ui.Image ref = await _decodeFile('test/golden/achromatopsia_ref.png');

    final ui.Image out = await ShaderFilter.applyAchromatopsiaGpu(src, 1.0);
    final int maxDiff = _maxChannelDiff(await _rgba(out), await _rgba(ref));

    expect(maxDiff, lessThanOrEqualTo(2),
        reason: 'applyAchromatopsiaGpu(1.0) が参照から $maxDiff/255 乖離している');

    src.dispose();
    ref.dispose();
    out.dispose();
  });

  test(
      'applyDeuteranopiaGpu(0.5) は resolveSeverityMatrix(0.5) の期待値と一致する'
      '（maxDiff<=2、protanopia_golden_test と同じ形）', () async {
    final ui.Image src = await _decodeFile('test/golden/protanopia_input.png');

    final ui.Image out = await ShaderFilter.applyDeuteranopiaGpu(src, 0.5);
    final Uint8List srcPx = await _rgba(src);
    final Uint8List outPx = await _rgba(out);

    final List<double> expectedMatrix = ShaderFilter.resolveSeverityMatrix(
      deuteranopiaColorMatrixGrid,
      0.5,
    );
    final Uint8List expectedPx = _applyColorMatrixSrgb(srcPx, expectedMatrix);

    final int maxDiff = _maxChannelDiff(outPx, expectedPx);
    expect(maxDiff, lessThanOrEqualTo(2),
        reason: 'applyDeuteranopiaGpu(0.5) が CPU 側の期待値から $maxDiff/255 '
            '乖離している');

    src.dispose();
    out.dispose();
  });
}
