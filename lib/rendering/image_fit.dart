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
