import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/rendering/cpu_vision_renderer.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';

/// CpuVisionRenderer の往復変換（`ui.Image` ⇄ raw RGBA8）の忠実性テスト（#85）。
///
/// `CpuVisionRenderer.apply()` 自体は実ブリッジ（`applyVisionCpuRgba8`）を必要と
/// するため、native lib をロードしない `flutter test` では呼べない（実描画の
/// 検証は `integration_test/cpu_preview_all_filters_test.dart` が担う）。
/// 本ファイルはブリッジを挟まない往復変換部分（`imageToRgba8`/`rgba8ToImage`）
/// のみを検証する。
///
/// 数値一致の調査（#85 の依頼事項）: `ui.Image.toByteData(format: rawRgba)` /
/// `ui.decodeImageFromPixels(..., PixelFormat.rgba8888, ...)` はいずれも
/// straight（非 premultiplied）RGBA8 のメモリ表現をそのまま読み書きするだけで、
/// sRGB⇄linear のガンマ変換や再圧縮を一切行わない。したがって
/// `CpuVisionRenderer` がこの往復で持ち込む誤差は理論上ゼロで、以下のテストは
/// それを実測で固定する。GPU（`ShaderFilter`）側は `srgbToLinear`/`linearToSrgb`
/// を通すため sensus 正本と GPU/CPU 丸め差（`test/vision_filter_golden_test.dart`
/// が maxDiff≤8 で許容）が生じるが、これは GPU シェーダ内部の話であり、本ファイル
/// が検証する Dart 側の往復変換とは別の層の差である。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ui.Image> decodeFile(String path) async {
    final Uint8List bytes = await File(path).readAsBytes();
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    return frame.image;
  }

  group('imageToRgba8 / rgba8ToImage の往復', () {
    test('既存 golden 参照 PNG を往復させてもバイト単位で一致する', () async {
      final ui.Image original =
          await decodeFile('test/golden/protanopia_ref.png');
      addTearDown(original.dispose);

      final Uint8List originalRgba8 =
          await CpuVisionRenderer.imageToRgba8(original);

      final ui.Image roundTripped = await CpuVisionRenderer.rgba8ToImage(
        originalRgba8,
        original.width,
        original.height,
      );
      addTearDown(roundTripped.dispose);

      expect(roundTripped.width, original.width);
      expect(roundTripped.height, original.height);

      final Uint8List roundTrippedRgba8 =
          await CpuVisionRenderer.imageToRgba8(roundTripped);

      expect(
        roundTrippedRgba8,
        equals(originalRgba8),
        reason: 'straight RGBA8 の往復は sRGB/linear 変換や再圧縮を含まないため、'
            'バイト単位で完全一致するはず（#85 の数値一致調査）',
      );
    });

    test('raw RGBA8 のバイト数は width*height*4 と一致する', () async {
      final ui.Image image =
          await decodeFile('test/golden/protanopia_input.png');
      addTearDown(image.dispose);

      final Uint8List rgba8 = await CpuVisionRenderer.imageToRgba8(image);
      expect(rgba8.length, image.width * image.height * 4);
    });
  });

  group('applier seam', () {
    tearDown(() {
      CpuVisionRenderer.applier = CpuVisionRenderer.apply;
    });

    test('既定値は CpuVisionRenderer.apply 自身', () {
      expect(CpuVisionRenderer.applier, same(CpuVisionRenderer.apply));
    });

    test('フェイクに差し替えて元へ戻せる（#58 と同じ @visibleForTesting seam パターン）', () async {
      var called = false;
      CpuVisionRenderer.applier = (source, filter, strength) async {
        called = true;
        return source;
      };
      expect(CpuVisionRenderer.applier, isNot(same(CpuVisionRenderer.apply)));

      final dummy = await decodeFile('test/golden/protanopia_input.png');
      addTearDown(dummy.dispose);
      // フェイクは source をそのまま返すだけなので、filter/strength の実値は
      // この呼び出し経路の確認には関係ない（任意の定数でよい）。
      await CpuVisionRenderer.applier(
        dummy,
        const VisionFilter.protanopia(),
        1.0,
      );
      expect(called, isTrue);
    });
  });
}
