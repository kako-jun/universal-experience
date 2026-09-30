import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/preview_image_source.dart';
import '../../models/vision_filter_contract_notes.dart' as contract_notes;
import '../../services/color_vision_compare.dart';
import '../../services/export_layers.dart';
import '../../services/export_service.dart';
import '../../services/vision_layer.dart';
import '../../src/rust/api/sensus_bridge.dart' show VisionStep;
import 'before_after_view.dart';

/// [ColorVisionCompareView] の書き出しファイル名に入れる識別子（`exportFilename` の
/// `symptomId`）。単独の型ではなく 4 型の比較であることを名前で区別する。
const String kColorVisionCompareExportId = 'color-vision-compare';

/// 色覚 4 型（protanopia / deuteranopia / tritanopia / achromatopsia）を、同じ画像・
/// 同じ強さで 2×2 に並べて比べるビュー（#84）。中央「見る」カラムで
/// [BeforeAfterView] の代わりに出る（切替は `home_screen.dart`、関係は
/// `docs/adr/2026-09-30-color-vision-2x2-compare.md`）。
///
/// 描画も書き出しも **既存の経路をそのまま使う**。専用のレンダラは持たない:
/// - 画像の読み込みと描画は [loadPreviewImage] / [renderPreviewAfter]
///   （= sensus の CPU `apply()`）を 4 回呼ぶ。
/// - 各セルの焼き込みは [buildExportCaption] + [composeCaptionedExportImage]（#43/#80 の
///   「シミュレーション（近似）」を含む、1 枚ずつ書き出すときと同じキャプション）。
///   4 枚を [composeCompareGrid] で 1 枚に並べ、保存と通知は
///   [savePngWithClipboard] / [showExportSuccess]（単独の書き出しと共通）。
///
/// 並べる型は `kColorVisionCompareEntries`（カタログが正本）、強さは全セル共通で
/// [strength] を受け取る（色覚層の強度。`colorVisionCompareInputOf` が決める）。
/// このウィジェットは選択状態を読まない presentational な部品。
///
/// **他の層を重ねているとき（#122）**: 4 セルは、色覚以外の層（[baseSteps]、適用順）を
/// **1 回だけ**合成した画像（土台）を共通の出発点にして、その上に色覚 4 型を 1 枚ずつ
/// 適用したもの。土台は (steps, サイズ, 元画像) が同じ間は使い回し、色覚の強さだけが動く
/// ときは再合成しない（セルごとの描画コストは色覚 1 回ぶんのまま）。[baseSteps] が空なら
/// 土台 = 原画（従来どおり）。土台・強さ・層の控えは描画した時点の値で固定し、書き出しは
/// それを使う（[_afterStrength] / [_afterBaseLayers]）。
///
/// 並行制御は [BeforeAfterView] と同じ「直列・最新優先」: 描画中に入力が変わったら
/// 途中の結果は捨て、進行中の 1 本が終わってから最新の入力で 1 回だけやり直す
/// （4 セルぶんの CPU 描画が同時に走らない）。描画中は直前の表示を残す。
class ColorVisionCompareView extends StatefulWidget {
  const ColorVisionCompareView({
    super.key,
    required this.strength,
    required this.imageSource,
    this.baseSteps = const [],
    this.baseLayers = const [],
    this.sampleSize,
  });

  /// 4 セル共通の強さ 0.0..1.0（色覚層の強度）。
  final double strength;

  /// 4 型の前に 1 回だけ適用する層のステップ列（適用順、強度 0 は除いたもの、#122）。
  /// 空なら土台 = 原画。
  final List<VisionStep> baseSteps;

  /// [baseSteps] と同じ層の控え（書き出しのキャプション・ファイル名と注記の素）。
  /// [ColorVisionCompareInput.baseLayers] と同じ。
  final List<ExportLayer> baseLayers;

  /// 4 セルが共通で使う元画像（サンプル or 読み込んだ画像、#78）。
  final PreviewImageSource imageSource;

  /// テスト用の描画解像度（正方形の一辺）。null（本番）は
  /// [BeforeAfterView.canonicalSampleSize]。
  final int? sampleSize;

  @override
  State<ColorVisionCompareView> createState() => _ColorVisionCompareViewState();
}

class _ColorVisionCompareViewState extends State<ColorVisionCompareView> {
  /// 描画の入力にする原画（正方形に収めたもの）。表示には使わない。
  ui.Image? _before;

  /// [_before] を作ったときのサイズ・元画像（再利用の判定用）。
  int? _currentSampleSize;
  PreviewImageSource? _currentImageSource;

  /// 土台（[_before] に [ColorVisionCompareView.baseSteps] を 1 回適用した画像、#122）。
  /// まだ作っていない間は null。steps が空の間は使わず（土台 = [_before]）、ソース・サイズが
  /// 変わるか dispose されるまで保持する。表示には使わない。
  ui.Image? _baseImage;

  /// [_baseImage] を作ったときの入力（再利用の判定用）。
  List<VisionStep>? _baseImageSteps;
  int? _baseImageSize;
  PreviewImageSource? _baseImageSource;

  /// 表示中の 4 セル（[kColorVisionCompareEntries] と同じ順）。まだ 1 回も
  /// 成功していない・最新の描画が失敗した間は null。
  List<ui.Image>? _afters;

  /// [_afters] を描画したときの強さ。書き出しのキャプションはこれから作る
  /// （widget.strength は描画より先に進んでいることがあるため、
  /// [BeforeAfterView] と同じ理由）。
  double? _afterStrength;

  /// [_afters] を描画したときの、土台に入っている層（強度が表示上 0 より大きいもの、適用順）。
  /// 書き出しのキャプション・ファイル名と、土台の注記はこれから作る（[_afterStrength] と同じ理由）。
  List<ExportLayer>? _afterBaseLayers;

  /// 最新の描画が失敗したか。次の入力の変化で再試行するまで残る（自動リトライしない）。
  bool _failed = false;

  bool _exporting = false;

  int _generation = 0;
  bool _rebuildInFlight = false;

  /// 描画中に新しい要求が来たか。来ていたら進行中の描画は途中で打ち切る。
  bool _rebuildPending = false;

  int get _effectiveSampleSize =>
      widget.sampleSize ?? BeforeAfterView.canonicalSampleSize;

  @override
  void initState() {
    super.initState();
    _scheduleRebuild();
  }

  @override
  void didUpdateWidget(ColorVisionCompareView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.strength != widget.strength ||
        oldWidget.sampleSize != widget.sampleSize ||
        oldWidget.imageSource != widget.imageSource ||
        !listEquals(oldWidget.baseSteps, widget.baseSteps) ||
        !listEquals(
            _layerKeys(oldWidget.baseLayers), _layerKeys(widget.baseLayers))) {
      _scheduleRebuild();
    }
  }

  static List<String> _layerKeys(List<ExportLayer> layers) =>
      [for (final l in layers) l.layer.strengthKey];

  void _scheduleRebuild() {
    if (_rebuildInFlight) {
      _rebuildPending = true;
      return;
    }
    _rebuildInFlight = true;
    unawaited(_runRebuild());
  }

  Future<void> _runRebuild() async {
    try {
      await _rebuild();
    } finally {
      _rebuildInFlight = false;
    }
    if (!mounted) return;
    if (_rebuildPending) {
      _rebuildPending = false;
      _scheduleRebuild();
    }
  }

  void _reportError(Object e, StackTrace st) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'color_vision_compare_view',
      ),
    );
  }

  void _onRebuildFailed(int generation) {
    if (generation != _generation || !mounted) return;
    // すぐ後ろに新しい入力の描画が控えている間は、失敗を出さない（表示中の画像を
    // 残す）。スライダーのドラッグ中に、打ち切り直前の 1 回の失敗が失敗表示を
    // 点滅させるのを防ぐ。最新の入力の描画が失敗したときだけ失敗を出す。
    if (_rebuildPending) return;
    final old = _afters;
    setState(() {
      _failed = true;
      _afters = null;
      _afterStrength = null;
      _afterBaseLayers = null;
    });
    if (old != null) {
      for (final image in old) {
        image.dispose();
      }
    }
  }

  /// 4 型を順に描画して、全部そろったら表示を差し替える。
  ///
  /// 入力（元画像・強さ・サイズ）は冒頭で固定する。await の間に widget が
  /// 先へ進んでも、この 1 回は固定した入力のまま最後まで描く（途中で
  /// [_rebuildPending] が立ったら打ち切る）。
  Future<void> _rebuild() async {
    if (!mounted) return;
    final generation = ++_generation;
    final source = widget.imageSource;
    final strength = widget.strength;
    final size = _effectiveSampleSize;
    // 土台の入力も冒頭で固定する（await の間に widget が先へ進んでも、この 1 回は固定した値）。
    final baseSteps = List<VisionStep>.unmodifiable(widget.baseSteps);
    final baseLayers = effectiveExportLayers(widget.baseLayers);

    final ui.Image before;
    if (_before != null &&
        _currentSampleSize == size &&
        _currentImageSource == source) {
      before = _before!;
    } else {
      try {
        before = await loadPreviewImage(source, size);
      } catch (e, st) {
        _reportError(e, st);
        _onRebuildFailed(generation);
        return;
      }
      if (generation != _generation || !mounted) {
        before.dispose();
        return;
      }
      // 原画は表示に使わないので、読み込めた時点で入れ替えてよい
      // （途中で打ち切られても次の回が再利用できる）。
      final old = _before;
      _before = before;
      _currentSampleSize = size;
      _currentImageSource = source;
      old?.dispose();
    }

    // 土台: steps が空なら原画、あれば 1 回だけ合成（同じ入力の間は使い回す）。
    // 保持した土台を捨てるのはソース・サイズが変わったときと dispose のときだけ。
    // steps が空の間（原画比較のホールド中など）も捨てずに持ち、解除後に層が
    // 変わっていなければ CPU 再合成しない（空 steps の間は土台を使わず原画を使う）。
    if (_baseImage != null &&
        (_baseImageSize != size || _baseImageSource != source)) {
      final stale = _baseImage;
      _baseImage = null;
      _baseImageSteps = null;
      stale?.dispose();
    }
    final ui.Image base;
    if (baseSteps.isEmpty) {
      base = before;
    } else if (_baseImage != null &&
        _baseImageSize == size &&
        _baseImageSource == source &&
        listEquals(_baseImageSteps, baseSteps)) {
      base = _baseImage!;
    } else {
      // renderer に渡すのは複製（原画は以降も使う）。
      final input = before.clone();
      ui.Image? composed;
      try {
        composed = await BeforeAfterView.renderAfterPipeline(input, baseSteps);
        if (composed == null) {
          throw StateError('Renderer returned no base image');
        }
      } catch (e, st) {
        _reportError(e, st);
        _onRebuildFailed(generation);
        return;
      } finally {
        if (!identical(composed, input)) input.dispose();
      }
      if (generation != _generation || !mounted) {
        composed.dispose();
        return;
      }
      final old = _baseImage;
      _baseImage = composed;
      _baseImageSteps = baseSteps;
      _baseImageSize = size;
      _baseImageSource = source;
      old?.dispose();
      base = composed;
    }

    final produced = <ui.Image>[];
    void discardProduced() {
      for (final image in produced) {
        image.dispose();
      }
    }

    for (final entry in kColorVisionCompareEntries) {
      // 新しい要求が来ている（またはビューが外れた）なら、残りは描かずに捨てる。
      if (_rebuildPending || !mounted) {
        discardProduced();
        return;
      }
      // renderer に渡すのは複製（土台は次のセルでも使う。await の間に
      // 別の入れ替えで dispose されても複製は生きている）。
      final input = base.clone();
      ui.Image? after;
      try {
        after = await renderPreviewAfter(
          input,
          colorVisionCompareFilter(entry),
          strength,
        );
        if (after == null) {
          throw StateError('Renderer returned no image for ${entry.id}');
        }
      } catch (e, st) {
        _reportError(e, st);
        discardProduced();
        _onRebuildFailed(generation);
        return;
      } finally {
        // renderer が入力をそのまま返したときだけ、その複製が結果になる。
        if (!identical(after, input)) input.dispose();
      }
      produced.add(after);
    }

    if (generation != _generation || !mounted) {
      discardProduced();
      return;
    }
    final old = _afters;
    setState(() {
      _afters = produced;
      _afterStrength = strength;
      _afterBaseLayers = baseLayers;
      _failed = false;
    });
    if (old != null) {
      for (final image in old) {
        image.dispose();
      }
    }
  }

  @override
  void dispose() {
    _before?.dispose();
    _baseImage?.dispose();
    final afters = _afters;
    if (afters != null) {
      for (final image in afters) {
        image.dispose();
      }
    }
    super.dispose();
  }

  /// 4 セルを 1 枚の PNG に合成して書き出す（#84）。
  ///
  /// 単独の書き出し（[BeforeAfterView] の `_export`）と同じ規約:
  /// - キャプションは **描画した時点の強さ**（[_afterStrength]）と土台の層（[_afterBaseLayers]）
  ///   から作る。widget の値は使わない。土台が無ければ従来どおり 1 型ずつの
  ///   [buildExportCaption]。土台があれば [buildLayeredExportCaption]（土台の層の行 + そのセルの
  ///   色覚の行。色覚の強度が 0% でも、画像と同じく行は残す）。
  /// - ファイル名は土台が無ければ従来どおり（[kColorVisionCompareExportId] + 強度の %）。
  ///   あれば [exportSymptomId] で「比較の印 + 土台の層の id（適用順）」をつなぐ（強度の % は
  ///   層ごとに違うので付けない。上限で落ちるのは末尾の層だけで、先頭の印は残る）。
  /// - 表示中の画像は書き出しの途中で入れ替わって破棄されうるので、開始時に複製する。
  /// - 二重起動しない。失敗（描画・合成・エンコード・保存のどれでも）は
  ///   [AppLocalizations.exportFailure] の SnackBar で知らせ、成功は保存先と
  ///   「フォルダで表示」（[showExportSuccess]）で知らせる。
  Future<void> _export(AppLocalizations l10n) async {
    final afters = _afters;
    final strength = _afterStrength;
    final baseLayers = _afterBaseLayers;
    if (afters == null ||
        strength == null ||
        baseLayers == null ||
        _exporting) {
      return;
    }
    setState(() => _exporting = true);
    final clones = [for (final image in afters) image.clone()];
    final composedCells = <ui.Image>[];
    final messenger = ScaffoldMessenger.of(context);
    try {
      final now = DateTime.now();
      final date = isoDate(now);
      for (var i = 0; i < kColorVisionCompareEntries.length; i++) {
        final entry = kColorVisionCompareEntries[i];
        final filter = colorVisionCompareFilter(entry);
        final caption = baseLayers.isEmpty
            ? buildExportCaption(
                l10n,
                filterId: entry.id,
                colorVisionType: null,
                filter: filter,
                strength: strength,
                isoDate: date,
              )
            : buildLayeredExportCaption(
                l10n,
                layers: [
                  ...baseLayers,
                  ExportLayer(
                    layer: VisionLayer(id: entry.id),
                    filter: filter,
                    strength: strength,
                  ),
                ],
                isoDate: date,
              );
        composedCells
            .add(await composeCaptionedExportImage(clones[i], caption));
      }
      final grid = await composeCompareGrid(composedCells);
      final bytes = await encodePngAndDispose(grid);
      final filename = exportFilename(
        symptomId: baseLayers.isEmpty
            ? kColorVisionCompareExportId
            : exportSymptomId([
                kColorVisionCompareExportId,
                for (final l in baseLayers) l.layer.strengthKey,
              ]),
        strengthPercent: baseLayers.isEmpty
            ? contract_notes.strengthPercent(strength)
            : null,
        isoDate: date,
        time: compactTime(now),
      );
      final path = await savePngWithClipboard(bytes, filename);
      if (!mounted) return;
      showExportSuccess(messenger, l10n, path);
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.exportFailure)));
    } finally {
      for (final image in clones) {
        image.dispose();
      }
      for (final image in composedCells) {
        image.dispose();
      }
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final afters = _afters;

    if (afters == null && !_failed) {
      // 最初の描画が終わるまでの、動かないプレースホルダ（アニメーションする
      // インジケータは widget test の pumpAndSettle を止めてしまう）。
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

    // 強さの表示は「いま見えている画像」に対応する値（描画した時点の強さ）にする。
    // 再描画の待ちの間に widget.strength だけ先へ進んでも、新しい強さを古い画像に
    // 被せない。まだ描けていない・失敗した間は入力の強さを出す。
    final percent =
        contract_notes.strengthPercent(_afterStrength ?? widget.strength);
    final entries = kColorVisionCompareEntries;
    final shownBaseLayers =
        _afterBaseLayers ?? effectiveExportLayers(widget.baseLayers);
    final cells = <Widget>[
      for (var i = 0; i < entries.length; i++)
        _CompareCell(
          label: visionFilterName(l10n, entries[i].id),
          semanticsLabel: afters == null
              ? l10n.compareCellFailedSemanticsLabel(
                  visionFilterName(l10n, entries[i].id),
                )
              : l10n.compareCellSemanticsLabel(
                  visionFilterName(l10n, entries[i].id),
                  percent,
                ),
          child: afters == null
              ? PreviewErrorPlaceholder(theme: theme, label: l10n.previewFailed)
              : PreviewImageView(image: afters[i]),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.compareSharedStrengthNote(percent),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  // 他の層を重ねているときだけ: 4 枚は、この層を先に適用した画像から始まる。
                  if (shownBaseLayers.isNotEmpty)
                    Text(
                      l10n.compareBaseNote(
                        layerNamesSummary(l10n, [
                          for (final l in shownBaseLayers)
                            visionLayerDisplayName(l10n, l.layer),
                        ]),
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            // 書き出せるのは 4 セルそろって描けているときだけ。
            if (afters != null)
              IconButton(
                icon: const Icon(Icons.download_outlined),
                tooltip: l10n.exportButtonTooltip,
                onPressed: _exporting ? null : () => _export(l10n),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (var row = 0; row < cells.length; row += 2) ...[
          if (row > 0) const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: cells[row]),
              const SizedBox(width: 12),
              Expanded(
                child:
                    row + 1 < cells.length ? cells[row + 1] : const SizedBox(),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 2×2 の 1 セル: 型名の見出し + 正方形の画像。見出しと画像は 1 つの
/// Semantics ノード（[semanticsLabel]）にまとめて読み上げる。
class _CompareCell extends StatelessWidget {
  const _CompareCell({
    required this.label,
    required this.semanticsLabel,
    required this.child,
  });

  final String label;
  final String semanticsLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      image: true,
      label: semanticsLabel,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 32,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                style: theme.textTheme.labelLarge,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
