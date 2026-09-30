import 'dart:typed_data';

import 'package:pasteboard/pasteboard.dart';

import '../rendering/image_fit.dart';

/// クリップボードから取り出した内容（#97）。
sealed class ClipboardContent {
  const ClipboardContent();
}

/// 画像がない（テキストだけ・空・画像でないファイルだけをコピーした、など）。
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

/// クリップボードの「ファイル」→「画像データ」の順に見て内容を決める。
///
/// **ファイルを先に見る**のは、ファイラでファイルをコピーしたとき OS が
/// ファイルのアイコン画像も一緒にクリップボードへ載せるため（macOS の Finder は
/// ファイル URL とアイコンの TIFF を載せる）。先に画像データを見ると、
/// 画像ファイルの中身ではなくアイコンを貼り付けてしまう。
///
/// - ファイルがある: 画像拡張子のものがあれば先頭の 1 枚を [ClipboardImageFile]
///   にする。画像でないファイルだけなら、画像データ（= アイコン）へ進まず
///   [ClipboardNoImage]。
/// - ファイルがない: 画像データ。無い・空なら [ClipboardNoImage]。
///
/// [files] と [imageBytes] は取得の口（本番は pasteboard）。テストは差し替える。
Future<ClipboardContent> resolveClipboardContent({
  required Future<List<String>> Function() files,
  required Future<Uint8List?> Function() imageBytes,
}) async {
  final paths = await files();
  if (paths.isNotEmpty) {
    for (final path in paths) {
      if (isUserImagePath(path)) return ClipboardImageFile(path);
    }
    return const ClipboardNoImage();
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
      );
}

/// 貼り付け経路（`pasteUserImageFromClipboard`）が使うリーダ。テストだけが
/// 差し替える（本番コードは代入しない）。
ClipboardImageReader clipboardImageReader =
    const PasteboardClipboardImageReader();
