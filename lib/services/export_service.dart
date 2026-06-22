import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

/// フィルタ適用後（after）画像を、症状名・強度・受診喚起・日付を焼き込んだ
/// PNG として書き出すための pure 中核 + I/O 分離サービス (#43)。
///
/// 規律2（定義/状態の分離）に従い、このサービスは **enum / i18n を一切引かない**。
/// 表示文言（症状名・強度ラベル・受診喚起・ISO 日付）は呼び出し側（UI）が
/// `AppLocalizations` で解決し、[ExportCaption] として渡す。これによりサービスは
/// pure（テスト容易・ロケール非依存）に保たれる。
///
/// 規律3（I/O 隔離）に従い、ファイル書き込みは [savePng] のみに閉じ込め、
/// 画像合成 [composeExportImage] と文字列生成（[isoDate] / [exportFilename]）は
/// 副作用を持たない純粋関数とする。

/// [DateTime] を `YYYY-MM-DD`（ゼロ埋め・スラッシュ禁止・ISO 固定）に整形する。
///
/// 日付表示規約（ISO 8601・スラッシュ M/D は曖昧で不可）に従う。テスト容易性の
/// ため `DateTime.now()` ではなく引数の [dt] を使う（決定論的）。
String isoDate(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// エクスポート PNG のファイル名を決定論的に組み立てる。
///
/// 例: `ue-protanopia-100pct-2026-06-23.png`。[symptomId] が `none` などでも妥当な
/// 名前になり、ファイル名に使えない文字（パス区切り・予約文字）は `-` に正規化する。
/// pure・決定論的（同じ入力なら常に同じ出力）。
String exportFilename({
  required String symptomId,
  required int strengthPercent,
  required String isoDate,
}) {
  final safeId = _sanitizeForFilename(symptomId);
  return 'ue-$safeId-${strengthPercent}pct-$isoDate.png';
}

/// ファイル名に使えない文字を `-` に置換し、連続・前後の `-` を畳む。
String _sanitizeForFilename(String raw) {
  // 英数・ハイフン・アンダースコア以外を `-` に。空なら `unknown`。
  final replaced = raw.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-');
  final collapsed = replaced.replaceAll(RegExp(r'-+'), '-');
  final trimmed = collapsed.replaceAll(RegExp(r'^-+|-+$'), '');
  return trimmed.isEmpty ? 'unknown' : trimmed;
}

/// [composeExportImage] に焼き込むキャプション（**解決済み i18n 文字列**）。
///
/// service を pure に保つため、enum/id ではなく既にローカライズされた文字列を受ける。
/// 文言の解決（`colorVisionTypeName` / `consultMessageForUrgency` / 強度ラベル /
/// `isoDate`）は呼び出し側（UI）の責務。
class ExportCaption {
  const ExportCaption({
    required this.symptomLabel,
    required this.strengthLabel,
    required this.isoDate,
    this.urgencyMessage,
  });

  /// 症状の表示名（例「1型2色覚（赤）」/ "Protanopia"）。
  final String symptomLabel;

  /// 強度の表示文字列（例「強度: 100%」/ "Strength: 100%"）。
  final String strengthLabel;

  /// 受診喚起メッセージ。null = 喚起なし（色覚特性は緊急性 none のため通常 null）。
  final String? urgencyMessage;

  /// ISO 日付（`YYYY-MM-DD`）。[isoDate] 関数で整形済みの文字列を渡す。
  final String isoDate;
}

/// [base] 画像の下部にキャプション帯を合成した新しい [ui.Image] を返す。
///
/// `PictureRecorder` + `Canvas` で base をそのまま描き、下に半透明の帯を敷いて
/// [TextPainter] で症状名 / 強度 / 受診喚起（あれば）/ ISO 日付を描画する。戻り画像の
/// 高さは `base.height + 帯の高さ`、幅は `base.width`。
///
/// **pure**: 引数の解決済み文字列のみを使い、enum/i18n をここで引かない（規律2）。
/// I/O を持たない（規律3）。
Future<ui.Image> composeExportImage(
    ui.Image base, ExportCaption caption) async {
  final width = base.width;
  // 行リストを組む（urgencyMessage は任意）。
  final lines = <_CaptionLine>[
    _CaptionLine(caption.symptomLabel, _Style.title),
    _CaptionLine(caption.strengthLabel, _Style.body),
    if (caption.urgencyMessage != null)
      _CaptionLine(caption.urgencyMessage!, _Style.note),
    _CaptionLine(caption.isoDate, _Style.meta),
  ];

  const horizontalPadding = 16.0;
  const verticalPadding = 14.0;
  const lineGap = 6.0;
  final maxTextWidth = width - horizontalPadding * 2;

  // 各行の TextPainter を用意し、帯の高さを測る。
  final painters = <TextPainter>[];
  double textBlockHeight = 0;
  for (var i = 0; i < lines.length; i++) {
    final tp = lines[i].buildPainter(maxTextWidth);
    painters.add(tp);
    textBlockHeight += tp.height;
    if (i != lines.length - 1) textBlockHeight += lineGap;
  }
  final bandHeight = (textBlockHeight + verticalPadding * 2).ceilToDouble();
  final totalHeight = base.height + bandHeight.toInt();

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);

  // base をそのまま上部に描画。
  canvas.drawImage(base, Offset.zero, Paint());

  // キャプション帯（半透明の濃い背景）。
  final bandTop = base.height.toDouble();
  canvas.drawRect(
    Rect.fromLTWH(0, bandTop, width.toDouble(), bandHeight),
    Paint()..color = const Color(0xE6101418),
  );

  // 行を順に描画。
  double y = bandTop + verticalPadding;
  for (final tp in painters) {
    tp.paint(canvas, Offset(horizontalPadding, y));
    y += tp.height + lineGap;
  }

  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, totalHeight);
  } finally {
    picture.dispose();
  }
}

/// PNG バイト列をダウンロード or ドキュメントディレクトリへ書き出し、フルパスを返す。
///
/// 規律3: I/O はこの関数だけに閉じ込める。デスクトップでは
/// [getDownloadsDirectory]、取得できない環境では
/// [getApplicationDocumentsDirectory] にフォールバックする。
Future<String> savePng(Uint8List bytes, String filename) async {
  final dir = (await getDownloadsDirectory()) ??
      (await getApplicationDocumentsDirectory());
  final file = File('${dir.path}${Platform.pathSeparator}$filename');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

/// キャプション 1 行の文言とスタイル種別。
class _CaptionLine {
  const _CaptionLine(this.text, this.style);

  final String text;
  final _Style style;

  TextPainter buildPainter(double maxWidth) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style.textStyle),
      textDirection: TextDirection.ltr,
      maxLines: style == _Style.note ? 2 : 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    return tp;
  }
}

/// 焼き込みテキストのスタイル種別。色は帯（暗背景）に対して読みやすい明色に固定。
enum _Style {
  title,
  body,
  note,
  meta;

  TextStyle get textStyle {
    switch (this) {
      case _Style.title:
        return const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 18,
          fontWeight: FontWeight.bold,
          height: 1.2,
        );
      case _Style.body:
        return const TextStyle(
          color: Color(0xFFE6E6E6),
          fontSize: 14,
          height: 1.2,
        );
      case _Style.note:
        return const TextStyle(
          color: Color(0xFFFFD27F),
          fontSize: 13,
          fontStyle: FontStyle.italic,
          height: 1.25,
        );
      case _Style.meta:
        return const TextStyle(
          color: Color(0xFFB8C0C8),
          fontSize: 12,
          height: 1.2,
        );
    }
  }
}
