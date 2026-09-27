import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../src/rust/api/sensus_bridge.dart';

/// [CpuVisionRenderer.apply] の型（テストでフェイクに差し替えるための seam。
/// `before_after_view.dart` の `AfterImageRenderer` と同じパターン）。
typedef VisionCpuApplier = Future<ui.Image> Function(
  ui.Image source,
  VisionFilter filter,
  double strength,
);

/// sensus の CPU `apply()`（`applyVisionCpuRgba8`）で静止画プレビューを描画する
/// レンダラ（#85）。
///
/// **プレビュー（静止画）はこちらが正本**。sensus の全 [VisionFilter]（30 種、
/// payload 込み）を描画できる。GPU（`shader_filter.dart` の `ShaderFilter`、#59）
/// は一部フィルタ・一部表現（`VisionFieldLossMode.blur` 等）に対応しないため、
/// ルーペのライブ表示専用に位置づけを変える。
///
/// `applyVisionCpuRgba8` は非同期公開（`#[frb(sync)]` を外した、#85）なので、
/// Rust 側スレッドプールで実行され、待っている間 UI スレッドを塞がない。
class CpuVisionRenderer {
  CpuVisionRenderer._();

  /// [apply] の供給源。`before_after_view.dart` の `renderAfter` はこれ経由で
  /// 呼ぶため production コードからも参照される（`sampleImageGenerator` /
  /// `afterImageRenderer` と同じ seam パターン、#58）。テストはこれをフェイクへ
  /// 差し替えて実ブリッジなしにマッピング契約を検証できる。production は
  /// そのまま既定値（[apply] 自身）を使う。
  static VisionCpuApplier applier = apply;

  /// [source] に [filter] を [strength]（0.0..=1.0）で適用した新しい [ui.Image]
  /// を返す。
  ///
  /// 内部で [source] を raw RGBA8 バイト列へ変換 → `applyVisionCpuRgba8` を
  /// 呼ぶ → 結果バイト列を新しい [ui.Image] に戻す、という往復を行う。
  /// アルゴリズムはここに一切持たない（正本は sensus_core、strength の
  /// clamp/NaN 処理も sensus 側の責務）。
  static Future<ui.Image> apply(
    ui.Image source,
    VisionFilter filter,
    double strength,
  ) async {
    final rgba8 = await imageToRgba8(source);
    final outBytes = await applyVisionCpuRgba8(
      filter: filter,
      rgba8: rgba8,
      width: source.width,
      height: source.height,
      strength: strength,
    );
    return rgba8ToImage(outBytes, source.width, source.height);
  }

  /// [image] を straight（非 premultiplied）RGBA8 の生バイト列に変換する。
  ///
  /// `@visibleForTesting`: 往復変換（このメソッドと [rgba8ToImage]）の忠実性を
  /// 実ブリッジなしで単体テストできるようにするため公開する。
  @visibleForTesting
  static Future<Uint8List> imageToRgba8(ui.Image image) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      throw StateError('ui.Image から raw RGBA バイト列を取得できなかった');
    }
    return byteData.buffer.asUint8List();
  }

  /// straight RGBA8 の生バイト列（[imageToRgba8] と同じレイアウト）から
  /// [ui.Image] を組み立てる。
  @visibleForTesting
  static Future<ui.Image> rgba8ToImage(
    Uint8List rgba8,
    int width,
    int height,
  ) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba8,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }
}
