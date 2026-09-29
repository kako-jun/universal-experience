/// What the before/after preview's "before" pane should render (#78).
///
/// Replaces the pre-#78 fixed programmatic hue-gradient sample
/// (`BeforeAfterView.generateSampleImage`, kept only as a legacy fallback for
/// callers that don't pass a [PreviewImageSource] — see that file's module
/// doc) with a real choice: one of the built-in sample scenes
/// (`lib/models/sample_catalog.dart`), or an image the user loaded
/// (`lib/services/image_source_state.dart`).
///
/// This is a plain value type (no `dart:ui` image data for the sample case,
/// and only a *reference* to the caller-owned decoded image for the user
/// case) so `==`/`hashCode` can drive `BeforeAfterView`'s
/// `didUpdateWidget`/generation-reuse checks (#58/#85) without needing to
/// compare pixel data.
library;

import 'dart:ui' as ui;

sealed class PreviewImageSource {
  const PreviewImageSource();
}

/// One of the built-in sample scenes (`lib/models/sample_catalog.dart`),
/// identified by [sampleId] (e.g. `'route_map'`).
final class SamplePreviewImageSource extends PreviewImageSource {
  const SamplePreviewImageSource(this.sampleId);

  final String sampleId;

  @override
  bool operator ==(Object other) =>
      other is SamplePreviewImageSource && other.sampleId == sampleId;

  @override
  int get hashCode => Object.hash(SamplePreviewImageSource, sampleId);

  @override
  String toString() => 'SamplePreviewImageSource($sampleId)';
}

/// An image the user loaded (file picker / drag & drop, #78). [image] is
/// owned by the caller (`ImageSourceState`) — `BeforeAfterView` only reads
/// pixels from it (to fit it into the canonical square, `lib/rendering/
/// image_fit.dart`) and never disposes it.
///
/// [generation] is a monotonic counter bumped by `ImageSourceState` every
/// time a *new* user image is loaded (even if the previous one is disposed
/// and a visually-identical new [ui.Image] object happens to be loaded
/// again). Equality/hashCode key off [generation] alone — [ui.Image] has no
/// meaningful value equality — so `BeforeAfterView`'s reuse/invalidation
/// checks (#58/#85: `didUpdateWidget`, `_rebuild`'s `reuseBefore`) correctly
/// treat "the same load" as unchanged and "a new load" (even of an
/// unchanged-looking file) as a change worth re-fitting.
final class UserPreviewImageSource extends PreviewImageSource {
  const UserPreviewImageSource(this.image, this.generation);

  final ui.Image image;
  final int generation;

  @override
  bool operator ==(Object other) =>
      other is UserPreviewImageSource && other.generation == generation;

  @override
  int get hashCode => Object.hash(UserPreviewImageSource, generation);

  @override
  String toString() => 'UserPreviewImageSource(generation: $generation)';
}
