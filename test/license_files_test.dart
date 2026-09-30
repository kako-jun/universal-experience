import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `rust_builder/LICENSE` は podspec（`rust_builder/macos/*.podspec`）が
/// `:file => '../LICENSE'` で参照するためのリポジトリ直下 `LICENSE` の複製。
/// CocoaPods はパッケージ外のファイルを解決できないので複製が要る。二重管理で
/// 食い違わないよう、バイト列の一致を機械的に守る（#71）。
void main() {
  test('rust_builder/LICENSE はリポジトリ直下の LICENSE と同一', () {
    final root = File('LICENSE').readAsBytesSync();
    final copy = File('rust_builder/LICENSE').readAsBytesSync();

    expect(root, isNotEmpty);
    expect(
      copy,
      equals(root),
      reason: 'rust_builder/LICENSE は podspec 用の複製。LICENSE を変えたら揃える',
    );
  });
}
