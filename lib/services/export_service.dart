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
/// 規律3（I/O 隔離）に従い、ファイル書き込み（[savePng] /
/// [writeBytesWithoutOverwrite]）と保存先を示す [revealInFolder] だけを I/O とし、
/// 画像合成 [composeExportImage]・文字列生成（[isoDate] / [compactTime] /
/// [exportFilename] / [numberedFilename]）・コマンド決定（[revealCommandFor]）は
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

/// [DateTime] の時刻を `HHMMSS`（24 時間・ゼロ埋め・コロン無し）に整形する。
///
/// ファイル名用。コロンは Windows / macOS Finder で使えないため区切りを入れない。
/// [isoDate] と同じく引数の [dt] だけを使う（決定論的）。
String compactTime(DateTime dt) {
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  final s = dt.second.toString().padLeft(2, '0');
  return '$h$m$s';
}

/// エクスポート PNG のファイル名を決定論的に組み立てる。
///
/// 例: `ue-protanopia-100pct-2026-06-23.png`。[time]（[compactTime] の文字列）を
/// 渡すと日付の後ろに `_` 区切りで付き、`ue-protanopia-100pct-2026-06-23_140509.png`
/// になる（同じ日に何度書き出しても別名になる、#64）。[symptomId] が `none` などでも
/// 妥当な名前になり、ファイル名に使えない文字（パス区切り・予約文字）は `-` に
/// 正規化する。pure・決定論的（同じ入力なら常に同じ出力）。
String exportFilename({
  required String symptomId,
  required int strengthPercent,
  required String isoDate,
  String? time,
}) {
  final safeId = _sanitizeForFilename(symptomId);
  final stamp = time == null ? isoDate : '${isoDate}_$time';
  return 'ue-$safeId-${strengthPercent}pct-$stamp.png';
}

/// [filename] の [attempt] 番目の候補名を返す（#64: 同名を上書きしない）。
///
/// `attempt <= 1` は [filename] そのもの。2 以上は拡張子の前に `-N` を挟む
/// （`a.png` → `a-2.png` → `a-3.png`）。拡張子が無い名前は末尾に付ける。
/// pure・決定論的。実際に空いている名前を探す I/O は [writeBytesWithoutOverwrite]。
String numberedFilename(String filename, int attempt) {
  if (attempt <= 1) return filename;
  final dot = filename.lastIndexOf('.');
  if (dot <= 0) return '$filename-$attempt';
  return '${filename.substring(0, dot)}-$attempt${filename.substring(dot)}';
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
/// 文言の解決（`colorVisionTypeName` / `resolveConsultNotice` / 強度ラベル /
/// `isoDate`）は呼び出し側（UI、`before_after_view.dart`）の責務。
class ExportCaption {
  const ExportCaption({
    required this.symptomLabel,
    required this.strengthLabel,
    required this.isoDate,
    this.urgencyMessage,
    this.escalationGroups = const [],
    this.disclaimer,
  });

  /// 症状の表示名（例「1型2色覚（赤）」/ "Protanopia"）。
  final String symptomLabel;

  /// 強度の表示文字列（例「強度: 100%」/ "Strength: 100%"）。
  final String strengthLabel;

  /// 受診喚起メッセージ。null = 喚起なし（色覚特性は緊急性 none のため通常 null）。
  final String? urgencyMessage;

  /// 条件付きエスカレーションを緊急度の段ごとにまとめたもの（解決済み、
  /// #76 レビュー M1、再レビュー S-a: PNG でも段ごとの見出しを出す）。
  /// [urgencyMessage] が null でも非空になり得る（urgency=none だが
  /// escalation を持つフィルタ、例: BPPV）。
  final List<ExportEscalationGroup> escalationGroups;

  /// 免責文の短い形（`ConsultNotice.disclaimerShort`、#76 レビュー M1/M2、
  /// 再レビュー M1': 診断ではない旨と根拠の両方を 1 行に収める）。
  /// null = 喚起なし（[urgencyMessage] と [escalationGroups] がどちらも無い）。
  final String? disclaimer;

  /// ISO 日付（`YYYY-MM-DD`）。[isoDate] 関数で整形済みの文字列を渡す。
  final String isoDate;
}

/// [ExportCaption.escalationGroups] の 1 段（見出し + 条件文のリスト）。
/// `lib/l10n/l10n_extensions.dart` の `ConsultEscalationGroup` と同じ形だが、
/// service は enum/i18n を引かない（規律2）ため独立した pure データ型として
/// 持つ。呼び出し側（`before_after_view.dart`）が
/// `ConsultNotice.escalationGroups` からこれへ詰め替える。
class ExportEscalationGroup {
  const ExportEscalationGroup({required this.header, required this.lines});

  /// 見出し（例 "See a doctor right away if:"）。
  final String header;

  /// 解決済みの条件文。
  final List<String> lines;
}

/// [base] 画像の下部にキャプション帯を合成した新しい [ui.Image] を返す。
///
/// `PictureRecorder` + `Canvas` で base をそのまま描き、下に半透明の帯を敷いて
/// [TextPainter] で症状名 / 強度 / 受診喚起（あれば）/ escalation（段ごとの
/// 見出し + 条件文、あれば、#76 レビュー M1・再レビュー S-a）/ 免責文（あれば）
/// / ISO 日付を描画する。戻り画像の高さは `base.height + 帯の高さ`、幅は
/// `base.width`。
///
/// **pure**: 引数の解決済み文字列のみを使い、enum/i18n をここで引かない（規律2）。
/// I/O を持たない（規律3）。
Future<ui.Image> composeExportImage(
    ui.Image base, ExportCaption caption) async {
  final width = base.width;
  // 行リストを組む（urgencyMessage/escalationGroups/disclaimer はいずれも
  // 任意。#76 レビュー M1: 免責文と escalation の行も必ず焼き込む）。
  final lines = <_CaptionLine>[
    _CaptionLine(caption.symptomLabel, _Style.title),
    _CaptionLine(caption.strengthLabel, _Style.body),
    if (caption.urgencyMessage != null)
      _CaptionLine(caption.urgencyMessage!, _Style.note),
    for (final group in caption.escalationGroups) ...[
      _CaptionLine(group.header, _Style.noteHeader),
      for (final line in group.lines) _CaptionLine('• $line', _Style.note),
    ],
    if (caption.disclaimer != null)
      _CaptionLine(caption.disclaimer!, _Style.meta),
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
  // 色の例外（DESIGN.md）: 以下のキャプション色はすべて、書き出す PNG に
  // 焼き込む画素の色。BuildContext を持たず、アプリのテーマ（ライト/ダーク）に
  // かかわらず同じ見た目で共有されるべきものなのでロールにしない。
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

/// [numberedFilename] で空きを探す上限。これを超えたら [StateError]。
const int kMaxExportNumbering = 1000;

/// [dir] に [filename] で [bytes] を書く。**既存のファイルは決して上書きしない**（#64）。
///
/// 同名があれば [numberedFilename] の連番（`-2`, `-3`, ...）で空きを探す。
/// 存在確認と作成は `File.create(exclusive: true)` で 1 操作にしてあるので、
/// 同時に 2 回書き出しても、確認と作成の間に割り込まれて上書きすることがない。
/// 書き込んだファイルのフルパスを返す。規律3: I/O はここと [savePng] だけ。
Future<String> writeBytesWithoutOverwrite(
  Directory dir,
  Uint8List bytes,
  String filename,
) async {
  for (var attempt = 1; attempt <= kMaxExportNumbering; attempt++) {
    final file = File(
      '${dir.path}${Platform.pathSeparator}${numberedFilename(filename, attempt)}',
    );
    try {
      await file.create(exclusive: true);
    } on PathExistsException {
      continue;
    } on FileSystemException {
      // Windows は既存ファイルで PathExistsException でなく別の
      // FileSystemException を返すことがある。存在するなら次の候補へ、
      // 存在しないなら本当の書き込み失敗なので呼び出し側へ返す。
      if (await file.exists()) continue;
      rethrow;
    }
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
  throw StateError('No free file name for $filename in ${dir.path}');
}

/// PNG バイト列をダウンロード or ドキュメントディレクトリへ書き出し、フルパスを返す。
///
/// 規律3: I/O はこの関数と [writeBytesWithoutOverwrite] だけに閉じ込める。
/// デスクトップでは [getDownloadsDirectory]、取得できない環境では
/// [getApplicationDocumentsDirectory] にフォールバックする。macOS のサンドボックス
/// では `com.apple.security.files.downloads.read-write` entitlement が無いと
/// [getDownloadsDirectory] がアプリのコンテナ内（ユーザーに見えない場所）を返す
/// ため、`macos/Runner/*.entitlements` にその entitlement を入れてある（#64）。
/// 同名ファイルは上書きせず連番にする（[writeBytesWithoutOverwrite]）。
Future<String> savePng(Uint8List bytes, String filename) async {
  final dir = (await getDownloadsDirectory()) ??
      (await getApplicationDocumentsDirectory());
  return writeBytesWithoutOverwrite(dir, bytes, filename);
}

/// 保存したファイルをファイルマネージャで示すコマンド（実行ファイルと引数）。
typedef RevealCommand = ({String executable, List<String> arguments});

/// [path] をファイルマネージャで示すコマンドを OS ごとに決める（#64）。
///
/// macOS は Finder でファイルを選択状態にする `open -R`、Windows は
/// `explorer /select,`、それ以外（Linux）は選択の標準手段が無いので
/// 含むフォルダを `xdg-open` で開く。pure（[platform] は
/// `Platform.operatingSystem` の値を渡す）。未対応 OS は null。
RevealCommand? revealCommandFor(String platform, String path) {
  switch (platform) {
    case 'macos':
      return (executable: 'open', arguments: ['-R', path]);
    case 'windows':
      return (executable: 'explorer', arguments: ['/select,$path']);
    case 'linux':
      final sep = path.lastIndexOf('/');
      final parent = sep > 0 ? path.substring(0, sep) : '/';
      return (executable: 'xdg-open', arguments: [parent]);
    default:
      return null;
  }
}

/// 保存したファイルの場所をファイルマネージャで開く。開けなかったら false。
///
/// 規律3: I/O。コマンドの決定は [revealCommandFor]（pure）。Windows の
/// `explorer` は成功でも終了コード 1 を返すので終了コードは見ず、起動できたか
/// だけで判定する。
Future<bool> revealInFolder(String path) async {
  final cmd = revealCommandFor(Platform.operatingSystem, path);
  if (cmd == null) return false;
  try {
    await Process.run(cmd.executable, cmd.arguments);
    return true;
  } on ProcessException {
    return false;
  }
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
  noteHeader,
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
          fontWeight: FontWeight.w500,
          height: 1.25,
        );
      // escalation の段見出し（emergency/earlyConsultation、#76 再レビュー
      // S-a）。note と同じ色だが太字にして、その下の条件文の行と区別する。
      case _Style.noteHeader:
        return const TextStyle(
          color: Color(0xFFFFD27F),
          fontSize: 13,
          fontWeight: FontWeight.bold,
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
