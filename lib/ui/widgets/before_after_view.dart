import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/disability_type.dart';
import '../../rendering/shader_filter.dart';

/// Side-by-side "before / after" preview for a colour-vision filter.
///
/// The *before* pane shows a generated sample image (a smooth hue gradient with
/// primary colour swatches — chosen because colour-vision deficiencies are most
/// visible on saturated reds/greens/blues). The *after* pane shows the same
/// image with the selected filter applied.
///
/// Only [ColorVisionType.protanopia] / [ColorVisionType.protanomaly] can be
/// rendered for real today: they route through
/// [ShaderFilter.applyProtanopiaGpu] (the one GPU path proven by the golden
/// test). protanomaly reuses the protanopia transform at a reduced strength
/// ([recommendedStrength]). Every other filter shows a "rendering coming soon"
/// placeholder, because live/GPU rendering for them is tracked by other issues
/// (#1/#3/#4 live capture, #11 follow-ups for the remaining shaders).
class BeforeAfterView extends StatefulWidget {
  const BeforeAfterView({
    super.key,
    required this.filterType,
    required this.intensity,
    this.sampleSize = 256,
  });

  /// The currently selected colour-vision type. [ColorVisionType.none] shows
  /// the original image on both sides.
  final ColorVisionType filterType;

  /// Filter strength 0.0..1.0, forwarded to the shader.
  final double intensity;

  /// Width/height in logical pixels of the generated square sample image.
  final int sampleSize;

  /// Whether [type] can currently be rendered to a real "after" image.
  ///
  /// Exposed as a static so tests and callers can reason about render coverage
  /// without instantiating the widget.
  static bool canRender(ColorVisionType type) {
    switch (type) {
      case ColorVisionType.none:
      case ColorVisionType.protanopia:
      case ColorVisionType.protanomaly:
        return true;
      case ColorVisionType.deuteranopia:
      case ColorVisionType.deuteranomaly:
      case ColorVisionType.tritanopia:
      case ColorVisionType.tritanomaly:
      case ColorVisionType.achromatopsia:
        return false;
    }
  }

  /// Builds the deterministic sample image used in the *before* pane.
  ///
  /// Programmatically generated (no asset dependency): a horizontal hue sweep
  /// with a vertical brightness ramp, overlaid with red/green/blue/yellow
  /// swatches along the bottom. Static + async so tests can obtain the same
  /// image the widget uses.
  static Future<ui.Image> generateSampleImage(int size) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final fSize = size.toDouble();

    // Hue sweep (left→right) with brightness ramp (top→bottom).
    const columns = 64;
    final colW = fSize / columns;
    for (int c = 0; c < columns; c++) {
      final hue = (c / columns) * 360.0;
      final color = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
      canvas.drawRect(
        Rect.fromLTWH(c * colW, 0, colW + 1, fSize),
        Paint()..color = color,
      );
    }
    // Brightness ramp as a translucent black gradient over the lower half.
    canvas.drawRect(
      Rect.fromLTWH(0, fSize * 0.5, fSize, fSize * 0.5),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, fSize * 0.5),
          Offset(0, fSize),
          const [Color(0x00000000), Color(0xCC000000)],
        ),
    );

    // Saturated swatches along the bottom — the cases CVD distorts most.
    const swatches = [
      Color(0xFFE53935), // red
      Color(0xFF43A047), // green
      Color(0xFF1E88E5), // blue
      Color(0xFFFDD835), // yellow
    ];
    final swW = fSize / swatches.length;
    final swTop = fSize * 0.75;
    for (int i = 0; i < swatches.length; i++) {
      canvas.drawRect(
        Rect.fromLTWH(i * swW, swTop, swW, fSize - swTop),
        Paint()..color = swatches[i],
      );
    }

    final picture = recorder.endRecording();
    try {
      return await picture.toImage(size, size);
    } finally {
      picture.dispose();
    }
  }

  /// Produces the *after* image for [type] from [source], or null when the
  /// filter has no real renderer yet.
  ///
  /// [ColorVisionType.none] returns [source] unchanged (clone via the shader is
  /// unnecessary). protanopia/protanomaly route through the GPU shader.
  static Future<ui.Image?> renderAfter(
    ui.Image source,
    ColorVisionType type,
    double strength,
  ) async {
    switch (type) {
      case ColorVisionType.none:
        return source;
      case ColorVisionType.protanopia:
      case ColorVisionType.protanomaly:
        return ShaderFilter.applyProtanopiaGpu(source, strength);
      case ColorVisionType.deuteranopia:
      case ColorVisionType.deuteranomaly:
      case ColorVisionType.tritanopia:
      case ColorVisionType.tritanomaly:
      case ColorVisionType.achromatopsia:
        return null;
    }
  }

  @override
  State<BeforeAfterView> createState() => _BeforeAfterViewState();
}

class _BeforeAfterViewState extends State<BeforeAfterView> {
  ui.Image? _before;
  ui.Image? _after;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  @override
  void didUpdateWidget(BeforeAfterView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterType != widget.filterType ||
        oldWidget.intensity != widget.intensity ||
        oldWidget.sampleSize != widget.sampleSize) {
      _rebuild();
    }
  }

  Future<void> _rebuild() async {
    setState(() => _loading = true);
    final before =
        _before ?? await BeforeAfterView.generateSampleImage(widget.sampleSize);
    final after = await BeforeAfterView.renderAfter(
      before,
      widget.filterType,
      widget.intensity,
    );
    if (!mounted) return;
    setState(() {
      _before = before;
      _after = after;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _before?.dispose();
    // _after may alias _before (when filterType == none); avoid double dispose.
    if (!identical(_after, _before)) {
      _after?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    if (_loading && _before == null) {
      // Non-animating placeholder while the first sample image is generated.
      // (A CircularProgressIndicator would animate forever and block
      // pumpAndSettle in widget tests.)
      return SizedBox(
        height: 180,
        child: Center(
          child: Text(
            l10n.previewPreparing,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Stack the two panes vertically on narrow widths.
        final stackVertically = constraints.maxWidth < 420;
        final beforePane = _Pane(
          label: l10n.previewPaneOriginal,
          child: _ImageView(image: _before),
        );
        final afterPane = _Pane(
          label: widget.filterType == ColorVisionType.none
              ? l10n.previewPaneOriginal
              : colorVisionTypeName(l10n, widget.filterType),
          child: _after != null
              ? _ImageView(image: _after)
              : _ComingSoonPlaceholder(
                  theme: theme, label: l10n.previewComingSoon),
        );

        if (stackVertically) {
          return Column(
            children: [
              beforePane,
              const SizedBox(height: 12),
              afterPane,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: beforePane),
            const SizedBox(width: 12),
            Expanded(child: afterPane),
          ],
        );
      },
    );
  }
}

class _Pane extends StatelessWidget {
  const _Pane({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: child,
          ),
        ),
      ],
    );
  }
}

class _ImageView extends StatelessWidget {
  const _ImageView({required this.image});

  final ui.Image? image;

  @override
  Widget build(BuildContext context) {
    final img = image;
    if (img == null) {
      return const ColoredBox(color: Color(0x11000000));
    }
    return CustomPaint(
      painter: _UiImagePainter(img),
      size: Size.infinite,
    );
  }
}

class _UiImagePainter extends CustomPainter {
  _UiImagePainter(this.image);

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(image, src, dst, Paint());
  }

  @override
  bool shouldRepaint(_UiImagePainter oldDelegate) =>
      !identical(oldDelegate.image, image);
}

class _ComingSoonPlaceholder extends StatelessWidget {
  const _ComingSoonPlaceholder({required this.theme, required this.label});

  final ThemeData theme;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.brush_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Encodes a [ui.Image] to PNG bytes. Helper kept here so tests can assert the
/// rendered "after" image is non-empty without depending on widget internals.
Future<Uint8List?> encodeImagePng(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data?.buffer.asUint8List();
}
