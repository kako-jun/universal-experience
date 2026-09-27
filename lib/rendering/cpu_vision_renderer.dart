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
/// プレビューには使わない。`ShaderFilter` 自体は将来のライブ画面キャプチャ
/// （#1/#3/#4）向けに残置してあるが、現状どの production コードからも呼ばれない。
///
/// `applyVisionCpuRgba8` は非同期公開（`#[frb(sync)]` を外した、#85）なので、
/// Rust 側スレッドプールで実行され、待っている間 UI スレッドを塞がない。
///
/// ## alpha の扱い（#85 レビュー S1）
///
/// Flutter の `ui.Image` は内部的に **premultiplied alpha** で GPU テクスチャを
/// 保持する（`ImageByteFormat.rawRgba` で読む生バイト列、`PixelFormat.rgba8888`
/// で書き込む生バイト列のいずれも premultiplied）。一方 sensus（Rust の `image`
/// crate 経由）は **straight（非 premultiplied）alpha** を前提にした画素処理を行う。
/// この前提の食い違いを踏まえず premultiplied のバイト列をそのまま sensus に渡す
/// と、alpha<255 のピクセルで RGB 値が実際より小さく（暗く）解釈され、逆に
/// straight のバイト列をそのまま premultiplied 前提の API に渡すと、alpha<255
/// のピクセルが実際より明るく／不透明に見える色ズレを起こす。
///
/// 本クラスは境界で明示的に変換する:
/// - 入力（[imageToRgba8]）: `ImageByteFormat.rawStraightRgba` で straight な
///   バイト列を読み、sensus にそのまま渡せる形にする。
/// - 出力（[rgba8ToImage]）: sensus が返す straight なバイト列を
///   [premultiplyStraightRgba8] で premultiplied に変換してから `ui.Image` を
///   組み立てる。
///
/// 変換は（Rust 側ではなく）Dart 側で行う: sensus_core / `apply_vision_cpu_rgba8`
/// の契約を「straight alpha の RGBA8」のまま単純に保ち（sensus_core 自体が
/// straight を前提にしているため、Rust 側で追加変換すると sensus 本来の契約が
/// 見えにくくなる）、Flutter 固有の premultiplied 前提はこの Flutter 側の
/// アダプタ層に閉じ込める。
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
  /// 内部で [source] を straight RGBA8 バイト列へ変換 → `applyVisionCpuRgba8` を
  /// 呼ぶ → 結果バイト列を premultiply してから新しい [ui.Image] に戻す、という
  /// 往復を行う。アルゴリズムはここに一切持たない（正本は sensus_core、strength
  /// の clamp/NaN 処理も sensus 側の責務）。
  ///
  /// デコードに失敗した場合（[rgba8ToImage] 参照）は例外がそのまま呼び出し元へ
  /// 伝わる。無限に待ち続けてハングすることはない（#85 レビュー S2）。
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

  /// [image] を **straight**（非 premultiplied）RGBA8 の生バイト列に変換する。
  ///
  /// `ImageByteFormat.rawRgba` ではなく [ui.ImageByteFormat.rawStraightRgba] を
  /// 使う（#85 レビュー S1）: 前者は premultiplied alpha を返すため、alpha<255
  /// のピクセルを straight alpha 前提の sensus にそのまま渡すと RGB が実際より
  /// 暗く解釈されてしまう。
  ///
  /// `@visibleForTesting`: 往復変換（このメソッドと [rgba8ToImage]）の忠実性を
  /// 実ブリッジなしで単体テストできるようにするため公開する。
  @visibleForTesting
  static Future<Uint8List> imageToRgba8(ui.Image image) async {
    final byteData =
        await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    if (byteData == null) {
      throw StateError('ui.Image から raw RGBA バイト列を取得できなかった');
    }
    // ByteData が指すのは必ずしもバッキング ByteBuffer の全域とは限らないため、
    // offsetInBytes/lengthInBytes で範囲を明示する（#85 レビュー S2）。
    return byteData.buffer
        .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
  }

  /// straight alpha の RGBA8 バイト列（[straight]）を premultiplied alpha に
  /// 変換する。
  ///
  /// Flutter の `PixelFormat.rgba8888`（[rgba8ToImage] が `ImageDescriptor.raw`
  /// に渡す形式）は premultiplied alpha を前提とする。sensus の出力は straight
  /// alpha なので、`ui.Image` を組み立てる前にここで変換する（#85 レビュー S1）。
  ///
  /// `premultiplied = round(straight * alpha / 255)`。alpha==255（このアプリの
  /// 実運用画像はほぼ全て不透明）のピクセルは恒等変換になる。
  ///
  /// fast path（#85 レビュー N5）: 全ピクセルの alpha が 255 なら変換自体が
  /// 恒等写像なので、新しいバッファを確保・コピーせず [straight] をそのまま
  /// 返す。1024px 四方（4MB）のバッファをフィルタのたびに複製するコストを、
  /// このアプリの主要ケース（不透明画像）で消す。
  @visibleForTesting
  static Uint8List premultiplyStraightRgba8(Uint8List straight) {
    var allOpaque = true;
    for (var i = 3; i < straight.length; i += 4) {
      if (straight[i] != 255) {
        allOpaque = false;
        break;
      }
    }
    if (allOpaque) return straight;

    final out = Uint8List(straight.length);
    for (var i = 0; i + 3 < straight.length; i += 4) {
      final a = straight[i + 3];
      if (a == 255) {
        out[i] = straight[i];
        out[i + 1] = straight[i + 1];
        out[i + 2] = straight[i + 2];
        out[i + 3] = 255;
        continue;
      }
      out[i] = (straight[i] * a + 127) ~/ 255;
      out[i + 1] = (straight[i + 1] * a + 127) ~/ 255;
      out[i + 2] = (straight[i + 2] * a + 127) ~/ 255;
      out[i + 3] = a;
    }
    return out;
  }

  /// straight alpha の RGBA8 生バイト列（[imageToRgba8] と同じレイアウト）から
  /// [ui.Image] を組み立てる。
  ///
  /// [ui.decodeImageFromPixels]（コールバック API）ではなく
  /// `ImmutableBuffer.fromUint8List` → `ImageDescriptor.raw` →
  /// `instantiateCodec` → `getNextFrame` の await 連鎖を使う（#85 レビュー S2）:
  /// 前者はデコードに失敗した場合にコールバックが一度も呼ばれず `Future` が
  /// 永久に解決しない（呼び出し元がハングする）経路があり得るのに対し、
  /// 後者は失敗が普通の例外として `Future` の rejection で伝わるため、
  /// 呼び出し元（[apply] → `renderAfter` → `_rebuild`）の既存の
  /// try/catch・失敗表示（#58）にそのまま乗る。
  ///
  /// [premultiplyStraightRgba8] で premultiplied に変換してから
  /// `ImageDescriptor.raw` へ渡す（S1 参照）。`buffer`/`descriptor`/`codec` は
  /// 使い終わったら必ず dispose する。
  @visibleForTesting
  static Future<ui.Image> rgba8ToImage(
    Uint8List rgba8Straight,
    int width,
    int height,
  ) async {
    final premultiplied = premultiplyStraightRgba8(rgba8Straight);
    final buffer = await ui.ImmutableBuffer.fromUint8List(premultiplied);
    try {
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: width,
        height: height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      try {
        final codec = await descriptor.instantiateCodec();
        try {
          final frame = await codec.getNextFrame();
          return frame.image;
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  }
}
