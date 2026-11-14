import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/preview_image_source.dart';
import '../../models/vision_filter_catalog.dart';
import '../../services/export_layers.dart';
import '../../services/export_plan.dart';
import '../../services/export_service.dart';
import '../../services/preview_diagnostics.dart';
import '../../src/rust/api/sensus_bridge.dart';
import 'export_feedback.dart';
import 'preview_rendering.dart';

/// 横並びのときの Before / After 2 枚の間隔（dp）。[BeforeAfterView.maxPaneSide] が
/// 幅の上限（2 枚分 + この間隔）を出すのにも使うので、1 か所で持つ。
const double kBeforeAfterPaneGap = 12;

/// Side-by-side "before / after" preview for the currently selected
/// `VisionFilterState` selection (#60).
///
/// The *before* pane shows [imageSource] (#78: one of the built-in sample
/// scenes, `lib/models/sample_catalog.dart`, or a user-loaded image —
/// `home_screen.dart` resolves this from `ImageSourceState`). The *after*
/// pane shows the same image with [filter] applied at [strength].
///
/// This widget is presentational: it doesn't read `VisionFilterState`
/// itself. The caller (`home_screen.dart`) resolves the
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
    this.variantId,
    this.sampleSize,
    this.steps,
    this.layerNames,
    this.layerIds,
    this.exportLayers,
    this.maxPaneSide,
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

  /// The alias id (`kVisionAliases`: protanomaly / deuteranomaly / tritanomaly)
  /// behind the current selection, or `null` when the selection is not an
  /// alias (plain catalog filter, preset, or nothing selected).
  ///
  /// The catalog (and therefore [filterId]) only has 5 color-vision entries
  /// (protanopia/deuteranopia/tritanopia/achromatopsia/tetrachromacy) —
  /// the -omaly (anomaly) aliases map to the same catalog id as their base
  /// -opia. Without this field, the after-pane label / export caption /
  /// filename would always say "Protanopia" even when the user picked
  /// "Protanomaly" (#60). When non-null, this overrides [filterId]-based name
  /// resolution for display purposes only — it never affects what's rendered
  /// (that's entirely [filter]/[strength]).
  final String? variantId;

  /// 複数層のときの合成ステップ列（適用順、強度 0 の層は除外済み。#119）。
  ///
  /// `null`（既定。層が 0〜1 のとき）なら従来どおり [filter] を [strength] で適用する
  /// （[afterImageRenderer]）。非 null のときは **この列を 1 回の合成で適用**し
  /// （[renderDefaultAfterPipeline] → [CpuVisionRenderer.pipelineApplier]。テストでは
  /// `pipelineApplier` を差し替える）、[filter] と
  /// [strength] は描画に使わない（見出し・書き出しが代表として参照する、フォーカス中の層の
  /// 値。複数層の見出しは #120、書き出しは [exportLayers] で #121）。空なら原画をそのまま見せる。
  final List<VisionStep>? steps;

  /// 重ねている層の表示名（適用順、#120）。2 つ以上のときだけ複数層として扱う（それ以外は従来どおり
  /// [filterId]/[variantId] の名前）。複数層のときは、after 側の見出しを
  /// 「名前 + 名前 …（+N）」（[layerNamesSummary]）にする（切らずに折り返す）。PNG 書き出しの
  /// キャプションは [exportLayers] から作る（#121）。
  final List<String>? layerNames;

  /// PNG 書き出しが描画時点で控える、重ねている全層の値（適用順、強度 0 の層を含む、#121）。
  /// 複数層のときだけ渡す（`null` なら従来どおり [filter]・[filterId]・[variantId]・
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

  /// Before / After を横に並べるとき、画像 1 枚（正方形）の一辺の上限（dp、#130）。
  /// `null`（既定）なら上限なしで、幅いっぱいに広がる。上限を越える幅のときは、2 枚を
  /// 中央に寄せて並べる（画像の大きさだけが変わる。見出しの行・書き出しボタンの位置は
  /// 2 枚の幅に追従する）。縦に積むとき（幅 420dp 未満）は使わない。
  /// 呼び出し側が、ウィンドウの高さに対して選択欄まで最初のビューポートに収まる大きさを渡す。
  final double? maxPaneSide;

  /// Explicit width/height (in pixels) for the generated square sample
  /// image. When `null` (the default, used by real callers), the resolution
  /// is [kCanonicalSampleSize] — **not** derived from the pane's layout size or
  /// `devicePixelRatio` (this pane used to auto-size to the
  /// rendered box × DPR, #58, but the CPU preview now always renders at a
  /// fixed canonical resolution and lets the display scale it — see
  /// [kCanonicalSampleSize] for why). Tests that want a small, fast image
  /// regardless of the canonical size pass an explicit (smaller) value here.
  final int? sampleSize;

  /// What the *before* pane should render (#78): one of the built-in sample
  /// scenes or a user-loaded image (`home_screen.dart` resolves this from
  /// `ImageSourceState.current`). [loadPreviewSourceImage]/
  /// [previewSourceImageLoader] supplies the image, fit into the canonical
  /// square via `lib/rendering/image_fit.dart`'s letterbox (see that file
  /// for why letterbox over crop).
  final PreviewImageSource imageSource;

  @override
  State<BeforeAfterView> createState() => _BeforeAfterViewState();
}

/// テスト用の差し替え口: [_BeforeAfterViewState] の描画 1 回（`_rebuild`）の冒頭で待つ。
/// 描画の段取りそのものが（描画器の例外は `_rebuild` の中で失敗表示になるので、それ以外で）
/// 例外で終わったときでも、待っている間に来て保留された要求が流れ、札が残らないことを
/// 確かめるためのもの（#185）。本番では null のまま（待たない）。
@visibleForTesting
Future<void> Function()? debugBeforeAfterRebuildHook;

/// 描画 1 回の入力。`_rebuild` の冒頭で `widget` から一度だけ読んで固定する（await の間に
/// 親が再 build して `widget.*` が先へ進んでも、画像に写っている層・強度と、書き出しに
/// 焼く値がずれないようにする、#121）。
class _RenderInput {
  _RenderInput(BeforeAfterView w, this.source, this.size)
      : steps = w.steps,
        filter = w.filter,
        strength = w.strength,
        filterId = w.filterId,
        variantId = w.variantId,
        exportLayers = w.exportLayers;

  final PreviewImageSource source;
  final int size;
  final List<VisionStep>? steps;
  final VisionFilter? filter;
  final double strength;
  final String? filterId;
  final String? variantId;
  final List<ExportLayer>? exportLayers;

  /// 描画結果のキャッシュの鍵（#185）。何も掛けない（原画のまま）入力は描画が軽いので
  /// 覚えない（null）。
  PreviewRenderKey? get cacheKey {
    final steps = this.steps;
    if (steps != null) {
      return steps.isEmpty
          ? null
          : PreviewRenderKey.pipeline(source: source, size: size, steps: steps);
    }
    final filter = this.filter;
    return filter == null
        ? null
        : PreviewRenderKey.single(
            source: source, size: size, filter: filter, strength: strength);
  }

  bool get heavy => previewInputIsHeavy(filter, steps);

  Future<ui.Image?> render(ui.Image input) => steps == null
      ? renderPreviewAfter(input, filter, strength)
      : renderDefaultAfterPipeline(input, steps!);
}

class _BeforeAfterViewState extends State<BeforeAfterView> {
  ui.Image? _before;
  ui.Image? _after;
  bool _exporting = false;

  /// Set when the most recently *applied* generation failed. Gates the "after" pane to a [PreviewErrorPlaceholder] instead of a
  /// stale/possibly-inconsistent image. Cleared back to `false` on the next
  /// successful generation. The actual exception/stack trace isn't retained
  /// here — it's reported once via [FlutterError.reportError] at the catch
  /// site instead.
  bool _failed = false;

  /// いまの [_after] が、重い描画の前に先に描いた低解像度の仮表示か（#185）。
  /// true の間は札に「低解像度の仮表示」と出し、書き出しは出さない。
  bool _afterProvisional = false;

  /// [_before] を読み込んだ解像度と元画像（#58/#78）。[_before] と一緒にだけ変わる。
  int? _currentSampleSize;
  PreviewImageSource? _currentImageSource;

  /// The `(filterId, variantId, strength)` that actually produced the
  /// currently-held [_after] (#60). `null` until the
  /// first successful render.
  ///
  /// [_export] must build its [ExportCaption] from these, **not** from
  /// `widget.filterId`/`widget.variantId`/`widget.strength`: those
  /// reflect the *live* widget props, which can already have moved on (e.g.
  /// the user dragged the intensity slider again) while `_after` still shows
  /// the previous render — [_scheduleRebuild] coalesces the
  /// new request instead of applying it immediately, so there's a real
  /// window where the two diverge. Exporting during that window must burn a
  /// caption matching the pixels actually being exported, not the slider's
  /// current position.
  String? _afterFilterId;
  String? _afterVariantId;
  double? _afterStrength;

  /// The actual [VisionFilter] that produced the currently-held [_after]
  /// (#76). Captured alongside [_afterFilterId] for the same reason.
  VisionFilter? _afterFilter;

  /// [BeforeAfterView.exportLayers] のうち、現在の [_after] を描画した時点のもの（#121）。
  List<ExportLayer>? _afterExportLayers;

  /// 描画の要求の通し番号。描画 1 回の結果は、終わった時点でこれが変わっていれば
  /// （新しい要求・キャッシュからの表示に追い越されていれば）表示に使わない（#58）。
  int _generation = 0;

  /// 描画（after）が走っているか。true の間は [_scheduleRebuild] は 2 本目を始めず、
  /// 要求を [_pendingRebuildSampleSize] に集約する（CPU 描画を同時に 1 本までにする）。
  bool _rebuildInFlight = false;

  /// 描画中に来た最新の要求（解像度）。後の要求で上書きされ、最新だけが残る。
  /// 走っている描画が終わったら [_runRebuild] が流す。
  int? _pendingRebuildSampleSize;

  /// 元画像（before）の読み込みの通し番号と、いま読み込んでいる入力（#185 (c)）。
  /// 読み込みは after の直列描画とは別に走らせ、終わったらすぐ before を差し替える
  /// （after の重い描画の最中にサンプルを替えても、元画像側が固まらない）。
  int _beforeGeneration = 0;
  (PreviewImageSource, int)? _beforeLoading;

  /// after の描画結果の LRU（#185 (b)）。付ける → 外す → 付けるで再描画しない。
  final PreviewRenderCache _cache = PreviewRenderCache();

  /// 直前のフル解像度の描画にかかった時間（[kProvisionalRenderAfter] の判定用、#185 (a)）。
  Duration? _lastFullRender;

  /// 描画 1 回が [kPreviewBusyThreshold] を越えたら、after 側に「描画中…」を出す（#185）。
  /// ネイティブの描画は途中で止められず、明るい画像の starbursts のように 1 回に数十秒
  /// かかることがある。その間 after は前の描画のままなので、止まっているのと見分けられる
  /// ようにする。
  late final PreviewBusyTracker _busy = PreviewBusyTracker(() {
    if (mounted) setState(() {});
  });

  /// 元画像の読み込みが長引いたら、before 側に札を出す（#185）。
  late final PreviewBusyTracker _beforeBusy = PreviewBusyTracker(() {
    if (mounted) setState(() {});
  });

  /// 描画 1 回が長時間終わらないとき診断ログへ残す（#185。リリースでも有効）。
  final PreviewRenderWatchdog _watchdog =
      PreviewRenderWatchdog(view: 'before_after');

  /// 元画像の読み込み用（段は `load`）。
  final PreviewRenderWatchdog _loadWatchdog =
      PreviewRenderWatchdog(view: 'before_after');

  /// 診断ログに添える入力の要約（カタログ id・層の数・強度・サンプル id・寸法。ユーザー
  /// 画像は `user` とだけ書く）。
  Map<String, Object?> _diagFields(int sampleSize) {
    final source = widget.imageSource;
    return {
      'filter': widget.layerIds?.join('+') ?? widget.filterId ?? 'none',
      'steps': widget.steps?.length,
      'strength': widget.strength.toStringAsFixed(2),
      'sample':
          source is SamplePreviewImageSource ? source.sampleId : 'user',
      'size': sampleSize,
    };
  }

  /// The sample size to render at when [BeforeAfterView.sampleSize] isn't
  /// explicitly set — [kCanonicalSampleSize] in production;
  /// tests can override via the widget's `sampleSize` constructor param.
  int get _effectiveSampleSize =>
      widget.sampleSize ?? kCanonicalSampleSize;

  bool _beforeMatches(PreviewImageSource source, int size) =>
      _before != null &&
      _currentImageSource == source &&
      _currentSampleSize == size;

  @override
  void initState() {
    super.initState();
    _requestBefore();
    _scheduleRebuild(_effectiveSampleSize);
  }

  @override
  void didUpdateWidget(BeforeAfterView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sampleSize != widget.sampleSize ||
        oldWidget.imageSource != widget.imageSource) {
      _requestBefore();
    }
    if (oldWidget.filter != widget.filter ||
        oldWidget.filterId != widget.filterId ||
        oldWidget.variantId != widget.variantId ||
        oldWidget.strength != widget.strength ||
        !listEquals(oldWidget.steps, widget.steps) ||
        oldWidget.sampleSize != widget.sampleSize ||
        oldWidget.imageSource != widget.imageSource) {
      _scheduleRebuild(_effectiveSampleSize);
    }
  }

  // ── 元画像（before）の読み込み（#185 (c)） ──

  /// いまの `widget.imageSource` の元画像が無ければ読み込みを始める。after の描画とは
  /// 別に走る（読み込みは軽い。重いのは after の CPU 描画）。後から別の元画像を頼まれたら、
  /// 先の読み込みの結果は捨てる（最新優先）。
  void _requestBefore() {
    final source = widget.imageSource;
    final size = _effectiveSampleSize;
    if (_beforeMatches(source, size)) {
      if (_beforeLoading != null) {
        // 読み込み中の別の元画像は要らなくなった（元に戻した）。
        _beforeGeneration++;
        _beforeLoading = null;
        _loadWatchdog.finish('superseded');
        _beforeBusy.end();
      }
      return;
    }
    if (_beforeLoading == (source, size)) return;
    final generation = ++_beforeGeneration;
    _beforeLoading = (source, size);
    _beforeBusy.begin();
    _loadWatchdog.start(_diagFields(size));
    _loadWatchdog.stage = 'load';
    unawaited(_loadBefore(generation, source, size));
  }

  Future<void> _loadBefore(
      int generation, PreviewImageSource source, int size) async {
    final ui.Image image;
    try {
      image = await loadPreviewImage(source, size);
    } catch (e, st) {
      if (generation != _beforeGeneration || !mounted) return;
      _loadWatchdog.finish('error');
      _beforeLoading = null;
      _beforeBusy.end();
      PreviewDiagnostics.recordError('preview_failed', e,
          {'view': 'before_after', 'stage': 'load', ..._loadWatchdog.fields});
      // 静かに握りつぶさず Flutter のエラー報告経路に乗せる（crash reporting 等が拾えるように）。
      FlutterError.reportError(FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'before_after_view',
      ));
      // 自動では再試行しない。次の入力の変化（[_rebuild] が [_requestBefore] を呼ぶ）で読み直す。
      _showFailure();
      return;
    }
    if (generation != _beforeGeneration || !mounted) {
      image.dispose();
      return;
    }
    _loadWatchdog.finish('done');
    _beforeLoading = null;
    _beforeBusy.end();
    final old = _before;
    setState(() {
      _before = image;
      _currentImageSource = source;
      _currentSampleSize = size;
    });
    // 描画器へは常に複製を渡し、[_after] も複製から作るので、古い before は誰とも
    // 共有していない。
    old?.dispose();
    // 読み込んだ画像（ユーザー画像）から描いた結果は、元画像を替えたら残さない
    // （サンプルの分はいつでも同じなので残す）。
    _cache.retainWhere(
        (k) => k.source is! UserPreviewImageSource || k.source == source);
    _scheduleRebuild(size);
  }

  // ── after の描画 ──

  /// 描画の入口。まず描画結果のキャッシュ（#185 (b)）を見て、当たればすぐ表示する
  /// （走っている描画があっても待たない。その結果は表示に使わず、キャッシュにだけ入る）。
  /// 外れたら、走っている描画があれば要求を保留に集約し（最新だけが残る）、無ければ始める。
  /// 保留は、走っている描画が終わった時点の `widget.*` で描く（古い控えでは描かない）。
  void _scheduleRebuild(int sampleSize) {
    if (_applyFromCache(sampleSize)) {
      _pendingRebuildSampleSize = null;
      // 走っている描画の結果は古い入力のものなので、表示に使わせない。
      _generation++;
      _busy.end();
      return;
    }
    if (_rebuildInFlight) {
      _pendingRebuildSampleSize = sampleSize;
      return;
    }
    _rebuildInFlight = true;
    unawaited(_runRebuild(sampleSize));
  }

  /// いまの入力の描画結果がキャッシュにあれば表示して true。
  bool _applyFromCache(int sampleSize) {
    if (!mounted || !_beforeMatches(widget.imageSource, sampleSize)) {
      return false;
    }
    final input = _RenderInput(widget, widget.imageSource, sampleSize);
    final key = input.cacheKey;
    if (key == null) return false;
    final hit = _cache.lookup(key);
    if (hit == null) return false;
    _applyAfter(hit, input, provisional: false);
    return true;
  }

  Future<void> _runRebuild(int sampleSize) async {
    _busy.begin();
    _watchdog.start(_diagFields(sampleSize));
    var outcome = 'error';
    try {
      await _rebuild(sampleSize);
      outcome = 'done';
    } catch (e, st) {
      // 描画の段取りそのものの例外（描画器の例外は [_rebuild] の中で失敗表示にしている）。
      // unawaited の未処理例外にせず、Flutter のエラー報告へ流す。
      PreviewDiagnostics.recordError(
          'preview_error', e, {'view': 'before_after', ..._watchdog.fields});
      FlutterError.reportError(FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'before_after_view',
      ));
    } finally {
      _watchdog.finish(outcome);
      // 例外で終わっても _rebuildInFlight を戻し、保留中の要求も流す（取りこぼすと、
      // 以後の要求が集約されたまま実行されず、次の操作まで追いつかない）。
      _rebuildInFlight = false;
      if (mounted) {
        final pending = _pendingRebuildSampleSize;
        if (pending != null) {
          _pendingRebuildSampleSize = null;
          _busy.pause();
          _scheduleRebuild(pending);
        } else {
          _busy.end();
        }
      }
    }
  }

  /// 最新の要求の描画が失敗したら呼ぶ。after を失敗表示にする（古い・不整合な画像を
  /// 出し続けない）。自動では再試行しない（次の入力の変化で [_scheduleRebuild] が呼ばれる）。
  /// 新しい要求に追い越されていれば何もしない。
  void _onRebuildFailed(int generation) {
    if (generation != _generation || !mounted) return;
    _showFailure();
  }

  void _showFailure() {
    final oldAfter = _after;
    setState(() {
      _failed = true;
      _after = null;
      _afterProvisional = false;
    });
    oldAfter?.dispose();
  }

  /// [image]（持ち主はこのビューへ移る）を after として表示する。
  void _applyAfter(ui.Image image, _RenderInput input,
      {required bool provisional}) {
    final oldAfter = _after;
    setState(() {
      _after = image;
      _afterProvisional = provisional;
      _afterFilterId = input.filterId; // #60
      _afterVariantId = input.variantId; // #60
      _afterStrength = input.strength;
      _afterFilter = input.filter; // #76
      _afterExportLayers = input.exportLayers; // #121
      _failed = false; // 成功したら失敗表示を解除する。
    });
    if (oldAfter != null && !identical(oldAfter, image)) oldAfter.dispose();
  }

  /// after を 1 回描く。
  ///
  /// 入力（[_RenderInput]）は冒頭で一度だけ読んで固定する。元画像がまだ読み込めて
  /// いなければ描かずに戻る（読み込みが終わると [_loadBefore] が描画を頼み直す）。
  /// 描画器には常に [_before] の複製を渡す（await の間に新しい元画像が読み込まれて
  /// [_before] が dispose されても、描画中の入力は生きている）。
  ///
  /// 重い入力（[previewInputIsHeavy]、または直前のフル解像度の描画が
  /// [kProvisionalRenderAfter] を越えたとき）は、先に [kProvisionalPreviewSize] で描いて
  /// 仮表示し、その後フル解像度で描いて差し替える（#185 (a)）。仮表示の後に新しい要求が
  /// 来ていれば、フル解像度は描かずに次の要求へ譲る。フル解像度の結果は、追い越されて
  /// いてもキャッシュには入れる（同じ入力に戻ったとき描き直さない）。
  Future<void> _rebuild(int sampleSize) async {
    final hook = debugBeforeAfterRebuildHook;
    if (hook != null) await hook();
    if (!mounted) return;
    final generation = ++_generation;
    final input = _RenderInput(widget, widget.imageSource, sampleSize);
    final before = _before;
    if (before == null || !_beforeMatches(input.source, sampleSize)) {
      _requestBefore();
      return;
    }
    final key = input.cacheKey;
    if (key != null) {
      final hit = _cache.lookup(key);
      if (hit != null) {
        _applyAfter(hit, input, provisional: false);
        return;
      }
    }

    // ここから先の await の間に [_before] が入れ替わって dispose されても困らないよう、
    // 描画器の入力は今のうちに複製しておく。
    final fullInput = before.clone();
    bool superseded() =>
        generation != _generation ||
        !mounted ||
        _pendingRebuildSampleSize != null;

    final slowLast = (_lastFullRender ?? Duration.zero) >= kProvisionalRenderAfter;
    if (key != null &&
        sampleSize > kProvisionalPreviewSize &&
        (input.heavy || slowLast)) {
      _watchdog.stage = 'provisional';
      final small = downscalePreviewImage(fullInput, kProvisionalPreviewSize);
      ui.Image? low;
      try {
        low = await input.render(small);
      } catch (e) {
        // 仮表示の失敗は表示に出さない（続けてフル解像度で描く）。記録だけ残す。
        PreviewDiagnostics.recordError('preview_failed', e, {
          'view': 'before_after',
          'stage': 'provisional',
          ..._watchdog.fields,
        });
      } finally {
        if (!identical(low, small)) small.dispose();
      }
      if (low != null) {
        if (superseded()) {
          low.dispose();
        } else {
          _applyAfter(low, input, provisional: true);
        }
      }
      if (superseded()) {
        fullInput.dispose();
        return;
      }
    }

    _watchdog.stage = 'render';
    final watch = Stopwatch()..start();
    ui.Image? after;
    try {
      after = await input.render(fullInput);
    } catch (e, st) {
      PreviewDiagnostics.recordError('preview_failed', e,
          {'view': 'before_after', 'stage': 'render', ..._watchdog.fields});
      FlutterError.reportError(FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'before_after_view',
      ));
      fullInput.dispose();
      _onRebuildFailed(generation);
      return;
    }

    // 描画器の型は null を許す（[AfterImageRenderer]）が、null は「after 画像が
    // 無い」状態で、空の枠を成功として出してしまう。例外と同じ失敗として扱う（#45）。
    if (after == null) {
      PreviewDiagnostics.record('preview_failed', {
        'view': 'before_after',
        'stage': 'render',
        'error': 'null_result',
        ..._watchdog.fields,
      });
      FlutterError.reportError(FlutterErrorDetails(
        exception: StateError('after renderer returned null'),
        library: 'before_after_view',
      ));
      fullInput.dispose();
      _onRebuildFailed(generation);
      return;
    }
    // 描画器が入力をそのまま返した（何も掛けない）ときは、その複製が結果になる。
    if (!identical(after, fullInput)) fullInput.dispose();
    _lastFullRender = watch.elapsed;
    // 外された後はキャッシュ（dispose で空にした）へ入れない（入れると誰も捨てない）。
    if (key != null && mounted) _cache.store(key, after);

    if (generation != _generation || !mounted) {
      // 追い越された・外された。表示には使わない（キャッシュには入れた）。
      after.dispose();
      return;
    }
    _applyAfter(after, input, provisional: false);
  }

  @override
  void dispose() {
    _busy.dispose();
    _beforeBusy.dispose();
    _watchdog.dispose();
    _loadWatchdog.dispose();
    _cache.clear();
    _before?.dispose();
    _after?.dispose();
    super.dispose();
  }

  /// Exports the current "after" image as a PNG with burned-in metadata (#43).
  ///
  /// i18n は **UI 側でここで解決** し、`ExportCaption`（解決済み文字列）として
  /// pure な [exportImageComposer] に渡す（規律2）。保存後はフルパスをテキストとして
  /// クリップボードへコピーし、SnackBar で結果を知らせる。画像そのものの
  /// クリップボード書き込みはプラグインを要し環境変更になるため非スコープ。
  ///
  /// caption は [_afterFilterId]/[_afterVariantId]/
  /// [_afterStrength]（`_after` を描画した時点の値）から作る。
  /// `widget.filterId`/`widget.variantId`/`widget.strength`
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
    final variantId = _afterVariantId;
    final afterFilter = _afterFilter;
    final exportLayers = _afterExportLayers;
    setState(() => _exporting = true);

    final messenger = ScaffoldMessenger.of(context);
    Uint8List? encoded;
    String? encodedName;
    try {
      final now = DateTime.now();
      final date = isoDate(now);
      final plan = planExport(
        l10n,
        layers: exportLayers,
        filterId: filterId,
        variantId: variantId,
        filter: afterFilter,
        strength: strength,
        isoDate: date,
      );

      final composed = await composeCaptionedExportImage(base, plan.caption);
      final bytes = await encodePngAndDispose(composed);

      final filename = exportFilename(
        symptomId: plan.symptomId,
        strengthPercent: plan.strengthPercent,
        isoDate: date,
        // #64: 同じ日に何度書き出しても別名になるよう時刻も入れる（それでも
        // 衝突したら savePng が連番にする）。焼き込むキャプションは日付のみ。
        time: compactTime(now),
      );
      encoded = bytes;
      encodedName = filename;
      final path = await saveExportPng(bytes, filename);

      if (!mounted) return;
      showExportSuccess(messenger, l10n, path);
    } catch (e) {
      if (!mounted) return;
      showExportFailure(
        messenger,
        l10n,
        e,
        bytes: encoded,
        filename: encodedName,
        onSaved: (path) => showExportSuccess(messenger, l10n, path),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    // The CPU preview renders at a canonical fixed size
    // (see [kCanonicalSampleSize]) regardless of the pane's
    // layout size or devicePixelRatio — LayoutBuilder here only decides
    // whether to stack the panes, it no longer drives sample-size generation
    // (the pre-#85 GPU-era `_recordPaneLayout`/auto-resize machinery, #58,
    // was removed along with it). The rendered image is simply scaled to fit
    // the pane (`_UiImagePainter.paint`, `FilterQuality.medium`).
    return LayoutBuilder(
      builder: (context, constraints) {
        // Stack the two panes vertically on narrow widths.
        final stackVertically = constraints.maxWidth < 420;

        if (_before == null && !_failed) {
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
          // 元画像の読み込みが長引いたら、before 側にも札を出す（#185）。
          child: PreviewBusyOverlay(
            label: _beforeBusy.showing ? l10n.previewLoadingSource : null,
            child: PreviewImageView(image: _before),
          ),
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
            : visionFilterDisplayName(l10n, widget.variantId, widget.filterId);
        final Widget afterImage = _failed
            ? PreviewErrorPlaceholder(theme: theme, label: l10n.previewFailed)
            : PreviewImageView(
                image: _after,
                // 何も選んでいないとき after は原画と同じで、見出し（afterName）が
                // 説明を担うので付けない（二重読み上げの回避）。
                // （`_after` は成功時にだけ非 null で代入され、描画器が null を返した
                // 場合も `_rebuild` が失敗として扱い `_failed` 分岐に入るので、
                // ここで画像が無いことはない。）
                semanticLabel:
                    widget.filterId == null && widget.variantId == null
                        ? null
                        // 複数層の代替テキストは、まとめずに全部の名前を読ませる。
                        : l10n.previewImageFilteredSemantics(
                            multiLayer ? layerNames.join(' + ') : afterName),
              );
        // 描画が長引いている間・低解像度の仮表示の間は、after の上に札を重ねる（#185）。
        final Widget afterChild = PreviewBusyOverlay(
          label: _afterProvisional
              ? l10n.previewRenderingProvisional
              : (_busy.showing ? l10n.previewRendering : null),
          child: afterImage,
        );
        // #60: 時間依存の注記は widget.filterId（カタログ id）からカタログを
        // 引いて解決する。after ペインの見出しは widget.variantId が
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
          // 低解像度の仮表示（#185）は書き出さない（フル解像度の結果を待つ）。
          trailing: _after != null && !_afterProvisional
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
                      const SizedBox(width: kBeforeAfterPaneGap),
                      Expanded(child: afterPane.buildHeading(context)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: beforePane.buildImage()),
                      const SizedBox(width: kBeforeAfterPaneGap),
                      Expanded(child: afterPane.buildImage()),
                    ],
                  ),
                ],
              );

        // 上限（maxPaneSide）を越える幅のときは、2 枚を中央に寄せて画像を小さくする。
        final maxSide = widget.maxPaneSide;
        final Widget sizedPanes = stackVertically || maxSide == null
            ? panes
            : Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 2 * maxSide + kBeforeAfterPaneGap,
                  ),
                  child: panes,
                ),
              );

        // #60: vertigo / bppv_rotation のような時間依存フィルタは、CPU
        // プレビュー（時刻を受け取らず常に同じ内部時刻で描画する、
        // `CpuVisionRenderer` の doc 参照）では静止フレームにしかならない。
        // その旨を短く注記する。
        if (showsStaticFrameNote) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              sizedPanes,
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
        return sizedPanes;
      },
    );
  }
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

