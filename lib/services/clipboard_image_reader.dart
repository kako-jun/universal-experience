import 'dart:io';
import 'dart:typed_data';

import 'package:pasteboard/pasteboard.dart';

import '../rendering/image_fit.dart';

/// クリップボードから取り出した内容（#97）。
sealed class ClipboardContent {
  const ClipboardContent();
}

/// 画像がない（テキストだけ・空、など）。
class ClipboardNoImage extends ClipboardContent {
  const ClipboardNoImage();
}

/// 画像のバイト列（スクリーンショットや、画像アプリでのコピー）。
/// 形式は実装依存（[PasteboardClipboardImageReader] は PNG）。
class ClipboardImageData extends ClipboardContent {
  const ClipboardImageData(this.bytes);

  final Uint8List bytes;
}

/// 画像ファイルそのもの（ファイラで画像ファイルを「コピー」した場合）の
/// パス。呼び出し側は選択・ドロップと同じ `loadUserImageFile`（サイズの
/// 事前判定付き）に回す。
class ClipboardImageFile extends ClipboardContent {
  const ClipboardImageFile(this.path);

  final String path;
}

/// 画像として読めない形式のファイルだけがコピーされている（Finder で
/// HEIC や TIFF を「コピー」した、など）。「画像がありません」ではなく、
/// 「そのファイルは読み込めない形式」と伝えるための型。
class ClipboardUnsupportedFiles extends ClipboardContent {
  const ClipboardUnsupportedFiles();
}

/// クリップボードから貼り付ける画像を取る口（#97）。
///
/// `image_source_picker.dart` の `pickImageFile`（#78）と同じ seam パターン:
/// 本番は [PasteboardClipboardImageReader]（プラットフォームチャネル経由で
/// OS のクリップボードを読む。素の `flutter test` では使えない）、テストは
/// フェイクの実装へ差し替える。
abstract interface class ClipboardImageReader {
  /// クリップボードの内容を返す。読み取り自体の失敗は例外で伝える。
  Future<ClipboardContent> read();
}

/// [path] の拡張子がユーザー画像として読める形式（[kUserImageFileExtensions]）
/// かどうか。大文字小文字は区別しない。
bool isUserImagePath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) return false;
  return kUserImageFileExtensions
      .contains(path.substring(dot + 1).toLowerCase());
}

/// [path] が「拡張子つきだが画像として読めない」形式か。拡張子のないパスは
/// ファイルの種類を決められないので含めない。
bool _hasNonImageExtension(String path) {
  final dot = path.lastIndexOf('.');
  final hasExtension = dot >= 0 && dot < path.length - 1;
  return hasExtension && !isUserImagePath(path);
}

/// クリップボードの「ファイル」→「画像データ」の順に見て内容を決める。
///
/// **ファイルを先に見る**のは、ファイラでファイルをコピーしたとき OS が
/// ファイルのアイコン画像も一緒にクリップボードへ載せるため（macOS の Finder は
/// ファイル URL とアイコンの TIFF を載せる）。先に画像データを見ると、
/// 画像ファイルの中身ではなくアイコンを貼り付けてしまう。
///
/// ただし [files] が返すパスのうち、[fileExists] が真のもの（実在するローカル
/// ファイル）だけを「ファイル」として扱う。macOS の実装は URL 一般を返し得る
/// ため、ブラウザの「イメージをコピー」で載る http(s) URL のような実在しない
/// パスを拾うと、画像データがあるのに貼り付けられなくなる。
///
/// - 実在するファイルに画像拡張子のものがある: 先頭の 1 枚を [ClipboardImageFile]。
/// - 実在するファイルがあるが画像拡張子のものは無く、拡張子つきの非対応形式
///   （.heic .txt など）がある: 画像データ（= アイコン）へ進まず
///   [ClipboardUnsupportedFiles]。
/// - 実在するファイルが無い、または拡張子なしのものだけ: 画像データ。無い・空
///   なら [ClipboardNoImage]。
///
/// [files]・[imageBytes]・[fileExists] は取得の口（本番は pasteboard と
/// `dart:io`）。省略した [fileExists] は「すべて実在する」扱い（純粋テスト用）。
Future<ClipboardContent> resolveClipboardContent({
  required Future<List<String>> Function() files,
  required Future<Uint8List?> Function() imageBytes,
  Future<bool> Function(String path)? fileExists,
}) async {
  final existing = <String>[];
  for (final path in await files()) {
    if (fileExists == null || await fileExists(path)) existing.add(path);
  }
  for (final path in existing) {
    if (isUserImagePath(path)) return ClipboardImageFile(path);
  }
  if (existing.any(_hasNonImageExtension)) {
    return const ClipboardUnsupportedFiles();
  }
  final bytes = await imageBytes();
  if (bytes == null || bytes.isEmpty) return const ClipboardNoImage();
  return ClipboardImageData(bytes);
}

/// `pasteboard` プラグイン（macOS: NSPasteboard、Linux: GtkClipboard、
/// Windows: クリップボードの DIB）で実クリップボードを読む本番実装。
class PasteboardClipboardImageReader implements ClipboardImageReader {
  const PasteboardClipboardImageReader();

  @override
  Future<ClipboardContent> read() => resolveClipboardContent(
        files: Pasteboard.files,
        imageBytes: () => Pasteboard.image,
        // ディレクトリや URL は File(...).exists() が偽になり、無視される。
        fileExists: (path) => File(path).exists(),
      );
}

/// 貼り付け経路（`pasteUserImageFromClipboard`）が使うリーダ。テストだけが
/// 差し替える（本番コードは代入しない）。
ClipboardImageReader clipboardImageReader =
    const PasteboardClipboardImageReader();
