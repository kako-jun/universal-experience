import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
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
  final ByteData? bd =
      await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  return bd!.buffer.asUint8List();
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

    expect(outPx.length, refPx.length,
        reason: 'GPU 出力と参照のバイト数が一致しない');

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
    expect(maxDiff, lessThanOrEqualTo(8),
        reason: '最大チャネル差が 8/255 を超えている');

    src.dispose();
    ref.dispose();
    out.dispose();
  });
}
