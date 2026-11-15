// プレビュー描画の診断ログ（#185）: 書式・個人情報を書かないこと・容量上限での退避・
// ウォッチドッグ（長時間未完了の記録）。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/services/preview_diagnostics.dart';
import 'package:universal_experience/services/vision_filter_state.dart';

class _MemorySink implements PreviewDiagnosticsSink {
  final lines = <String>[];
  @override
  void write(String line) => lines.add(line);
}

void main() {
  late _MemorySink sink;

  setUp(() {
    sink = _MemorySink();
    PreviewDiagnostics.sink = sink;
  });
  tearDown(() => PreviewDiagnostics.sink = null);

  test('書き込み先が無ければ何もしない（既定・テスト）', () {
    PreviewDiagnostics.sink = null;
    PreviewDiagnostics.record('x', {'a': 1});
    expect(sink.lines, isEmpty);
  });

  test('1 件 1 行で、時刻・種類・key=value を並べる', () {
    PreviewDiagnostics.record('preview_failed', {'stage': 'render', 'n': 2});
    expect(sink.lines, hasLength(1));
    expect(
        sink.lines.single,
        matches(
            RegExp(r'^\d{4}-\d\d-\d\dT\S+Z preview_failed stage=render n=2$')));
  });

  test('例外は型名だけを書き、メッセージ（パス・ファイル名を含みうる）は書かない', () {
    PreviewDiagnostics.recordError(
        'preview_failed',
        StateError('bad\nthing at /mnt/data/secret-name.png and '
            r'C:\Users\someone\Pictures\private.jpg'));
    final line = sink.lines.single;
    expect(line, endsWith(' preview_failed error=StateError'));
    for (final leak in ['/mnt', 'secret-name', 'Users', 'someone', 'private']) {
      expect(line, isNot(contains(leak)));
    }
  });

  test('値は英数字と _.+:- だけにし、パス区切り・空白・改行は _ に崩す', () {
    PreviewDiagnostics.record('x', {
      'a': '/home/u/x y\nz',
      'b': r'C:\Users\u',
      'c': 'myopia+starbursts',
      'd': 'cell:protanopia',
      'e': 0.4,
      'f': 'z' * 200,
    });
    final line = sink.lines.single;
    expect(line, contains(' a=_home_u_x_y_z '));
    expect(line, contains(' b=C:_Users_u '));
    expect(line, contains(' c=myopia+starbursts '));
    expect(line, contains(' d=cell:protanopia '));
    expect(line, contains(' e=0.4 '));
    expect(line, contains(' f=${'z' * 80}'));
    expect(line, isNot(contains('z' * 81)));
    expect(line.split(' '), hasLength(2 + 6), reason: '値の中に区切りの空白が混ざらない');
  });

  test('ファイルの書き込み先は上限を越えたら .1 へ退避する', () async {
    final dir = await Directory.systemTemp.createTemp('preview_diag');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/preview-diagnostics.log');
    final fileSink = FilePreviewDiagnosticsSink(file, maxBytes: 100);
    for (var i = 0; i < 10; i++) {
      fileSink.write('line $i ${'x' * 20}');
    }
    await fileSink.flush();
    expect(await file.exists(), isTrue);
    expect(await File('${file.path}.1').exists(), isTrue);
    expect(await file.length(), lessThan(100 + 40));
    expect(await file.readAsString(), contains('line 9'));
  });

  test('installPreviewDiagnosticsLog は logs/ を作り、起動を記録する', () async {
    final dir = await Directory.systemTemp.createTemp('preview_diag');
    addTearDown(() => dir.delete(recursive: true));
    await installPreviewDiagnosticsLog(dir, environment: const {});
    final s = PreviewDiagnostics.sink! as FilePreviewDiagnosticsSink;
    await s.flush();
    final log = File('${dir.path}/logs/preview-diagnostics.log');
    expect(await log.readAsString(), contains('app_start'));
  });

  test('UE_PREVIEW_DIAGNOSTICS=0 なら何も書かず、ファイルも作らない', () async {
    PreviewDiagnostics.sink = null;
    final dir = await Directory.systemTemp.createTemp('preview_diag');
    addTearDown(() => dir.delete(recursive: true));
    await installPreviewDiagnosticsLog(dir,
        environment: const {'UE_PREVIEW_DIAGNOSTICS': '0'});
    expect(PreviewDiagnostics.sink, isNull);
    expect(await Directory('${dir.path}/logs').exists(), isFalse);
    expect(previewDiagnosticsDisabled(const {'UE_PREVIEW_DIAGNOSTICS': '1'}),
        isFalse);
    expect(previewDiagnosticsDisabled(const {}), isFalse);
  });

  group('ウォッチドッグ', () {
    testWidgets('しきい値を越えたら止まっている段を記録し、その後の完了も記録する', (tester) async {
      {
        final w = PreviewRenderWatchdog(
            view: 'before_after', threshold: const Duration(seconds: 10));
        w.start({'filter': 'starbursts', 'sample': 'info_board'});
        w.stage = 'render';
        await tester.pump(const Duration(seconds: 9));
        expect(sink.lines, isEmpty);
        await tester.pump(const Duration(seconds: 2));
        expect(sink.lines, hasLength(1));
        expect(sink.lines.single, contains('preview_stalled'));
        expect(sink.lines.single, contains('stage=render'));
        expect(sink.lines.single, contains('filter=starbursts'));
        w.finish('done');
        expect(sink.lines.last, contains('preview_recovered'));
        expect(sink.lines.last, contains('outcome=done'));
      }
    });

    testWidgets('しきい値の前に終われば何も書かない', (tester) async {
      final w = PreviewRenderWatchdog(view: 'compare');
      w.start(const {});
      await tester.pump(const Duration(seconds: 3));
      w.finish('done');
      await tester.pump(const Duration(seconds: 30));
      expect(sink.lines, isEmpty);
    });
  });

  test('原画比較の開始・解除を記録する（ホットキーが持っているかだけ添える）', () {
    final state = VisionFilterState();
    final hotkey = Object();
    final hud = Object();
    final stop = watchBypassForDiagnostics(state,
        isHeldByHotkey: () => state.isHeldBy(hotkey));
    state.acquireBypass(hotkey);
    state.acquireBypass(hud); // すでに原画比較中: 記録しない
    state.releaseBypass(hotkey);
    state.releaseBypass(hud);
    state.acquireBypass(hud);
    state.clearBypass();
    stop();
    state.acquireBypass(hotkey);
    expect([for (final l in sink.lines) l.substring(l.indexOf(' ') + 1)], [
      'bypass_on hotkey=true',
      'bypass_off',
      'bypass_on hotkey=false',
      'bypass_off',
    ]);
  });
}
