/// CLI: generate the built-in preview sample images (#78) as PNG assets.
///
/// Usage:
///   dart run tools/generate_samples.dart
///
/// Output: `assets/samples/*.png` — 7 scenes (see `assets/samples/README.md`
/// for the full list + rationale) plus one grayscale depth-map companion for
/// the "depth_landscape" scene.
///
/// Everything here is procedurally generated with `package:image` (a pure-Dart
/// rasterizer, no Flutter engine / `dart:ui` needed — this runs as a plain
/// `dart run`, unlike `BeforeAfterView.generateSampleImage`, which needs a
/// live Flutter binding). No external assets are downloaded or embedded: text
/// uses `package:image`'s built-in bitmap fonts (Arial 14/24/48, vendored
/// inside the package itself), and every shape is drawn with basic primitives
/// (rects/circles/lines/polygons). No human faces appear anywhere (#78).
///
/// Re-run this whenever a scene needs to change — the PNGs are committed
/// (small, optimized at `level: 9`), not generated at build/runtime, so the
/// app never depends on `package:image` (a dev-only tool dependency, see
/// pubspec.yaml).
library;

import 'dart:io';

import 'package:image/image.dart' as img;

/// Canonical sample size — matches `BeforeAfterView.canonicalSampleSize`
/// (#85) so samples never need runtime upscaling.
const int kSize = 1024;

const String _outDir = 'assets/samples';

void main() {
  final dir = Directory(_outDir);
  if (!dir.existsSync()) dir.createSync(recursive: true);

  final scenes = <String, img.Image Function()>{
    'route_map': _generateRouteMap,
    'chart': _generateChart,
    'traffic_signs': _generateTrafficSigns,
    'info_board': _generateInfoBoard,
    'fruit_stand': _generateFruitStand,
    'night_scene': _generateNightScene,
    'depth_landscape': _generateDepthLandscape,
  };

  for (final entry in scenes.entries) {
    _write('${entry.key}.png', entry.value());
  }
  // Depth-map companion for depth_landscape (#78 着手コメント: 深度付き
  // サンプルの素材だけをこの PR で用意する。depth_aware_blur との配線は別 Issue)。
  _write('depth_landscape_depth.png', _generateDepthLandscapeDepthMap());

  stdout.writeln('Done. Wrote ${scenes.length + 1} PNGs to $_outDir/');
}

void _write(String filename, img.Image image) {
  final bytes = img.encodePng(image, level: 9);
  final path = '$_outDir/$filename';
  File(path).writeAsBytesSync(bytes);
  stdout.writeln('  $path (${(bytes.length / 1024).toStringAsFixed(1)} KiB)');
}

img.Image _canvas(img.Color background) {
  final image = img.Image(width: kSize, height: kSize, numChannels: 3);
  img.fill(image, color: background);
  return image;
}

// ── 1. 路線図（色で区別する複数路線、駅名の文字）──────────────────────────

/// A schematic transit map: 5 differently-coloured routes crossing a grid,
/// with circular station markers and short alphanumeric labels. Red/green
/// routes are placed so a protan/deutan viewer must rely on position (not
/// hue) to tell them apart — the point of the scene.
img.Image _generateRouteMap() {
  final image = _canvas(img.ColorRgb8(0xF3, 0xF1, 0xEA));

  const routes = <(String, int, int, int, List<List<double>>)>[
    ('R', 0xE5, 0x39, 0x35, [
      [0.08, 0.15],
      [0.35, 0.15],
      [0.55, 0.40],
      [0.92, 0.40],
    ]),
    ('G', 0x2E, 0x7D, 0x32, [
      [0.08, 0.55],
      [0.40, 0.55],
      [0.40, 0.20],
      [0.75, 0.20],
      [0.75, 0.88],
    ]),
    ('B', 0x1E, 0x88, 0xE5, [
      [0.15, 0.92],
      [0.15, 0.30],
      [0.60, 0.30],
      [0.60, 0.08],
    ]),
    ('O', 0xFB, 0x8C, 0x00, [
      [0.90, 0.10],
      [0.90, 0.65],
      [0.20, 0.65],
      [0.20, 0.95],
    ]),
    ('P', 0x8E, 0x24, 0xAA, [
      [0.50, 0.05],
      [0.50, 0.50],
      [0.85, 0.80],
    ]),
  ];

  var stationIndex = 0;
  for (final (code, r, g, b, points) in routes) {
    final color = img.ColorRgb8(r, g, b);
    final px = points.map((p) => (p[0] * kSize, p[1] * kSize)).toList();
    for (var i = 0; i < px.length - 1; i++) {
      img.drawLine(
        image,
        x1: px[i].$1.round(),
        y1: px[i].$2.round(),
        x2: px[i + 1].$1.round(),
        y2: px[i + 1].$2.round(),
        color: color,
        thickness: 12,
        antialias: true,
      );
    }
    // Route code label near the first point, in the route's own colour.
    img.drawString(
      image,
      code,
      font: img.arial24,
      x: px.first.$1.round() + 14,
      y: px.first.$2.round() - 30,
      color: color,
    );
    // Station markers along the route (white disc + coloured ring + label).
    for (var i = 0; i < px.length; i++) {
      final (x, y) = px[i];
      img.fillCircle(
        image,
        x: x.round(),
        y: y.round(),
        radius: 14,
        color: img.ColorRgb8(0xFF, 0xFF, 0xFF),
      );
      img.drawCircle(
        image,
        x: x.round(),
        y: y.round(),
        radius: 14,
        color: color,
        antialias: true,
      );
      img.drawString(
        image,
        '${String.fromCharCode(65 + stationIndex % 26)}${stationIndex ~/ 26 + 1}',
        font: img.arial14,
        x: x.round() + 18,
        y: y.round() + 4,
        color: img.ColorRgb8(0x21, 0x21, 0x21),
      );
      stationIndex++;
    }
  }
  return image;
}

// ── 2. 凡例付きのグラフ（赤・緑・青・橙の系列）──────────────────────────

/// A 4-series grouped bar chart with a legend box. Series colours are the
/// canonical red/green/blue/orange spread called for by the Issue.
img.Image _generateChart() {
  final image = _canvas(img.ColorRgb8(0xFA, 0xFA, 0xF8));

  final axisColor = img.ColorRgb8(0x42, 0x42, 0x42);
  const originX = 100;
  const originY = kSize - 140;
  const topY = 90;
  const rightX = kSize - 60;

  img.drawLine(image,
      x1: originX, y1: topY, x2: originX, y2: originY,
      color: axisColor, thickness: 3);
  img.drawLine(image,
      x1: originX, y1: originY, x2: rightX, y2: originY,
      color: axisColor, thickness: 3);

  const series = <(String, int, int, int)>[
    ('A', 0xE5, 0x39, 0x35), // red
    ('B', 0x2E, 0x7D, 0x32), // green
    ('C', 0x1E, 0x88, 0xE5), // blue
    ('D', 0xFB, 0x8C, 0x00), // orange
  ];
  // Deterministic per-category heights (0.0..1.0), varied enough that no two
  // series look identical in every category.
  const heights = <List<double>>[
    [0.85, 0.55, 0.30, 0.65],
    [0.40, 0.90, 0.60, 0.25],
    [0.60, 0.35, 0.80, 0.50],
    [0.30, 0.65, 0.45, 0.85],
    [0.75, 0.20, 0.55, 0.40],
  ];

  final categories = heights.length;
  const plotWidth = rightX - originX - 40;
  final groupWidth = plotWidth / categories;
  final barWidth = groupWidth / (series.length + 1);
  final maxBarHeight = (originY - topY - 20).toDouble();

  for (var c = 0; c < categories; c++) {
    for (var s = 0; s < series.length; s++) {
      final (_, r, g, b) = series[s];
      final h = heights[c][s] * maxBarHeight;
      final x1 = originX + 20 + c * groupWidth + s * barWidth;
      final x2 = x1 + barWidth * 0.85;
      img.fillRect(
        image,
        x1: x1.round(),
        y1: (originY - h).round(),
        x2: x2.round(),
        y2: originY,
        color: img.ColorRgb8(r, g, b),
      );
    }
  }

  // Legend: swatch + single-letter code for each series, boxed top-right.
  const legendX = kSize - 220;
  const legendY = 90;
  img.drawRect(image,
      x1: legendX - 16,
      y1: legendY - 16,
      x2: kSize - 60,
      y2: legendY + series.length * 40 + 8,
      color: axisColor);
  for (var s = 0; s < series.length; s++) {
    final (code, r, g, b) = series[s];
    final y = legendY + s * 40;
    img.fillRect(image,
        x1: legendX, y1: y, x2: legendX + 28, y2: y + 28,
        color: img.ColorRgb8(r, g, b));
    img.drawString(image, code,
        font: img.arial24, x: legendX + 44, y: y + 2, color: axisColor);
  }
  return image;
}

// ── 3. 信号・標識 ──────────────────────────────────────────────────

/// A traffic light (red lit, amber/green dim — position, not just colour,
/// carries the meaning) plus three road-sign shapes (warning triangle,
/// prohibition circle, information rectangle) so shape/border redundancy is
/// visible alongside colour.
img.Image _generateTrafficSigns() {
  final image = _canvas(img.ColorRgb8(0xE8, 0xE8, 0xE4));

  // Traffic light housing.
  const housingX1 = 120, housingY1 = 140, housingX2 = 300, housingY2 = 620;
  img.fillRect(image,
      x1: housingX1,
      y1: housingY1,
      x2: housingX2,
      y2: housingY2,
      color: img.ColorRgb8(0x21, 0x21, 0x21));
  final cx = ((housingX1 + housingX2) / 2).round();
  const lampRadius = 70;
  final lampYs = [housingY1 + 100, housingY1 + 240, housingY1 + 380];
  // Only the top (red) lamp is "lit" (bright); the others are dim — the
  // vertical position is the redundant, colour-independent cue.
  final lampColors = [
    img.ColorRgb8(0xFF, 0x17, 0x44),
    img.ColorRgb8(0x4A, 0x3B, 0x10),
    img.ColorRgb8(0x14, 0x3D, 0x1C),
  ];
  for (var i = 0; i < 3; i++) {
    img.fillCircle(image,
        x: cx, y: lampYs[i], radius: lampRadius, color: lampColors[i]);
  }

  // Warning triangle (yellow, black border, exclamation mark).
  const triCx = 640.0, triCy = 260.0, triR = 170.0;
  final triPoints = [
    img.Point(triCx, triCy - triR),
    img.Point(triCx - triR * 0.87, triCy + triR * 0.6),
    img.Point(triCx + triR * 0.87, triCy + triR * 0.6),
  ];
  img.fillPolygon(image,
      vertices: triPoints, color: img.ColorRgb8(0xFD, 0xD8, 0x35));
  for (var i = 0; i < triPoints.length; i++) {
    final a = triPoints[i];
    final b = triPoints[(i + 1) % triPoints.length];
    img.drawLine(image,
        x1: a.xi, y1: a.yi, x2: b.xi, y2: b.yi,
        color: img.ColorRgb8(0x21, 0x21, 0x21), thickness: 10, antialias: true);
  }
  img.drawString(image, '!',
      font: img.arial48,
      x: triCx.round() - 8,
      y: triCy.round() - 10,
      color: img.ColorRgb8(0x21, 0x21, 0x21));

  // Prohibition circle (white, thick red ring, diagonal bar).
  const proCx = 640, proCy = 620, proR = 150;
  img.fillCircle(image,
      x: proCx, y: proCy, radius: proR, color: img.ColorRgb8(0xFF, 0xFF, 0xFF));
  img.drawCircle(image,
      x: proCx, y: proCy, radius: proR,
      color: img.ColorRgb8(0xE5, 0x39, 0x35), antialias: true);
  img.drawCircle(image,
      x: proCx, y: proCy, radius: proR - 8,
      color: img.ColorRgb8(0xE5, 0x39, 0x35), antialias: true);
  img.drawLine(image,
      x1: proCx - 100, y1: proCy - 100, x2: proCx + 100, y2: proCy + 100,
      color: img.ColorRgb8(0xE5, 0x39, 0x35), thickness: 20, antialias: true);

  // Information rectangle (blue, rounded, white "P").
  img.fillRect(image,
      x1: 880, y1: 460, x2: 1010, y2: 590,
      color: img.ColorRgb8(0x1E, 0x88, 0xE5), radius: 16);
  img.drawString(image, 'P',
      font: img.arial48, x: 925, y: 495, color: img.ColorRgb8(0xFF, 0xFF, 0xFF));

  return image;
}

// ── 4. 文字の多い案内板（大小の文字）──────────────────────────────────

/// A signage board: one large headline plus many small table-like rows, so
/// filters that blur or lose fine detail (refraction, contrast sensitivity,
/// tunnel vision, field loss) visibly change which lines stay readable.
img.Image _generateInfoBoard() {
  final image = _canvas(img.ColorRgb8(0xF1, 0xED, 0xE1));
  final textColor = img.ColorRgb8(0x1A, 0x23, 0x3D);
  final ruleColor = img.ColorRgb8(0xB8, 0xB0, 0x98);

  img.drawString(image, 'INFORMATION',
      font: img.arial48, x: 60, y: 50, color: textColor);
  img.drawLine(image,
      x1: 60, y1: 140, x2: kSize - 60, y2: 140, color: ruleColor, thickness: 4);

  const rows = <(String, String, String)>[
    ('A1', '08:05', 'CENTRAL'),
    ('A2', '08:20', 'RIVERSIDE'),
    ('B1', '08:32', 'NORTH GATE'),
    ('B2', '08:47', 'OLD TOWN'),
    ('C1', '09:03', 'HARBOR'),
    ('C2', '09:15', 'MARKET SQ'),
    ('D1', '09:28', 'EAST HILL'),
    ('D2', '09:40', 'GREEN PARK'),
    ('E1', '09:55', 'WEST END'),
    ('E2', '10:10', 'AIRPORT'),
  ];
  var y = 180;
  const rowHeight = 76;
  for (final (code, time, place) in rows) {
    img.drawString(image, code, font: img.arial24, x: 60, y: y, color: textColor);
    img.drawString(image, time, font: img.arial24, x: 200, y: y, color: textColor);
    img.drawString(image, place, font: img.arial24, x: 380, y: y, color: textColor);
    // A line of small print under each row (fine detail for blur filters).
    img.drawString(
      image,
      'platform ${1 + rows.indexOf((code, time, place)) % 4} · via loop line · please mind the gap',
      font: img.arial14,
      x: 60,
      y: y + 34,
      color: img.ColorRgb8(0x5A, 0x54, 0x46),
    );
    img.drawLine(image,
        x1: 60,
        y1: y + rowHeight - 8,
        x2: kSize - 60,
        y2: y + rowHeight - 8,
        color: ruleColor,
        thickness: 2);
    y += rowHeight;
  }
  return image;
}

// ── 5. 食べ物・果物（色の見分け。熟した赤・未熟な緑など）──────────────────

/// Rows of stylised fruit: ripe-red vs. unripe-green (the classic
/// protan/deutan test pair), plus orange/yellow and purple/blue for broader
/// hue coverage (tritan-relevant).
img.Image _generateFruitStand() {
  final image = _canvas(img.ColorRgb8(0xE9, 0xD9, 0xB6));

  void fruitRow(int y, List<(int, int, int)> colors, {bool banana = false}) {
    final n = colors.length;
    final spacing = kSize / n;
    for (var i = 0; i < n; i++) {
      final (r, g, b) = colors[i];
      final cx = (spacing * i + spacing / 2).round();
      if (banana) {
        img.fillPolygon(image, vertices: [
          img.Point(cx - 70.0, y + 40.0),
          img.Point(cx - 30.0, y - 60.0),
          img.Point(cx + 40.0, y - 50.0),
          img.Point(cx + 70.0, y + 50.0),
        ], color: img.ColorRgb8(r, g, b));
      } else {
        img.fillCircle(image, x: cx, y: y, radius: 90, color: img.ColorRgb8(r, g, b));
        // Small stem, always the same dark colour (shape/position cue, not hue).
        img.fillRect(image,
            x1: cx - 6, y1: y - 100, x2: cx + 6, y2: y - 75,
            color: img.ColorRgb8(0x3E, 0x27, 0x14));
        // Soft highlight for a touch of roundness.
        img.fillCircle(image,
            x: cx - 30, y: y - 30, radius: 20,
            color: img.ColorRgb8(
              (r + 255) ~/ 2,
              (g + 255) ~/ 2,
              (b + 255) ~/ 2,
            ));
      }
    }
  }

  // Row 1: ripe red vs. unripe green — the primary red/green discrimination
  // test (#78 issue text: "熟した赤・未熟な緑").
  fruitRow(260, [
    (0xC6, 0x28, 0x28), // ripe tomato red
    (0x55, 0x8B, 0x2F), // unripe green
    (0xC6, 0x28, 0x28),
    (0x55, 0x8B, 0x2F),
    (0xC6, 0x28, 0x28),
  ]);
  // Row 2: citrus orange + banana yellow.
  fruitRow(520, [
    (0xFB, 0x8C, 0x00),
    (0xFB, 0x8C, 0x00),
  ]);
  fruitRow(520, [
    (0xFD, 0xD8, 0x35),
    (0xFD, 0xD8, 0x35),
    (0xFD, 0xD8, 0x35),
  ], banana: false);
  // Row 3: grapes purple + plum blue (tritan-relevant blue/purple pair).
  fruitRow(800, [
    (0x6A, 0x1B, 0x9A),
    (0x39, 0x49, 0xAB),
    (0x6A, 0x1B, 0x9A),
    (0x39, 0x49, 0xAB),
    (0x6A, 0x1B, 0x9A),
  ]);
  return image;
}

// ── 6. 夜景（点光源。広いベタ白を置かない）──────────────────────────────

/// A night scene: dark gradient sky, a silhouette skyline, and many small
/// bright point-lights (for starbursts/glare, and for the night-blindness
/// low-light contrast case). #51 note 3: never a wide flat-white area — every
/// bright pixel here is a small point, not a fill.
img.Image _generateNightScene() {
  final image = img.Image(width: kSize, height: kSize, numChannels: 3);
  for (var y = 0; y < kSize; y++) {
    final t = y / kSize;
    final r = (0x05 + (0x12 - 0x05) * t).round();
    final g = (0x05 + (0x12 - 0x05) * t).round();
    final b = (0x10 + (0x2A - 0x10) * t).round();
    img.drawLine(image, x1: 0, y1: y, x2: kSize - 1, y2: y, color: img.ColorRgb8(r, g, b));
  }

  // Skyline silhouette along the bottom — a depth/shape cue independent of
  // colour, and it keeps the point-lights from floating in empty space.
  const buildings = <List<int>>[
    [0, 620, 140, 1024],
    [150, 520, 260, 1024],
    [270, 700, 380, 1024],
    [390, 460, 470, 1024],
    [480, 640, 620, 1024],
    [630, 560, 760, 1024],
    [770, 500, 900, 1024],
    [910, 660, 1024, 1024],
  ];
  for (final r in buildings) {
    img.fillRect(image,
        x1: r[0], y1: r[1], x2: r[2], y2: r[3],
        color: img.ColorRgb8(0x02, 0x02, 0x06));
  }

  // Deterministic point-lights (small LCG so re-running reproduces the same
  // image byte-for-byte).
  var seed = 20260927;
  int next(int mod) {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed % mod;
  }

  const warm = (0xFF, 0xF3, 0xB0);
  const cool = (0xCF, 0xE8, 0xFF);
  const signalRed = (0xFF, 0x52, 0x52);
  const signalGreen = (0x69, 0xF0, 0xAE);
  final palette = [warm, warm, warm, cool, cool, signalRed, signalGreen];

  for (var i = 0; i < 70; i++) {
    final x = next(kSize);
    // Bias lights toward the upper 70% (window lights + a few low ones near
    // buildings), keeping the very bottom mostly dark silhouette.
    final y = next((kSize * 0.72).round());
    final radius = 2 + next(5);
    final (r, g, b) = palette[next(palette.length)];
    img.fillCircle(image, x: x, y: y, radius: radius, color: img.ColorRgb8(r, g, b));
  }
  return image;
}

// ── 7. 奥行きのある風景（手前・中間・遠景。深度マップ付き）────────────────

/// Layered depth cues: pale/desaturated distant mountains, a mid-saturation
/// midground tree cluster, and a large, sharp, dark foreground silhouette.
/// Paired with [_generateDepthLandscapeDepthMap] (same layout, encoded as
/// grayscale depth) for the future depth_aware_blur experience (#1/#78, not
/// wired up in this PR — see assets/samples/README.md).
img.Image _generateDepthLandscape() {
  final image = img.Image(width: kSize, height: kSize, numChannels: 3);
  // Sky: hazy near horizon, deeper blue at the top (aerial perspective).
  for (var y = 0; y < 640; y++) {
    final t = y / 640;
    final r = (0xCF + (0x7E - 0xCF) * t).round();
    final g = (0xE3 + (0xA6 - 0xE3) * t).round();
    final b = (0xF0 + (0xD8 - 0xF0) * t).round();
    img.drawLine(image, x1: 0, y1: y, x2: kSize - 1, y2: y, color: img.ColorRgb8(r, g, b));
  }

  // Background: far, pale, low-contrast mountain ridge.
  img.fillPolygon(image, vertices: [
    img.Point(0.0, 560.0),
    img.Point(220.0, 380.0),
    img.Point(430.0, 500.0),
    img.Point(620.0, 340.0),
    img.Point(860.0, 480.0),
    img.Point(1024.0, 420.0),
    img.Point(1024.0, 640.0),
    img.Point(0.0, 640.0),
  ], color: img.ColorRgb8(0xA9, 0xB8, 0xC4));

  // Midground: a cluster of trees/houses — mid saturation, mid size.
  final midColor = img.ColorRgb8(0x4E, 0x7D, 0x4A);
  for (final cx in [140, 260, 340, 700, 800, 900]) {
    img.fillCircle(image, x: cx, y: 660, radius: 70, color: midColor);
  }
  img.fillRect(image,
      x1: 470, y1: 600, x2: 620, y2: 700,
      color: img.ColorRgb8(0xB0, 0x7A, 0x4E));
  img.fillPolygon(image, vertices: [
    img.Point(465.0, 600.0),
    img.Point(545.0, 530.0),
    img.Point(625.0, 600.0),
  ], color: img.ColorRgb8(0x8C, 0x3B, 0x2E));

  // Foreground: large, sharp, dark silhouette (a fence + a bush) close to
  // the camera, occupying the bottom of the frame.
  final fgColor = img.ColorRgb8(0x18, 0x24, 0x14);
  img.fillRect(image, x1: 0, y1: 760, x2: kSize, y2: kSize, color: fgColor);
  for (var x = 40; x < kSize; x += 90) {
    img.fillRect(image, x1: x, y1: 640, x2: x + 22, y2: 800, color: fgColor);
  }
  img.fillCircle(image, x: 860, y: 700, radius: 140, color: fgColor);
  img.fillCircle(image, x: 980, y: 760, radius: 110, color: fgColor);

  return image;
}

/// Grayscale depth companion for [_generateDepthLandscape]. Convention
/// (documented in assets/samples/README.md): **brighter = nearer**,
/// **darker = farther**, 8-bit, same pixel layout as the colour scene.
img.Image _generateDepthLandscapeDepthMap() {
  final image = img.Image(width: kSize, height: kSize, numChannels: 1);
  // Sky/background mountains: far → dark.
  img.fill(image, color: img.ColorRgb8(40, 40, 40));
  img.fillPolygon(image, vertices: [
    img.Point(0.0, 560.0),
    img.Point(220.0, 380.0),
    img.Point(430.0, 500.0),
    img.Point(620.0, 340.0),
    img.Point(860.0, 480.0),
    img.Point(1024.0, 420.0),
    img.Point(1024.0, 640.0),
    img.Point(0.0, 640.0),
  ], color: img.ColorRgb8(70, 70, 70));

  // Midground: mid gray.
  final midGray = img.ColorRgb8(140, 140, 140);
  for (final cx in [140, 260, 340, 700, 800, 900]) {
    img.fillCircle(image, x: cx, y: 660, radius: 70, color: midGray);
  }
  img.fillRect(image, x1: 470, y1: 600, x2: 620, y2: 700, color: midGray);
  img.fillPolygon(image, vertices: [
    img.Point(465.0, 600.0),
    img.Point(545.0, 530.0),
    img.Point(625.0, 600.0),
  ], color: midGray);

  // Foreground: near → bright.
  final fgGray = img.ColorRgb8(230, 230, 230);
  img.fillRect(image, x1: 0, y1: 760, x2: kSize, y2: kSize, color: fgGray);
  for (var x = 40; x < kSize; x += 90) {
    img.fillRect(image, x1: x, y1: 640, x2: x + 22, y2: 800, color: fgGray);
  }
  img.fillCircle(image, x: 860, y: 700, radius: 140, color: fgGray);
  img.fillCircle(image, x: 980, y: 760, radius: 110, color: fgGray);

  return image;
}
