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

/// 画像として読めないファイル・フォルダだけがコピーされている（Finder で
/// HEIC や TIFF、フォルダ、.app を「コピー」した、など）。「画像がありません」
/// ではなく、「コピーしたファイルは読み込めない形式」と伝えるための型。
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

/// [path] がこの端末のローカルに実在するか（ファイルでもフォルダでも、
/// `.app` のようなバンドルでも真）。http(s) URL など実在しないパスは偽。
///
/// 本番の [PasteboardClipboardImageReader] が使う実在判定。
Future<bool> localPathExists(String path) async =>
    await FileSystemEntity.type(path) != FileSystemEntityType.notFound;

/// クリップボードの「ローカルのファイル・フォルダ」→「画像データ」の順に見て
/// 内容を決める。
///
/// **ファイルを先に見る**のは、ファイラでファイルやフォルダをコピーしたとき OS が
/// そのアイコン画像も一緒にクリップボードへ載せるため（macOS の Finder は
/// ファイル URL とアイコンの TIFF を載せる）。先に画像データを見ると、
/// 画像ファイルの中身ではなくアイコンを貼り付けてしまう。
///
/// [files] が返すパスは 2 段で見る。(a) [existsLocally] が真か（ローカルに何かしら
/// 実在するか。ファイルでもフォルダでもよい）、(b) 画像拡張子か。macOS の実装は
/// URL 一般を返し得るため、ブラウザの「イメージをコピー」で載る http(s) URL の
/// ような**実在しない**パスだけは無視する（拾うと、画像データがあるのに貼り付け
/// られなくなる）。
///
/// - 実在するもののうち画像拡張子のものがある: 先頭の 1 枚を [ClipboardImageFile]。
/// - 実在するものはあるが画像が 1 枚も無い（HEIC などの非対応形式、フォルダ、
///   拡張子なしのファイル、`.app` など）: 画像データ（= アイコン）へ進まず
///   [ClipboardUnsupportedFiles]。
/// - 実在するものが無い（空、または URL などだけ）: 画像データ。無い・空なら
///   [ClipboardNoImage]。
///
/// [files]・[imageBytes]・[existsLocally] は取得の口（本番は pasteboard と
/// [localPathExists]）。省略した [existsLocally] は「すべて実在する」扱い
/// （純粋テスト用）。
Future<ClipboardContent> resolveClipboardContent({
  required Future<List<String>> Function() files,
  required Future<Uint8List?> Function() imageBytes,
  Future<bool> Function(String path)? existsLocally,
}) async {
  final existing = <String>[];
  for (final path in await files()) {
    if (existsLocally == null || await existsLocally(path)) existing.add(path);
  }
  for (final path in existing) {
    if (isUserImagePath(path)) return ClipboardImageFile(path);
  }
  if (existing.isNotEmpty) return const ClipboardUnsupportedFiles();
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
        existsLocally: localPathExists,
      );
}

/// 貼り付け経路（`pasteUserImageFromClipboard`）が使うリーダ。テストだけが
/// 差し替える（本番コードは代入しない）。
ClipboardImageReader clipboardImageReader =
    const PasteboardClipboardImageReader();
