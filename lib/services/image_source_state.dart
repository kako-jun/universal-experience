import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../models/preview_image_source.dart';
import '../models/sample_catalog.dart';

/// Which image the before/after preview's "before" pane renders, and how it
/// got there (#78). **The single source of truth** for this, mirroring how
/// `VisionFilterState` (#60) is the single source of truth for the filter
/// selection — `home_screen.dart` reads only [current] to build
/// `BeforeAfterView.imageSource`.
///
/// ## Two independent axes
///
/// - **sample vs. user image** ([isUsingUserImage]): whether the preview
///   shows one of the built-in scenes (`lib/models/sample_catalog.dart`) or
///   an image the user loaded ([setUserImage]).
/// - **auto-follow vs. manual pick** ([isFollowingRecommended], sample mode
///   only): whether the shown sample tracks the current filter's
///   recommendation ([followRecommendedSample], called from `home_screen.dart`
///   whenever `VisionFilterState`'s selection changes) or was pinned by the
///   user explicitly picking a different sample ([selectSample]).
///
/// Per the Issue: picking a filter switches to that filter's recommended
/// sample, **except** while a user image is active (switching filters never
/// interrupts looking at your own photo) — [followRecommendedSample] is a
/// no-op whenever [isUsingUserImage] is true. Manually picking a sample stops
/// auto-follow until [resetToRecommended] is called (the "back to
/// recommended" affordance the Issue calls for).
///
/// ## User image ownership / dispose (#58/#85 discipline)
///
/// [setUserImage] takes ownership of the decoded [ui.Image] it's given:
/// replacing it (a new pick/drop) or [clearUserImage] disposes the previous
/// one, and so does [dispose]. `BeforeAfterView` only *reads* pixels from it
/// (via `UserPreviewImageSource.image`, fit into the canonical square by
/// `lib/rendering/image_fit.dart`) and never disposes it — see
/// `PreviewImageSource`'s doc for the full ownership contract. The image is
/// never written to disk and never leaves the process (#78: no persistence,
/// nothing sent off-device) — only this in-memory decoded copy is kept, and
/// it's gone the moment it's replaced or the app closes.
class ImageSourceState extends ChangeNotifier {
  ImageSourceState({String initialSampleId = kDefaultSampleId})
      : _sampleId = initialSampleId;

  String _sampleId;
  bool _autoFollowRecommended = true;
  bool _isUsingUserImage = false;

  ui.Image? _userImage;
  int _userImageGeneration = 0;

  /// The current sample id — kept even while [isUsingUserImage] is true, so
  /// switching back to sample mode ([resetToRecommended]) doesn't lose the
  /// last sample shown.
  String get selectedSampleId => _sampleId;

  /// Whether a user image is the active preview source.
  bool get isUsingUserImage => _isUsingUserImage;

  /// Whether a user image has been loaded at all (even if [isUsingUserImage]
  /// is currently false because the user switched back to a sample via
  /// [resetToRecommended]) — lets the UI offer "view your image again"
  /// without re-picking.
  bool get hasUserImage => _userImage != null;

  /// Whether the shown sample auto-follows the filter's recommendation.
  /// Always false while [isUsingUserImage] is true (there's no "sample"
  /// being shown to follow anything).
  bool get isFollowingRecommended => _autoFollowRecommended && !_isUsingUserImage;

  /// The [PreviewImageSource] `home_screen.dart` passes to
  /// `BeforeAfterView.imageSource`.
  PreviewImageSource get current {
    final userImage = _userImage;
    if (_isUsingUserImage && userImage != null) {
      return UserPreviewImageSource(userImage, _userImageGeneration);
    }
    return SamplePreviewImageSource(_sampleId);
  }

  /// Manually picks a sample (#78: "ユーザーが手でサンプルを選んだ場合").
  /// Switches away from a user image if one was active, and stops
  /// auto-follow until [resetToRecommended] is called.
  void selectSample(String sampleId) {
    _isUsingUserImage = false;
    _sampleId = sampleId;
    _autoFollowRecommended = false;
    notifyListeners();
  }

  /// Called whenever the selected filter changes (`home_screen.dart`,
  /// mirroring the `_persistFilterState` listener pattern). No-op unless
  /// both [isUsingUserImage] is false and auto-follow is still enabled — a
  /// user image or a manually-pinned sample must never be interrupted by a
  /// filter change.
  void followRecommendedSample(String sampleId) {
    if (_isUsingUserImage || !_autoFollowRecommended) return;
    if (_sampleId == sampleId) return;
    _sampleId = sampleId;
    notifyListeners();
  }

  /// "おすすめに戻す" (#78): switches back to sample mode (without discarding
  /// a loaded user image — [hasUserImage] stays true, so the user can flip
  /// back via [useLoadedUserImage]) and re-enables auto-follow, jumping
  /// immediately to [sampleId] (the caller passes the *current* filter's
  /// recommendation, `recommendedSampleIdForFilter`).
  void resetToRecommended(String sampleId) {
    _isUsingUserImage = false;
    _autoFollowRecommended = true;
    _sampleId = sampleId;
    notifyListeners();
  }

  /// Switches back to a previously-loaded user image ([hasUserImage])
  /// without re-picking. No-op if none is loaded.
  void useLoadedUserImage() {
    if (_userImage == null || _isUsingUserImage) return;
    _isUsingUserImage = true;
    notifyListeners();
  }

  /// Loads [image] as the user's preview source (file picker / drag & drop,
  /// #78) and switches to it immediately. Disposes the previously-held user
  /// image (if any) — the caller (picker/drop-target widget) hands over
  /// ownership of [image] to this state.
  void setUserImage(ui.Image image) {
    _userImage?.dispose();
    _userImage = image;
    _userImageGeneration++;
    _isUsingUserImage = true;
    notifyListeners();
  }

  /// Discards the loaded user image entirely and falls back to
  /// [fallbackSampleId] with auto-follow re-enabled.
  void clearUserImage(String fallbackSampleId) {
    _userImage?.dispose();
    _userImage = null;
    _isUsingUserImage = false;
    _autoFollowRecommended = true;
    _sampleId = fallbackSampleId;
    notifyListeners();
  }

  @override
  void dispose() {
    _userImage?.dispose();
    super.dispose();
  }
}
