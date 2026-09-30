import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/disability_type.dart';
import '../../models/preview_image_source.dart';
import '../../models/sample_catalog.dart';
import '../../models/vision_filter_catalog.dart';
import '../../models/vision_filter_contract_notes.dart' as contract_notes;
import '../../rendering/cpu_vision_renderer.dart';
import '../../rendering/image_fit.dart';
import '../../services/export_layers.dart';
import '../../services/export_service.dart';
import '../../services/vision_filter_metadata.dart';
import '../../services/vision_layer.dart' show quickColorVisionTypeOf;
import '../../src/rust/api/sensus_bridge.dart';

/// [_BeforeAfterViewState] が内部で使う「before 画像を [PreviewImageSource]
/// から読み込む」ステップの型（#78）。実体は
/// [BeforeAfterView.loadPreviewSourceImage]。widget test が世代管理
/// （古い結果は破棄され最新だけが残ること）を検証するために、応答が遅れる
/// フェイクへ差し替えられるようにするための seam（#58 と同じパターン）。
typedef PreviewSourceImageLoader = Future<ui.Image> Function(
  PreviewImageSource source,
  int size,
);

/// [PreviewImageSource] からの画像読み込みの供給源（テストで差し替え可能）。
/// 既定は [BeforeAfterView.loadPreviewSourceImage]。
@visibleForTesting
PreviewSourceImageLoader previewSourceImageLoader =
    BeforeAfterView.loadPreviewSourceImage;

/// [_BeforeAfterViewState] が内部で使う after 画像描画ステップの型。
///
/// 実体は [BeforeAfterView.renderAfter]。用途は [previewSourceImageLoader] と
/// 同じ（#58）。[filter] は `VisionFilterState.build`（#60）が組み立てた、payload 込みの
/// sensus [VisionFilter]。null は「何も選択されていない」を表し、[source] を
/// そのまま返す（[BeforeAfterView.renderAfter] 参照）。
typedef AfterImageRenderer = Future<ui.Image?> Function(
  ui.Image source,
  VisionFilter? filter,
  double strength,
);

/// after 画像描画の供給源（テストで差し替え可能）。既定は
/// [BeforeAfterView.renderAfter]。
@visibleForTesting
AfterImageRenderer afterImageRenderer = BeforeAfterView.renderAfter;

/// [_BeforeAfterViewState._export] が使うキャプション合成ステップの型。
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

/// [_BeforeAfterViewState._export] が使う PNG 書き出しステップの型。
///
/// 実体は [savePng]。`path_provider` の実プラットフォームを要する I/O
/// （`test/export_service_test.dart` の doc 参照）なので、widget test では
/// フェイクに差し替えて実ファイルへ触れずに済ませる。
typedef PngSaver = Future<String> Function(Uint8List bytes, String filename);

/// PNG 書き出しの供給源（テストで差し替え可能）。既定は [savePng]。
@visibleForTesting
PngSaver pngSaver = savePng;

/// 保存したファイルの場所を開く処理の型。実体は [revealInFolder]。
/// 実 OS のファイルマネージャを起動するので、widget test ではフェイクに差し替える。
typedef FolderRevealer = Future<bool> Function(String path);

/// 「フォルダで表示」の供給源（テストで差し替え可能）。既定は [revealInFolder]。
@visibleForTesting
FolderRevealer folderRevealer = revealInFolder;

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

/// Side-by-side "before / after" preview for the currently selected
/// `VisionFilterState` selection (#60).
///
/// The *before* pane shows [imageSource] (#78: one of the built-in sample
/// scenes, `lib/models/sample_catalog.dart`, or a user-loaded image —
/// `home_screen.dart` resolves this from `ImageSourceState`). The *after*
/// pane shows the same image with [filter] applied at [strength].
///
/// This widget is presentational: it doesn't read `VisionFilterState` or
/// `FilterService` itself. The caller (`home_screen.dart`) resolves the
/// current selection — whichever of the color-vision quick pick, the advanced
/// catalog, or an experience preset was used last — into a single
/// `(filter, filterId, strength)` triple via `VisionFilterState.build` and
/// `lib/services/preview_selection.dart`'s `previewStrength`, and passes it
/// down. [filter] `null` means nothing is selected; both panes show the
/// original image.
///
/// Rendering routes through sensus's CPU `apply()` (`CpuVisionRenderer`, #85)
/// — the *preview* (this static image) is the CPU path's canonical consumer,
/// and (since #60) can render any of sensus's 30 [VisionFilter] variants, not
/// just the 7 color-vision types. The GPU `ShaderFilter` path (#59) is kept
/// for a future *live* screen-capture display (#1/#3/#4) but isn't called
/// from any production code today.
class BeforeAfterView extends StatefulWidget {
  const BeforeAfterView({
    super.key,
    required this.filter,
    required this.filterId,
    required this.strength,
    required this.imageSource,
    this.colorVisionType,
    this.sampleSize,
    this.steps,
    this.layerNames,
    this.layerIds,
    this.exportLayers,
  }) : assert(
          (filter == null) == (filterId == null),
          'filter and filterId must both be null or both be set',
        );

  /// The sensus filter to render, built from the current
  /// `VisionFilterState` selection (payload included). `null` shows the
  /// original image on both sides.
  final VisionFilter? filter;

  /// The catalog id (snake_case) [filter] was built from — used to resolve
  /// the after-pane label / export caption ([visionFilterName]) and whether
  /// the filter is time-dependent ([VisionFilterEntry.isTimeDependent]).
  /// Must be non-null iff [filter] is non-null.
  final String? filterId;

  /// Filter strength 0.0..1.0, forwarded to the renderer.
  final double strength;

  /// The actual [ColorVisionType] behind the current selection, when it came
  /// from the color-vision quick pick (`FilterBrowser`/tray via
  /// `lib/services/color_vision_selection.dart`). `null` for advanced-catalog
  /// or preset selections (and for the quick pick's own "none"/original).
  ///
  /// The catalog (and therefore [filterId]) only has 5 color-vision entries
  /// (protanopia/deuteranopia/tritanopia/achromatopsia/tetrachromacy) —
  /// -omaly (anomaly) types map to the same catalog id as their base -opia
  /// (`visionFilterForColorVisionType`'s contract). Without this field, the
  /// after-pane label / export caption / filename would always say
  /// "Protanopia" even when the user picked "Protanomaly" (#60). When
  /// non-null, this overrides [filterId]-based name resolution for display
  /// purposes only — it never affects what's rendered (that's entirely
  /// [filter]/[strength]).
  final ColorVisionType? colorVisionType;

  /// 複数層のときの合成ステップ列（適用順、強度 0 の層は除外済み。#119）。
  ///
  /// `null`（既定。層が 0〜1 のとき）なら従来どおり [filter] を [strength] で適用する
  /// （[afterImageRenderer]）。非 null のときは **この列を 1 回の合成で適用**し
  /// （[BeforeAfterView.renderAfterPipeline] → [CpuVisionRenderer.pipelineApplier]。テストでは
  /// `pipelineApplier` を差し替える）、[filter] と
  /// [strength] は描画に使わない（見出し・書き出しが代表として参照する、フォーカス中の層の
  /// 値。複数層の見出しは #120、書き出しは [exportLayers] で #121）。空なら原画をそのまま見せる。
  final List<VisionStep>? steps;

  /// 重ねている層の表示名（適用順、#120）。2 つ以上のときだけ複数層として扱う（それ以外は従来どおり
  /// [filterId]/[colorVisionType] の名前）。複数層のときは、after 側の見出しを
  /// 「名前 + 名前 …（+N）」（[layerNamesSummary]）にする（切らずに折り返す）。PNG 書き出しの
  /// キャプションは [exportLayers] から作る（#121）。
  final List<String>? layerNames;

  /// PNG 書き出しが描画時点で控える、重ねている全層の値（適用順、強度 0 の層を含む、#121）。
  /// 複数層のときだけ渡す（`null` なら従来どおり [filter]・[filterId]・[colorVisionType]・
  /// [strength] の 1 層として書き出す）。キャプションには**強度が 0 より大きい層だけ**が
  /// 載る（[effectiveExportLayers]）。それが 2 つ以上ならその全層の行・合成した受診喚起、
  /// 1 つならその層だけ（1 層のときと同じ見た目）、0 なら [filter] 側の 1 層（フォーカス中の層。
  /// 原画比較中や全層強度 0 で、画像が原画のままのとき）。
  final List<ExportLayer>? exportLayers;

  /// 重ねている層のカタログ id（適用順、[layerNames] と同じ並び、#120）。複数層のとき、
  /// 時間依存のフィルタ（[VisionFilterEntry.isTimeDependent]）が 1 つでもあれば「静止フレーム」の
  /// 注記を出すために使う（[filterId] はフォーカス中の層 1 つしか指さない）。`null` なら
  /// 従来どおり [filterId] だけで判定する。
  final List<String>? layerIds;

  /// Explicit width/height (in pixels) for the generated square sample
  /// image. When `null` (the default, used by real callers), the resolution
  /// is [canonicalSampleSize] — **not** derived from the pane's layout size or
  /// `devicePixelRatio` (this pane used to auto-size to the
  /// rendered box × DPR, #58, but the CPU preview now always renders at a
  /// fixed canonical resolution and lets the display scale it — see
  /// [canonicalSampleSize] for why). Tests that want a small, fast image
  /// regardless of the canonical size pass an explicit (smaller) value here.
  final int? sampleSize;

  /// What the *before* pane should render (#78): one of the built-in sample
  /// scenes or a user-loaded image (`home_screen.dart` resolves this from
  /// `ImageSourceState.current`). [loadPreviewSourceImage]/
  /// [previewSourceImageLoader] supplies the image, fit into the canonical
  /// square via `lib/rendering/image_fit.dart`'s letterbox (see that file
  /// for why letterbox over crop).
  final PreviewImageSource imageSource;

  /// The fixed resolution (square side, pixels) the CPU preview renders at
  /// when [sampleSize] is `null`.
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
  static const int canonicalSampleSize = 1024;

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
  static Future<ui.Image> loadPreviewSourceImage(
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
  static Future<ui.Image?> renderAfter(
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
  static Future<ui.Image?> renderAfterPipeline(
    ui.Image source,
    List<VisionStep> steps,
  ) async {
    if (steps.isEmpty) return source;
    return CpuVisionRenderer.pipelineApplier(source, steps);
  }

  @override
  State<BeforeAfterView> createState() => _BeforeAfterViewState();
}

class _BeforeAfterViewState extends State<BeforeAfterView> {
  ui.Image? _before;
  ui.Image? _after;
  bool _loading = true;
  bool _exporting = false;

  /// Set when the most recently *applied* generation failed. Gates the "after" pane to a [PreviewErrorPlaceholder] instead of a
  /// stale/possibly-inconsistent image. Cleared back to `false` on the next
  /// successful generation. The actual exception/stack trace isn't retained
  /// here — it's reported once via [FlutterError.reportError] at the catch
  /// site instead.
  bool _failed = false;

  /// Resolution (square side, pixels) the currently-held [_before]/[_after]
  /// were generated at. `null` until the first generation completes (#58).
  /// Since pane-size-driven auto-sizing was removed, this only
  /// changes if [BeforeAfterView.sampleSize] itself changes (test-only in
  /// practice) — production always uses [BeforeAfterView.canonicalSampleSize].
  int? _currentSampleSize;

  /// The [PreviewImageSource] (#78) that actually produced the
  /// currently-held [_before]. `null` until the first generation completes.
  /// Set from the `source` local captured at the start of the [_rebuild]
  /// call that produced [_before] — **not** re-read from
  /// `widget.imageSource` at assignment time, which could have already moved
  /// on to a newer value while this call was awaiting the loader (see
  /// [_rebuild]'s doc).
  PreviewImageSource? _currentImageSource;

  /// The `(filterId, colorVisionType, strength)` that actually produced the
  /// currently-held [_after] (#60). `null` until the
  /// first successful render.
  ///
  /// [_export] must build its [ExportCaption] from these, **not** from
  /// `widget.filterId`/`widget.colorVisionType`/`widget.strength`: those
  /// reflect the *live* widget props, which can already have moved on (e.g.
  /// the user dragged the intensity slider again) while `_after` still shows
  /// the previous render — [_scheduleRebuild] coalesces the
  /// new request instead of applying it immediately, so there's a real
  /// window where the two diverge. Exporting during that window must burn a
  /// caption matching the pixels actually being exported, not the slider's
  /// current position.
  String? _afterFilterId;
  ColorVisionType? _afterColorVisionType;
  double? _afterStrength;

  /// The actual [VisionFilter] that produced the currently-held [_after]
  /// (#76). Captured alongside [_afterFilterId] for the same reason: the
  /// export caption's urgency note must reflect the filter that produced the
  /// exported pixels, not whatever `widget.filter` has moved on to while a
  /// slower re-render is still in flight.
  VisionFilter? _afterFilter;

  /// [BeforeAfterView.exportLayers] のうち、現在の [_after] を描画した時点のもの（#121）。
  /// [_afterFilter] などと同じ理由で、書き出しはこちらから作る。
  List<ExportLayer>? _afterExportLayers;

  /// Monotonic request id. Bumped on every [_rebuild] call so a slow/late
  /// async result can tell it has been superseded by a newer request and
  /// discard (dispose) itself instead of overwriting `_before`/`_after` with
  /// stale data or leaking GPU images (#58). [_scheduleRebuild]
  /// now serializes calls to [_rebuild] so at most one is ever in flight
  /// at a time, but this check stays as the defense against a slow result
  /// racing a `dispose()` (see [_rebuild]'s own `mounted` guards).
  int _generation = 0;

  /// Whether a [_rebuild] is currently in flight. While
  /// `true`, [_scheduleRebuild] doesn't start another one — it just records
  /// the request in [_pendingRebuildSampleSize] so the CPU `apply()` path
  /// (heavier than the old GPU shader path) never has more than one job
  /// running at once, e.g. while a slider is being dragged.
  bool _rebuildInFlight = false;

  /// The most recently requested sample size while a [_rebuild] is already
  /// running. Overwritten by each new request — only the
  /// latest survives. Consumed (and cleared) by [_runRebuild] once the
  /// in-flight job finishes.
  int? _pendingRebuildSampleSize;

  /// The sample size to render at when [BeforeAfterView.sampleSize] isn't
  /// explicitly set — [BeforeAfterView.canonicalSampleSize] in production;
  /// tests can override via the widget's `sampleSize` constructor param.
  int get _effectiveSampleSize =>
      widget.sampleSize ?? BeforeAfterView.canonicalSampleSize;

  @override
  void initState() {
    super.initState();
    // The sample size no longer depends on the pane's
    // layout (it's canonical/fixed), so there's no need to wait for a
    // LayoutBuilder pass before triggering the first generation.
    _scheduleRebuild(_effectiveSampleSize);
  }

  @override
  void didUpdateWidget(BeforeAfterView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filter != widget.filter ||
        oldWidget.filterId != widget.filterId ||
        oldWidget.colorVisionType != widget.colorVisionType ||
        oldWidget.strength != widget.strength ||
        !listEquals(oldWidget.steps, widget.steps) ||
        oldWidget.sampleSize != widget.sampleSize ||
        oldWidget.imageSource != widget.imageSource) {
      _scheduleRebuild(_effectiveSampleSize);
    }
  }

  /// Entry point for triggering a [_rebuild]. If one is
  /// already running, records [sampleSize] as the pending request (replacing
  /// any earlier pending one) and returns without starting a second job —
  /// the CPU `apply()` path is heavier than the old GPU shader path, so
  /// letting a rapidly-changing slider spawn one native-bridge call per
  /// frame would waste work and could reorder unpredictably. Once the
  /// in-flight job finishes, [_runRebuild] starts the pending request (if
  /// any) using whatever [_effectiveSampleSize]/`widget.filter`/
  /// `widget.strength` are current *at that time* — not stale snapshots
  /// from when the request was made — so the final result always reflects
  /// the latest inputs. [_rebuild]'s own generation/dispose/failure
  /// bookkeeping (#58) is unchanged; this only gates how many are in flight.
  void _scheduleRebuild(int sampleSize) {
    if (_rebuildInFlight) {
      _pendingRebuildSampleSize = sampleSize;
      return;
    }
    _rebuildInFlight = true;
    unawaited(_runRebuild(sampleSize));
  }

  Future<void> _runRebuild(int sampleSize) async {
    try {
      await _rebuild(sampleSize);
    } finally {
      // _rebuild が例外を投げても（現状は内部で catch して
      // いるため起きない想定だが）_rebuildInFlight が true のまま固着して
      // 以後の要求が永久に集約されたまま実行されなくなる事態を避ける。
      _rebuildInFlight = false;
    }
    if (!mounted) return;
    final pending = _pendingRebuildSampleSize;
    if (pending != null) {
      _pendingRebuildSampleSize = null;
      _scheduleRebuild(pending);
    }
  }

  /// Cleans up after a failed [_rebuild]: if this
  /// call is still the latest request, resets `_loading` so the UI doesn't
  /// stay stuck on the "preparing" placeholder, and shows a failure state
  /// instead of the (possibly now-stale) `_after`. A permanent
  /// failure doesn't retry itself (no timer, no auto-resize) — only a user
  /// action (`didUpdateWidget` seeing a filter/strength/sampleSize
  /// change) calls [_scheduleRebuild] again, so there's no busy-loop risk
  /// (the resize-driven retry path no longer exists; retrying is now
  /// inherently user-driven only). If a
  /// newer request has already superseded this one, does nothing (that newer
  /// request owns the state now).
  void _onRebuildFailed(int generation) {
    if (generation != _generation || !mounted) return;
    final oldAfter = _after;
    setState(() {
      _loading = false;
      _failed = true;
      _after = null;
    });
    // _after may have aliased _before (filter == null) — don't dispose
    // the image that's still the current `_before`.
    if (oldAfter != null && !identical(oldAfter, _before)) {
      oldAfter.dispose();
    }
  }

  /// [widget.imageSource] はこの関数の冒頭で一度だけ読み、
  /// [source] に固定する。以後（[previewSourceImageLoader] の呼び出し・
  /// [_currentImageSource] への記録のどちらも）は必ずこの [source] を使い、
  /// `widget.imageSource` を読み直さない。
  ///
  /// 理由: この関数は `await previewSourceImageLoader(...)` の間 sleep する。
  /// その間に親が再 build して `didUpdateWidget` が `widget.imageSource` を
  /// 新しい値へ更新しても、[_scheduleRebuild] は `_rebuildInFlight` が true の
  /// 間は `_generation` を上げず新しい要求を待避させるだけなので、この呼び出し
  /// の `generation` は最新のままになり得る（[isLatest] が true のまま）。
  /// もし `widget.imageSource` を assignment 時点で読み直していたら、実際に
  /// 読み込んだのは古い source の画像なのに `_currentImageSource` には新しい
  /// source が記録され、以後の [reuseBefore] 判定が「新しい source の画像は
  /// もう読み込み済み」と誤認して再読み込みをスキップしてしまう
  /// （実際に表示されているのは古い source の画像のまま）。
  Future<void> _rebuild(int sampleSize) async {
    if (!mounted) return;
    final generation = ++_generation;
    final source = widget.imageSource;
    final reuseBefore = _before != null &&
        _currentSampleSize == sampleSize &&
        _currentImageSource == source;
    setState(() => _loading = true);

    final ui.Image before;
    if (reuseBefore) {
      before = _before!;
    } else {
      try {
        before = await previewSourceImageLoader(source, sampleSize);
      } catch (e, st) {
        // 静かに握りつぶさず Flutter のエラー報告経路に
        // 乗せる（crash reporting 等が拾えるように）。
        FlutterError.reportError(FlutterErrorDetails(
          exception: e,
          stack: st,
          library: 'before_after_view',
        ));
        // 生成に失敗しても loading に固着させず、次の
        // レイアウト/更新で再試行できるようにする。
        _onRebuildFailed(generation);
        return;
      }
    }

    if (generation != _generation || !mounted) {
      // generator の後・renderer の前でも世代を確認し、既に
      // 追い越されていれば（GPU コストのかかる）renderer を呼ばずに捨てる。
      if (!reuseBefore && !identical(before, _before)) before.dispose();
      return;
    }

    // `before` が再利用中の `_before` そのものだと、await
    // している間に別の（より新しい）`_rebuild` がそれを dispose する可能性が
    // ある。renderer には複製を渡し、`_before`/`_after` の実体には触れさせない。
    // 新規生成した `before` はまだどこにも共有されていないため複製不要。
    final bool clonedInput = reuseBefore;
    final ui.Image rendererInput = clonedInput ? before.clone() : before;

    // 描画器に渡す入力と、描画した画像に記録する値（書き出しのキャプション・強度・
    // フィルタ）は、ここで一度だけ読んでローカルに固定する。描画器の await の間に親が
    // 再 build して `widget.*` が新しい値になっても（[_scheduleRebuild] は実行中は世代を
    // 上げず待避させるだけなので、この呼び出しが最新のまま完了し得る）、画像に写っている
    // 層の集合・強度と、書き出しに焼く値がずれないようにする（#121）。
    final steps = widget.steps;
    final renderFilter = widget.filter;
    final renderStrength = widget.strength;
    final renderFilterId = widget.filterId;
    final renderColorVisionType = widget.colorVisionType;
    final renderExportLayers = widget.exportLayers;

    ui.Image? after;
    try {
      after = steps == null
          ? await afterImageRenderer(
              rendererInput,
              renderFilter,
              renderStrength,
            )
          : await BeforeAfterView.renderAfterPipeline(rendererInput, steps);
    } catch (e, st) {
      // こちらも同様に報告する。
      FlutterError.reportError(FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'before_after_view',
      ));
      if (clonedInput) {
        rendererInput.dispose();
      } else if (!identical(before, _before)) {
        before.dispose();
      }
      _onRebuildFailed(generation);
      return;
    }

    // 描画器の型は null を許す（[AfterImageRenderer]）が、null は「after 画像が
    // 無い」状態で、空の枠を成功として出してしまう。例外と同じ失敗として扱う（#45）。
    if (after == null) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: StateError('after renderer returned null'),
        library: 'before_after_view',
      ));
      if (clonedInput) {
        rendererInput.dispose();
      } else if (!identical(before, _before)) {
        before.dispose();
      }
      _onRebuildFailed(generation);
      return;
    }

    final bool isLatest = generation == _generation && mounted;
    if (!isLatest) {
      // Superseded while we awaited the renderer, or disposed meanwhile —
      // discard everything we produced instead of leaking or touching state
      // a newer request already owns.
      if (!reuseBefore && !identical(before, _before)) before.dispose();
      // `rendererInput` は clone された時点でこの呼び出し
      // だけが所有する私有オブジェクト。`after` と同一（filter == null で
      // clone がそのまま返った場合）でも無条件に dispose する — 「同一なら
      // どちらかに任せる」という以前の条件分岐は、両方の条件が同時に false に
      // なる組み合わせで dispose 漏れ（リーク）を起こしていた。
      if (clonedInput) rendererInput.dispose();
      if (!identical(after, rendererInput) &&
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
      _afterFilterId = renderFilterId; // #60
      _afterColorVisionType = renderColorVisionType; // #60
      _afterStrength = renderStrength;
      _afterFilter = renderFilter; // #76
      _afterExportLayers = renderExportLayers; // #121
      _currentSampleSize = sampleSize;
      _currentImageSource = source; // widget.imageSource ではなく、冒頭で固定した source
      _loading = false;
      _failed = false; // 成功したら失敗表示を解除する。
    });

    if (clonedInput && !identical(rendererInput, after)) {
      // The clone only exists to protect the renderer call; it never becomes
      // the new `_after` unless the renderer returned it unchanged
      // (filter == null), so dispose it now.
      rendererInput.dispose();
    }
    if (!identical(oldBefore, before)) {
      oldBefore?.dispose();
    }
    // _after may alias _before (filter == null) or the old _before —
    // avoid double-disposing either.
    if (oldAfter != null &&
        !identical(oldAfter, oldBefore) &&
        !identical(oldAfter, after)) {
      oldAfter.dispose();
    }
  }

  @override
  void dispose() {
    _before?.dispose();
    // _after may alias _before (when filter == null); avoid double dispose.
    if (!identical(_after, _before)) {
      _after?.dispose();
    }
    super.dispose();
  }

  /// Exports the current "after" image as a PNG with burned-in metadata (#43).
  ///
  /// i18n は **UI 側でここで解決** し、`ExportCaption`（解決済み文字列）として
  /// pure な [exportImageComposer] に渡す（規律2）。保存後はフルパスをテキストとして
  /// クリップボードへコピーし、SnackBar で結果を知らせる。画像そのものの
  /// クリップボード書き込みはプラグインを要し環境変更になるため非スコープ。
  ///
  /// caption は [_afterFilterId]/[_afterColorVisionType]/
  /// [_afterStrength]（`_after` を描画した時点の値）から作る。
  /// `widget.filterId`/`widget.colorVisionType`/`widget.strength`
  /// （呼び出し時点の *現在* の値）を使うと、export をタップした瞬間までに
  /// スライダー操作で widget の props が先に進んでいた場合、表示中（＝実際に
  /// エクスポートされる）画像とは異なる caption を焼き込んでしまう。
  ///
  /// [_afterFilterId] は「原画（何も選択していない）」を描画したときも
  /// `null` になり得る（#60）。「まだ一度も描画していない」との区別には
  /// [_afterStrength]（成功描画のたびに必ず非 null になる）を使う。
  Future<void> _export(AppLocalizations l10n) async {
    final base = _after;
    final strength = _afterStrength;
    if (base == null || strength == null || _exporting) {
      return;
    }
    final filterId = _afterFilterId;
    final colorVisionType = _afterColorVisionType;
    final afterFilter = _afterFilter;
    final exportLayers = _afterExportLayers;
    setState(() => _exporting = true);

    final messenger = ScaffoldMessenger.of(context);
    try {
      final now = DateTime.now();
      final date = isoDate(now);
      final plan = planExport(
        l10n,
        layers: exportLayers,
        filterId: filterId,
        colorVisionType: colorVisionType,
        filter: afterFilter,
        strength: strength,
        isoDate: date,
      );

      final composed = await exportImageComposer(base, plan.caption);
      final bytes = await encodePngAndDispose(composed);

      final filename = exportFilename(
        symptomId: plan.symptomId,
        strengthPercent: plan.strengthPercent,
        isoDate: date,
        // #64: 同じ日に何度書き出しても別名になるよう時刻も入れる（それでも
        // 衝突したら savePng が連番にする）。焼き込むキャプションは日付のみ。
        time: compactTime(now),
      );
      final path = await savePngWithClipboard(bytes, filename);

      if (!mounted) return;
      showExportSuccess(messenger, l10n, path);
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

    // The CPU preview renders at a canonical fixed size
    // (see [BeforeAfterView.canonicalSampleSize]) regardless of the pane's
    // layout size or devicePixelRatio — LayoutBuilder here only decides
    // whether to stack the panes, it no longer drives sample-size generation
    // (the pre-#85 GPU-era `_recordPaneLayout`/auto-resize machinery, #58,
    // was removed along with it). The rendered image is simply scaled to fit
    // the pane (`_UiImagePainter.paint`, `FilterQuality.medium`).
    return LayoutBuilder(
      builder: (context, constraints) {
        // Stack the two panes vertically on narrow widths.
        final stackVertically = constraints.maxWidth < 420;

        if (_loading && _before == null) {
          // Non-animating placeholder while the first sample image is
          // generated. (A CircularProgressIndicator would animate forever
          // and block pumpAndSettle in widget tests.)
          return SizedBox(
            height: 180,
            child: Center(
              // 「準備中」が現れた瞬間だけ読み上げられる（#45）。完了すると
              // この liveRegion のノード自体が消えるので、完了は読まれない
              // （完了は画像の代替テキストが現れることで伝わる）。
              child: Semantics(
                liveRegion: true,
                child: Text(
                  l10n.previewPreparing,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        }

        final layerNames = widget.layerNames;
        final multiLayer = layerNames != null && layerNames.length > 1;
        final beforePane = _Pane(
          label: l10n.previewPaneOriginal,
          wrapLabel: multiLayer,
          // 見出し「元の画像」が説明を担うので、画像には代替テキストを付けない
          // （同じ文言の二重読み上げを避ける、#45）。
          child: PreviewImageView(image: _before),
        );
        // 最新世代が失敗した場合は _failed が立ち、
        // _after は null にされている。stale/不整合な画像を出し続けるより
        // 失敗を明示する。全 30 種が実描画対応済み（#59/#85 で CPU 経路に切替、
        // #60 で advanced カタログ・プリセットも結線）なので、失敗以外で
        // `_after` が null のまま安定することはない（一度も成功して
        // いなければこの分岐に来る前に上の `_loading` ガードで preparing 表示に
        // なる）。それでも [PreviewImageView] 自身が null を安全に扱うため、二分岐で
        // 十分（「描画は近日対応」プレースホルダは #86 で YAGNI と判断して撤去）。
        final afterName = multiLayer
            ? layerNamesSummary(l10n, layerNames)
            : visionFilterDisplayName(
                l10n, widget.colorVisionType, widget.filterId);
        final Widget afterChild = _failed
            ? PreviewErrorPlaceholder(theme: theme, label: l10n.previewFailed)
            : PreviewImageView(
                image: _after,
                // 何も選んでいないとき after は原画と同じで、見出し（afterName）が
                // 説明を担うので付けない（二重読み上げの回避）。
                // （`_after` は成功時にだけ非 null で代入され、描画器が null を返した
                // 場合も `_rebuild` が失敗として扱い `_failed` 分岐に入るので、
                // ここで画像が無いことはない。）
                semanticLabel:
                    widget.filterId == null && widget.colorVisionType == null
                        ? null
                        // 複数層の代替テキストは、まとめずに全部の名前を読ませる。
                        : l10n.previewImageFilteredSemantics(
                            multiLayer ? layerNames.join(' + ') : afterName),
              );
        // #60: 時間依存の注記は widget.filterId（カタログ id）からカタログを
        // 引いて解決する。after ペインの見出しは widget.colorVisionType が
        // あればそちらを優先する（#60: -omaly の名前を正しく出すため、
        // [visionFilterDisplayName] 参照）。
        // 複数層のときは、どれか 1 層でも時間依存なら出す（フォーカス中の層だけでは判らない）。
        final layerIds = widget.layerIds;
        final showsStaticFrameNote = multiLayer && layerIds != null
            ? layerIds.any(
                (id) => kVisionFilterCatalogById[id]?.isTimeDependent ?? false)
            : (widget.filterId == null
                    ? null
                    : kVisionFilterCatalogById[widget.filterId])
                ?.isTimeDependent ??
                false;
        final afterPane = _Pane(
          label: afterName,
          // 複数層の見出しは切らずに折り返す。両ペインとも折り返し方式にして、
          // ラベルの縦位置を揃える（[_Pane.wrapLabel]）。
          wrapLabel: multiLayer,
          // Export is only meaningful when a real "after" image exists.
          // The failed state (null _after) gets no button.
          // 複数層でも書き出せる（キャプションは層ごとの行、#121）。
          trailing: _after != null
              ? IconButton(
                  icon: const Icon(Icons.download_outlined),
                  iconSize: 20,
                  tooltip: l10n.exportButtonTooltip,
                  onPressed: _exporting ? null : () => _export(l10n),
                )
              : null,
          child: afterChild,
        );

        final Widget panes = stackVertically
            ? Column(
                children: [beforePane, const SizedBox(height: 12), afterPane],
              )
            // 横並びは、見出しの行と画像の行を別々に組む。見出しが折り返して片方だけ高くなっても
            // 画像の行は見出しの行の下から始まるので、左右の画像の上端が揃う。
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: beforePane.buildHeading(context)),
                      const SizedBox(width: 12),
                      Expanded(child: afterPane.buildHeading(context)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: beforePane.buildImage()),
                      const SizedBox(width: 12),
                      Expanded(child: afterPane.buildImage()),
                    ],
                  ),
                ],
              );

        // #60: vertigo / bppv_rotation のような時間依存フィルタは、CPU
        // プレビュー（時刻を受け取らず常に同じ内部時刻で描画する、
        // `CpuVisionRenderer` の doc 参照）では静止フレームにしかならない。
        // その旨を短く注記する。
        if (showsStaticFrameNote) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              panes,
              const SizedBox(height: 8),
              Text(
                l10n.previewStaticFrameNote,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        }
        return panes;
      },
    );
  }
}

/// 書き出し PNG に焼き込む [ExportCaption] を、描画時の値から解決する（#43/#76/#80、
/// 2×2 比較の各セル #84 と共有）。
///
/// i18n はここで解決し、pure な [exportImageComposer] へは解決済み文字列だけを渡す
/// （規律2）。引数は **画像を描画した時点の値** を渡すこと（呼び出し時点の現在の
/// widget props ではなく）。
///
/// - 受診喚起は プレビューの注記（`FilterParamPanel`・`ExperiencePresetTile`）と同じ
///   正本・同じ解決経路（[resolveConsultNotice]）を使う。色覚 7 型は urgency=none
///   かつ escalation も無いので notice は自然に null になる。
/// - 実験的なフィルタ（四色覚）には、近似であることに加えて「実験的」も焼き込む。
///   対象は [VisionFilterEntry.isExperimental] が正本。
/// - escalation は `ConsultNotice.escalationGroups` を詰め替えるだけで、グルーピングの
///   ロジックはここに複製しない。
ExportCaption buildExportCaption(
  AppLocalizations l10n, {
  required String? filterId,
  required ColorVisionType? colorVisionType,
  required VisionFilter? filter,
  required double strength,
  required String isoDate,
}) {
  final notice = filter == null
      ? null
      : resolveConsultNotice(
          l10n,
          visionFilterUrgencyProvider(filter),
          visionFilterUrgencyEscalationProvider(filter),
        );
  return ExportCaption(
    symptomLabel: visionFilterDisplayName(l10n, colorVisionType, filterId),
    strengthLabel: l10n.strengthLabel(contract_notes.strengthPercent(strength)),
    isoDate: isoDate,
    simulationNotice: l10n.exportSimulationNotice,
    experimentalNotice:
        (kVisionFilterCatalogById[filterId]?.isExperimental ?? false)
        ? l10n.exportExperimentalNotice
        : null,
    urgencyMessage: notice?.message,
    escalationGroups: [
      for (final g in notice?.escalationGroups ?? const [])
        ExportEscalationGroup(header: g.header, lines: g.lines),
    ],
    disclaimer: notice?.disclaimerShort,
  );
}

/// [planExport] の結果: 焼き込むキャプション・ファイル名の症状 id・強度（% の整数。複数層は null）。
typedef ExportPlan = ({
  ExportCaption caption,
  String symptomId,
  int? strengthPercent,
});

/// 書き出しの内容（キャプション・ファイル名の素）を、描画時点の値から決める（#121）。
///
/// [layers] は重ねている全層（[BeforeAfterView.exportLayers]、単一層なら null）。
/// キャプションに数えるのは**強度が 0 より大きい層だけ**（[effectiveExportLayers]。強度 0 の層は
/// 画素に効かないので、症状の行にも受診喚起にもファイル名にも入れない。表示が「0%」になる強度も同じ）。
///
/// - 2 層以上: [buildLayeredExportCaption]（層ごとの行 + 合成した受診喚起）。ファイル名は
///   層の id を適用順につないだもの（[exportSymptomId]）で、強度の % は付けない。
/// - 1 層: その層だけを、単一層の書き出し（[buildExportCaption]）と同じ見た目・同じ名前にする。
/// - 0 層（単一層、原画比較中、全層が強度 0 で画像が原画のまま）: 引数の
///   [filterId]/[colorVisionType]/[filter]/[strength]（フォーカス中の層の値）で、従来どおりの
///   単一層の書き出し。
ExportPlan planExport(
  AppLocalizations l10n, {
  required List<ExportLayer>? layers,
  required String? filterId,
  required ColorVisionType? colorVisionType,
  required VisionFilter? filter,
  required double strength,
  required String isoDate,
}) {
  final effective = effectiveExportLayers(layers ?? const []);
  if (effective.length >= 2) {
    return (
      caption: buildLayeredExportCaption(l10n,
          layers: effective, isoDate: isoDate),
      symptomId: exportSymptomId([for (final l in effective) l.layer.strengthKey]),
      strengthPercent: null,
    );
  }
  if (effective.length == 1) {
    final only = effective.single;
    filterId = only.layer.id;
    colorVisionType = quickColorVisionTypeOf(only.layer);
    filter = only.filter;
    strength = only.strength;
  }
  return (
    caption: buildExportCaption(
      l10n,
      filterId: filterId,
      colorVisionType: colorVisionType,
      filter: filter,
      strength: strength,
      isoDate: isoDate,
    ),
    // colorVisionType があればその id（-omaly を含む）を使う（#60）。
    // filterId は -omaly を base の -opia と区別できないため。
    symptomId: exportSymptomId([colorVisionType?.id ?? filterId ?? 'none']),
    strengthPercent: contract_notes.strengthPercent(strength),
  );
}

/// 複数の層（[layers]、適用順、2 つ以上。呼び出し側が強度 0 を除いたもの）を重ねた書き出しの
/// [ExportCaption]（#121）。
///
/// - 症状の行: 層ごとに 1 行（名前 + その層の強度）。
/// - 受診喚起: 各層の緊急度の**最大**と、escalation の**段ごとの併合（重複は 1 行）**を
///   [consultInputForFilters]（[mergeConsultInputs]）で 1 つにして、単一層と同じ
///   [resolveConsultNotice] の経路で解決する。
/// - 実験的の注記: どれか 1 層でも [VisionFilterEntry.isExperimental] なら添える。
/// - 「シミュレーション（近似）」は常に焼き込む。
ExportCaption buildLayeredExportCaption(
  AppLocalizations l10n, {
  required List<ExportLayer> layers,
  required String isoDate,
}) {
  final input = consultInputForFilters([for (final l in layers) l.filter]);
  final notice = resolveConsultNotice(l10n, input.urgency, input.escalation);
  return ExportCaption.layered(
    layers: [
      for (final l in layers)
        ExportLayerRow(
          name: visionLayerDisplayName(l10n, l.layer),
          strengthLabel:
              l10n.strengthLabel(contract_notes.strengthPercent(l.strength)),
        ),
    ],
    isoDate: isoDate,
    simulationNotice: l10n.exportSimulationNotice,
    experimentalNotice: layers.any(
            (l) => kVisionFilterCatalogById[l.layer.id]?.isExperimental ?? false)
        ? l10n.exportExperimentalNotice
        : null,
    urgencyMessage: notice?.message,
    escalationGroups: [
      for (final g in notice?.escalationGroups ?? const [])
        ExportEscalationGroup(header: g.header, lines: g.lines),
    ],
    disclaimer: notice?.disclaimerShort,
  );
}

/// [composed]（[exportImageComposer] などの戻り値）を PNG にエンコードし、
/// **[composed] を破棄する**（エンコードの成否にかかわらず）。エンコード結果が
/// 得られなければ [StateError]。
Future<Uint8List> encodePngAndDispose(ui.Image composed) async {
  Uint8List? bytes;
  try {
    bytes = await encodeImagePng(composed);
  } finally {
    composed.dispose();
  }
  if (bytes == null) {
    throw StateError('PNG encoding returned no bytes');
  }
  return bytes;
}

/// [bytes] を [filename] で保存し（[pngSaver]）、保存先のフルパスを
/// クリップボードへテキストとしてコピーして、そのパスを返す。画像そのものの
/// クリップボード書き込みはプラグインを要し環境変更になるため非スコープ。
Future<String> savePngWithClipboard(Uint8List bytes, String filename) async {
  final path = await pngSaver(bytes, filename);
  await Clipboard.setData(ClipboardData(text: path));
  return path;
}

/// 書き出し成功の SnackBar（保存先の表示 + 「フォルダで表示」）。
///
/// #64: 保存先はユーザーが実際に辿れる場所（Downloads）。パスを読ませるだけでなく、
/// その場でファイルマネージャを開けるようにする。アクション付きの SnackBar は既定で
/// 消えないので、時間で閉じるよう明示する。[messenger] は書き出し開始時に取って
/// あり context を使わないので、ビューが外れた後でも「開けなかった」を必ず知らせる。
void showExportSuccess(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  String path,
) {
  messenger.showSnackBar(
    SnackBar(
      content: Text(l10n.exportSuccess(path)),
      persist: false,
      duration: const Duration(seconds: 10),
      action: SnackBarAction(
        label: l10n.exportRevealAction,
        onPressed: () async {
          final opened = await folderRevealer(path);
          if (!opened) {
            messenger.showSnackBar(
              SnackBar(content: Text(l10n.exportRevealFailure)),
            );
          }
        },
      ),
    ),
  );
}

class _Pane extends StatelessWidget {
  const _Pane({
    required this.label,
    required this.child,
    this.trailing,
    this.wrapLabel = false,
  });

  final String label;

  /// 見出しを切らずに折り返す（複数層の見出し、#120）。false なら 1 行で省略記号。
  final bool wrapLabel;
  final Widget child;

  /// Optional action shown to the right of the label (e.g. the export button).
  final Widget? trailing;

  /// 見出しの行（ラベル + 右の操作）。
  Widget buildHeading(BuildContext context) {
    final theme = Theme.of(context);
    // 書き出しボタン（after 側だけ）を含む行は 48dp（タップ領域の下限、#45）。
    // before 側にも同じ高さを使うのは、左右の見出し行の高さを揃えて
    // 画像の上端をずらさないため。
    final text = Text(
      label,
      style: theme.textTheme.labelLarge,
      overflow: wrapLabel ? null : TextOverflow.ellipsis,
    );
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 48,
        maxHeight: wrapLabel ? double.infinity : 48,
      ),
      child: Row(
        // 折り返す見出し（複数層）は、ラベルの先頭行を左右で同じ高さに置く。左右で行数が違っても
        // 縦位置がずれない。1 行の見出しは 48dp の中央（上下 14dp = (48 - 行高 20) / 2）。
        crossAxisAlignment:
            wrapLabel ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Expanded(
            child: wrapLabel
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: text,
                  )
                : text,
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }

  /// 画像（正方形）。
  Widget buildImage() {
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        buildHeading(context),
        const SizedBox(height: 8),
        buildImage(),
      ],
    );
  }
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

/// Encodes a [ui.Image] to PNG bytes. Helper kept here so tests can assert the
/// rendered "after" image is non-empty without depending on widget internals.
Future<Uint8List?> encodeImagePng(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data?.buffer.asUint8List();
}
