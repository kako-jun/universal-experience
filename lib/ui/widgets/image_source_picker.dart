import 'dart:async';
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/sample_catalog.dart';
import '../../rendering/image_fit.dart';
import '../../services/image_source_state.dart';
import '../../services/vision_filter_state.dart';

/// Opens the OS file picker restricted to common image types and returns the
/// picked file's raw bytes, or `null` if the user cancelled (#78).
///
/// Seam for widget tests (mirrors `before_after_view.dart`'s
/// `sampleImageGenerator` pattern): production uses
/// [_defaultPickImageBytes], which calls the real `file_selector` plugin
/// (platform channel — not available in plain `flutter test`).
typedef ImageBytesPicker = Future<Uint8List?> Function();

@visibleForTesting
ImageBytesPicker pickImageBytes = _defaultPickImageBytes;

Future<Uint8List?> _defaultPickImageBytes() async {
  const typeGroup = XTypeGroup(
    label: 'images',
    extensions: ['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp'],
  );
  final file = await openFile(acceptedTypeGroups: [typeGroup]);
  if (file == null) return null;
  return file.readAsBytes();
}

/// Decodes [bytes] and hands the result to `ImageSourceState.setUserImage`
/// — which takes ownership of it (disposes the previous user image,
/// #58/#85 discipline). A decode failure (unsupported/corrupt file) is
/// reported via [FlutterError.reportError] (same convention as
/// `before_after_view.dart`'s generator/renderer errors) and, only if
/// [context] is still mounted, surfaced with a SnackBar.
///
/// Shared by [ImageSourcePicker]'s pick button, its drag-and-drop target,
/// and the first-run welcome banner's "try it with your photo" action
/// (`lib/ui/widgets/welcome_banner.dart`) — every entry point that ends with
/// raw image bytes goes through this one function.
Future<void> loadUserImageBytes(BuildContext context, Uint8List bytes) async {
  final imageSourceState = context.read<ImageSourceState>();
  ui.Image decoded;
  try {
    decoded = await decodeImageBytes(bytes);
  } catch (e, st) {
    FlutterError.reportError(FlutterErrorDetails(
      exception: e,
      stack: st,
      library: 'image_source_picker',
    ));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.imageSourcePickFailed),
      ),
    );
    return;
  }
  imageSourceState.setUserImage(decoded);
}

/// Opens the file picker and loads the result via [loadUserImageBytes]
/// (#78). No-op if the user cancels the picker.
Future<void> pickAndLoadUserImage(BuildContext context) async {
  final bytes = await pickImageBytes();
  if (bytes == null) return;
  if (!context.mounted) return;
  await loadUserImageBytes(context, bytes);
}

/// Sample-picker chips + "choose a photo" button + drag-and-drop target for
/// [child] (#78).
///
/// Wraps [child] (the `BeforeAfterView` preview) in a `desktop_drop`
/// [DropTarget] so dropping an image file anywhere over the preview loads
/// it — the sample chips and the "choose a photo…" button sit above it.
/// Reads and writes only `ImageSourceState` (the single source of truth for
/// which image is shown, #78) and `VisionFilterState` (to resolve the
/// current filter's recommended sample for the chips/"back to recommended"
/// button); it never touches `BeforeAfterView` internals directly.
///
/// Images are decoded in memory only ([decodeImageBytes]) — never written to
/// disk, never sent anywhere (#78).
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
    final bytes = await details.files.first.readAsBytes();
    if (!mounted) return;
    await loadUserImageBytes(context, bytes);
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
            _buildControls(l10n, theme, imageSourceState, recommendedId),
            const SizedBox(height: 12),
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
                  border: Border.all(
                    color: _dragging
                        ? theme.colorScheme.primary
                        : Colors.transparent,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: widget.child,
              ),
            ),
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
        if (imageSourceState.hasUserImage)
          ChoiceChip(
            label: Text(l10n.imageSourceYourPhotoChipLabel),
            selected: imageSourceState.isUsingUserImage,
            onSelected: (_) => imageSourceState.useLoadedUserImage(),
          ),
        OutlinedButton.icon(
          onPressed: () => pickAndLoadUserImage(context),
          icon: const Icon(Icons.photo_outlined, size: 18),
          label: Text(l10n.imageSourcePickButton),
        ),
        Text(
          l10n.imageSourceDropHint,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (!imageSourceState.isFollowingRecommended)
          TextButton(
            onPressed: () =>
                imageSourceState.resetToRecommended(recommendedId),
            child: Text(l10n.imageSourceResetToRecommended),
          ),
      ],
    );
  }
}
