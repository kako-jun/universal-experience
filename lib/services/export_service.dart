import 'dart:io';
import 'dart:math' as math;
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
/// 規律3（I/O 隔離）に従い、ファイル書き込み（[savePng] / [savePngInto] /
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
/// 正規化する。複数の層を重ねた書き出し（[exportSymptomId]）は層ごとに強度が違い
/// 1 つの % で表せないので、[strengthPercent] を null にして `-Npct` の部分を省く
/// （例 `ue-glaucoma-protanopia-2026-06-23.png`）。pure・決定論的（同じ入力なら常に同じ出力）。
String exportFilename({
  required String symptomId,
  int? strengthPercent,
  required String isoDate,
  String? time,
}) {
  final safeId = _sanitizeForFilename(symptomId);
  final stamp = time == null ? isoDate : '${isoDate}_$time';
  final pct = strengthPercent == null ? '' : '-${strengthPercent}pct';
  return 'ue-$safeId$pct-$stamp.png';
}

/// [exportSymptomId] が返す文字列の最大長。ファイル名全体（`ue-` 接頭辞・日付・時刻・拡張子を
/// 含む）がファイルシステムの上限に近づかないよう、症状 id の部分だけを抑える。
const int kMaxExportSymptomIdLength = 48;

/// 書き出しのファイル名に入れる症状 id を、層の id 列 [ids]（**適用順**）から作る。
///
/// - 1 つなら、そのまま（[exportFilename] が従来どおり正規化する。長さも変えない）。
/// - 複数なら、各 id をファイル名用に正規化（[exportFilename] と同じ規則）して `-` でつなぐ。
///   [kMaxExportSymptomIdLength] を超えるときは、収まる分の id だけを残し、落とした層の数を
///   `-plusN` で示す（id の途中で切らない。先頭の 1 つだけで上限を超えるときに限り、その id を
///   上限で切る）。
///
/// 並びは呼び出し側の順（層は段順に並んでいるので、選んだ順に依存しない）。空なら `none`。
/// pure・決定論的。
String exportSymptomId(List<String> ids) {
  if (ids.isEmpty) return 'none';
  if (ids.length == 1) return ids.single;
  final safe = [for (final id in ids) _sanitizeForFilename(id)];
  final whole = safe.join('-');
  if (whole.length <= kMaxExportSymptomIdLength) return whole;
  final kept = <String>[];
  for (var i = 0; i < safe.length; i++) {
    final rest = safe.length - i - 1;
    final candidate = [...kept, safe[i]].join('-');
    final withSuffix = rest == 0 ? candidate : '$candidate-plus$rest';
    if (withSuffix.length > kMaxExportSymptomIdLength) break;
    kept.add(safe[i]);
  }
  final omitted = safe.length - kept.length;
  if (kept.isEmpty) {
    // 先頭の id 1 つだけで上限を超える（通常は起きない）。id を切って、残りは数だけ示す。
    final suffix = '-plus$omitted';
    final head = safe.first
        .substring(0, kMaxExportSymptomIdLength - suffix.length)
        .replaceAll(RegExp(r'-+$'), '');
    return '$head$suffix';
  }
  return omitted == 0 ? kept.join('-') : '${kept.join('-')}-plus$omitted';
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
/// 文言の解決（`visionFilterDisplayName` / `resolveConsultNotice` / 強度ラベル /
/// `isoDate`）は呼び出し側（UI、`before_after_view.dart`）の責務。
class ExportCaption {
  const ExportCaption({
    required this.symptomLabel,
    required this.strengthLabel,
    required this.isoDate,
    required this.simulationNotice,
    this.experimentalNotice,
    this.urgencyMessage,
    this.escalationGroups = const [],
    this.disclaimer,
    this.layers = const [],
  });

  /// 複数の層を重ねた書き出し用。[layers]（適用順、2 つ以上）の各行を、[symptomLabel] と
  /// [strengthLabel] の 2 行の代わりに描く。この 2 つは描画も参照もしないので空にする。
  ExportCaption.layered({
    required this.layers,
    required this.isoDate,
    required this.simulationNotice,
    this.experimentalNotice,
    this.urgencyMessage,
    this.escalationGroups = const [],
    this.disclaimer,
  })  : assert(layers.length > 1, 'layered caption needs 2 or more layers'),
        symptomLabel = '',
        strengthLabel = '';

  /// 症状の表示名（例「1型2色覚（赤）」/ "Protanopia"）。
  final String symptomLabel;

  /// 強度の表示文字列（例「強度: 100%」/ "Strength: 100%"）。
  final String strengthLabel;

  /// 「これは近似のシミュレーションであり、実際の見え方そのものではない」旨の
  /// 1 文（例「シミュレーション（近似）」/ "Simulation (approximation)"、#80）。
  /// 書き出した画像だけが単体で共有されても、実際の見え方と誤解されないように
  /// **必須**（省略できない）で、受診喚起の有無にかかわらず常に焼き込む。
  final String simulationNotice;

  /// 実験的なフィルタ（検証済みのモデルではなく可視化にとどまるもの。現在は
  /// 四色覚）の書き出しにだけ添える 1 文（例「実験的な可視化」/
  /// "Experimental visualization"、#80）。null = 添えない。[simulationNotice]
  /// と同じく途中で省略せず、必ず全文を焼き込む。
  final String? experimentalNotice;

  /// 受診喚起メッセージ。null = 喚起なし（色覚特性は緊急性 none のため通常 null）。
  final String? urgencyMessage;

  /// 条件付きエスカレーションを緊急度の段ごとにまとめたもの（解決済み、
  /// PNG でも段ごとの見出しを出す）。
  /// [urgencyMessage] が null でも非空になり得る（urgency=none だが
  /// escalation を持つフィルタ、例: BPPV）。
  final List<ExportEscalationGroup> escalationGroups;

  /// 免責文の短い形（`ConsultNotice.disclaimerShort`。診断ではない旨と根拠の
  /// 両方を 1 行に収める）。
  /// null = 喚起なし（[urgencyMessage] と [escalationGroups] がどちらも無い）。
  final String? disclaimer;

  /// ISO 日付（`YYYY-MM-DD`）。[isoDate] 関数で整形済みの文字列を渡す。
  final String isoDate;

  /// 重ねた層ごとの行（適用順）。2 つ以上のときだけ描画に使い（[ExportCaption.layered]）、
  /// そのとき [symptomLabel]・[strengthLabel] の行は描かない。空・1 つなら従来の
  /// [symptomLabel] + [strengthLabel] の 2 行（層が 1 つの書き出しは従来と同じ見た目）。
  final List<ExportLayerRow> layers;
}

/// [ExportCaption.layers] の 1 行（層の表示名と強度の表示文字列、どちらも解決済み）。
class ExportLayerRow {
  const ExportLayerRow({required this.name, required this.strengthLabel});

  /// 層の表示名（例「1型2色覚（赤）」/ "Protanopia"）。
  final String name;

  /// 強度の表示文字列（例「強度: 100%」/ "Strength: 100%"）。
  final String strengthLabel;
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
/// [TextPainter] で症状名 / 強度 / シミュレーション（近似）の注記 /
/// 実験的フィルタの注記（あれば）/ 受診喚起（あれば）/ escalation（段ごとの
/// 見出し + 条件文、あれば）/ 免責文（あれば）/ ISO 日付を描画する。
/// 複数層（[ExportCaption.layers] が 2 行以上、#121）のときは、症状名 + 強度の 2 行の代わりに、
/// 層ごとに 1 行（番号 + 名前 + その層の強度）を描く。
/// シミュレーション（近似）・実験的の注記と層の行は、狭い画像でも省略せず折り返して
/// 全文を描く（画像だけが共有されても近似だと分かるようにするため）。帯の高さは各行の
/// 高さの合計なので、行が増えても切れたり重なったりしない。戻り画像の高さは
/// `base.height + 帯の高さ`、幅は `base.width`。
///
/// **pure**: 引数の解決済み文字列のみを使い、enum/i18n をここで引かない（規律2）。
/// I/O を持たない（規律3）。
Future<ui.Image> composeExportImage(
    ui.Image base, ExportCaption caption) async {
  final width = base.width;
  // 行リストを組む（urgencyMessage/escalationGroups/disclaimer はいずれも
  // 任意。免責文と escalation の行も必ず焼き込む）。
  final layered = caption.layers.length > 1;
  final lines = <_CaptionLine>[
    if (layered)
      // 層ごとに 1 行（番号 + 名前 + 強度）。長い言語では折り返して全文を描く。
      for (var i = 0; i < caption.layers.length; i++)
        _CaptionLine(
          '${i + 1}. ${caption.layers[i].name}',
          _Style.layerName,
          suffix: caption.layers[i].strengthLabel,
        )
    else ...[
      _CaptionLine(caption.symptomLabel, _Style.title),
      _CaptionLine(caption.strengthLabel, _Style.body),
    ],
    _CaptionLine(caption.simulationNotice, _Style.notice),
    if (caption.experimentalNotice != null)
      _CaptionLine(caption.experimentalNotice!, _Style.notice),
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

  const verticalPadding = 14.0;
  const lineGap = 6.0;
  // 左右の余白は通常 16px。ごく狭い画像では文字が画像の外へ出ないよう、
  // 幅の 1/8 まで縮める（幅 128px 未満で効く）。
  final horizontalPadding = math.min(16.0, width / 8);
  // それでも 0 以下にしない（その場合は 1 文字ずつ折り返して描く）。
  final maxTextWidth = math.max(1.0, width - horizontalPadding * 2);

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

/// 2×2 比較の書き出し（[composeCompareGrid]）で、セルの間と外周に空ける余白（px）。
const int kCompareGridGap = 16;

/// [composeCompareGrid] の配置結果: 全体のサイズと、各セルを置く位置。
typedef CompareGridLayout = ({ui.Size size, List<ui.Offset> origins});

/// 大きさの異なりうるセル（[cellSizes]、左上から右へ・下へ並べる順）を [columns]
/// 列のグリッドに並べる配置を計算する。**pure**（画像には触れない）。
///
/// 各スロットは全セルの最大幅 × その行の最大高さ。セルはスロットの左上に置く。
/// セルの間と外周には [kCompareGridGap] の余白を空ける。[composeCompareGrid] が
/// 使い、テストが「各セルがどこに置かれるか」を実画素で検証するときにも使う。
CompareGridLayout compareGridLayout(
  List<ui.Size> cellSizes, {
  int columns = 2,
}) {
  assert(columns >= 1);
  final gap = kCompareGridGap.toDouble();
  final slotWidth = cellSizes.fold<double>(0, (m, s) => math.max(m, s.width));
  final rows = (cellSizes.length / columns).ceil();
  final rowHeights = <double>[
    for (var r = 0; r < rows; r++)
      cellSizes
          .skip(r * columns)
          .take(columns)
          .fold<double>(0, (m, s) => math.max(m, s.height)),
  ];
  final origins = <ui.Offset>[];
  var y = gap;
  for (var r = 0; r < rows; r++) {
    final inRow = math.min(columns, cellSizes.length - r * columns);
    for (var c = 0; c < inRow; c++) {
      origins.add(ui.Offset(gap + c * (slotWidth + gap), y));
    }
    y += rowHeights[r] + gap;
  }
  final usedColumns = math.min(columns, cellSizes.length);
  return (
    size: ui.Size(
      usedColumns == 0 ? 0 : gap + usedColumns * (slotWidth + gap),
      cellSizes.isEmpty ? 0 : y,
    ),
    origins: origins,
  );
}

/// キャプション込みのセル画像 [cells]（[composeExportImage] の戻り値）を [columns]
/// 列のグリッドに並べた 1 枚の [ui.Image] を返す（色覚 4 型の 2×2 比較の書き出し、#84）。
///
/// 配置は [compareGridLayout]。各セルは **加工せずそのまま** 描くので、セル内の
/// 型名・強度・「シミュレーション（近似）」の焼き込みは 1 枚ずつ書き出したときと
/// 同じ画素になる（ここで文言を足さない・削らない）。余白は不透明の暗色で埋める。
/// [cells] は破棄しない（呼び出し側の所有）。**pure**（I/O・i18n なし）。
Future<ui.Image> composeCompareGrid(
  List<ui.Image> cells, {
  int columns = 2,
}) async {
  if (cells.isEmpty) {
    throw ArgumentError.value(cells, 'cells', 'must not be empty');
  }
  final layout = compareGridLayout([
    for (final c in cells) ui.Size(c.width.toDouble(), c.height.toDouble()),
  ], columns: columns);
  final width = layout.size.width.toInt();
  final height = layout.size.height.toInt();

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  // 色の例外（DESIGN.md §2.3）: 書き出す PNG に焼き込む画素の色（キャプション帯と
  // 同じ理由で、テーマのロールにしない）。
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF101418),
  );
  for (var i = 0; i < cells.length; i++) {
    canvas.drawImage(cells[i], layout.origins[i], Paint());
  }
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

/// [numberedFilename] で空きを探す上限。これを超えたら [StateError]。
const int kMaxExportNumbering = 1000;

/// [file] に [bytes] を書く既定の書き込み処理（[writeBytesWithoutOverwrite] の差し替え口）。
Future<void> _defaultWriteFile(File file, Uint8List bytes) async {
  await file.writeAsBytes(bytes, flush: true);
}

/// [dir] に [filename] で [bytes] を書く。**既存のファイルは決して上書きしない**（#64）。
///
/// 同名があれば [numberedFilename] の連番（`-2`, `-3`, ...）で空きを探す。
/// 存在確認と作成は `File.create(exclusive: true)` で 1 操作にしてあるので、
/// 同時に 2 回書き出しても、確認と作成の間に割り込まれて上書きすることがない。
/// 作成に成功したあと書き込みに失敗したら、0 バイトなど中途半端なファイルを残さず
/// 削除してから元の例外を投げる（削除自体の失敗は握りつぶす）。
/// 書き込んだファイルのフルパスを返す。規律3: I/O はここと [savePng] だけ。
///
/// [writeFile] はテスト用の差し替え口（書き込み失敗の再現）。
Future<String> writeBytesWithoutOverwrite(
  Directory dir,
  Uint8List bytes,
  String filename, {
  Future<void> Function(File file, Uint8List bytes) writeFile =
      _defaultWriteFile,
}) async {
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
    try {
      await writeFile(file, bytes);
    } catch (_) {
      try {
        await file.delete();
      } catch (_) {
        // 掃除の失敗で元の例外を隠さない。
      }
      rethrow;
    }
    return file.path;
  }
  throw StateError('No free file name for $filename in ${dir.path}');
}

/// [dir] のシンボリックリンクを解決した実ディレクトリを返す。解決できなければ
/// （リンク切れ・存在しない・権限なし）[dir] をそのまま返す。
Future<Directory> resolveDirectoryOrSelf(Directory dir) async {
  try {
    return Directory(await dir.resolveSymbolicLinks());
  } on FileSystemException {
    return dir;
  }
}

/// [path] のシンボリックリンクを解決した実パスを返す。解決できなければ [path]。
Future<String> resolvePathOrSelf(String path) async {
  try {
    return await File(path).resolveSymbolicLinks();
  } on FileSystemException {
    return path;
  }
}

/// [dir] に PNG を書き、**実パス**を返す（[savePng] の本体。テスト可能にするため分離）。
///
/// macOS のサンドボックスでは `getDownloadsDirectory()` がコンテナ内のパス
/// （`~/Library/Containers/<bundle>/Data/Downloads`）を返し、実機ではそれが
/// `~/Downloads` へのシンボリックリンクになっている。書き込みはリンク越しに実
/// `~/Downloads` へ入るが、そのまま返すと SnackBar・クリップボード・「フォルダで
/// 表示」がコンテナ側のパスになる。ユーザーに見せる／Finder に渡すパスは
/// [resolveSymbolicLinks] で実パスに揃える（解決できなければ元のパス）。
Future<String> savePngInto(
  Directory dir,
  Uint8List bytes,
  String filename,
) async {
  final realDir = await resolveDirectoryOrSelf(dir);
  final written = await writeBytesWithoutOverwrite(realDir, bytes, filename);
  return resolvePathOrSelf(written);
}

/// PNG バイト列をダウンロード or ドキュメントディレクトリへ書き出し、フルパス
/// （シンボリックリンク解決済みの実パス）を返す。
///
/// 規律3: I/O はこの関数・[savePngInto]・[writeBytesWithoutOverwrite] だけに
/// 閉じ込める。デスクトップでは [getDownloadsDirectory]、取得できない環境では
/// [getApplicationDocumentsDirectory] にフォールバックする。macOS のサンドボックス
/// では、`com.apple.security.files.downloads.read-write` entitlement が無いと
/// コンテナ内 `Data/Downloads` のリンク先（実 `~/Downloads`）への書き込みが
/// サンドボックスに拒否される想定で、付けるとリンク経由で実 `~/Downloads` に
/// 書ける（どちらも修正前の実機挙動は未検証）ため、`macos/Runner/*.entitlements`
/// に入れてある（#64）。同名ファイルは
/// 上書きせず連番にする（[writeBytesWithoutOverwrite]）。
Future<String> savePng(Uint8List bytes, String filename) async {
  final dir = (await getDownloadsDirectory()) ??
      (await getApplicationDocumentsDirectory());
  return savePngInto(dir, bytes, filename);
}

/// [revealCommandFor] のコマンドをどう実行し、何を成功とみなすか。
enum RevealMode {
  /// 実行して終了を待ち、終了コード 0 を成功とする（macOS の `open -R`。短命）。
  runAndCheckExit,

  /// 実行して終了を待つが、終了コードは見ない。Windows の `explorer` は
  /// 成功しても終了コード 1 を返すことがあるため。
  runIgnoreExit,

  /// 切り離して起動し、起動できたことだけを成功とする。Linux の `xdg-open` は
  /// 環境によってファイルマネージャが終了するまで戻らないことがあり、切り離すと
  /// 終了コードが取れないため。
  startDetached,
}

/// 保存したファイルをファイルマネージャで示すコマンド。
typedef RevealCommand = ({
  String executable,
  List<String> arguments,
  RevealMode mode,
});

/// [path] をファイルマネージャで示すコマンドを OS ごとに決める（#64）。
///
/// macOS は Finder でファイルを選択状態にする `/usr/bin/open -R`、Windows は
/// `explorer /select,`、それ以外（Linux）は選択の標準手段が無いので含むフォルダを
/// `xdg-open` で開く。pure（[platform] は `Platform.operatingSystem` の値を渡す）。
/// 未対応 OS は null。
///
/// 未確認: Windows でパスにスペースやカンマを含むときの `/select,` の解釈
/// （引数の引用の仕方）は Windows 実機で確認が要る。
RevealCommand? revealCommandFor(String platform, String path) {
  switch (platform) {
    case 'macos':
      return (
        executable: '/usr/bin/open',
        arguments: ['-R', path],
        mode: RevealMode.runAndCheckExit,
      );
    case 'windows':
      return (
        executable: 'explorer',
        arguments: ['/select,$path'],
        mode: RevealMode.runIgnoreExit,
      );
    case 'linux':
      final sep = path.lastIndexOf('/');
      final parent = sep > 0 ? path.substring(0, sep) : '/';
      return (
        executable: 'xdg-open',
        arguments: [parent],
        mode: RevealMode.startDetached,
      );
    default:
      return null;
  }
}

/// [RevealCommand] を実行し、終了コードを返す。[RevealMode.startDetached] は
/// 終了コードが無いので null。起動できなければ [ProcessException]。
typedef RevealRunner = Future<int?> Function(RevealCommand command);

Future<int?> _defaultRevealRunner(RevealCommand command) async {
  if (command.mode == RevealMode.startDetached) {
    await Process.start(
      command.executable,
      command.arguments,
      mode: ProcessStartMode.detached,
    );
    return null;
  }
  final result = await Process.run(command.executable, command.arguments);
  return result.exitCode;
}

/// 保存したファイルの場所をファイルマネージャで開く。開けなかったら false。
///
/// 規律3: I/O。コマンドと成功条件の決定は [revealCommandFor]（pure）。
/// [platform] と [runner] はテスト用の差し替え口。
Future<bool> revealInFolder(
  String path, {
  String? platform,
  RevealRunner runner = _defaultRevealRunner,
}) async {
  final cmd = revealCommandFor(platform ?? Platform.operatingSystem, path);
  if (cmd == null) return false;
  try {
    final exitCode = await runner(cmd);
    return cmd.mode == RevealMode.runAndCheckExit ? exitCode == 0 : true;
  } on ProcessException {
    return false;
  }
}

/// キャプション 1 行の文言とスタイル種別。
class _CaptionLine {
  const _CaptionLine(this.text, this.style, {this.suffix});

  final String text;
  final _Style style;

  /// [text] の後ろに [_Style.body] で続ける文字列（層の行の強度）。null なら無し。
  final String? suffix;

  TextPainter buildPainter(double maxWidth) {
    // 近似・実験的の注記と層の行は行数を制限しない（省略記号で「近似」や層の名前・強度が
    // 消えると、画像だけが共有されたときに実際の見え方と誤解されるため）。
    final unlimited = style == _Style.notice || style == _Style.layerName;
    final suffix = this.suffix;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: style.textStyle,
        children: [
          if (suffix != null)
            // 名前（太字）に続く強度は細字。style に太さを書かないと親（太字）の太さを引き継ぐ。
            TextSpan(
              text: '  $suffix',
              style:
                  _Style.body.textStyle.copyWith(fontWeight: FontWeight.normal),
            ),
        ],
      ),
      textDirection: TextDirection.ltr,
      maxLines: unlimited ? null : (style == _Style.note ? 2 : 1),
      ellipsis: unlimited ? null : '…',
    )..layout(maxWidth: maxWidth);
    return tp;
  }
}

/// 焼き込みテキストのスタイル種別。色は帯（暗背景）に対して読みやすい明色に固定。
enum _Style {
  title,
  layerName,
  body,
  notice,
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
      // 複数層の行の名前。title より一回り小さく、強度（body）と並べても名前が先に読める太さ。
      case _Style.layerName:
        return const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 15,
          fontWeight: FontWeight.bold,
          height: 1.2,
        );
      case _Style.body:
        return const TextStyle(
          color: Color(0xFFE6E6E6),
          fontSize: 14,
          height: 1.2,
        );
      // 「シミュレーション（近似）」。受診喚起（琥珀色）と混ざらない白系で、
      // 強度行より目立つ太さにする。
      case _Style.notice:
        return const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.2,
        );
      case _Style.note:
        return const TextStyle(
          color: Color(0xFFFFD27F),
          fontSize: 13,
          fontWeight: FontWeight.w500,
          height: 1.25,
        );
      // escalation の段見出し（emergency/earlyConsultation）。note と同じ色
      // だが太字にして、その下の条件文の行と区別する。
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
