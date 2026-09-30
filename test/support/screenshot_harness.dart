// UI スクリーンショット基盤の共通部品（#72）。
//
// ヘッドレス環境（実ディスプレイなし）でも画面を「目で見て」判断できるように、
// widget を実フォント付きで描画して PNG に書き出す。`flutter test` 既定の
// フォント（Ahem＝全角の四角）では文字が読めないため、実行環境にあるシステム
// フォントを FontLoader で読み込む。
//
// - フォントファイルはリポにコミットしない。存在しない環境（CI の Linux 等）では
//   警告だけ出して既定フォントのまま進む（PNG は読めないが落ちない）。
// - 書き出しは `UE_SCREENSHOTS=1` のときだけ（[screenshotsEnabled]）。
//   通常の `flutter test` / CI ではスキップされ、他テストに影響しない。
// - 出力先は `UE_SCREENSHOT_DIR`。未指定ならリポ外の
//   `<システム tmp>/ue_screenshots`。

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// `UE_SCREENSHOTS=1` のときだけ true。
bool get screenshotsEnabled => Platform.environment['UE_SCREENSHOTS'] == '1';

/// PNG の出力先ディレクトリ（存在しなければ作る）。
Directory screenshotOutputDir() {
  final env = Platform.environment['UE_SCREENSHOT_DIR'];
  final dir = Directory(
    (env != null && env.isNotEmpty)
        ? env
        : '${Directory.systemTemp.path}/ue_screenshots',
  );
  dir.createSync(recursive: true);
  return dir;
}

/// Flutter SDK の `bin/cache/artifacts/material_fonts`。見つからなければ null。
Directory? _materialFontsDir() {
  final candidates = <String>[];
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty) {
    candidates.add('$root/bin/cache/artifacts/material_fonts');
  }
  // flutter_tester = <sdk>/bin/cache/artifacts/engine/<platform>/flutter_tester
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 6; i++) {
    candidates.add('${dir.path}/material_fonts');
    candidates.add('${dir.path}/artifacts/material_fonts');
    dir = dir.parent;
  }
  for (final c in candidates) {
    if (Directory(c).existsSync()) return Directory(c);
  }
  return null;
}

/// 日本語グリフを持つシステムフォントの候補（存在する最初の 1 つを使う）。
const List<String> _japaneseFontCandidates = <String>[
  '/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc',
  '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
  '/Library/Fonts/Arial Unicode.ttf',
  '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
  '/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc',
  '/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc',
];

/// キー記号（⌘⇧⌥ 等）を持つシステムフォントの候補。
const List<String> _symbolFontCandidates = <String>[
  '/System/Library/Fonts/Apple Symbols.ttf',
  '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
  '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
];

bool _fontsLoaded = false;

/// スクリーンショット用のフォント（Roboto・日本語・Material Icons）を読み込む。
///
/// 何度呼んでも 1 回だけ読む。ファイルが無いものは黙ってスキップし、見つからな
/// かった種類を stderr に 1 行出す。
Future<void> loadScreenshotFonts() async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;

  Future<ByteData> read(File f) async {
    final bytes = await f.readAsBytes();
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }

  final fontsDir = _materialFontsDir();
  final missing = <String>[];

  if (fontsDir != null) {
    final icons = File('${fontsDir.path}/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      final loader = FontLoader('MaterialIcons')..addFont(read(icons));
      await loader.load();
    } else {
      missing.add('MaterialIcons');
    }

    final roboto = <File>[
      File('${fontsDir.path}/Roboto-Regular.ttf'),
      File('${fontsDir.path}/Roboto-Bold.ttf'),
    ].where((f) => f.existsSync()).toList();
    if (roboto.isNotEmpty) {
      final loader = FontLoader('Roboto');
      for (final f in roboto) {
        loader.addFont(read(f));
      }
      await loader.load();
    } else {
      missing.add('Roboto');
    }
  } else {
    missing.addAll(<String>['MaterialIcons', 'Roboto']);
  }

  // 日本語は別ファミリ名で読み込み、テーマの fontFamilyFallback から参照する
  // （[screenshotFontFallback]）。
  File? ja;
  for (final p in _japaneseFontCandidates) {
    final f = File(p);
    if (f.existsSync()) {
      ja = f;
      break;
    }
  }
  if (ja != null) {
    final loader = FontLoader(kScreenshotJapaneseFamily)..addFont(read(ja));
    await loader.load();
  } else {
    missing.add('Japanese');
  }

  // ⌘⇧ などの記号（ホットキー表記）用。無くても続行する。
  for (final p in _symbolFontCandidates) {
    final f = File(p);
    if (f.existsSync()) {
      final loader = FontLoader(kScreenshotSymbolFamily)..addFont(read(f));
      await loader.load();
      break;
    }
  }

  if (missing.isNotEmpty) {
    stderr.writeln(
      '[ui_screenshots] fonts not found: ${missing.join(', ')} '
      '(text/icons may render as boxes)',
    );
  }
}

/// 日本語フォントのファミリ名。
const String kScreenshotJapaneseFamily = 'UEShotJapanese';

/// テキストの fontFamilyFallback に渡す一覧。
const List<String> screenshotFontFallback = <String>[
  kScreenshotJapaneseFamily,
  kScreenshotSymbolFamily,
];

/// 記号フォントのファミリ名。
const String kScreenshotSymbolFamily = 'UEShotSymbols';

/// [boundaryKey] の RepaintBoundary を PNG にして [name].png として書き出す。
///
/// `testWidgets` の中から呼ぶ。実 I/O とエンコードのため `runAsync` を使う。
/// 書き出したファイルのパスを返す。
Future<String> writeScreenshot(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  final path = '${screenshotOutputDir().path}/$name.png';
  await tester.runAsync(() async {
    final boundary = boundaryKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await File(path).writeAsBytes(data!.buffer.asUint8List());
  });
  return path;
}
