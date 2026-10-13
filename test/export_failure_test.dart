import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/models/preview_image_source.dart';
import 'package:universal_experience/services/export_service.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';
import 'package:universal_experience/ui/widgets/preview_rendering.dart';
import 'package:universal_experience/ui/widgets/export_feedback.dart';

import 'support/sample_image_generator.dart';
import 'support/vision_filter_metadata_fixture.dart';

/// PNG 書き出し失敗の種類別通知・保存場所の選択・クリップボード（#162）のテスト。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FileSystemException fsError(int code) =>
      FileSystemException('x', '/p', OSError('os', code));

  group('classifyExportError', () {
    ExportFailureKind posix(Object e) => classifyExportError(e, isWindows: false);
    ExportFailureKind win(Object e) => classifyExportError(e, isWindows: true);

    test('保存先が無い（OS 共通の型）', () {
      for (final w in [false, true]) {
        expect(
            classifyExportError(const ExportNoTargetDirectoryException(),
                isWindows: w),
            ExportFailureKind.noTargetDirectory);
        expect(
            classifyExportError(MissingPlatformDirectoryException('none'),
                isWindows: w),
            ExportFailureKind.noTargetDirectory);
      }
    });

    test('POSIX の errno', () {
      expect(posix(fsError(2)), ExportFailureKind.noTargetDirectory);
      for (final code in [1, 13, 30]) {
        expect(posix(fsError(code)), ExportFailureKind.notWritable,
            reason: 'errno $code');
      }
      expect(posix(fsError(28)), ExportFailureKind.diskFull);
      // Windows 専用の番号は POSIX では別物（5 = EIO, 3 = ESRCH など）。
      for (final code in [3, 5, 19, 39, 112]) {
        expect(posix(fsError(code)), ExportFailureKind.other,
            reason: 'errno $code');
      }
    });

    test('Windows のエラーコード', () {
      for (final code in [2, 3]) {
        expect(win(fsError(code)), ExportFailureKind.noTargetDirectory,
            reason: 'code $code');
      }
      for (final code in [5, 19]) {
        expect(win(fsError(code)), ExportFailureKind.notWritable,
            reason: 'code $code');
      }
      for (final code in [39, 112]) {
        expect(win(fsError(code)), ExportFailureKind.diskFull,
            reason: 'code $code');
      }
      // POSIX 専用の番号は Windows では別物。
      for (final code in [1, 13, 28, 30]) {
        expect(win(fsError(code)), ExportFailureKind.other,
            reason: 'code $code');
      }
    });

    test('エンコード失敗', () {
      expect(classifyExportError(const ExportEncodeException()),
          ExportFailureKind.encodeFailed);
    });

    test('その他（番号なし・無関係な例外）', () {
      expect(classifyExportError(const FileSystemException('x')),
          ExportFailureKind.other);
      expect(classifyExportError(StateError('boom')), ExportFailureKind.other);
    });
  });

  group('ensurePngExtension', () {
    test('.png が無ければ足し、あれば（大文字小文字を問わず）そのまま', () {
      expect(ensurePngExtension('/a/b'), '/a/b.png');
      expect(ensurePngExtension('/a/b.jpg'), '/a/b.jpg.png');
      expect(ensurePngExtension('/a/b.png'), '/a/b.png');
      expect(ensurePngExtension('/a/b.PNG'), '/a/b.PNG');
      expect(ensurePngExtension('/a/b.Png'), '/a/b.Png');
    });
  });

  group('exportFailureMessage', () {
    test('種類ごとに別の文言（en / ja とも）', () {
      for (final locale in const [Locale('en'), Locale('ja')]) {
        final l10n = lookupAppLocalizations(locale);
        final messages = {
          for (final k in ExportFailureKind.values)
            exportFailureMessage(l10n, k),
        };
        expect(messages.length, ExportFailureKind.values.length,
            reason: '${locale.languageCode}: 全種類が別の文言');
        expect(exportFailureMessage(l10n, ExportFailureKind.other),
            l10n.exportFailure);
      }
    });

    test('保存場所を選び直せるのは保存先の問題だけ', () {
      expect(isSaveLocationProblem(ExportFailureKind.noTargetDirectory), isTrue);
      expect(isSaveLocationProblem(ExportFailureKind.notWritable), isTrue);
      expect(isSaveLocationProblem(ExportFailureKind.diskFull), isTrue);
      expect(isSaveLocationProblem(ExportFailureKind.encodeFailed), isFalse);
      expect(isSaveLocationProblem(ExportFailureKind.other), isFalse);
    });
  });

  test('writePngToPath: .png を足したときは既存ファイルを上書きしない', () async {
    final dir = await Directory.systemTemp.createTemp('ue162c');
    addTearDown(() => dir.delete(recursive: true));
    final sep = Platform.pathSeparator;
    final existing = File('${dir.path}${sep}out.png');
    await existing.writeAsBytes([9, 9, 9]);
    final written =
        await writePngToPath('${dir.path}${sep}out', Uint8List.fromList([1]));
    expect(await existing.readAsBytes(), [9, 9, 9], reason: '既存は無傷');
    expect(written, isNot(endsWith('${sep}out.png')));
    expect(await File(written).readAsBytes(), [1]);
  });

  test('writePngToPath: .png で終わる選択は（ダイアログの確認済みなので）上書きする', () async {
    final dir = await Directory.systemTemp.createTemp('ue162d');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}${Platform.pathSeparator}out.png';
    await File(path).writeAsBytes([9, 9, 9]);
    final written = await writePngToPath(path, Uint8List.fromList([1]));
    expect(await File(written).readAsBytes(), [1]);
  });

  test('writePngToPath は選ばれたパスに書く', () async {
    final dir = await Directory.systemTemp.createTemp('ue162');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}${Platform.pathSeparator}out';
    final written = await writePngToPath(path, Uint8List.fromList([1, 2, 3]));
    expect(written, endsWith('out.png'), reason: '拡張子が無ければ .png を足す');
    expect(await File(written).readAsBytes(), [1, 2, 3]);
  });

  group('BeforeAfterView の書き出し通知', () {
    final clipboardWrites = <String>[];
    final en = lookupAppLocalizations(const Locale('en'));

    setUp(() {
      installVisionFilterMetadataFixture();
      clipboardWrites.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardWrites.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
      previewSourceImageLoader = loadDefaultPreviewSourceImage;
      afterImageRenderer = renderDefaultAfter;
      exportImageComposer = composeExportImage;
      resetExportSeams();
      resetVisionFilterMetadataProviders();
    });

    Future<void> pumpAndExport(
      WidgetTester tester, {
      required Future<String> Function(Uint8List, String) saver,
    }) async {
      late ui.Image before1, after1, composedStub;
      await tester.runAsync(() async {
        before1 = await generateSampleImage(4);
        after1 = await generateSampleImage(4);
        composedStub = await generateSampleImage(4);
      });
      previewSourceImageLoader = (source, size) => Future.value(before1);
      afterImageRenderer = (source, filter, strength) => Future.value(after1);
      exportImageComposer = (base, caption) async => composedStub;
      pngSaver = saver;

      await tester.pumpWidget(const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: BeforeAfterView(
            filter: VisionFilter.protanopia(),
            filterId: 'protanopia',
            strength: 1.0,
            imageSource: SamplePreviewImageSource('test'),
            sampleSize: 16,
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byTooltip(en.exportButtonTooltip));
      await tester.runAsync(() async {
        for (var i = 0; i < 50; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await Future<void>.delayed(const Duration(milliseconds: 20));
          if (find.byType(SnackBar).evaluate().isNotEmpty) return;
        }
      });
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('成功してもクリップボードには書かない。「パスをコピー」を押すと書く',
        (tester) async {
      await pumpAndExport(tester, saver: (b, f) async => '/real/Downloads/$f');

      expect(find.textContaining('/real/Downloads/'), findsOneWidget);
      expect(clipboardWrites, isEmpty, reason: '書き出しだけでは書かない');

      await tester.tap(find.text(en.exportCopyPathAction));
      await tester.pump();
      expect(clipboardWrites.length, 1);
      expect(clipboardWrites.single, startsWith('/real/Downloads/ue-'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(en.exportPathCopied), findsOneWidget);
    });

    for (final c in <(String, Object, String Function())>[
      ('保存先なし', const ExportNoTargetDirectoryException(),
          () => en.exportFailureNoTargetDirectory),
      ('書き込み不可', const FileSystemException('x', '/p', OSError('perm', 13)),
          () => en.exportFailureNotWritable),
      ('その他', StateError('boom'), () => en.exportFailure),
    ]) {
      testWidgets('保存失敗 (${c.$1}) は種類別の文言', (tester) async {
        await pumpAndExport(tester, saver: (b, f) async => throw c.$2);
        expect(find.text(c.$3()), findsOneWidget);
        expect(clipboardWrites, isEmpty);
      });
    }

    testWidgets('保存先の問題でない失敗には「保存場所を選ぶ」を付けない', (tester) async {
      await pumpAndExport(tester, saver: (b, f) async => throw StateError('x'));
      expect(find.text(en.exportChooseLocationAction), findsNothing);
    });

    testWidgets('保存先に書けないとき「保存場所を選ぶ」で選んだ場所へ書ける',
        (tester) async {
      const chosen = '/picked/place/shot.png';
      Uint8List? writtenBytes;
      String? writtenPath;
      pngPathWriter = (path, bytes) async {
        writtenPath = path;
        writtenBytes = bytes;
        return path;
      };
      String? suggested;
      saveLocationPicker = (name) async {
        suggested = name;
        return chosen;
      };
      await pumpAndExport(tester,
          saver: (b, f) async => throw const ExportNoTargetDirectoryException());
      expect(find.text(en.exportFailureNoTargetDirectory), findsOneWidget);

      await tester.tap(find.text(en.exportChooseLocationAction));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(suggested, startsWith('ue-protanopia-'));
      expect(writtenPath, chosen);
      expect(writtenBytes, isNotEmpty);
      expect(find.textContaining('shot.png'), findsOneWidget,
          reason: '成功通知に選んだ場所が出る');
      expect(clipboardWrites, isEmpty);
    });

    testWidgets('保存ダイアログをキャンセルしたら何も書かない', (tester) async {
      saveLocationPicker = (name) async => null;
      var writes = 0;
      pngPathWriter = (path, bytes) async {
        writes++;
        return path;
      };
      await pumpAndExport(tester,
          saver: (b, f) async => throw const ExportNoTargetDirectoryException());
      await tester.tap(find.text(en.exportChooseLocationAction));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(writes, 0);
      expect(clipboardWrites, isEmpty);
    });

    testWidgets('選んだ場所への書き込みも失敗したら、その失敗文言をもう一度出す（ループしない）',
        (tester) async {
      var picks = 0;
      saveLocationPicker = (name) async {
        picks++;
        return '/readonly/x.png';
      };
      pngPathWriter = (path, bytes) async => throw const FileSystemException(
          'x', '/readonly/x.png', OSError('denied', 13));
      await pumpAndExport(tester,
          saver: (b, f) async => throw const ExportNoTargetDirectoryException());
      await tester.tap(find.text(en.exportChooseLocationAction));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));

      expect(picks, 1, reason: '自動で再度ダイアログを開かない');
      expect(find.text(en.exportFailureNotWritable), findsOneWidget);
      expect(find.text(en.exportChooseLocationAction), findsOneWidget,
          reason: 'もう一度選び直せる');
      expect(tester.takeException(), isNull);
    });
  });
}
