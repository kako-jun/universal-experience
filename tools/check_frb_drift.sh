#!/usr/bin/env bash
# FRB codegen のドリフト検証。
#
# lib/src/rust/ と rust/src/frb_generated.rs が rust/src/api/ の Rust コードと
# 同期していることを、`flutter_rust_bridge_codegen generate` をやり直して比較する。
#
# - build_runner は走らせない（--no-build-runner）。CI の新しい Dart SDK と
#   freezed 2.x が使う analyzer が噛み合わず、build_runner が例外後に応答しなく
#   なるため（#88）。`*.freezed.dart` は生成物をコミットしてあるので、FRB の
#   Dart 出力との食い違いは後続の `flutter analyze` / `flutter test` で落ちる。
# - Dart のフォーマッタは SDK のバージョンで出力が変わる。比較前に、手元（コミット済み）
#   側にも同じ SDK の `dart format` を掛けてからフォーマット差を消して比較する。
# - 比較が終わったら（差分の有無に関わらず）作業ツリーを実行前の内容に戻す。
#
# 使い方: tools/check_frb_drift.sh  （差分があれば非 0 で終了）
set -euo pipefail
cd "$(dirname "$0")/.."

DART_DIR=lib/src/rust
RUST_FILE=rust/src/frb_generated.rs

work=$(mktemp -d)
orig="$work/orig"
norm="$work/norm"
mkdir -p "$orig" "$norm"
cp -R "$DART_DIR" "$orig/dart"
cp "$RUST_FILE" "$orig/frb_generated.rs"
restore() {
  rm -rf "$DART_DIR"
  cp -R "$orig/dart" "$DART_DIR"
  cp "$orig/frb_generated.rs" "$RUST_FILE"
  rm -rf "$work"
}
trap restore EXIT

# 手元側のフォーマットを実行中の SDK に揃える（FRB 自身の設定と同じ行長 80）。
# 言語バージョン（pubspec の sdk 制約由来）でフォーマット様式が変わるため、
# プロジェクト内のパスに対してその場で掛け、結果を比較の基準として退避する。
dart format --line-length 80 "$DART_DIR" >/dev/null
cp -R "$DART_DIR" "$norm/dart"
cp "$RUST_FILE" "$norm/frb_generated.rs"

flutter_rust_bridge_codegen generate --no-build-runner </dev/null

status=0
diff -ru "$norm/dart" "$DART_DIR" || status=1
diff -u "$norm/frb_generated.rs" "$RUST_FILE" || status=1

if [ "$status" -ne 0 ]; then
  echo "::error::FRB codegen のドリフトを検出: \`flutter_rust_bridge_codegen generate\` を実行して差分をコミットしてください。"
fi
exit "$status"
