import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/disability_type.dart';
import '../../rendering/shader_filter.dart';
import '../../services/export_service.dart';

/// [_BeforeAfterViewState] が内部で使うサンプル画像生成ステップの型。
///
/// 実体は [BeforeAfterView.generateSampleImage]。widget test が世代管理
/// （古い結果は破棄され最新だけが残ること）を検証するために、応答が遅れる
/// フェイクへ差し替えられるようにするための seam（#58）。
typedef SampleImageGenerator = Future<ui.Image> Function(int size);

/// サンプル画像生成の供給源（テストで差し替え可能）。既定は
/// [BeforeAfterView.generateSampleImage]。production はそのまま既定値を使う。
/// fixture 注入専用なので、外部からの書き換えを抑止するため `@visibleForTesting`。
@visibleForTesting
SampleImageGenerator sampleImageGenerator = BeforeAfterView.generateSampleImage;

/// [_BeforeAfterViewState] が内部で使う after 画像描画ステップの型。
///
/// 実体は [BeforeAfterView.renderAfter]。用途は [sampleImageGenerator] と同じ（#58）。
typedef AfterImageRenderer = Future<ui.Image?> Function(
  ui.Image source,
  ColorVisionType type,
  double strength,
);

/// after 画像描画の供給源（テストで差し替え可能）。既定は
/// [BeforeAfterView.renderAfter]。
@visibleForTesting
AfterImageRenderer afterImageRenderer = BeforeAfterView.renderAfter;

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
/// (#1/#3/#4 live capture, #59 follow-ups for the remaining shaders).
class BeforeAfterView extends StatefulWidget {
  const BeforeAfterView({
    super.key,
    required this.filterType,
    required this.intensity,
    this.sampleSize,
  });

  /// The currently selected colour-vision type. [ColorVisionType.none] shows
  /// the original image on both sides.
  final ColorVisionType filterType;

  /// Filter strength 0.0..1.0, forwarded to the shader.
  final double intensity;

  /// Explicit width/height (in pixels) for the generated square sample
  /// image. When `null` (the default, used by real callers), the resolution
  /// is instead derived automatically from the rendered pane's logical size
  /// × `devicePixelRatio`, capped at [_BeforeAfterViewState._maxAutoSampleSize]
  /// (#58: avoids blurry upscaling on Retina/HiDPI displays without
  /// generating arbitrarily large textures). Tests that want a small,
  /// deterministic image regardless of layout pass an explicit value.
  final int? sampleSize;

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
  bool _exporting = false;

  /// Resolution (square side, pixels) the currently-held [_before]/[_after]
  /// were generated at. `null` until the first generation completes (#58).
  int? _currentSampleSize;

  /// Auto-sizing target already requested (generation in flight or
  /// debounced) but not yet applied — guards against re-scheduling the same
  /// resize on every intermediate build (#58).
  int? _pendingResizeSampleSize;

  /// Debounces auto-size regeneration while the pane is being resized, so a
  /// drag/window-resize doesn't regenerate the sample image on every frame.
  Timer? _resizeDebounceTimer;

  /// Monotonic request id. Bumped on every [_rebuild] call so a slow/late
  /// async result can tell it has been superseded by a newer request and
  /// discard (dispose) itself instead of overwriting `_before`/`_after` with
  /// stale data or leaking GPU images (#58).
  int _generation = 0;

  static const int _minAutoSampleSize = 32;
  static const int _maxAutoSampleSize = 1024;
  static const Duration _resizeDebounceDuration = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    // Auto mode (widget.sampleSize == null) can't size itself yet — it has
    // no layout constraints until the first LayoutBuilder pass in build(),
    // which triggers the first _rebuild via _handleLayout instead (#58).
    final explicitSize = widget.sampleSize;
    if (explicitSize != null) {
      _rebuild(explicitSize);
    }
  }

  @override
  void didUpdateWidget(BeforeAfterView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterType != widget.filterType ||
        oldWidget.intensity != widget.intensity ||
        oldWidget.sampleSize != widget.sampleSize) {
      final size = widget.sampleSize ?? _currentSampleSize;
      // If no generation has completed yet (auto mode, first layout still
      // pending), skip: the upcoming/in-flight _rebuild already reads the
      // current widget.filterType/intensity when it runs.
      if (size != null) {
        _rebuild(size);
      }
    }
  }

  /// Desired sample resolution for a pane whose logical square side is
  /// [paneLogicalSize] at the given [devicePixelRatio], capped at
  /// [_maxAutoSampleSize] so a large window/high DPR doesn't generate an
  /// arbitrarily large texture (#58).
  int _autoSampleSize(double paneLogicalSize, double devicePixelRatio) {
    final physical = (paneLogicalSize * devicePixelRatio).round();
    if (physical < _minAutoSampleSize) return _minAutoSampleSize;
    if (physical > _maxAutoSampleSize) return _maxAutoSampleSize;
    return physical;
  }

  /// Called from [build]'s `LayoutBuilder` with the pane's current logical
  /// square side and device pixel ratio (#58).
  ///
  /// No-ops when [BeforeAfterView.sampleSize] is set explicitly (tests that
  /// want a fixed, deterministic size). Otherwise: the very first generation
  /// runs as soon as possible (deferred to after this frame, since `build()`
  /// itself can't call `setState`); later changes (the pane being resized)
  /// are debounced so a drag doesn't regenerate on every frame.
  void _handleLayout(double paneLogicalSize, double devicePixelRatio) {
    if (widget.sampleSize != null) return;
    final target = _autoSampleSize(paneLogicalSize, devicePixelRatio);
    if (target == _currentSampleSize || target == _pendingResizeSampleSize) {
      return;
    }
    _pendingResizeSampleSize = target;
    _resizeDebounceTimer?.cancel();
    _resizeDebounceTimer = null;
    if (_currentSampleSize == null) {
      // First generation: don't debounce, but defer past this build frame
      // (setState can't be called synchronously while building).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _rebuild(target);
      });
    } else {
      _resizeDebounceTimer = Timer(_resizeDebounceDuration, () {
        if (mounted) _rebuild(target);
      });
    }
  }

  Future<void> _rebuild(int sampleSize) async {
    if (!mounted) return;
    final generation = ++_generation;
    final reuseBefore = _before != null && _currentSampleSize == sampleSize;
    setState(() => _loading = true);

    final before =
        reuseBefore ? _before! : await sampleImageGenerator(sampleSize);
    final after = await afterImageRenderer(
      before,
      widget.filterType,
      widget.intensity,
    );

    if (generation != _generation || !mounted) {
      // Superseded by a newer request, or the widget was disposed while we
      // were awaiting — discard this result instead of leaking a GPU image
      // or calling setState after dispose (#58). `before` may still be
      // identical to the current `_before` (e.g. a still-current image that
      // a later request also happened to reuse); never dispose that one.
      if (!reuseBefore && !identical(before, _before)) {
        before.dispose();
      }
      if (after != null &&
          !identical(after, before) &&
          !identical(after, _after)) {
        after.dispose();
      }
      return;
    }

    final oldBefore = _before;
    final oldAfter = _after;
    setState(() {
      _before = before;
      _after = after;
      _currentSampleSize = sampleSize;
      _loading = false;
    });
    _pendingResizeSampleSize = null;

    if (!identical(oldBefore, before)) {
      oldBefore?.dispose();
    }
    // _after may alias _before (filterType == none) or the old _before —
    // avoid double-disposing either.
    if (oldAfter != null &&
        !identical(oldAfter, oldBefore) &&
        !identical(oldAfter, after)) {
      oldAfter.dispose();
    }
  }

  @override
  void dispose() {
    _resizeDebounceTimer?.cancel();
    _before?.dispose();
    // _after may alias _before (when filterType == none); avoid double dispose.
    if (!identical(_after, _before)) {
      _after?.dispose();
    }
    super.dispose();
  }

  /// Exports the current "after" image as a PNG with burned-in metadata (#43).
  ///
  /// i18n は **UI 側でここで解決** し、`ExportCaption`（解決済み文字列）として
  /// pure な [composeExportImage] に渡す（規律2）。保存後はフルパスをテキストとして
  /// クリップボードへコピーし、SnackBar で結果を知らせる。画像そのものの
  /// クリップボード書き込みはプラグインを要し環境変更になるため非スコープ。
  Future<void> _export(AppLocalizations l10n) async {
    final base = _after;
    if (base == null || _exporting) return;
    setState(() => _exporting = true);

    final messenger = ScaffoldMessenger.of(context);
    try {
      final strengthPercent = (widget.intensity.clamp(0.0, 1.0) * 100).round();
      final date = isoDate(DateTime.now());
      // 色覚特性は urgency=none のため受診喚起は出さない（緊急性のある症状ではない）。
      // 色覚 7 型（このウィジェットが扱う範囲）は urgency=none なので受診喚起は焼かない。
      // sensus advanced フィルタ（緑内障等）の live export に拡張する際は、ここで
      // `consultMessageForUrgency(...)` を解決して `urgencyMessage` に渡せる（拡張ポイント）。
      final caption = ExportCaption(
        symptomLabel: widget.filterType == ColorVisionType.none
            ? l10n.previewPaneOriginal
            : colorVisionTypeName(l10n, widget.filterType),
        strengthLabel: l10n.strengthLabel(strengthPercent),
        isoDate: date,
      );

      final composed = await composeExportImage(base, caption);
      Uint8List? bytes;
      try {
        bytes = await encodeImagePng(composed);
      } finally {
        composed.dispose();
      }
      if (bytes == null) {
        throw StateError('PNG encoding returned no bytes');
      }

      final filename = exportFilename(
        symptomId: widget.filterType.id,
        strengthPercent: strengthPercent,
        isoDate: date,
      );
      final path = await savePng(bytes, filename);
      await Clipboard.setData(ClipboardData(text: path));

      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.exportSuccess(path))));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.exportFailure)));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;

    // Wraps the whole widget (including the loading placeholder) so the
    // pane's logical size is known from the very first build — auto sizing
    // (#58) needs it to trigger the first sample generation.
    return LayoutBuilder(
      builder: (context, constraints) {
        // Stack the two panes vertically on narrow widths.
        final stackVertically = constraints.maxWidth < 420;
        // Mirrors how each pane is actually sized below: full width when
        // stacked, half (minus the 12px gutter) side-by-side.
        final paneLogicalSize = stackVertically
            ? constraints.maxWidth
            : (constraints.maxWidth - 12) / 2;
        if (paneLogicalSize.isFinite && paneLogicalSize > 0) {
          _handleLayout(paneLogicalSize, devicePixelRatio);
        }

        if (_loading && _before == null) {
          // Non-animating placeholder while the first sample image is
          // generated. (A CircularProgressIndicator would animate forever
          // and block pumpAndSettle in widget tests.)
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

        final beforePane = _Pane(
          label: l10n.previewPaneOriginal,
          child: _ImageView(image: _before),
        );
        final afterPane = _Pane(
          label: widget.filterType == ColorVisionType.none
              ? l10n.previewPaneOriginal
              : colorVisionTypeName(l10n, widget.filterType),
          // Export is only meaningful when a real "after" image exists.
          // Coming-soon filters (null _after) get no button.
          trailing: _after != null
              ? IconButton(
                  icon: const Icon(Icons.download_outlined),
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  tooltip: l10n.exportButtonTooltip,
                  onPressed: _exporting ? null : () => _export(l10n),
                )
              : null,
          child: _after != null
              ? _ImageView(image: _after)
              : _ComingSoonPlaceholder(
                  theme: theme,
                  label: l10n.previewComingSoon,
                ),
        );

        if (stackVertically) {
          return Column(
            children: [beforePane, const SizedBox(height: 12), afterPane],
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
  const _Pane({required this.label, required this.child, this.trailing});

  final String label;
  final Widget child;

  /// Optional action shown to the right of the label (e.g. the export button).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 32,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
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
    return CustomPaint(painter: _UiImagePainter(img), size: Size.infinite);
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
    // filterQuality medium+ (#58): the sample is now sized close to the
    // pane's physical resolution, but drawImageRect still scales it to fit
    // `size` exactly — the default FilterQuality.none (nearest-neighbour)
    // looks aliased on any residual up/downscale, especially on Retina.
    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
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
