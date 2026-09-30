import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Fits [source] (any aspect ratio) into a `size`×`size` square, preserving
/// aspect ratio via **letterboxing** (#78) — the whole source image is drawn
/// scaled-to-fit and centred, with neutral bars filling any leftover space,
/// as opposed to a centre-crop that would discard part of the source.
///
/// Letterbox was chosen over crop because a symptom's effect can appear
/// anywhere in a user-supplied photo — cropping risks silently discarding
/// exactly the part the person picked the photo to test (documented in
/// docs/ARCHITECTURE.md). The bar colour ([kImageFitLetterboxColor]) is a
/// fixed neutral mid-gray rather than pure white/black, so it doesn't itself
/// read as a bright-glare or a swallowed-dark cue under filters that are
/// sensitive to those extremes (photophobia/starbursts, night_blindness).
///
/// Returns a **new** [ui.Image] the caller owns and must dispose — this
/// function never disposes [source] (the caller decides that: a transient
/// decode of a sample asset should be disposed right after fitting, while a
/// user-loaded image is owned by `ImageSourceState` and must outlive this
/// call, #78/#58/#85 dispose discipline).
Future<ui.Image> fitImageToSquare(ui.Image source, int size) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final fSize = size.toDouble();

  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, fSize, fSize),
    ui.Paint()..color = kImageFitLetterboxColor,
  );

  final srcW = source.width.toDouble();
  final srcH = source.height.toDouble();
  if (srcW > 0 && srcH > 0) {
    final scale = math.min(fSize / srcW, fSize / srcH);
    final drawW = srcW * scale;
    final drawH = srcH * scale;
    final dx = (fSize - drawW) / 2;
    final dy = (fSize - drawH) / 2;
    canvas.drawImageRect(
      source,
      ui.Rect.fromLTWH(0, 0, srcW, srcH),
      ui.Rect.fromLTWH(dx, dy, drawW, drawH),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
  }

  final picture = recorder.endRecording();
  try {
    return await picture.toImage(size, size);
  } finally {
    picture.dispose();
  }
}

/// Letterbox bar colour for [fitImageToSquare] (#78). Neutral mid-gray —
/// see that function's doc for why not pure white/black.
///
/// 色の例外（DESIGN.md）: 画像内容の一部（フィルタに通る画素）であり、
/// アプリのテーマ（ライト/ダーク）で変わってはならないためロールにしない。
const ui.Color kImageFitLetterboxColor = ui.Color(0xFF808080);

/// Decodes arbitrary encoded image bytes (PNG/JPEG/etc., whatever
/// `dart:ui`'s codec supports) into a [ui.Image]. Shared by
/// `BeforeAfterView.loadPreviewSourceImage` (sample assets, #78) and the
/// user image picker/drop handlers (`lib/ui/widgets/image_source_picker.dart`)
/// so the decode step has one implementation. The caller owns and must
/// dispose the returned image.
Future<ui.Image> decodeImageBytes(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    return frame.image;
  } finally {
    codec.dispose();
  }
}

/// Maximum long-edge dimension [decodeUserImageBytes] decodes a user image
/// to (#78). A modern phone photo can easily be 4000px+ on the
/// long edge; decoding (and holding in memory) at full intrinsic resolution
/// when the canonical preview size is only [1024]（`BeforeAfterView.
/// canonicalSampleSize`) wastes memory for no visual benefit —
/// [fitImageToSquare] would immediately downscale it anyway. 2048 leaves
/// headroom above the canonical size while still bounding memory use.
const int kUserImageMaxDimension = 2048;

/// ユーザー画像として受け付けるファイルの拡張子（小文字）。ファイル選択
/// （`image_source_picker.dart`）とクリップボードのファイル判定
/// （`clipboard_image_reader.dart`、#97）が共有する。
const List<String> kUserImageFileExtensions = [
  'png',
  'jpg',
  'jpeg',
  'gif',
  'bmp',
  'webp',
];

/// Decodes [bytes] into a [ui.Image] the same way [decodeImageBytes] does,
/// but downscales **during** decode so neither dimension exceeds
/// [kUserImageMaxDimension] (#78), preserving aspect ratio.
/// Unlike [decodeImageBytes] (used for the already-1024px sample assets,
/// which never need downscaling), this reads the image's intrinsic size
/// cheaply via [ui.ImageDescriptor] first (`ui.instantiateImageCodecWithSize`)
/// so the decoder itself only ever materialises the bounded size, rather
/// than decoding at full resolution and downscaling afterward.
///
/// Used only for user-loaded images
/// (`lib/ui/widgets/image_source_picker.dart`) — sample assets go through
/// [decodeImageBytes] instead. The caller owns and must dispose the
/// returned image.
Future<ui.Image> decodeUserImageBytes(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  // instantiateImageCodecWithSize disposes `buffer` itself once it's read
  // the (cheap, header-only) intrinsic size — the caller must not also
  // dispose it.
  final codec = await ui.instantiateImageCodecWithSize(
    buffer,
    getTargetSize: (intrinsicWidth, intrinsicHeight) {
      final longEdge = math.max(intrinsicWidth, intrinsicHeight);
      if (longEdge <= kUserImageMaxDimension) {
        return ui.TargetImageSize(
            width: intrinsicWidth, height: intrinsicHeight);
      }
      final scale = kUserImageMaxDimension / longEdge;
      return ui.TargetImageSize(
        width: (intrinsicWidth * scale).round(),
        height: (intrinsicHeight * scale).round(),
      );
    },
  );
  try {
    final frame = await codec.getNextFrame();
    return frame.image;
  } finally {
    codec.dispose();
  }
}
