import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/rendering/color_matrices.g.dart';
import 'package:universal_experience/rendering/shader_filter.dart';

/// protanopia GPU golden テスト。
///
/// 方法(b): 参照出力は sensus CLI が生成した PNG を正本とする
///   (`test/golden/protanopia_ref.png`、`sensus --filter protanopia -s 1.0`)。
///   入力 (`test/golden/protanopia_input.png`) を Flutter の FragmentProgram で
///   GPU 描画し、出力ピクセルが参照とトレランス内で一致することを assert する。
///
/// 入力/参照を PNG ファイルに固定した理由: rust bridge(FRB) のネイティブ統合
/// (.so ランタイムロード) が本フェーズ未配線のため、参照経路(a) は使えない。
/// sensus CLI 参照 PNG を commit することで再現性を担保する (#11 報告参照)。

/// テスト実行時の cwd はパッケージルート。golden PNG を直接ファイルから読む
/// (pubspec の assets に列挙せず、テスト専用の固定入力/参照として扱う)。
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

/// `shaders/protanopia.frag` と同じ計算（srgb→linear→3x3行列→clamp→linear→srgb）を
/// Dart で素朴に再現し、期待出力 RGBA を計算する。GPU シェーダのブラックボックス
/// 出力を独立に検算するための、テスト専用のリファレンス実装。
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


/// [a] と [b] の最大チャネル差（RGB のみ、alpha は除く）。
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

  test('protanopia GPU 出力が sensus CLI 参照とトレランス内で一致する', () async {
    final ui.Image src = await _decodeFile('test/golden/protanopia_input.png');
    final ui.Image ref = await _decodeFile('test/golden/protanopia_ref.png');

    expect(src.width, ref.width);
    expect(src.height, ref.height);

    final ui.Image out = await ShaderFilter.applyProtanopiaGpu(src, 1.0);

    final Uint8List outPx = await _rgba(out);
    final Uint8List refPx = await _rgba(ref);

    expect(outPx.length, refPx.length, reason: 'GPU 出力と参照のバイト数が一致しない');

    // チャネル差の集計 + PSNR。RGB のみ比較 (alpha は両者 255)。
    double sumSq = 0;
    int maxDiff = 0;
    double sumAbs = 0;
    int count = 0;
    for (int i = 0; i + 3 < outPx.length; i += 4) {
      for (int c = 0; c < 3; c++) {
        final int d = (outPx[i + c] - refPx[i + c]).abs();
        if (d > maxDiff) maxDiff = d;
        sumAbs += d;
        sumSq += d * d;
        count++;
      }
    }
    final double mse = sumSq / count;
    final double psnr = mse == 0
        ? double.infinity
        : 10 * (math.log(255 * 255 / mse) / math.ln10);
    final double meanAbs = sumAbs / count;

    // ignore: avoid_print
    print('protanopia golden: PSNR=${psnr.toStringAsFixed(2)}dB '
        'meanAbs=${meanAbs.toStringAsFixed(3)} maxDiff=$maxDiff');

    // srgb<->linear の pow と GPU/CPU の丸めで数値差が出るため許容する。
    expect(psnr, greaterThanOrEqualTo(30.0),
        reason: 'PSNR が 30dB 未満: GPU 出力が sensus 参照から乖離している');
    expect(maxDiff, lessThanOrEqualTo(8), reason: '最大チャネル差が 8/255 を超えている');

    src.dispose();
    ref.dispose();
    out.dispose();
  });

  test('strength=0.0 は原画とほぼ一致する（線形補間が effect なしを再現する）',
      () async {
    final ui.Image src = await _decodeFile('test/golden/protanopia_input.png');

    final ui.Image out = await ShaderFilter.applyProtanopiaGpu(src, 0.0);

    final Uint8List srcPx = await _rgba(src);
    final Uint8List outPx = await _rgba(out);

    final int maxDiff = _maxChannelDiff(srcPx, outPx);
    // srgb<->linear の往復による丸め誤差のみを許容する（補間が外れて
    // severity=1.0 行列が常時かかると、この差は数十〜100超まで跳ね上がる）。
    expect(maxDiff, lessThanOrEqualTo(2),
        reason: 'strength=0.0 は単位行列（=原画）になるはずだが、GPU 出力が入力と '
            '$maxDiff/255 も乖離している（線形補間が外れている可能性）');

    src.dispose();
    out.dispose();
  });

  test(
      'strength=0.5 は ShaderFilter.resolveSeverityMatrix の期待値と一致し、'
      '原画とも s=1.0 とも十分に異なる', () async {
    final ui.Image src = await _decodeFile('test/golden/protanopia_input.png');

    final ui.Image outHalf = await ShaderFilter.applyProtanopiaGpu(src, 0.5);
    final ui.Image outFull = await ShaderFilter.applyProtanopiaGpu(src, 1.0);

    final Uint8List srcPx = await _rgba(src);
    final Uint8List outHalfPx = await _rgba(outHalf);
    final Uint8List outFullPx = await _rgba(outFull);

    // ShaderFilter が GPU に渡すのと同じ行列（sensus と同じ区分線形補間。
    // 「行列の正しさ」自体は test/color_matrix_interpolation_test.dart が
    // sensus CPU fixture と突き合わせて別途検証済み）。本テストの目的は
    // 「GPU シェーダの色行列適用そのものが CPU 計算と一致するか」の確認。
    final List<double> expectedMatrix = ShaderFilter.resolveSeverityMatrix(
      protanopiaColorMatrixGrid,
      0.5,
    );
    final Uint8List expectedPx = _applyColorMatrixSrgb(srcPx, expectedMatrix);

    final int diffFromExpected = _maxChannelDiff(outHalfPx, expectedPx);
    expect(diffFromExpected, lessThanOrEqualTo(2),
        reason: 'GPU 出力(s=0.5)が CPU 側で計算した期待値と '
            '$diffFromExpected/255 乖離している');

    // 原画とも s=1.0 とも十分に異なること（= 補間が実際に効いていること）の対照。
    // 中間強度の効果が識別できる程度に離れているかを、sensus golden の
    // トレランス（maxDiff<=8）よりゆるい閾値で確認する。
    final int diffFromInput = _maxChannelDiff(outHalfPx, srcPx);
    final int diffFromFull = _maxChannelDiff(outHalfPx, outFullPx);
    expect(diffFromInput, greaterThan(4),
        reason: 's=0.5 の出力が原画と区別できないほど近い（補間が効いていない）');
    expect(diffFromFull, greaterThan(4),
        reason: 's=0.5 の出力が s=1.0 と区別できないほど近い（補間が外れて常時'
            'severity=1.0 行列がかかっている可能性）');

    src.dispose();
    outHalf.dispose();
    outFull.dispose();
  });
}
