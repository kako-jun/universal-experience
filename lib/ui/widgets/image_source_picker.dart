import 'dart:async';
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/sample_catalog.dart';
import '../../rendering/image_fit.dart';
import '../../services/app_shortcuts.dart';
import '../../services/clipboard_image_reader.dart';
import '../../services/image_source_state.dart';
import '../../services/vision_filter_state.dart';

/// Opens the OS file picker restricted to common image types and returns the
/// picked [XFile], or `null` if the user cancelled (#78).
///
/// Seam for widget tests (mirrors `before_after_view.dart`'s
/// `previewSourceImageLoader` pattern): production uses
/// [_defaultPickImageFile], which calls the real `file_selector` plugin
/// (platform channel — not available in plain `flutter test`). Returns the
/// [XFile] itself (not its bytes) so [loadUserImageFile] can check
/// [XFile.length] **before** reading the file body (#78 レビュー S1).
typedef ImageFilePicker = Future<XFile?> Function();

@visibleForTesting
ImageFilePicker pickImageFile = _defaultPickImageFile;

Future<XFile?> _defaultPickImageFile() {
  const typeGroup = XTypeGroup(
    label: 'images',
    extensions: ['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp'],
  );
  return openFile(acceptedTypeGroups: [typeGroup]);
}

/// Maximum accepted user image file size (#78 レビュー S1), checked via
/// [XFile.length] **before** [loadUserImageFile] reads the file body — an
/// oversized file is rejected without ever loading its bytes into memory.
const int kMaxUserImageFileBytes = 50 * 1024 * 1024; // 50MB

/// Thrown by [loadUserImageFile] when a file's reported length exceeds
/// [kMaxUserImageFileBytes] (#78 レビュー nit). A distinct type (rather than
/// a plain [StateError]) so the catch block can show a size-specific
/// SnackBar (`imageSourceFileTooLarge`) instead of the generic
/// `imageSourcePickFailed` one — a 200MB RAW file and a corrupt PNG are
/// different problems with different fixes for the person picking the file.
class UserImageTooLargeException implements Exception {
  const UserImageTooLargeException(this.bytes);

  /// The file's reported length in bytes (always `> kMaxUserImageFileBytes`).
  final int bytes;

  @override
  String toString() =>
      'UserImageTooLargeException: $bytes bytes (max $kMaxUserImageFileBytes)';
}

/// Reads and decodes [file] into a [ui.Image] and hands it to
/// `ImageSourceState.setUserImage` — which takes ownership of it (disposes
/// the previous user image, #58/#85 discipline). Shared by
/// [ImageSourcePicker]'s pick button, its drag-and-drop target, and the
/// first-run welcome banner's "try it with your photo" action
/// (`lib/ui/widgets/welcome_banner.dart`) — every entry point that ends with
/// an [XFile] goes through this one function.
///
/// #78 レビュー S1: rejects (without reading the file body) anything larger
/// than [kMaxUserImageFileBytes], and decodes via [decodeUserImageBytes]
/// (downscales during decode so no dimension exceeds
/// [kUserImageMaxDimension]).
///
/// #78 レビュー S2: the size check, the read, and the decode all run inside
/// **one** try/catch — any failure along the way (oversized file, unreadable
/// file, corrupt/unsupported image data) is reported via
/// [FlutterError.reportError] (same convention as `before_after_view.dart`'s
/// generator/renderer errors) and, only if [context] is still mounted,
/// surfaced with a SnackBar — [UserImageTooLargeException] gets the
/// size-specific `imageSourceFileTooLarge` message (#78 レビュー nit), any
/// other failure gets the generic `imageSourcePickFailed`. `ImageSourceState`
/// is left untouched on any failure.
///
/// Returns `true` on success, `false` on failure — the welcome banner
/// (`lib/ui/widgets/welcome_banner.dart`) uses this to decide whether its
/// "try it with your photo" action should dismiss itself (#78 レビュー Q3:
/// only on an actual successful load, never on cancel/failure).
Future<bool> loadUserImageFile(BuildContext context, XFile file) async {
  final imageSourceState = context.read<ImageSourceState>();
  ui.Image decoded;
  try {
    final length = await file.length();
    if (length > kMaxUserImageFileBytes) {
      throw UserImageTooLargeException(length);
    }
    final bytes = await file.readAsBytes();
    decoded = await decodeUserImageBytes(bytes);
  } catch (e, st) {
    _reportUserImageError(e, st);
    if (!context.mounted) return false;
    final l10n = AppLocalizations.of(context)!;
    _showUserImageFailure(
      context,
      e is UserImageTooLargeException
          ? l10n
              .imageSourceFileTooLarge(kMaxUserImageFileBytes ~/ (1024 * 1024))
          : l10n.imageSourcePickFailed,
    );
    return false;
  }
  imageSourceState.setUserImage(decoded);
  return true;
}

/// Reports [error] via [FlutterError.reportError] (same convention as
/// `before_after_view.dart`). Shared by every user-image entry point
/// ([loadUserImageFile], [pasteUserImageFromClipboard]).
void _reportUserImageError(Object error, StackTrace stack) {
  FlutterError.reportError(FlutterErrorDetails(
    exception: error,
    stack: stack,
    library: 'image_source_picker',
  ));
}

/// Shows [message] in a SnackBar. The caller checks `context.mounted` first
/// (after the async gap), so [context] is never used across it here.
void _showUserImageFailure(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Thrown by [pasteUserImageFromClipboard] when the clipboard holds no image
/// (#97) — the most common failure for a paste (text copied, or nothing),
/// so it gets its own SnackBar (`imageSourcePasteNoImage`) telling the
/// person to copy an image first.
class ClipboardHasNoImageException implements Exception {
  const ClipboardHasNoImageException();

  @override
  String toString() => 'ClipboardHasNoImageException';
}

/// Thrown by [pasteUserImageFromClipboard] when the clipboard image's bytes
/// can't be decoded (#97) — an image format Flutter's codec doesn't read.
class ClipboardImageUnsupportedException implements Exception {
  const ClipboardImageUnsupportedException(this.cause);

  final Object cause;

  @override
  String toString() => 'ClipboardImageUnsupportedException: $cause';
}

/// Pastes the clipboard's image as the preview's user image (#97, Cmd/Ctrl+V
/// and the "Paste" button). Goes through the **same** decode + hand-over
/// path as [loadUserImageFile] — [decodeUserImageBytes] (downscales during
/// decode, so a 8K screenshot is bounded to [kUserImageMaxDimension]) →
/// `ImageSourceState.setUserImage` — so the single source of truth is
/// unchanged; only the byte source differs ([clipboardImageReader], a test
/// seam). Nothing is written to disk or sent anywhere.
///
/// Failures never touch `ImageSourceState` and are reported via
/// [FlutterError.reportError] + a SnackBar (only if [context] is still
/// mounted): no image on the clipboard ([ClipboardHasNoImageException],
/// `imageSourcePasteNoImage`), more than [kMaxUserImageFileBytes] of image
/// data ([UserImageTooLargeException], `imageSourcePasteTooLarge` — checked
/// before decoding), bytes the codec can't read
/// ([ClipboardImageUnsupportedException], `imageSourcePasteUnsupported`), or
/// the clipboard read itself failing (`imageSourcePasteFailed`).
///
/// Returns `true` on success, `false` on failure.
Future<bool> pasteUserImageFromClipboard(BuildContext context) async {
  final imageSourceState = context.read<ImageSourceState>();
  ui.Image decoded;
  try {
    final bytes = await clipboardImageReader.readImageBytes();
    if (bytes == null || bytes.isEmpty) {
      throw const ClipboardHasNoImageException();
    }
    if (bytes.length > kMaxUserImageFileBytes) {
      throw UserImageTooLargeException(bytes.length);
    }
    try {
      decoded = await decodeUserImageBytes(bytes);
    } catch (e) {
      throw ClipboardImageUnsupportedException(e);
    }
  } catch (e, st) {
    _reportUserImageError(e, st);
    if (!context.mounted) return false;
    final l10n = AppLocalizations.of(context)!;
    _showUserImageFailure(
      context,
      switch (e) {
        ClipboardHasNoImageException() => l10n.imageSourcePasteNoImage,
        UserImageTooLargeException() => l10n.imageSourcePasteTooLarge(
            kMaxUserImageFileBytes ~/ (1024 * 1024),
          ),
        ClipboardImageUnsupportedException() =>
          l10n.imageSourcePasteUnsupported,
        _ => l10n.imageSourcePasteFailed,
      },
    );
    return false;
  }
  imageSourceState.setUserImage(decoded);
  return true;
}

/// Opens the file picker and loads the result via [loadUserImageFile]
/// (#78). Returns `false` (without touching `ImageSourceState`) if the user
/// cancels the picker; otherwise returns [loadUserImageFile]'s result.
Future<bool> pickAndLoadUserImage(BuildContext context) async {
  final file = await pickImageFile();
  if (file == null) return false;
  if (!context.mounted) return false;
  return loadUserImageFile(context, file);
}

/// Drag-and-drop target for [child] + sample-picker chips + "choose a photo"
/// and "paste" buttons (#78, #97).
///
/// Wraps [child] (the `BeforeAfterView` preview) in a `desktop_drop`
/// [DropTarget] so dropping an image file anywhere over the preview loads
/// it — the sample chips and the "choose a photo…" button sit right below it
/// (#72: the preview comes first so it stays in the first viewport).
/// Reads and writes only `ImageSourceState` (the single source of truth for
/// which image is shown, #78) and `VisionFilterState` (to resolve the
/// current filter's recommended sample for the chips/"back to recommended"
/// button); it never touches `BeforeAfterView` internals directly.
///
/// Images are decoded in memory only ([decodeUserImageBytes]) — never
/// written to disk, never sent anywhere (#78).
class ImageSourcePicker extends StatefulWidget {
  const ImageSourcePicker({super.key, required this.child});

  final Widget child;

  @override
  State<ImageSourcePicker> createState() => _ImageSourcePickerState();
}

class _ImageSourcePickerState extends State<ImageSourcePicker> {
  bool _dragging = false;

  Future<void> _handleDrop(DropDoneDetails details) async {
    if (details.files.isEmpty) return;
    // 複数ファイルが同時にドロップされても最初の 1 枚だけを使う（#78:
    // ユーザー画像は常に 1 枚）。残りは黙って無視する。
    if (!mounted) return;
    await loadUserImageFile(context, details.files.first);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Consumer2<ImageSourceState, VisionFilterState>(
      builder: (context, imageSourceState, visionState, _) {
        final recommendedId =
            recommendedSampleIdForFilter(visionState.selectedId);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropTarget(
              onDragEntered: (_) => setState(() => _dragging = true),
              onDragExited: (_) => setState(() => _dragging = false),
              onDragDone: (details) {
                setState(() => _dragging = false);
                unawaited(_handleDrop(details));
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  // #78 レビュー nit: Colors.transparent ではなく colorScheme
                  // のロール（primary、alpha=0）を使う。見た目は同じ透明だが、
                  // Colors.* を直接参照しない規約に従う。
                  border: Border.all(
                    color: theme.colorScheme.primary
                        .withAlpha(_dragging ? 255 : 0),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: widget.child,
              ),
            ),
            const SizedBox(height: 12),
            // サンプル画像の切替はプレビューに隣接させ、その下に置く（#72）。
            _buildControls(l10n, theme, imageSourceState, recommendedId),
          ],
        );
      },
    );
  }

  Widget _buildControls(
    AppLocalizations l10n,
    ThemeData theme,
    ImageSourceState imageSourceState,
    String recommendedId,
  ) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        Text(l10n.imageSourceSectionLabel, style: theme.textTheme.labelLarge),
        for (final entry in kSampleCatalog)
          ChoiceChip(
            label: Text(sampleImageName(l10n, entry.id)),
            selected: !imageSourceState.isUsingUserImage &&
                imageSourceState.selectedSampleId == entry.id,
            onSelected: (_) => imageSourceState.selectSample(entry.id),
          ),
        if (imageSourceState.hasUserImage) ...[
          ChoiceChip(
            label: Text(l10n.imageSourceYourPhotoChipLabel),
            selected: imageSourceState.isUsingUserImage,
            onSelected: (_) => imageSourceState.useLoadedUserImage(),
          ),
          // #78 レビュー nit: 読み込んだユーザー画像を閉じる UI。
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: l10n.imageSourceClosePhotoTooltip,
            onPressed: () => imageSourceState.clearUserImage(recommendedId),
          ),
        ],
        OutlinedButton.icon(
          onPressed: () => pickAndLoadUserImage(context),
          icon: const Icon(Icons.photo_outlined, size: 18),
          label: Text(l10n.imageSourcePickButton),
        ),
        // #97: クリップボードの画像を貼り付ける。Cmd/Ctrl+V（home_screen.dart）
        // と同じ経路（pasteUserImageFromClipboard）を通る。
        Tooltip(
          message: l10n.imageSourcePasteTooltip(pasteShortcutLabel()),
          child: OutlinedButton.icon(
            onPressed: () => pasteUserImageFromClipboard(context),
            icon: const Icon(Icons.content_paste, size: 18),
            label: Text(l10n.imageSourcePasteButton),
          ),
        ),
        Text(
          l10n.imageSourceDropHint,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (!imageSourceState.isFollowingRecommended)
          TextButton(
            onPressed: () => imageSourceState.resetToRecommended(recommendedId),
            child: Text(l10n.imageSourceResetToRecommended),
          ),
      ],
    );
  }
}
