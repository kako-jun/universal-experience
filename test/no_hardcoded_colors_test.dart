// lib/ の UI コードにハードコード色（`Colors.*` / `Color(0x..)` / `.shade`）を
// 増やさないためのガード（#62 / #72、DESIGN.md「カラートークン」）。
//
// 色は `Theme.of(context).colorScheme` のロールだけを使う。例外は DESIGN.md の
// 例外表にある 5 ファイルだけで、ここの許可リストと表は同じ内容を保つ。
// 例外を増やすときは DESIGN.md の表と、該当箇所の「なぜロールにできないか」の
// コメントも一緒に更新すること。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// DESIGN.md の例外表と一致させる（パスは lib/ からの相対）。
const Set<String> _allowedFiles = <String>{
  'ui/theme/app_theme.dart', // カラートークンの生成元（seedColor）
  'main.dart', // OS ウィンドウの下地色（テーマ前）
  'services/loupe_window_controller.dart', // OS ウィンドウの下地色
  'services/export_service.dart', // 書き出す PNG に焼き込むキャプション色
  'rendering/image_fit.dart', // 画像内容（レターボックス色）
};

void main() {
  test('lib/ にロール化できるハードコード色が無い（例外表のファイルを除く）', () {
    final pattern = RegExp(r'\bColors\.[a-zA-Z]|\bColor\(\s*0x|\.shade\d');
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final rel = entity.path.substring('lib/'.length);
      if (rel.startsWith('src/rust/') || rel.startsWith('l10n/')) continue;
      if (_allowedFiles.contains(rel)) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) continue; // コメント内の言及は対象外
        if (pattern.hasMatch(line)) offenders.add('$rel:${i + 1}: $line');
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
