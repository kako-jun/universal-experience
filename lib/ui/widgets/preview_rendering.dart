import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/preview_image_source.dart';
import '../../models/sample_catalog.dart';
import '../../rendering/cpu_vision_renderer.dart';
import '../../rendering/image_fit.dart';
import '../../services/export_service.dart';
import '../../src/rust/api/sensus_bridge.dart';

// プレビューの描画（before の読み込み・after の描画・書き出し画像の合成）の差し替え口と、
// 画像の表示部品。`BeforeAfterView`（#58/#60）と 2×2 比較（`ColorVisionCompareView`、
// #84）が共有する。ウィジェット同士が段取りを借りないよう、共有の実体はここに置く（#159）。

/// `_BeforeAfterViewState` が内部で使う「before 画像を [PreviewImageSource]
/// から読み込む」ステップの型（#78）。実体は
/// [loadDefaultPreviewSourceImage]。widget test が世代管理
/// （古い結果は破棄され最新だけが残ること）を検証するために、応答が遅れる
/// フェイクへ差し替えられるようにするための seam（#58 と同じパターン）。
typedef PreviewSourceImageLoader = Future<ui.Image> Function(
  PreviewImageSource source,
  int size,
);

/// The fixed resolution (square side, pixels) the CPU preview renders at
/// when `sampleSize` is `null`（`kCanonicalSampleSize` の実体）.
///
/// Rationale for a **canonical size** instead of sizing to the rendered
/// pane × `devicePixelRatio` (the pre-#85 GPU-era behaviour, #58):
/// - Several sensus filters key their effect off **fixed pixel counts**
///   rather than a size-relative ratio — e.g. `DetailLoss.cellSize` (a
///   payload the UI lets the user pick directly, in px), eye_strain's
///   pillbox blur radius (`strength × 1.5px`), dry_eye's noise tile
///   (32px), cataract's noise cell (32px), metamorphopsia's max
///   displacement (8px), flickering_stars' point blob radius (2px) —
///   re-rendering at a different resolution every time the window resizes
///   would change how those filters look, independent of any real change
///   in strength (`starbursts` is excluded from this list: its ray length
///   is itself a size-relative *ratio*, `rayLengthRatio`, not a fixed
///   pixel count).
/// - The disk-blur family (myopia/hyperopia/presbyopia/astigmatism) derives
///   its blur radius as `strength × ratio × min(width, height)`; sensus's
///   elliptical kernel degenerates to a single center pixel (a no-op) once
///   that radius drops under ~1px (see
///   `integration_test/cpu_preview_all_filters_test.dart`). A small pane on
///   a low-DPR display could shrink the old auto-derived sample size enough
///   to silently lose the effect for the tightest-ratio filters
///   (astigmatism/presbyopia, ratio 1.1%).
///
/// 1024 keeps every filter's effect comfortably visible. Per-filter CPU
/// `apply()` timing at this size is recorded on Issue
/// #85 — see that Issue for the measured numbers/method rather than a
/// number here that could silently go stale. The pane simply scales the
/// rendered image up/down to fit (`_UiImagePainter.paint`,
/// `FilterQuality.medium`); it never re-renders on resize.
const int kCanonicalSampleSize = 1024;

/// [PreviewImageSource] からの画像読み込みの供給源（テストで差し替え可能）。
/// 既定は [loadDefaultPreviewSourceImage]。
@visibleForTesting
PreviewSourceImageLoader previewSourceImageLoader =
    loadDefaultPreviewSourceImage;

/// `_BeforeAfterViewState` が内部で使う after 画像描画ステップの型。
///
/// 実体は [renderDefaultAfter]。用途は [previewSourceImageLoader] と
/// 同じ（#58）。[filter] は `VisionFilterState.build`（#60）が組み立てた、payload 込みの
/// sensus [VisionFilter]。null は「何も選択されていない」を表し、[source] を
/// そのまま返す（[renderDefaultAfter] 参照）。
typedef AfterImageRenderer = Future<ui.Image?> Function(
  ui.Image source,
  VisionFilter? filter,
  double strength,
);

/// after 画像描画の供給源（テストで差し替え可能）。既定は
/// [renderDefaultAfter]。
@visibleForTesting
AfterImageRenderer afterImageRenderer = renderDefaultAfter;

/// `BeforeAfterView` の書き出し が使うキャプション合成ステップの型。
///
/// 実体は [composeExportImage]。widget test が実ファイル I/O（[pngSaver]）に
/// 触れずに export の挙動（caption が描画時の
/// `(filterId, strength)` から作られること）を検証できるようにするための
/// seam（#58 の `previewSourceImageLoader`/`afterImageRenderer` と同じパターン）。
typedef ExportImageComposer = Future<ui.Image> Function(
  ui.Image base,
  ExportCaption caption,
);

/// export 用画像合成の供給源（テストで差し替え可能）。既定は
/// [composeExportImage]。
@visibleForTesting
ExportImageComposer exportImageComposer = composeExportImage;

/// 上の 3 つの差し替え口（[previewSourceImageLoader] / [afterImageRenderer] /
/// [exportImageComposer]）を、テスト以外のコード（2×2 比較の
/// `color_vision_compare_view.dart`、#84）から呼ぶための入口。差し替え口そのものは
/// `@visibleForTesting` なので、本番コードはここを経由して同じ経路（と、テストでの
/// 差し替え）を共有する。
Future<ui.Image> loadPreviewImage(PreviewImageSource source, int size) =>
    previewSourceImageLoader(source, size);

/// [afterImageRenderer] の呼び出し口（[loadPreviewImage] 参照）。
Future<ui.Image?> renderPreviewAfter(
  ui.Image source,
  VisionFilter? filter,
  double strength,
) =>
    afterImageRenderer(source, filter, strength);

/// [exportImageComposer] の呼び出し口（[loadPreviewImage] 参照）。
Future<ui.Image> composeCaptionedExportImage(
  ui.Image base,
  ExportCaption caption,
) =>
    exportImageComposer(base, caption);

/// Loads the canonical-size *before* image for [source] (#78): a built-in
/// sample scene (decoded from `assets/samples/`) or a user-loaded image.
/// Either way the result is fit into a `size`×`size` square via
/// [fitImageToSquare] (letterbox — see that function's doc), so callers
/// never need to special-case the source's original aspect ratio.
///
/// For [SamplePreviewImageSource], the asset bytes are decoded into a
/// transient [ui.Image] that's disposed immediately after fitting (it's
/// never shared/cached — [fitImageToSquare] copies pixels into a brand new
/// image). For [UserPreviewImageSource], [UserPreviewImageSource.image] is
/// only *read*, never disposed here (`ImageSourceState` owns it — see
/// `PreviewImageSource`'s doc for the full ownership contract).
Future<ui.Image> loadDefaultPreviewSourceImage(
  PreviewImageSource source,
  int size,
) async {
  switch (source) {
    case SamplePreviewImageSource(:final sampleId):
      final entry = kSampleCatalogById[sampleId];
      if (entry == null) {
        throw ArgumentError('Unknown sample id: $sampleId');
      }
      final data = await rootBundle.load(entry.assetPath);
      final decoded = await decodeImageBytes(data.buffer.asUint8List());
      try {
        return await fitImageToSquare(decoded, size);
      } finally {
        decoded.dispose();
      }
    case UserPreviewImageSource(:final image):
      return fitImageToSquare(image, size);
  }
}

/// Produces the *after* image for [filter] from [source] at [strength].
///
/// `null` [filter] (nothing selected) returns [source] unchanged (no
/// filter to apply) without calling the renderer. Otherwise renders through
/// [CpuVisionRenderer.applier] — CPU `apply()`, not the GPU shader path
/// (#85; GPU is kept for a future live screen-capture display, unused
/// today). The mapping from a UI selection (color-vision quick pick /
/// advanced catalog / experience preset) to a [VisionFilter] happens
/// upstream, in `VisionFilterState.build` (#60) — this widget never
/// constructs a [VisionFilter] itself.
Future<ui.Image?> renderDefaultAfter(
  ui.Image source,
  VisionFilter? filter,
  double strength,
) async {
  if (filter == null) return source;
  return CpuVisionRenderer.applier(source, filter, strength);
}

/// 複数層の after 画像: [source] に [steps] を並びの順に 1 回の合成で適用する
/// （#119）。[steps] が空（全層が強度 0、または原画比較中）なら [source] をそのまま返し、
/// レンダラは呼ばない。
Future<ui.Image?> renderDefaultAfterPipeline(
  ui.Image source,
  List<VisionStep> steps,
) async {
  if (steps.isEmpty) return source;
  return CpuVisionRenderer.pipelineApplier(source, steps);
}

/// A ui.Image drawn to fill its box (also used by the 2x2 color-vision compare
/// view, #84). Shows a neutral placeholder box while [image] is null.
///
/// [semanticLabel] は画像の代替テキスト（スクリーンリーダー向け、#45）。null なら
/// 読み上げ対象にしない（周囲の文言が説明を担うとき）。
class PreviewImageView extends StatelessWidget {
  const PreviewImageView({super.key, required this.image, this.semanticLabel});

  final ui.Image? image;

  /// 画像の代替テキスト。
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final img = image;
    final Widget content = img == null
        ? ColoredBox(
            color: Theme.of(context).colorScheme.onSurface.withAlpha(0x11),
          )
        : CustomPaint(painter: _UiImagePainter(img), size: Size.infinite);
    final label = semanticLabel;
    if (label == null) return content;
    return Semantics(image: true, label: label, child: content);
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

/// 描画がこの時間を越えて続いたら「描画中…」（[PreviewBusyBadge]）を出す（#185）。
///
/// CPU 描画は途中で止められず、組み合わせによっては 1 回に数十秒かかる（例: 明るい画像に
/// 掛けた starbursts。sensus の starbursts は明るい画素の数に比例して重くなる）。その間は
/// プレビューが変わらないので、止まっているのではなく描いている最中だと見せる。普段の
/// 描画（数十〜数百 ms）では出ないよう、少し待ってから出す。
const Duration kPreviewBusyThreshold = Duration(milliseconds: 500);

/// 描画が [threshold] を越えて続いているかを数える（#185）。
///
/// 描画の列（実行中 + 保留）が始まったら [begin]、列が空になったら [end] を呼ぶ。
/// [begin] から [threshold] 経っても [end] が来なければ [showing] が true になり、
/// [onChanged] が呼ばれる（呼び出し側が `setState` する）。途中で [begin] が重なっても
/// 時計は最初の [begin] から数える（保留の要求が続く間は出しっぱなし）。
class PreviewBusyTracker {
  PreviewBusyTracker(this.onChanged, {this.threshold = kPreviewBusyThreshold});

  final VoidCallback onChanged;
  final Duration threshold;

  Timer? _timer;
  bool _showing = false;

  /// 「描画中…」を出すべきか。
  bool get showing => _showing;

  void begin() {
    if (_timer != null || _showing) return;
    _timer = Timer(threshold, () {
      _timer = null;
      _showing = true;
      onChanged();
    });
  }

  void end() {
    _timer?.cancel();
    _timer = null;
    if (_showing) {
      _showing = false;
      onChanged();
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

/// 描画が長引いている間の「描画中…」の札（#185）。アニメーションはしない
/// （widget test の pumpAndSettle を止めないため。「準備中」と同じ方針）。
/// 現れたときに一度だけ読み上げる（liveRegion）。
class PreviewBusyBadge extends StatelessWidget {
  const PreviewBusyBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      liveRegion: true,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hourglass_top, size: 16, color: scheme.onSurface),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown in the "after" pane when the latest generation/render attempt
/// failed. Colours come only from `colorScheme` roles
/// (#72 の方針): the `error`/`onErrorContainer` family, not a hardcoded value.
class PreviewErrorPlaceholder extends StatelessWidget {
  const PreviewErrorPlaceholder(
      {super.key, required this.theme, required this.label});

  final ThemeData theme;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: ColoredBox(
        color: theme.colorScheme.errorContainer,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
