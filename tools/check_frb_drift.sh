#!/usr/bin/env bash
# FRB codegen のドリフト検証。
#
# lib/src/rust/ と rust/src/frb_generated.rs が rust/src/api/ の Rust コードと
# 同期していることを、`flutter_rust_bridge_codegen generate` をやり直して比較する。
#
# - build_runner は走らせない（--no-build-runner）。CI の新しい Dart SDK と
#   freezed 2.x が使う analyzer が噛み合わず、build_runner が例外後に応答しなく
#   なるため（#88）。`*.freezed.dart` はコミット済みの生成物で、この検証の比較対象
#   外。FRB の Dart 出力と構造的に食い違えば `flutter analyze` / `flutter test` が
#   落とすが、freezed のバージョンだけ上げて出力が stale になった場合は検出できない。
# - Dart のフォーマッタは SDK のバージョンで出力が変わる（折り返し位置・末尾カンマ）。
#   コミット済みの整形結果は新旧どちらの SDK でも不動点にならないため、Dart ファイルは
#   空白と閉じ括弧直前の末尾カンマを除いた字句列で比較する。Rust 側（rustfmt）は
#   そのまま比較する。この正規化は次の差を隠しうる: 文字列リテラル・コメント内の空白、
#   1 要素レコード `(T,)` と括弧式 `(T)` の違い。
# - 結果は CI の Flutter SDK に依存する（generate が内部で通す `dart fix` /
#   `dart format` の挙動）。SDK 更新で空白・末尾カンマ以外の書き換えが起きれば偽陽性に
#   なりうる（CI の Flutter は stable 浮動）。
# - 比較・復元の対象は lib/src/rust/ と rust/src/frb_generated.rs のみ。codegen が
#   それ以外（rust/src/lib.rs の `mod frb_generated;` 追記など）を書き換えても
#   検出できず、復元もされない。
# - 比較が終わったら（差分の有無に関わらず）対象を実行前の内容に戻す。
#
# 使い方: tools/check_frb_drift.sh  （差分があれば非 0 で終了）
set -euo pipefail
cd "$(dirname "$0")/.."

DART_DIR=lib/src/rust
RUST_FILE=rust/src/frb_generated.rs

orig=$(mktemp -d)
cp -R "$DART_DIR" "$orig/dart"
cp "$RUST_FILE" "$orig/frb_generated.rs"

restore() {
  rm -rf "$DART_DIR"
  cp -R "$orig/dart" "$DART_DIR"
  cp "$orig/frb_generated.rs" "$RUST_FILE"
  rm -rf "$orig"
}
trap restore EXIT

flutter_rust_bridge_codegen generate --no-build-runner </dev/null

# 空白を全て除き、閉じ括弧の直前の `,` を除く。
normalize() {
  tr -d ' \t\r\n' <"$1" | sed -E 's/,([])}])/\1/g'
}

status=0

# ファイル集合の差（生成物の増減）。
if ! diff <(cd "$orig/dart" && find . -type f | sort) <(cd "$DART_DIR" && find . -type f | sort); then
  echo "DRIFT: file set changed（生成ファイルが増減）"
  status=1
fi

while IFS= read -r rel; do
  [ -f "$DART_DIR/$rel" ] || continue
  if ! cmp -s <(normalize "$orig/dart/$rel") <(normalize "$DART_DIR/$rel"); then
    echo "DRIFT: $DART_DIR/$rel"
    diff -u "$orig/dart/$rel" "$DART_DIR/$rel" | head -200 || true
    status=1
  fi
done < <(cd "$orig/dart" && find . -type f | sort)

if ! diff -u "$orig/frb_generated.rs" "$RUST_FILE"; then
  status=1
fi

if [ "$status" -ne 0 ]; then
  echo "::error::FRB codegen のドリフトを検出: \`flutter_rust_bridge_codegen generate\` を実行して差分をコミットしてください。"
fi
exit "$status"
