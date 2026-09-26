import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `tools/generate_color_matrices.dart` の生成物（`lib/rendering/color_matrices.g.dart`）
/// が `tools/color_matrices.g.json` と同期していることを CI で常時確認する（#59）。
///
/// `test/shader_codegen_test.dart` の
/// 「generate_shaders.dart --check reports no drift」と同じパターン。CI の独立ステップ
/// （`.github/workflows/ci.yml` の "Verify color matrix codegen has no drift"）が
/// ドリフトの原因切り分けをしやすくする目的で同じ --check を回すのに加え、
/// `flutter test` からもこのテストで検知できるようにする。
void main() {
  test('generate_color_matrices.dart --check reports no drift (committed in sync)',
      () {
    final result = Process.runSync(
      'dart',
      <String>['run', 'tools/generate_color_matrices.dart', '--check'],
    );
    expect(result.exitCode, 0,
        reason: 'color matrices are stale; run '
            'dart run tools/generate_color_matrices.dart\n'
            '${result.stdout}\n${result.stderr}');
  });
}
