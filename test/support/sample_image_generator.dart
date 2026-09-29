// テスト専用のダミー正方形画像ファクトリ（#78 レビュー S4）。
//
// 元は `BeforeAfterView.generateSampleImage`（production の before ペインが
// 使っていた、意味を持たない色相グラデーション）。production 側は #78 で
// 意味のあるサンプル画像集（`lib/models/sample_catalog.dart`）に置き換わり、
// `BeforeAfterView.imageSource` が必須パラメータになったのに伴い legacy パス
// ごと撤去されたが、多数の widget/unit test がこれを「実 GPU 画像を要する
// テスト（dispose 検証・往復変換テスト等）向けの、手軽で決定的なダミー正方形
// 画像」として使い続けているため、production コードから独立させてここへ移した。

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Builds a deterministic square test image: a horizontal hue sweep with a
/// vertical brightness ramp, overlaid with red/green/blue/yellow swatches
/// along the bottom. Static + async so tests can obtain a real, disposable
/// [ui.Image] without touching `rootBundle`/asset decode.
Future<ui.Image> generateSampleImage(int size) async {
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
