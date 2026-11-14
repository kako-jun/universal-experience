import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
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
/// 読み上げ対象にしない（周囲の文言が説明を担うとき）。[image] が null の間も読ませない。
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
    // 画像がまだ無い（描画中の空の枠）ときは、画像として読ませない（#185: 元画像の読み込みを
    // 描画から分けたので、after だけが空の時間がある。その間は「描画中…」の札が状態を伝える）。
    if (label == null || img == null) return content;
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

/// 1 回の描画がこの時間を越えて続いたら「描画中…」（[PreviewBusyBadge]）を出す（#185）。
///
/// CPU 描画は途中で止められず、組み合わせによっては 1 回に数十秒かかる（例: 明るい画像に
/// 掛けた starbursts。sensus の starbursts は明るい画素の数に比例して重くなる）。その間は
/// プレビューが変わらないので、止まっているのではなく描いている最中だと見せる。普段の
/// 描画（数十〜数百 ms）では出ないよう、少し待ってから出す。
const Duration kPreviewBusyThreshold = Duration(milliseconds: 500);

/// 描画 1 回が [threshold] を越えて続いているかを数える（#185）。
///
/// 描画を 1 回始めるたびに [begin]、その描画が終わってすぐ次の描画（保留していた要求）が
/// 続くなら [pause]、列が空になったら [end] を呼ぶ。数えるのは**1 回の描画**の時間で、
/// 列全体の時間ではない: 速い描画が続くだけ（スライダーのドラッグ中など）では出さず、
/// 札の出し入れと読み上げを繰り返さない。一度出したら、列が空になる（[end]）まで
/// 出しっぱなしにする（続けて重い描画が流れるときに消えて点き直さない）。
/// 出し入れのたびに [onChanged] が呼ばれる（呼び出し側が `setState` する）。
class PreviewBusyTracker {
  PreviewBusyTracker(this.onChanged, {this.threshold = kPreviewBusyThreshold});

  final VoidCallback onChanged;
  final Duration threshold;

  Timer? _timer;
  bool _showing = false;

  /// 「描画中…」を出すべきか。
  bool get showing => _showing;

  /// 描画を 1 回始めた。出ていなければ、ここから [threshold] を数え直す。
  void begin() {
    if (_showing) return;
    _timer?.cancel();
    _timer = Timer(threshold, () {
      _timer = null;
      _showing = true;
      onChanged();
    });
  }

  /// 描画が走ったまま、まだ追いついていない要求が増えた（保留に積んだ）。札が出ておらず
  /// 時計も止まっていれば、ここから [threshold] を数え始める（走っている描画は止められない
  /// ので、その終わりと次の描画を待つ間も「描画中…」を出せるようにする）。動いている時計は
  /// 数え直さない。
  void resume() {
    if (_showing || _timer != null) return;
    begin();
  }

  /// 描画が 1 回終わり、すぐ次の描画が続く。時計は止めるが、出ている札は消さない。
  void pause() {
    _timer?.cancel();
    _timer = null;
  }

  /// 描画の列が空になった（表示が最新の入力に追いついた）。
  void end() {
    pause();
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
/// 現れたときと文言が変わったときに読み上げる（liveRegion）。明るい画像の上でも
/// 輪郭が分かるよう `outlineVariant` の枠を付ける。
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
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hourglass_top, size: 16, color: scheme.onSurface),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurface),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 画像の上端中央に [PreviewBusyBadge] を重ねる（[label] が null なら重ねない）。
/// 札の有無で子の組み方（ツリーの形）を変えないよう、常に Stack で組む。
class PreviewBusyOverlay extends StatelessWidget {
  const PreviewBusyOverlay({super.key, required this.child, this.label});

  final Widget child;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final label = this.label;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (label != null)
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: PreviewBusyBadge(label: label),
            ),
          ),
      ],
    );
  }
}

/// 重い描画のとき先に描く、低解像度の仮表示の一辺（px、#185）。
///
/// starbursts の計算量は一辺のほぼ 3 乗（明るい画素の数 × 光条の長さ）なので、
/// 1024px の 1/2 で描けば 1/8 程度で済む。仮表示は [PreviewBusyBadge] に
/// 「低解像度の仮表示」と出し、書き出しには使わない。フル解像度の結果が出たら差し替える。
/// 画素数で効き方が決まるフィルタ（[kCanonicalSampleSize] の doc）は、仮表示の間だけ
/// 見え方が少し違うことがある。
const int kProvisionalPreviewSize = 512;

/// 直前のフル解像度の描画がこの時間を越えたら、次の描画も先に低解像度で描く（#185）。
const Duration kProvisionalRenderAfter = Duration(seconds: 2);

/// 入力が重い（先に低解像度で描く）と分かっているフィルタか（#185）。
///
/// starbursts は明るい画像に 1024px で掛けると 1 回に数十秒かかる（kako-jun/sensus#196）。
/// ほかのフィルタは重い画像でも数秒以内（#185 の計測）なので、ここでは名指ししない
/// （それ以外で遅かったときは [kProvisionalRenderAfter] で拾う）。
bool previewInputIsHeavy(VisionFilter? filter, List<VisionStep>? steps) {
  bool heavy(VisionFilter? f) => f is VisionFilter_Starbursts;
  if (steps != null) return steps.any((s) => heavy(s.filter));
  return heavy(filter);
}

/// 正方形の画像を [size]×[size] へ縮める（低解像度の仮表示用、#185）。呼び出し側が
/// 戻り値を dispose する。[source] は dispose しない。`toImageSync` なので待たない。
ui.Image downscalePreviewImage(ui.Image source, int size) {
  final recorder = ui.PictureRecorder();
  final fSize = size.toDouble();
  ui.Canvas(recorder).drawImageRect(
    source,
    Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
    Rect.fromLTWH(0, 0, fSize, fSize),
    Paint()..filterQuality = FilterQuality.medium,
  );
  final picture = recorder.endRecording();
  try {
    return picture.toImageSync(size, size);
  } finally {
    picture.dispose();
  }
}

/// after 画像の描画結果のキャッシュの鍵（#185）: 元画像・解像度・描画の入力
/// （複数層なら合成ステップ列、1 層ならフィルタ + 強度）。どれかが違えば別の画像。
@immutable
class PreviewRenderKey {
  const PreviewRenderKey.single({
    required this.source,
    required this.size,
    required VisionFilter this.filter,
    required double this.strength,
  }) : steps = null;

  const PreviewRenderKey.pipeline({
    required this.source,
    required this.size,
    required List<VisionStep> this.steps,
  })  : filter = null,
        strength = null;

  final PreviewImageSource source;
  final int size;
  final VisionFilter? filter;
  final double? strength;
  final List<VisionStep>? steps;

  @override
  bool operator ==(Object other) =>
      other is PreviewRenderKey &&
      other.source == source &&
      other.size == size &&
      other.filter == filter &&
      other.strength == strength &&
      listEquals(other.steps, steps);

  @override
  int get hashCode => Object.hash(source, size, filter, strength,
      steps == null ? null : Object.hashAll(steps!));
}

/// 描画結果のキャッシュの件数の上限（#185）。1024px の RGBA は 1 枚 4 MiB なので、
/// 最大で約 24 MiB（GPU/ネイティブ側のメモリ）。
const int kPreviewRenderCacheCapacity = 6;

/// after 画像の描画結果を、入力（[PreviewRenderKey]）ごとに覚えておく小さな LRU（#185）。
///
/// 付ける → 外す → 付ける のように同じ入力に戻ったとき、重い CPU 描画をやり直さずに
/// すぐ表示するためのもの。
/// - メモリの中だけに置き、ディスクには書かない。持ち主のビューが外れたら [clear] で全部捨てる。
/// - 件数は [capacity] まで。越えたら最も長く使っていないものから捨てる。
/// - 読み込んだ画像（ユーザー画像）から描いたものは、元画像を切り替えたら捨てる
///   （[retainWhere]。呼び出し側が行う）。
/// - 画像の持ち主はキャッシュ。[lookup] / [store] はどちらも複製をやり取りするので、
///   呼び出し側は受け取った画像を自由に dispose してよい。
class PreviewRenderCache {
  PreviewRenderCache({this.capacity = kPreviewRenderCacheCapacity});

  final int capacity;

  // 挿入順 = 使った順（末尾が最新）。
  final Map<PreviewRenderKey, ui.Image> _entries = {};

  /// いま持っている件数（テスト用）。
  @visibleForTesting
  int get length => _entries.length;

  /// [key] の画像の複製（呼び出し側が持ち主）。無ければ null。
  ui.Image? lookup(PreviewRenderKey key) {
    final image = _entries.remove(key);
    if (image == null) return null;
    _entries[key] = image;
    return image.clone();
  }

  /// [image] の複製を [key] で覚える（[image] 自体は呼び出し側のまま）。
  void store(PreviewRenderKey key, ui.Image image) {
    _entries.remove(key)?.dispose();
    _entries[key] = image.clone();
    while (_entries.length > capacity) {
      final oldest = _entries.keys.first;
      _entries.remove(oldest)!.dispose();
    }
  }

  /// [keep] が false を返す鍵を捨てる。
  void retainWhere(bool Function(PreviewRenderKey key) keep) {
    final drop = [
      for (final k in _entries.keys)
        if (!keep(k)) k,
    ];
    for (final k in drop) {
      _entries.remove(k)!.dispose();
    }
  }

  void clear() {
    for (final image in _entries.values) {
      image.dispose();
    }
    _entries.clear();
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
