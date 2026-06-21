import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/rendering/shader_filter.dart';

/// 色覚（色変換系）フィルタの GPU golden テスト（#31）。
///
/// protanopia 1 種のみだった golden を、同カテゴリの代表
/// （deuteranopia / tritanopia / achromatopsia）へ拡張する。
///
/// ## 参照の正本
/// 参照 PNG（`test/golden/<filter>_ref.png`）と uniform 値
/// （`test/golden/color_uniforms.json`）は、いずれも **sensus_core**（プロジェクト
/// 宣言の正本）から rust の `golden_gen` が生成したもの。生成手順:
///   cd rust && cargo test -- --ignored gen_color_golden_refs
/// rust 側の `protanopia_ref_matches_sensus_core` テストが「既存 protanopia_ref.png ==
/// sensus_core::apply」をビット一致で守っており、この生成経路が CLI 参照と等価である
/// ことを保証する（= 捏造ではない）。
///
/// ## 方式
/// 入力 `protanopia_input.png` を共有し、各フィルタの `.frag` を FragmentProgram で
/// GPU 描画して参照 PNG とトレランス内一致を assert する。uniform は JSON の正本値を
/// そのまま流し込み、色行列・luma 重みを Dart に再実装しない（#34 のハードコード増殖を
/// 避ける）。空間・時間依存フィルタは GPU/CPU のカーネル差でピクセル等価にならないため
/// 対象外（色変換カテゴリ代表に限定）。

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

/// 各色変換フィルタの (shader アセット, 参照 PNG, JSON キー)。入力は protanopia と共有。
const Map<String, String> _shaderAsset = <String, String>{
  'deuteranopia': 'shaders/deuteranopia.frag',
  'tritanopia': 'shaders/tritanopia.frag',
  'achromatopsia': 'shaders/achromatopsia.frag',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late final Map<String, List<double>> uniformsByFilter;

  setUpAll(() {
    final raw = File('test/golden/color_uniforms.json').readAsStringSync();
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final filters = decoded['filters'] as Map<String, dynamic>;
    uniformsByFilter = filters.map(
      (key, value) => MapEntry(
        key,
        (value as List<dynamic>).map((e) => (e as num).toDouble()).toList(),
      ),
    );
  });

  for (final name in _shaderAsset.keys) {
    test('$name GPU 出力が sensus_core 参照とトレランス内で一致する', () async {
      final ui.Image src =
          await _decodeFile('test/golden/protanopia_input.png');
      final ui.Image ref = await _decodeFile('test/golden/${name}_ref.png');

      expect(src.width, ref.width);
      expect(src.height, ref.height);

      final List<double>? scalars = uniformsByFilter[name];
      expect(scalars, isNotNull,
          reason: 'color_uniforms.json に $name の uniform が無い（再生成漏れ）');

      final ui.Image out = await ShaderFilter.applyColorFilterGpu(
        src,
        _shaderAsset[name]!,
        scalars!,
      );

      final Uint8List outPx = await _rgba(out);
      final Uint8List refPx = await _rgba(ref);

      expect(outPx.length, refPx.length,
          reason: 'GPU 出力と参照のバイト数が一致しない');

      // RGB のみ比較（alpha は両者 255）。PSNR + 最大チャネル差で評価する。
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
      print('$name golden: PSNR=${psnr.toStringAsFixed(2)}dB '
          'meanAbs=${meanAbs.toStringAsFixed(3)} maxDiff=$maxDiff');

      // srgb<->linear の pow と GPU/CPU 丸めの差を許容（protanopia golden と同基準）。
      expect(psnr, greaterThanOrEqualTo(30.0),
          reason: 'PSNR が 30dB 未満: GPU 出力が sensus 参照から乖離している');
      expect(maxDiff, lessThanOrEqualTo(8),
          reason: '最大チャネル差が 8/255 を超えている');

      src.dispose();
      ref.dispose();
      out.dispose();
    });
  }
}
