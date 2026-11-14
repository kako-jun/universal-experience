// プレビュー描画の診断ログ（#185）: 書式・個人情報を書かないこと・容量上限での退避・
// ウォッチドッグ（長時間未完了の記録）。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/services/preview_diagnostics.dart';

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

  test('例外は型と短いメッセージだけ。ホームディレクトリは ~ に、改行は空白にする', () {
    final home = Platform.environment['HOME'] ?? '/home/someone';
    PreviewDiagnostics.recordError(
        'preview_failed', StateError('bad\nthing at $home/x.png${'y' * 300}'));
    final line = sink.lines.single;
    expect(line, contains('error=StateError'));
    expect(line, isNot(contains('\n')));
    expect(line, isNot(contains(home)));
    expect(line, contains('~/x.png'));
    expect(line.length, lessThan(320), reason: 'メッセージは 200 文字で切る');
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
    await installPreviewDiagnosticsLog(dir);
    final s = PreviewDiagnostics.sink! as FilePreviewDiagnosticsSink;
    await s.flush();
    final log = File('${dir.path}/logs/preview-diagnostics.log');
    expect(await log.readAsString(), contains('app_start'));
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
}
