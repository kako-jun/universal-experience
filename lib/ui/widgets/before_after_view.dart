import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/disability_type.dart';
import '../../rendering/cpu_vision_renderer.dart';
import '../../services/export_service.dart';
import '../../services/filter_service.dart';

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
/// All eight [ColorVisionType] values render for real. Rendering routes
/// through sensus's CPU `apply()` (`CpuVisionRenderer`, #85) — the *preview*
/// (this static image) is the CPU path's canonical consumer; the GPU
/// `ShaderFilter` path (#59) is reserved for the loupe's *live* display. The
/// -omaly types reuse their base -opia's [VisionFilter] at a reduced strength
/// ([recommendedStrength]); see [visionFilterForColorVisionType] for the
/// single source of the `ColorVisionType` → `VisionFilter` mapping. Live
/// *screen* capture (as opposed to this synthetic sample image) is still
/// tracked by #1/#3/#4.
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

  /// Produces the *after* image for [type] from [source]. Returns null only
  /// if [type] has no real renderer yet — none of today's eight values does,
  /// but the nullable return stays so a future `ColorVisionType` addition
  /// without a renderer degrades to [_ImageView]'s own null-safe placeholder
  /// instead of a hard error.
  ///
  /// [ColorVisionType.none] returns [source] unchanged (no filter to apply).
  /// Every other type maps to a sensus [VisionFilter] via
  /// [visionFilterForColorVisionType] (the single source shared with
  /// [FilterService.sensusFilter]) and renders through
  /// [CpuVisionRenderer.applier] — CPU `apply()`, not the GPU shader path
  /// (#85; GPU is reserved for the loupe's live display). Each -omaly type
  /// maps to the same [VisionFilter] as its base -opia; the reduced
  /// [strength] is what distinguishes them (see [recommendedStrength]).
  static Future<ui.Image?> renderAfter(
    ui.Image source,
    ColorVisionType type,
    double strength,
  ) async {
    final filter = visionFilterForColorVisionType(type);
    if (filter == null) return source;
    return CpuVisionRenderer.applier(source, filter, strength);
  }

  @override
  State<BeforeAfterView> createState() => _BeforeAfterViewState();
}

class _BeforeAfterViewState extends State<BeforeAfterView> {
  ui.Image? _before;
  ui.Image? _after;
  bool _loading = true;
  bool _exporting = false;

  /// Set when the most recently *applied* generation failed (#58 レビュー
  /// SHOULD-1). Gates the "after" pane to a [_ErrorPlaceholder] instead of a
  /// stale/possibly-inconsistent image. Cleared back to `false` on the next
  /// successful generation. The actual exception/stack trace isn't retained
  /// here — it's reported once via [FlutterError.reportError] at the catch
  /// site instead (#58 レビュー nit-1).
  bool _failed = false;

  /// Resolution (square side, pixels) the currently-held [_before]/[_after]
  /// were generated at. `null` until the first generation completes (#58).
  int? _currentSampleSize;

  /// Auto-sizing target already requested (generation in flight or
  /// debounced) but not yet applied — guards against re-scheduling the same
  /// resize on every intermediate build (#58).
  int? _pendingResizeSampleSize;

  /// Sample size the *latest completed* [_rebuild] attempt failed at (#58
  /// レビュー MUST-1). A permanent failure (missing asset, shader compile
  /// error, …) must not turn into a busy loop: [_evaluateAutoResize] refuses
  /// to auto-retry the same size again — only a genuine size change (a real
  /// resize) or a user action (filterType/intensity change, handled in
  /// [didUpdateWidget]) retries. Cleared back to `null` on success.
  int? _failedSampleSize;

  /// Debounces auto-size regeneration while the pane is being resized, so a
  /// drag/window-resize doesn't regenerate the sample image on every frame.
  Timer? _resizeDebounceTimer;

  /// Monotonic request id. Bumped on every [_rebuild] call so a slow/late
  /// async result can tell it has been superseded by a newer request and
  /// discard (dispose) itself instead of overwriting `_before`/`_after` with
  /// stale data or leaking GPU images (#58).
  int _generation = 0;

  /// Latest pane logical square side / devicePixelRatio recorded by
  /// [build]'s `LayoutBuilder` (#58 レビュー Q1: layout フェーズ自体は記録するだけ
  /// で、判定・タイマー起動などの副作用は起こさない). Consumed by
  /// [_evaluateAutoResize], which runs from a post-frame callback.
  double? _pendingPaneLogicalSize;
  double? _pendingDevicePixelRatio;
  bool _autoResizeCallbackScheduled = false;

  static const int _minAutoSampleSize = 32;
  static const int _maxAutoSampleSize = 2048; // #58 レビュー N5
  static const Duration _resizeDebounceDuration = Duration(milliseconds: 300);

  /// Logical pane side used when the incoming layout constraints are
  /// unbounded (e.g. inside a horizontally-scrolling list) and no real size
  /// can be derived (#58 レビュー Q2).
  static const double _fallbackPaneLogicalSize = 256;

  @override
  void initState() {
    super.initState();
    // Auto mode (widget.sampleSize == null) can't size itself yet — it has
    // no layout constraints until the first LayoutBuilder pass in build(),
    // which triggers the first generation via _evaluateAutoResize instead
    // (#58).
    final explicitSize = widget.sampleSize;
    if (explicitSize != null) {
      _rebuild(explicitSize);
    }
  }

  @override
  void didUpdateWidget(BeforeAfterView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sampleSize != null) {
      // #58 レビュー N2: 明示サイズに切り替わったら auto 用のリサイズタイマーは
      // 不要（残っていると意味のない再生成が後から起きる）。
      _cancelResizeTimer();
    }
    if (oldWidget.filterType != widget.filterType ||
        oldWidget.intensity != widget.intensity ||
        oldWidget.sampleSize != widget.sampleSize) {
      // #58 レビュー M1: auto モードで初回生成がまだ完了していない間に
      // filterType/intensity が変わると、_currentSampleSize はまだ null。
      // その場合は _pendingResizeSampleSize（初回/リサイズで既に決まっている
      // 生成先サイズ）を使う。
      // #58 レビュー MUST-1/nit-3: 恒久的な失敗で _currentSampleSize/
      // _pendingResizeSampleSize がどちらも null のままのことがある
      // （auto-resize 側は busy loop を避けるため自動では再試行しない）。
      // その場合は _failedSampleSize を使い、ユーザー操作（フィルタ/強度の変更）
      // での再試行を可能にする。_failedSampleSize は _currentSampleSize より
      // 優先する: 一度成功したサイズが残っていても、レイアウトが変わった後に
      // 失敗したのであれば、古い（もう画面のサイズに合っていない）成功時の
      // サイズへ後戻りさせるとちらつく。すべて null なら auto の初回レイアウトが
      // まだ来ていないということなので、そのレイアウトに任せてここでは何もしない
      // （実行される _rebuild は呼び出し時点の widget.filterType/intensity を
      // 読むので、更新は取りこぼされない）。
      final size = widget.sampleSize ??
          _pendingResizeSampleSize ??
          _failedSampleSize ??
          _currentSampleSize;
      if (size != null) {
        // 直接 _rebuild するので、保留中のデバウンスタイマー（あれば）は不要。
        _cancelResizeTimer();
        _rebuild(size);
      }
    }
  }

  void _cancelResizeTimer() {
    _resizeDebounceTimer?.cancel();
    _resizeDebounceTimer = null;
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
  /// #58 レビュー Q1: レイアウトフェーズでは値を記録し、まだ1回も予約していなけ
  /// れば post-frame コールバックを1つ予約するだけに留める。実際の判定（サイズ
  /// が変わったか）・タイマーの起動・`_rebuild` の呼び出しはすべて
  /// [_evaluateAutoResize]（post-frame コールバックからのみ呼ばれる）で行う。
  void _recordPaneLayout(double paneLogicalSize, double devicePixelRatio) {
    _pendingPaneLogicalSize = paneLogicalSize;
    _pendingDevicePixelRatio = devicePixelRatio;
    if (widget.sampleSize != null || _autoResizeCallbackScheduled) return;
    _autoResizeCallbackScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoResizeCallbackScheduled = false;
      _evaluateAutoResize();
    });
  }

  /// Runs (only from a post-frame callback, never during layout/build — Q1)
  /// the actual auto-size decision: no-ops when [BeforeAfterView.sampleSize]
  /// is set explicitly (re-checked here too — N2 — in case it changed while
  /// this callback was in flight) or the widget was disposed. Otherwise: the
  /// very first generation runs immediately; later changes (the pane being
  /// resized) are debounced so a drag doesn't regenerate on every frame.
  void _evaluateAutoResize() {
    if (!mounted || widget.sampleSize != null) return;
    final paneLogicalSize = _pendingPaneLogicalSize;
    final devicePixelRatio = _pendingDevicePixelRatio;
    if (paneLogicalSize == null || devicePixelRatio == null) return;
    final target = _autoSampleSize(paneLogicalSize, devicePixelRatio);

    if (target == _currentSampleSize) {
      // #58 レビュー N1: A→B→A のようにサイズが元に戻った場合、B 用に予約され
      // ていたデバウンスタイマーが残っていると、後で誤って B へ作り直してしまう
      // ので、ここで破棄しておく。
      if (_pendingResizeSampleSize != null &&
          _pendingResizeSampleSize != target) {
        _cancelResizeTimer();
        _pendingResizeSampleSize = null;
      }
      return;
    }
    if (target == _pendingResizeSampleSize) return;
    if (target == _failedSampleSize) {
      // #58 レビュー MUST-1: 恒久的な失敗（アセット欠落・シェーダのコンパイル
      // 失敗など）を、毎フレーム（初回）や 300ms 周期（リサイズ後）で
      // 再試行し続ける busy loop にしない。サイズが変わらない限り自動では
      // 再試行しない。ユーザー操作（filterType/intensity の変更）による
      // 再試行は didUpdateWidget 側の size 解決式でカバーする。時間ベースの
      // 再試行・バックオフは方針として入れない。
      return;
    }

    _pendingResizeSampleSize = target;
    _cancelResizeTimer();
    if (_currentSampleSize == null && _failedSampleSize == null) {
      // Very first generation ever attempted for this widget: no debounce.
      // We're already inside a post-frame callback here, so calling
      // _rebuild (and its setState) is safe.
      // #58 レビュー nit-2: a *previous* failure (even though it also left
      // _currentSampleSize null) must NOT be treated as "first generation"
      // here — otherwise resizing right after a permanent failure would
      // retry immediately (and again on every subsequent resize frame while
      // it keeps failing) instead of going through the debounce path below.
      _rebuild(target);
    } else {
      _resizeDebounceTimer = Timer(_resizeDebounceDuration, () {
        // #58 レビュー N2: 発火時点で改めて確認する。
        if (mounted && widget.sampleSize == null) _rebuild(target);
      });
    }
  }

  /// Cleans up after a failed [_rebuild] (#58 レビュー S1/MUST-1/SHOULD-1): if
  /// this call is still the latest request, resets `_loading` so the UI
  /// doesn't stay stuck on the "preparing" placeholder, records [sampleSize]
  /// in [_failedSampleSize] (so [_evaluateAutoResize] won't busy-loop
  /// retrying the same size — MUST-1) and clears `_pendingResizeSampleSize`
  /// (so a genuine size change or a user action can still retry), and shows
  /// a failure state instead of the (possibly now-stale) `_after` (SHOULD-1).
  /// If a newer request has already superseded this one, does nothing (that
  /// newer request owns the state now).
  void _onRebuildFailed(int generation, int sampleSize) {
    if (generation != _generation || !mounted) return;
    _failedSampleSize = sampleSize;
    _pendingResizeSampleSize = null;
    final oldAfter = _after;
    setState(() {
      _loading = false;
      _failed = true;
      _after = null;
    });
    // _after may have aliased _before (filterType == none) — don't dispose
    // the image that's still the current `_before`.
    if (oldAfter != null && !identical(oldAfter, _before)) {
      oldAfter.dispose();
    }
  }

  Future<void> _rebuild(int sampleSize) async {
    if (!mounted) return;
    final generation = ++_generation;
    final reuseBefore = _before != null && _currentSampleSize == sampleSize;
    setState(() => _loading = true);

    final ui.Image before;
    if (reuseBefore) {
      before = _before!;
    } else {
      try {
        before = await sampleImageGenerator(sampleSize);
      } catch (e, st) {
        // #58 レビュー nit-1: 静かに握りつぶさず Flutter のエラー報告経路に
        // 乗せる（crash reporting 等が拾えるように）。
        FlutterError.reportError(FlutterErrorDetails(
          exception: e,
          stack: st,
          library: 'before_after_view',
        ));
        // #58 レビュー S1: 生成に失敗しても loading に固着させず、次の
        // レイアウト/更新で再試行できるようにする。
        _onRebuildFailed(generation, sampleSize);
        return;
      }
    }

    if (generation != _generation || !mounted) {
      // #58 レビュー N3: generator の後・renderer の前でも世代を確認し、既に
      // 追い越されていれば（GPU コストのかかる）renderer を呼ばずに捨てる。
      if (!reuseBefore && !identical(before, _before)) before.dispose();
      return;
    }

    // #58 レビュー S2: `before` が再利用中の `_before` そのものだと、await
    // している間に別の（より新しい）`_rebuild` がそれを dispose する可能性が
    // ある。renderer には複製を渡し、`_before`/`_after` の実体には触れさせない。
    // 新規生成した `before` はまだどこにも共有されていないため複製不要。
    final bool clonedInput = reuseBefore;
    final ui.Image rendererInput = clonedInput ? before.clone() : before;

    ui.Image? after;
    try {
      after = await afterImageRenderer(
        rendererInput,
        widget.filterType,
        widget.intensity,
      );
    } catch (e, st) {
      // #58 レビュー nit-1: こちらも同様に報告する。
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
      _onRebuildFailed(generation, sampleSize);
      return;
    }

    final bool isLatest = generation == _generation && mounted;
    if (!isLatest) {
      // Superseded while we awaited the renderer, or disposed meanwhile —
      // discard everything we produced instead of leaking or touching state
      // a newer request already owns.
      if (!reuseBefore && !identical(before, _before)) before.dispose();
      // #58 レビュー SHOULD-2: `rendererInput` は clone された時点でこの呼び出し
      // だけが所有する私有オブジェクト。`after` と同一（filterType == none で
      // clone がそのまま返った場合）でも無条件に dispose する — 「同一なら
      // どちらかに任せる」という以前の条件分岐は、両方の条件が同時に false に
      // なる組み合わせで dispose 漏れ（リーク）を起こしていた。
      if (clonedInput) rendererInput.dispose();
      if (after != null &&
          !identical(after, rendererInput) &&
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
      _failed = false; // #58 レビュー SHOULD-1: 成功したら失敗表示を解除する。
    });
    _pendingResizeSampleSize = null;
    _failedSampleSize = null; // #58 レビュー MUST-1: 成功したので再試行を許可する。

    if (clonedInput && !identical(rendererInput, after)) {
      // The clone only exists to protect the renderer call; it never becomes
      // the new `_after` unless the renderer returned it unchanged
      // (filterType == none), so dispose it now.
      rendererInput.dispose();
    }
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
    _cancelResizeTimer();
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
    // #58 レビュー N4: DPR だけを購読する（MediaQuery 全体の変更で余計に
    // rebuild しない）。
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);

    // Wraps the whole widget (including the loading placeholder) so the
    // pane's logical size is known from the very first build — auto sizing
    // (#58) needs it to trigger the first sample generation.
    return LayoutBuilder(
      builder: (context, constraints) {
        // Stack the two panes vertically on narrow widths.
        final stackVertically = constraints.maxWidth < 420;
        // Mirrors how each pane is actually sized below: full width when
        // stacked, half (minus the 12px gutter) side-by-side. Falls back to
        // a fixed logical size when the incoming constraints are unbounded
        // (e.g. inside a horizontally-scrolling list) — #58 レビュー Q2.
        final rawPaneLogicalSize = stackVertically
            ? constraints.maxWidth
            : (constraints.maxWidth - 12) / 2;
        final paneLogicalSize =
            rawPaneLogicalSize.isFinite && rawPaneLogicalSize > 0
                ? rawPaneLogicalSize
                : _fallbackPaneLogicalSize;
        // #58 レビュー Q1: レイアウト（build）フェーズでは値を記録するだけ。
        // 判定・タイマー起動などの副作用は _evaluateAutoResize（post-frame）で
        // 行う。
        _recordPaneLayout(paneLogicalSize, devicePixelRatio);

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
        // #58 レビュー SHOULD-1: 最新世代が失敗した場合は _failed が立ち、
        // _after は null にされている。stale/不整合な画像を出し続けるより
        // 失敗を明示する。全 ColorVisionType が実描画対応済み（#59、#85 で CPU
        // 経路に切替）なので、失敗以外で `_after` が null のまま安定することは
        // ない（一度も成功して
        // いなければこの分岐に来る前に上の `_loading` ガードで preparing 表示に
        // なる）。それでも [_ImageView] 自身が null を安全に扱うため、二分岐で
        // 十分（「描画は近日対応」プレースホルダは #86 レビューで YAGNI 判定・撤去）。
        final Widget afterChild = _failed
            ? _ErrorPlaceholder(theme: theme, label: l10n.previewFailed)
            : _ImageView(image: _after);
        final afterPane = _Pane(
          label: widget.filterType == ColorVisionType.none
              ? l10n.previewPaneOriginal
              : colorVisionTypeName(l10n, widget.filterType),
          // Export is only meaningful when a real "after" image exists.
          // The failed state (null _after) gets no button.
          trailing: _after != null
              ? IconButton(
                  icon: const Icon(Icons.download_outlined),
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  tooltip: l10n.exportButtonTooltip,
                  onPressed: _exporting ? null : () => _export(l10n),
                )
              : null,
          child: afterChild,
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

/// Shown in the "after" pane when the latest generation/render attempt
/// failed (#58 レビュー SHOULD-1). Colours come only from `colorScheme` roles
/// (#72 の方針): the `error`/`onErrorContainer` family, not a hardcoded value.
class _ErrorPlaceholder extends StatelessWidget {
  const _ErrorPlaceholder({required this.theme, required this.label});

  final ThemeData theme;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
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
    );
  }
}

/// Encodes a [ui.Image] to PNG bytes. Helper kept here so tests can assert the
/// rendered "after" image is non-empty without depending on widget internals.
Future<Uint8List?> encodeImagePng(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data?.buffer.asUint8List();
}
