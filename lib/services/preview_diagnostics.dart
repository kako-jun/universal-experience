import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'vision_filter_state.dart';

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
/// - 中身: 時刻・出来事の種類・描画の段・フィルタのカタログ id・層の数・強度・
///   サンプル id（ユーザー画像は `user` とだけ書く）・寸法・例外の型名。例外の
///   メッセージは書かない（パスやファイル名を含みうるため）。値は英数字と `_.+:-` だけに
///   絞り、それ以外の文字（パス区切り・空白など）は `_` に置き換える。
/// - 無効化: 環境変数 `UE_PREVIEW_DIAGNOSTICS=0` で起動すると書かない
///   （[installPreviewDiagnosticsLog]）。判断の記録は
///   `docs/adr/2026-11-14-preview-diagnostics-log.md`。
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

  /// 例外を記録する。型名だけを残す（メッセージ・スタックは残さない。メッセージには
  /// ファイルのパスや名前が入りうるため）。
  static void recordError(
    String event,
    Object error, [
    Map<String, Object?> fields = const {},
  ]) {
    record(event, {...fields, 'error': error.runtimeType});
  }

  /// 値を英数字と `_.+:-` だけにする（それ以外は `_`）。長さは 80 文字まで。
  /// 書くのはこちらで組み立てた id・数値だけの想定だが、万一パスや自由な文字列が
  /// 渡っても、区切り文字ごと崩して読めないようにする。
  static String _sanitize(String value) {
    final out = value.replaceAll(RegExp(r'[^A-Za-z0-9_.+:\-]'), '_');
    return out.length > 80 ? out.substring(0, 80) : out;
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

/// 診断ログを無効にする環境変数（値が `0` のとき無効）。
const String kPreviewDiagnosticsEnvVar = 'UE_PREVIEW_DIAGNOSTICS';

/// [environment] で診断ログが無効にされているか（[kPreviewDiagnosticsEnvVar] が `0`）。
bool previewDiagnosticsDisabled(Map<String, String> environment) =>
    environment[kPreviewDiagnosticsEnvVar]?.trim() == '0';

/// [supportDir]（アプリのサポートディレクトリ）の `logs/preview-diagnostics.log` を
/// 診断ログの書き込み先にする。失敗しても例外は出さない（ログなしで続ける）。
/// [kPreviewDiagnosticsEnvVar] が `0` なら何もしない（ファイルも作らない）。
Future<void> installPreviewDiagnosticsLog(Directory supportDir,
    {Map<String, String>? environment}) async {
  if (previewDiagnosticsDisabled(environment ?? Platform.environment)) return;
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

/// 原画比較（bypass）の切り替わりを診断ログへ残す（#185 の切り分け）。
///
/// ホットキー「押している間だけ原画」は、keyUp が届かない環境では押すたびに
/// 切り替わる（`hotkey_actions.dart`）。1 回押しただけで原画表示が残ると、
/// 「フィルタが反映されない」と同じ見え方になるが、描画は止まらないので描画の記録には
/// 出ない。そこで `bypass_on` / `bypass_off`（on のときはホットキーが持っているか）を
/// 残す。誰が持っているかは [isHeldByHotkey] でだけ見る（ほかの情報は書かない）。
/// 戻り値を呼ぶと見張りをやめる。
VoidCallback watchBypassForDiagnostics(
  VisionFilterState state, {
  required bool Function() isHeldByHotkey,
}) {
  var last = state.bypassed;
  void listener() {
    final now = state.bypassed;
    if (now == last) return;
    last = now;
    PreviewDiagnostics.record(
      now ? 'bypass_on' : 'bypass_off',
      now ? {'hotkey': isHeldByHotkey()} : const {},
    );
  }

  state.addListener(listener);
  return () => state.removeListener(listener);
}
