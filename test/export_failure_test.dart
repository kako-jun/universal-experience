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
import 'package:universal_experience/ui/widgets/export_feedback.dart';

import 'support/sample_image_generator.dart';
import 'support/vision_filter_metadata_fixture.dart';

/// PNG 書き出し失敗の種類別通知・保存場所の選択・クリップボード（#162）のテスト。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FileSystemException fsError(int code) =>
      FileSystemException('x', '/p', OSError('os', code));

  group('classifyExportError', () {
    test('保存先が無い', () {
      expect(classifyExportError(const ExportNoTargetDirectoryException()),
          ExportFailureKind.noTargetDirectory);
      expect(classifyExportError(MissingPlatformDirectoryException('none')),
          ExportFailureKind.noTargetDirectory);
      expect(classifyExportError(fsError(2)),
          ExportFailureKind.noTargetDirectory); // ENOENT
      expect(classifyExportError(fsError(3)),
          ExportFailureKind.noTargetDirectory); // Windows PATH_NOT_FOUND
    });

    test('書き込めない', () {
      for (final code in [1, 13, 30, 5, 19]) {
        expect(classifyExportError(fsError(code)),
            ExportFailureKind.notWritable,
            reason: 'errno $code');
      }
    });

    test('エンコード失敗', () {
      expect(classifyExportError(const ExportEncodeException()),
          ExportFailureKind.encodeFailed);
    });

    test('その他（未知の errno・番号なし・無関係な例外）', () {
      expect(classifyExportError(fsError(28)), ExportFailureKind.other);
      expect(classifyExportError(const FileSystemException('x')),
          ExportFailureKind.other);
      expect(classifyExportError(StateError('boom')), ExportFailureKind.other);
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
            reason: '${locale.languageCode}: 4 種類が別の文言');
        expect(exportFailureMessage(l10n, ExportFailureKind.other),
            l10n.exportFailure);
      }
    });

    test('保存場所を選び直せるのは保存先の問題だけ', () {
      expect(isSaveLocationProblem(ExportFailureKind.noTargetDirectory), isTrue);
      expect(isSaveLocationProblem(ExportFailureKind.notWritable), isTrue);
      expect(isSaveLocationProblem(ExportFailureKind.encodeFailed), isFalse);
      expect(isSaveLocationProblem(ExportFailureKind.other), isFalse);
    });
  });

  test('writePngToPath は選ばれたパスに書く', () async {
    final dir = await Directory.systemTemp.createTemp('ue162');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}${Platform.pathSeparator}out.png';
    final written = await writePngToPath(path, Uint8List.fromList([1, 2, 3]));
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
      previewSourceImageLoader = BeforeAfterView.loadPreviewSourceImage;
      afterImageRenderer = BeforeAfterView.renderAfter;
      exportImageComposer = composeExportImage;
      pngSaver = savePng;
      saveLocationPicker = (name) async => null;
      pngPathWriter = writePngToPath;
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
      await pumpAndExport(tester,
          saver: (b, f) async => throw const ExportNoTargetDirectoryException());
      await tester.tap(find.text(en.exportChooseLocationAction));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(clipboardWrites, isEmpty);
    });
  });
}
