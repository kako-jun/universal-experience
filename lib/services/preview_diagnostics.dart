import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// プレビュー描画の診断ログ（#185）。
///
/// 実機で「プレビューが固まる」不具合が起きたとき、リリースビルドでも後から原因を
/// 辿れるように、描画経路の失敗・例外・長時間未完了（ウォッチドッグ）だけを 1 行ずつ
/// ファイルへ残す。
///
/// - 置き場所: アプリのサポートディレクトリ（Linux は `~/.local/share/<アプリ id>/`）の
///   `logs/preview-diagnostics.log`。[installPreviewDiagnosticsLog] で有効にする
///   （`main()` だけが呼ぶ。テストでは呼ばないので何も書かない）。
/// - 容量: [kPreviewDiagnosticsMaxBytes] を越えたら `.1` へ退避して新しく始める
///   （最大で 2 ファイル分）。
/// - 中身: 時刻・出来事の種類・描画の段・フィルタのカタログ id・層の数・サンプル id
///   （ユーザー画像は `user` とだけ書く）・例外の型と短いメッセージ。ファイル名・
///   パス・画像の中身は書かない（メッセージ中のホームディレクトリは `~` に置き換える）。
/// - 失敗は握りつぶす（診断のために本体を止めない）。
class PreviewDiagnostics {
  PreviewDiagnostics._();

  /// 書き込み先。null の間は何も書かない（既定。テストも null のまま）。
  static PreviewDiagnosticsSink? sink;

  /// 1 件記録する。[fields] の値は文字列化して `key=value` で並べる。
  static void record(String event, [Map<String, Object?> fields = const {}]) {
    final s = sink;
    if (s == null) return;
    final buf = StringBuffer()
      ..write(DateTime.now().toUtc().toIso8601String())
      ..write(' ')
      ..write(event);
    for (final e in fields.entries) {
      buf
        ..write(' ')
        ..write(e.key)
        ..write('=')
        ..write(_sanitize('${e.value}'));
    }
    s.write(buf.toString());
  }

  /// 例外を記録する。型と、短く切ったメッセージだけを残す（スタックは残さない）。
  static void recordError(
    String event,
    Object error, [
    Map<String, Object?> fields = const {},
  ]) {
    var message = error.toString();
    if (message.length > 200) message = '${message.substring(0, 200)}…';
    record(event, {
      ...fields,
      'error': error.runtimeType,
      'message': message,
    });
  }

  static String _sanitize(String value) {
    var out = value.replaceAll(RegExp(r'[\r\n\t]+'), ' ');
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) out = out.replaceAll(home, '~');
    // 値の中の空白は区切りと紛れるので詰めて引用する。
    return out.contains(' ') ? '"${out.replaceAll('"', "'")}"' : out;
  }
}

/// 診断ログの書き込み先（テストで差し替えられるよう抽象化）。
abstract class PreviewDiagnosticsSink {
  void write(String line);
}

/// ログ 1 ファイルの上限（バイト）。越えたら `.1` へ退避する。
const int kPreviewDiagnosticsMaxBytes = 256 * 1024;

/// [file] に追記する書き込み先。書き込みは順番に 1 つずつ行い、上限を越えたら
/// `.1` へ退避する。I/O の失敗は黙って捨てる。
class FilePreviewDiagnosticsSink implements PreviewDiagnosticsSink {
  FilePreviewDiagnosticsSink(this.file,
      {this.maxBytes = kPreviewDiagnosticsMaxBytes});

  final File file;
  final int maxBytes;
  Future<void> _tail = Future<void>.value();

  @override
  void write(String line) {
    _tail = _tail.then((_) => _append(line)).catchError((Object _) {});
  }

  /// 先に積んだ書き込みがすべて終わるまで待つ（テスト用）。
  @visibleForTesting
  Future<void> flush() => _tail;

  Future<void> _append(String line) async {
    try {
      if (await file.exists() && await file.length() >= maxBytes) {
        await file.rename('${file.path}.1');
      }
      await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }
}

/// [supportDir]（アプリのサポートディレクトリ）の `logs/preview-diagnostics.log` を
/// 診断ログの書き込み先にする。失敗しても例外は出さない（ログなしで続ける）。
Future<void> installPreviewDiagnosticsLog(Directory supportDir) async {
  try {
    final dir = Directory('${supportDir.path}/logs');
    await dir.create(recursive: true);
    PreviewDiagnostics.sink =
        FilePreviewDiagnosticsSink(File('${dir.path}/preview-diagnostics.log'));
    PreviewDiagnostics.record('app_start');
  } catch (_) {}
}

/// 描画 1 回の長時間未完了を見張る（ウォッチドッグ）。[start] から [threshold] を
/// 過ぎても [finish] が呼ばれなければ `preview_stalled` を記録し、その後に終わったら
/// `preview_recovered`（かかった時間つき）を記録する。
class PreviewRenderWatchdog {
  PreviewRenderWatchdog({
    required this.view,
    this.threshold = const Duration(seconds: 10),
  });

  /// 記録に添える描画元の名前（`before_after` / `compare`）。
  final String view;
  final Duration threshold;

  Timer? _timer;
  Stopwatch? _watch;
  bool _stalled = false;

  /// いまどの段を待っているか（`load` / `render` など）。描画側が await の前に書く。
  String stage = 'start';
  Map<String, Object?> _fields = const {};

  /// 描画を始めた。[fields] は記録に添える入力の要約。
  void start(Map<String, Object?> fields) {
    _timer?.cancel();
    _fields = fields;
    stage = 'start';
    _stalled = false;
    _watch = Stopwatch()..start();
    _timer = Timer(threshold, () {
      _stalled = true;
      PreviewDiagnostics.record('preview_stalled', {
        'view': view,
        'stage': stage,
        'elapsed_ms': _watch?.elapsedMilliseconds,
        ..._fields,
      });
    });
  }

  /// 直近の [start] に渡した入力の要約（失敗の記録にも添える）。
  Map<String, Object?> get fields => _fields;

  /// 描画が（成功・失敗・破棄のどれかで）終わった。
  void finish(String outcome) {
    _timer?.cancel();
    _timer = null;
    if (_stalled) {
      PreviewDiagnostics.record('preview_recovered', {
        'view': view,
        'outcome': outcome,
        'elapsed_ms': _watch?.elapsedMilliseconds,
        ..._fields,
      });
    }
    _stalled = false;
    _watch = null;
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
