// lib/rendering/image_fit.dart（#78）のテスト。
//
// fitImageToSquare のレターボックス（縦横比を保って中央配置、余白は
// kImageFitLetterboxColor）契約と、source を dispose しない契約を検証する。

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/rendering/image_fit.dart';

/// [width]×[height] の単色画像を作る。
Future<ui.Image> _solidImage(int width, int height, ui.Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = color,
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

/// [image] の [x],[y] にある画素の ARGB を返す（rawRgba、premultiplied 済み
/// なので不透明画素なら straight と一致する — このテストは常に alpha=255）。
Future<ui.Color> _pixelAt(ui.Image image, int x, int y) async {
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = byteData!.buffer.asUint8List();
  final offset = (y * image.width + x) * 4;
  return ui.Color.fromARGB(
    bytes[offset + 3],
    bytes[offset],
    bytes[offset + 1],
    bytes[offset + 2],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('fitImageToSquare', () {
    test('正方形の source はそのまま size×size に収まり、余白は出ない', () async {
      const red = ui.Color(0xFFE53935);
      final source = await _solidImage(200, 200, red);
      addTearDown(source.dispose);

      final fitted = await fitImageToSquare(source, 64);
      addTearDown(fitted.dispose);

      expect(fitted.width, 64);
      expect(fitted.height, 64);
      expect(await _pixelAt(fitted, 0, 0), red);
      expect(await _pixelAt(fitted, 63, 63), red);
      expect(await _pixelAt(fitted, 32, 32), red);
    });

    test('横長の source は上下にレターボックスの余白ができる', () async {
      const blue = ui.Color(0xFF1E88E5);
      // 200x100（2:1）を 64x64 に収めると、上下 16px ずつ余白ができる。
      final source = await _solidImage(200, 100, blue);
      addTearDown(source.dispose);

      final fitted = await fitImageToSquare(source, 64);
      addTearDown(fitted.dispose);

      expect(fitted.width, 64);
      expect(fitted.height, 64);
      // 中央の帯は元画像の色。
      expect(await _pixelAt(fitted, 32, 32), blue);
      // 上端・下端は余白（レターボックス色）。
      expect(await _pixelAt(fitted, 32, 0), kImageFitLetterboxColor);
      expect(await _pixelAt(fitted, 32, 63), kImageFitLetterboxColor);
    });

    test('縦長の source は左右にレターボックスの余白ができる', () async {
      const green = ui.Color(0xFF2E7D32);
      final source = await _solidImage(100, 200, green);
      addTearDown(source.dispose);

      final fitted = await fitImageToSquare(source, 64);
      addTearDown(fitted.dispose);

      expect(await _pixelAt(fitted, 32, 32), green);
      expect(await _pixelAt(fitted, 0, 32), kImageFitLetterboxColor);
      expect(await _pixelAt(fitted, 63, 32), kImageFitLetterboxColor);
    });

    test('source を dispose しない（呼び出し元が所有権を保持する契約）', () async {
      final source = await _solidImage(50, 50, const ui.Color(0xFFFFFFFF));
      addTearDown(source.dispose);

      final fitted = await fitImageToSquare(source, 32);
      fitted.dispose();

      expect(source.debugDisposed, isFalse);
    });
  });

  group('decodeImageBytes', () {
    test('往復デコードした画像は元と同じサイズになる', () async {
      final source = await _solidImage(40, 30, const ui.Color(0xFFFFD835));
      addTearDown(source.dispose);
      final pngData = await source.toByteData(format: ui.ImageByteFormat.png);
      final Uint8List pngBytes = pngData!.buffer.asUint8List();

      final decoded = await decodeImageBytes(pngBytes);
      addTearDown(decoded.dispose);

      expect(decoded.width, 40);
      expect(decoded.height, 30);
    });

    test('不正なバイト列は例外を投げる（#78: 呼び出し側でエラー処理する契約）', () async {
      expect(
        () => decodeImageBytes(Uint8List.fromList([1, 2, 3, 4, 5])),
        throwsA(anything),
      );
    });
  });

  group('decodeUserImageBytes', () {
    test('長辺が上限を超える画像は、縦横比を保ったままデコード時にダウンスケールされる', () async {
      // 3000×1000（長辺 3000 > kUserImageMaxDimension=2048）。
      // scale = 2048/3000 = 0.68266...、高さ = round(1000 * scale) = 683。
      final source = await _solidImage(3000, 1000, const ui.Color(0xFFE53935));
      addTearDown(source.dispose);
      final pngData = await source.toByteData(format: ui.ImageByteFormat.png);
      final Uint8List pngBytes = pngData!.buffer.asUint8List();

      final decoded = await decodeUserImageBytes(pngBytes);
      addTearDown(decoded.dispose);

      expect(decoded.width, 2048);
      expect(decoded.height, 683);
    });

    test('長辺が上限以下の画像はそのままのサイズでデコードされる', () async {
      final source = await _solidImage(800, 600, const ui.Color(0xFF1E88E5));
      addTearDown(source.dispose);
      final pngData = await source.toByteData(format: ui.ImageByteFormat.png);
      final Uint8List pngBytes = pngData!.buffer.asUint8List();

      final decoded = await decodeUserImageBytes(pngBytes);
      addTearDown(decoded.dispose);

      expect(decoded.width, 800);
      expect(decoded.height, 600);
    });
  });
}
