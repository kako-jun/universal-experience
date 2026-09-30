import 'dart:typed_data';

import 'package:pasteboard/pasteboard.dart';

/// クリップボードから画像のバイト列を取る口（#97）。
///
/// `image_source_picker.dart` の `pickImageFile`（#78）と同じ seam パターン:
/// 本番は [PasteboardClipboardImageReader]（プラットフォームチャネル経由で
/// OS のクリップボードを読む。素の `flutter test` では使えない）、テストは
/// フェイクの実装へ差し替える。
abstract interface class ClipboardImageReader {
  /// クリップボードにある画像のバイト列を返す。画像が無ければ `null`。
  ///
  /// 形式は実装依存（[PasteboardClipboardImageReader] は macOS/Linux/Windows
  /// のいずれでも PNG）。呼び出し側は形式を仮定せず、`decodeUserImageBytes`
  /// で読めるかどうかで判断する。読み取り自体の失敗は例外で伝える。
  Future<Uint8List?> readImageBytes();
}

/// `pasteboard` プラグイン（macOS: NSPasteboard、Linux: GtkClipboard、
/// Windows: クリップボードの DIB）で実クリップボードを読む本番実装。
class PasteboardClipboardImageReader implements ClipboardImageReader {
  const PasteboardClipboardImageReader();

  @override
  Future<Uint8List?> readImageBytes() => Pasteboard.image;
}

/// 貼り付け経路（`pasteUserImageFromClipboard`）が使うリーダ。テストだけが
/// 差し替える（本番コードは代入しない）。
ClipboardImageReader clipboardImageReader =
    const PasteboardClipboardImageReader();
