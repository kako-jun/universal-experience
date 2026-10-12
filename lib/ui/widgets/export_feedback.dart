import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../services/export_service.dart';

/// [_BeforeAfterViewState._export] が使う PNG 書き出しステップの型。
///
/// 実体は [savePng]。`path_provider` の実プラットフォームを要する I/O
/// （`test/export_service_test.dart` の doc 参照）なので、widget test では
/// フェイクに差し替えて実ファイルへ触れずに済ませる。
typedef PngSaver = Future<String> Function(Uint8List bytes, String filename);

/// PNG 書き出しの供給源（テストで差し替え可能）。既定は [savePng]。
@visibleForTesting
PngSaver pngSaver = savePng;

/// 保存したファイルの場所を開く処理の型。実体は [revealInFolder]。
/// 実 OS のファイルマネージャを起動するので、widget test ではフェイクに差し替える。
typedef FolderRevealer = Future<bool> Function(String path);

/// 「フォルダで表示」の供給源（テストで差し替え可能）。既定は [revealInFolder]。
@visibleForTesting
FolderRevealer folderRevealer = revealInFolder;

/// [bytes] を [filename] で保存して保存先のフルパスを返す（[pngSaver] の呼び出し口。
/// クリップボードには触れない、#162）。
Future<String> saveExportPng(Uint8List bytes, String filename) =>
    pngSaver(bytes, filename);

/// 書き出し成功の SnackBar（保存先の表示 + 「フォルダで表示」 + 「パスをコピー」）。
/// クリップボードへはコピー操作が押されたときだけ書く（#162）。
///
/// #64: 保存先はユーザーが実際に辿れる場所（Downloads）。パスを読ませるだけでなく、
/// その場でファイルマネージャを開けるようにする。アクション付きの SnackBar は既定で
/// 消えないので、時間で閉じるよう明示する。[messenger] は書き出し開始時に取って
/// あり context を使わないので、ビューが外れた後でも「開けなかった」を必ず知らせる。
void showExportSuccess(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  String path,
) {
  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Expanded(child: Text(l10n.exportSuccess(path))),
          // #162: パスのコピーはこの操作が押されたときだけ（書き出し時に勝手に
          // クリップボードを上書きしない）。
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: path));
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(content: Text(l10n.exportPathCopied)),
                );
            },
            style: TextButton.styleFrom(
              foregroundColor:
                  Theme.of(messenger.context).colorScheme.inversePrimary,
            ),
            child: Text(l10n.exportCopyPathAction),
          ),
        ],
      ),
      persist: false,
      duration: const Duration(seconds: 10),
      action: SnackBarAction(
        label: l10n.exportRevealAction,
        onPressed: () async {
          final opened = await folderRevealer(path);
          if (!opened) {
            messenger.showSnackBar(
              SnackBar(content: Text(l10n.exportRevealFailure)),
            );
          }
        },
      ),
    ),
  );
}

/// 保存ダイアログで保存先を選ばせる処理の型。選ばれたパス（キャンセルは null）を返す。
typedef SaveLocationPicker = Future<String?> Function(String suggestedName);

Future<String?> defaultSaveLocationPicker(String suggestedName) async {
  final location = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: const [
      XTypeGroup(label: 'PNG', extensions: ['png']),
    ],
  );
  return location?.path;
}

/// 保存ダイアログの供給源（テストで差し替え可能）。既定は file_selector の
/// [getSaveLocation]（macOS / Windows / Linux 対応）。
@visibleForTesting
SaveLocationPicker saveLocationPicker = defaultSaveLocationPicker;

/// 選ばれた場所へ書く処理の供給源（テストで差し替え可能）。既定は [writePngToPath]。
@visibleForTesting
Future<String> Function(String path, Uint8List bytes) pngPathWriter =
    writePngToPath;

/// 書き出し周りの差し替え口（[pngSaver] / [folderRevealer] / [saveLocationPicker] /
/// [pngPathWriter]）を本番の既定へ戻す（テストの tearDown 用、#162）。
@visibleForTesting
void resetExportSeams() {
  pngSaver = savePng;
  folderRevealer = revealInFolder;
  saveLocationPicker = defaultSaveLocationPicker;
  pngPathWriter = writePngToPath;
}

/// [kind] に対応する失敗文言（#162）。
String exportFailureMessage(AppLocalizations l10n, ExportFailureKind kind) {
  switch (kind) {
    case ExportFailureKind.noTargetDirectory:
      return l10n.exportFailureNoTargetDirectory;
    case ExportFailureKind.notWritable:
      return l10n.exportFailureNotWritable;
    case ExportFailureKind.diskFull:
      return l10n.exportFailureDiskFull;
    case ExportFailureKind.encodeFailed:
      return l10n.exportFailureEncode;
    case ExportFailureKind.other:
      return l10n.exportFailure;
  }
}

/// 保存先の問題（フォルダが無い・書き込めない・空き容量なし）か。保存場所を選び直せば解決しうる。
bool isSaveLocationProblem(ExportFailureKind kind) =>
    kind == ExportFailureKind.noTargetDirectory ||
    kind == ExportFailureKind.notWritable ||
    kind == ExportFailureKind.diskFull;

/// 書き出し失敗の SnackBar（#162）。[error] を分類して種類別の文言を出す。
///
/// 保存先の問題で、かつ書き出す [bytes] が手元にあるときだけ、SnackBar に
/// 「保存場所を選ぶ」を付ける。押すと保存ダイアログで場所を選び、書けたら
/// [onSaved] を呼ぶ（書けなければもう一度この関数で知らせる）。常時ダイアログを
/// 出さず、既定の保存先（ダウンロード）への 1 タップ書き出しは維持する。
void showExportFailure(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  Object error, {
  Uint8List? bytes,
  String? filename,
  required void Function(String path) onSaved,
}) {
  final kind = classifyExportError(error);
  final canChoose =
      isSaveLocationProblem(kind) && bytes != null && filename != null;
  messenger.showSnackBar(
    SnackBar(
      content: Text(exportFailureMessage(l10n, kind)),
      persist: false,
      duration: const Duration(seconds: 10),
      action: canChoose
          ? SnackBarAction(
              label: l10n.exportChooseLocationAction,
              onPressed: () async {
                try {
                  final path = await saveLocationPicker(filename);
                  if (path == null) return;
                  onSaved(await pngPathWriter(path, bytes));
                } catch (e) {
                  showExportFailure(
                    messenger,
                    l10n,
                    e,
                    bytes: bytes,
                    filename: filename,
                    onSaved: onSaved,
                  );
                }
              },
            )
          : null,
    ),
  );
}
