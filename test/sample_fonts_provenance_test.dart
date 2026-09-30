// サンプル画像の文字の出典（#99）の検証。
//
// サンプル生成は package:image 同梱の Arial ビットマップ（出典が自作と言い切れない）
// をやめ、OFL の Noto Sans / Noto Sans JP 由来のビットマップフォント
// （tools/fonts/）に切り替えた。ここでは「Arial への依存が戻っていないこと」
// 「フォントの実体とライセンス全文・著作権表示が揃っていること」を固定する。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final fontDir = Directory('tools/fonts');

  test('tools/generate_samples.dart は package:image の Arial ビットマップを使わない', () {
    final source = File('tools/generate_samples.dart').readAsStringSync();
    expect(source.toLowerCase(), isNot(contains('arial')));
    // 文字は _drawText（収録外の文字は例外）を通し、img.drawString を直接呼ばない。
    final direct = RegExp(r'img\.drawString\(').allMatches(source).length;
    expect(direct, 1, reason: 'img.drawString は _drawText の内部 1 か所だけ');
  });

  test('各 .fnt に対応するアトラス PNG があり、収録文字が空でない', () {
    final fnts = fontDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.fnt'))
        .toList();
    expect(fnts, isNotEmpty);
    for (final fnt in fnts) {
      final png = File(fnt.path.replaceFirst(RegExp(r'\.fnt$'), '.png'));
      expect(png.existsSync(), isTrue, reason: png.path);
      final lines = fnt.readAsLinesSync();
      expect(lines.where((l) => l.startsWith('char ')), isNotEmpty,
          reason: fnt.path);
    }
  });

  test('日本語フォントに案内板の文字（出口・駅・営業中・のりば案内）が収録されている', () {
    Set<int> ids(String name) => File('tools/fonts/$name.fnt')
        .readAsLinesSync()
        .where((l) => l.startsWith('char '))
        .map((l) => int.parse(RegExp(r'id=(\d+)').firstMatch(l)!.group(1)!))
        .toSet();

    final sign = ids('noto_sans_jp_bold_96');
    for (final c in '出口駅営業中'.runes) {
      expect(sign, contains(c), reason: String.fromCharCode(c));
    }
    final heading = ids('noto_sans_jp_bold_48');
    for (final c in 'のりば案内'.runes) {
      expect(heading, contains(c), reason: String.fromCharCode(c));
    }
  });

  test('OFL 全文と著作権表示が同梱され、出典 README が版・配布元・ライセンスを明記する', () {
    for (final name in ['OFL-NotoSans.txt', 'OFL-NotoSansJP.txt']) {
      final text = File('tools/fonts/$name').readAsStringSync();
      expect(text, contains('SIL OPEN FONT LICENSE Version 1.1'), reason: name);
      expect(text, startsWith('Copyright'), reason: name);
    }
    final readme = File('tools/fonts/README.md').readAsStringSync();
    expect(readme, contains('SIL Open Font License 1.1'));
    expect(readme, contains('Noto Sans'));
    expect(readme, contains('025970232f4f8ff349310d9785431e87d20ed27c'));
    expect(readme, contains('f8d157532fbfaeda587e826d4cd5b21a49186f7c'));
    expect(readme, contains('https://github.com/notofonts/'));
  });

  test('フォントのソフトウェア本体（TTF/OTF）はリポに含めない', () {
    final binaries = fontDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => RegExp(r'\.(ttf|otf|woff2?)$').hasMatch(f.path));
    expect(binaries, isEmpty);
  });
}
