
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/export_service.dart';

/// 保存ダイアログで保存先を選ばせる処理の型。選ばれたパス（キャンセルは null）を返す。
typedef SaveLocationPicker = Future<String?> Function(String suggestedName);

Future<String?> _defaultSaveLocationPicker(String suggestedName) async {
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
SaveLocationPicker saveLocationPicker = _defaultSaveLocationPicker;

/// 選ばれた場所へ書く処理の供給源（テストで差し替え可能）。既定は [writePngToPath]。
@visibleForTesting
Future<String> Function(String path, Uint8List bytes) pngPathWriter =
    writePngToPath;

/// [kind] に対応する失敗文言（#162）。
String exportFailureMessage(AppLocalizations l10n, ExportFailureKind kind) {
  switch (kind) {
    case ExportFailureKind.noTargetDirectory:
      return l10n.exportFailureNoTargetDirectory;
    case ExportFailureKind.notWritable:
      return l10n.exportFailureNotWritable;
    case ExportFailureKind.encodeFailed:
      return l10n.exportFailureEncode;
    case ExportFailureKind.other:
      return l10n.exportFailure;
  }
}

/// 保存先の問題（フォルダが無い・書き込めない）か。保存場所を選び直せば解決しうる。
bool isSaveLocationProblem(ExportFailureKind kind) =>
    kind == ExportFailureKind.noTargetDirectory ||
    kind == ExportFailureKind.notWritable;

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
