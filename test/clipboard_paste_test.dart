// クリップボードからの画像貼り付け（#97）のテスト。
//
// - pasteUserImageFromClipboard: 取得（ClipboardImageReader の seam）→
//   サイズ確認 → ダウンスケールデコード → ImageSourceState.setUserImage の経路と、
//   失敗 4 種（画像なし / 巨大 / 非対応形式 / 読み取り失敗）の SnackBar。
// - HomeScreen の Cmd/Ctrl+V と「貼り付け」ボタン: 同じ経路に配線されていること、
//   テキスト入力にフォーカスがある間はキーを奪わないこと（DESIGN.md §6.3）。
//
// 実クリップボード（pasteboard のプラットフォームチャネル）は素の flutter test
// では読めないため、clipboardImageReader をフェイクに差し替える。

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show LogicalKeyboardKey, MethodCall, SystemChannels;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/services/app_shortcuts.dart';
import 'package:universal_experience/services/clipboard_image_reader.dart';
import 'package:universal_experience/services/image_source_state.dart';
import 'package:universal_experience/ui/widgets/image_source_picker.dart';

import 'support/home_screen_harness.dart';
import 'support/sample_image_generator.dart';

/// SnackBar 等で SizedBox が増えても context を一意に取るための目印。
const _hostKey = Key('paste_host');

/// 呼び出し回数を数え、返す中身をテストごとに差し替えられるフェイクのリーダ。
class _FakeClipboardImageReader implements ClipboardImageReader {
  /// 画像データ（`null` は「画像なし」）を返すフェイク。
  _FakeClipboardImageReader(Future<Uint8List?> Function() onRead)
      : _read = (() async {
          final bytes = await onRead();
          return bytes == null
              ? const ClipboardNoImage()
              : ClipboardImageData(bytes);
        });

  /// クリップボードの内容（ファイル等を含む）をそのまま返すフェイク。
  _FakeClipboardImageReader.content(this._read);

  final Future<ClipboardContent> Function() _read;
  int calls = 0;

  @override
  Future<ClipboardContent> read() {
    calls++;
    return _read();
  }
}

/// 失敗は `FlutterError.reportError` で報告される（loadUserImageFile と同じ
/// 規律）。意図的に失敗させるテストがそれでテスト失敗にならないよう差し替える。
void _suppressFlutterErrorReporting() {
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (_) {};
  addTearDown(() => FlutterError.onError = originalOnError);
}

Future<Uint8List> _validPngBytes() async {
  final image = await generateSampleImage(8);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// [condition] が成り立つまで実イベントループを回す（デコードは実エンジンの
/// 非同期処理のため runAsync が要る）。
Future<void> _waitUntil(WidgetTester tester, bool Function() condition) {
  return tester.runAsync(() async {
    for (var i = 0; i < 100; i++) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final en = lookupAppLocalizations(const Locale('en'));
  final ja = lookupAppLocalizations(const Locale('ja'));

  tearDown(() {
    clipboardImageReader = const PasteboardClipboardImageReader();
  });

  group('pasteUserImageFromClipboard', () {
    Widget localized(ImageSourceState imageSourceState) {
      return ChangeNotifierProvider<ImageSourceState>.value(
        value: imageSourceState,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SizedBox(key: _hostKey)),
        ),
      );
    }

    Future<bool?> paste(
      WidgetTester tester,
      ImageSourceState imageSourceState,
    ) async {
      await tester.pumpWidget(localized(imageSourceState));
      final context = tester.element(find.byKey(_hostKey));
      final ok =
          await tester.runAsync(() => pasteUserImageFromClipboard(context));
      await tester.pump();
      return ok;
    }

    testWidgets('画像があれば ImageSourceState.setUserImage に渡り、原画がユーザー画像になる',
        (tester) async {
      final imageSourceState = ImageSourceState();
      final bytes = await tester.runAsync(_validPngBytes);
      final reader = _FakeClipboardImageReader(() async => bytes);
      clipboardImageReader = reader;

      final ok = await paste(tester, imageSourceState);

      expect(ok, isTrue);
      expect(reader.calls, 1);
      expect(imageSourceState.hasUserImage, isTrue);
      expect(imageSourceState.isUsingUserImage, isTrue);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('クリップボードに画像がない（null）と SnackBar を出し、状態は変えない', (tester) async {
      _suppressFlutterErrorReporting();
      final imageSourceState = ImageSourceState();
      clipboardImageReader = _FakeClipboardImageReader(() async => null);

      final ok = await paste(tester, imageSourceState);

      expect(ok, isFalse);
      expect(imageSourceState.hasUserImage, isFalse);
      expect(find.text(en.imageSourcePasteNoImage), findsOneWidget);
    });

    testWidgets('空のバイト列も「画像なし」として扱う', (tester) async {
      _suppressFlutterErrorReporting();
      final imageSourceState = ImageSourceState();
      clipboardImageReader =
          _FakeClipboardImageReader(() async => Uint8List(0));

      final ok = await paste(tester, imageSourceState);

      expect(ok, isFalse);
      expect(imageSourceState.hasUserImage, isFalse);
      expect(find.text(en.imageSourcePasteNoImage), findsOneWidget);
    });

    testWidgets('上限（50MB）を超える画像は、デコードせず専用文言で弾く', (tester) async {
      _suppressFlutterErrorReporting();
      final imageSourceState = ImageSourceState();
      // 中身は不正なバイト列（ゼロ埋め）。デコードまで進めば「非対応形式」の
      // 文言になるので、サイズ超過の文言が出ること自体が「デコード前に弾いた」
      // 証拠になる。
      clipboardImageReader = _FakeClipboardImageReader(
        () async => Uint8List(kMaxUserImageFileBytes + 1),
      );

      final ok = await paste(tester, imageSourceState);

      expect(ok, isFalse);
      expect(imageSourceState.hasUserImage, isFalse);
      expect(find.text(en.imageSourcePasteTooLarge(50)), findsOneWidget);
      expect(find.text(en.imageSourcePasteUnsupported), findsNothing);
    });

    testWidgets('上限ちょうどの大きさまでは許可される（境界）', (tester) async {
      // 有効な PNG の末尾へゼロを足して上限ちょうどにする（PNG は IEND 以降の
      // 余分なバイトを無視する）。サイズ判定が > であること（= 上限ちょうどは
      // 通ること）の境界。
      final imageSourceState = ImageSourceState();
      final bytes = await tester.runAsync(() async {
        final png = await _validPngBytes();
        final padded = Uint8List(kMaxUserImageFileBytes)..setAll(0, png);
        return padded;
      });
      clipboardImageReader = _FakeClipboardImageReader(() async => bytes);

      final ok = await paste(tester, imageSourceState);

      expect(ok, isTrue);
      expect(imageSourceState.hasUserImage, isTrue);
    });

    testWidgets('画像として読めないバイト列は「非対応形式」の SnackBar', (tester) async {
      _suppressFlutterErrorReporting();
      final imageSourceState = ImageSourceState();
      clipboardImageReader = _FakeClipboardImageReader(
        () async => Uint8List.fromList([1, 2, 3, 4, 5]),
      );

      final ok = await paste(tester, imageSourceState);

      expect(ok, isFalse);
      expect(imageSourceState.hasUserImage, isFalse);
      expect(find.text(en.imageSourcePasteUnsupported), findsOneWidget);
    });

    testWidgets('クリップボードの読み取り自体が失敗しても SnackBar で報告する', (tester) async {
      _suppressFlutterErrorReporting();
      final imageSourceState = ImageSourceState();
      clipboardImageReader = _FakeClipboardImageReader(
        () async => throw StateError('clipboard unavailable'),
      );

      final ok = await paste(tester, imageSourceState);

      expect(ok, isFalse);
      expect(imageSourceState.hasUserImage, isFalse);
      expect(find.text(en.imageSourcePasteFailed), findsOneWidget);
    });

    testWidgets('実行中の二重起動は無視され、読み取りは 1 回だけ', (tester) async {
      final imageSourceState = ImageSourceState();
      final bytes = await tester.runAsync(_validPngBytes);
      // Completer は実イベントループ側（runAsync）で作る。テスト本体の
      // FakeAsync ゾーンで作ると、完了のマイクロタスクが回らず固まる。
      final gate =
          (await tester.runAsync(() async => Completer<Uint8List?>()))!;
      final reader = _FakeClipboardImageReader(() => gate.future);
      clipboardImageReader = reader;
      await tester.pumpWidget(localized(imageSourceState));
      final context = tester.element(find.byKey(_hostKey));

      final results = await tester.runAsync(() async {
        final first = pasteUserImageFromClipboard(context);
        // 1 回目がまだ読み取り中の間に、もう 2 回（キーリピート・二度押し相当）。
        final second = pasteUserImageFromClipboard(context);
        final third = pasteUserImageFromClipboard(context);
        gate.complete(bytes);
        return (first: await first, second: await second, third: await third);
      });
      await tester.pump();

      expect(results!.first, isTrue);
      expect(results.second, isFalse, reason: '実行中の呼び出しは無視');
      expect(results.third, isFalse);
      expect(reader.calls, 1);
      expect(imageSourceState.hasUserImage, isTrue);
    });

    testWidgets('完了後は再び貼り付けられる', (tester) async {
      final imageSourceState = ImageSourceState();
      final bytes = await tester.runAsync(_validPngBytes);
      final reader = _FakeClipboardImageReader(() async => bytes);
      clipboardImageReader = reader;

      expect(await paste(tester, imageSourceState), isTrue);
      final context = tester.element(find.byKey(_hostKey));
      final again =
          await tester.runAsync(() => pasteUserImageFromClipboard(context));

      expect(again, isTrue);
      expect(reader.calls, 2, reason: 'ガードは完了で解除される');
    });

    testWidgets('読み取りが例外で終わってもガードは解除され、次は貼り付けられる', (tester) async {
      _suppressFlutterErrorReporting();
      final imageSourceState = ImageSourceState();
      final bytes = await tester.runAsync(_validPngBytes);
      var shouldThrow = true;
      final reader = _FakeClipboardImageReader(() async {
        if (shouldThrow) throw StateError('clipboard unavailable');
        return bytes;
      });
      clipboardImageReader = reader;

      expect(await paste(tester, imageSourceState), isFalse);
      expect(find.text(en.imageSourcePasteFailed), findsOneWidget);

      shouldThrow = false;
      final context = tester.element(find.byKey(_hostKey));
      final ok =
          await tester.runAsync(() => pasteUserImageFromClipboard(context));

      expect(ok, isTrue, reason: '例外のあとでも in-flight ガードが残らない');
      expect(reader.calls, 2);
      expect(imageSourceState.hasUserImage, isTrue);
    });

    group('ファイルをコピーした場合', () {
      late Directory dir;

      setUp(() {
        dir = Directory.systemTemp.createTempSync('ue97_');
      });
      tearDown(() {
        dir.deleteSync(recursive: true);
      });

      testWidgets('画像ファイルは loadUserImageFile の経路で読み込まれる', (tester) async {
        final imageSourceState = ImageSourceState();
        final bytes = await tester.runAsync(_validPngBytes);
        final file = File('${dir.path}/copied.png')..writeAsBytesSync(bytes!);
        clipboardImageReader = _FakeClipboardImageReader.content(
          () async => ClipboardImageFile(file.path),
        );

        final ok = await paste(tester, imageSourceState);

        expect(ok, isTrue);
        expect(imageSourceState.hasUserImage, isTrue);
        expect(imageSourceState.isUsingUserImage, isTrue);
      });

      testWidgets('読めないファイルは選択と同じ文言で失敗し、状態は変えない', (tester) async {
        _suppressFlutterErrorReporting();
        final imageSourceState = ImageSourceState();
        final file = File('${dir.path}/broken.png')
          ..writeAsBytesSync([1, 2, 3]);
        clipboardImageReader = _FakeClipboardImageReader.content(
          () async => ClipboardImageFile(file.path),
        );

        final ok = await paste(tester, imageSourceState);

        expect(ok, isFalse);
        expect(imageSourceState.hasUserImage, isFalse);
        expect(find.text(en.imageSourcePickFailed), findsOneWidget);
      });
    });

    testWidgets('失敗しても、すでに読み込んだユーザー画像は保たれる', (tester) async {
      _suppressFlutterErrorReporting();
      final imageSourceState = ImageSourceState();
      await tester.runAsync(() async {
        imageSourceState.setUserImage(await generateSampleImage(4));
      });
      final before = imageSourceState.current;
      clipboardImageReader = _FakeClipboardImageReader(() async => null);

      await paste(tester, imageSourceState);

      expect(imageSourceState.current, before,
          reason: '貼り付けに失敗しても generation は進まない');
    });
  });

  group('resolveClipboardContent（ファイルを先に見る）', () {
    final pngBytes = Uint8List.fromList([137, 80, 78, 71]);

    Future<ClipboardContent> resolve({
      List<String> files = const [],
      Uint8List? image,
      required List<String> log,
    }) {
      return resolveClipboardContent(
        files: () async {
          log.add('files');
          return files;
        },
        imageBytes: () async {
          log.add('image');
          return image;
        },
      );
    }

    test('画像ファイルがあれば、画像データ（アイコン）は見に行かずファイルを返す', () async {
      final log = <String>[];
      final content = await resolve(
        files: ['/tmp/a/photo.PNG'],
        image: pngBytes,
        log: log,
      );

      expect(content, isA<ClipboardImageFile>());
      expect((content as ClipboardImageFile).path, '/tmp/a/photo.PNG');
      expect(log, ['files'], reason: 'Finder がファイルと一緒に載せるアイコンを拾わない');
    });

    test('複数ファイルなら、画像でないものを飛ばして先頭の画像 1 枚', () async {
      final content = await resolve(
        files: ['/x/readme.txt', '/x/first.jpg', '/x/second.png'],
        log: [],
      );

      expect((content as ClipboardImageFile).path, '/x/first.jpg');
    });

    test('画像でないファイルだけなら、画像データへ進まず「画像なし」', () async {
      final log = <String>[];
      final content = await resolve(
        files: ['/x/readme.txt', '/x/archive.zip', '/x/noextension'],
        image: pngBytes,
        log: log,
      );

      expect(content, isA<ClipboardNoImage>());
      expect(log, ['files'], reason: 'ファイルのアイコン画像を貼り付けない');
    });

    test('ファイルが無ければ画像データを返す', () async {
      final log = <String>[];
      final content = await resolve(image: pngBytes, log: log);

      expect(content, isA<ClipboardImageData>());
      expect((content as ClipboardImageData).bytes, pngBytes);
      expect(log, ['files', 'image']);
    });

    test('ファイルも画像データも無い、または空なら「画像なし」', () async {
      expect(await resolve(log: []), isA<ClipboardNoImage>());
      expect(
        await resolve(image: Uint8List(0), log: []),
        isA<ClipboardNoImage>(),
      );
    });

    test('isUserImagePath: 対応拡張子だけを大文字小文字を問わず受け付ける', () {
      for (final ok in [
        'a.png',
        'a.JPG',
        'a.jpeg',
        'a.gif',
        'a.bmp',
        'a.WebP'
      ]) {
        expect(isUserImagePath(ok), isTrue, reason: ok);
      }
      for (final ng in ['a.txt', 'a.tiff', 'png', 'a.', 'a.png.txt', '']) {
        expect(isUserImagePath(ng), isFalse, reason: ng);
      }
    });
  });

  group('HomeScreen: 貼り付けボタン・Cmd/Ctrl+V', () {
    setUp(installHomeScreenFixtures);
    tearDown(resetHomeScreenFixtures);

    const wide = Size(1200, 4000);

    Future<void> pressPasteShortcut(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    testWidgets('Ctrl+V でクリップボードの画像がプレビューの原画になる', (tester) async {
      final harness = await pumpHomeScreen(tester, size: wide);
      final bytes = await tester.runAsync(_validPngBytes);
      final reader = _FakeClipboardImageReader(() async => bytes);
      clipboardImageReader = reader;
      expect(harness.imageSource.hasUserImage, isFalse);

      await pressPasteShortcut(tester);
      await _waitUntil(tester, () => harness.imageSource.hasUserImage);
      await tester.pump();

      expect(reader.calls, 1);
      expect(harness.imageSource.hasUserImage, isTrue);
      expect(harness.imageSource.isUsingUserImage, isTrue);
    });

    testWidgets('macOS では Cmd+V が割り当てられ、Ctrl+V は効かない', (tester) async {
      // 割り当てはビルド時のプラットフォームで決まるので、画面を組む前に指定する。
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final bytes = await tester.runAsync(_validPngBytes);
        final reader = _FakeClipboardImageReader(() async => bytes);
        clipboardImageReader = reader;
        final harness = await pumpHomeScreen(tester, size: wide);
        expect(pasteShortcutLabel(), '⌘V');

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft,
            platform: 'macos');
        await tester.sendKeyEvent(LogicalKeyboardKey.keyV, platform: 'macos');
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft,
            platform: 'macos');
        await tester.pump();
        expect(reader.calls, 0, reason: 'macOS では Ctrl+V は割り当てない');
        expect(harness.imageSource.hasUserImage, isFalse);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft,
            platform: 'macos');
        await tester.sendKeyEvent(LogicalKeyboardKey.keyV, platform: 'macos');
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft,
            platform: 'macos');
        await _waitUntil(tester, () => harness.imageSource.hasUserImage);
        await tester.pump();
        expect(reader.calls, 1);
        expect(harness.imageSource.hasUserImage, isTrue);
      } finally {
        // フレームワークは test 本体の終了直後に「未リセットの上書きが無いか」を
        // 検査するので、tearDown ではなくここで戻す。
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('テキスト入力（検索欄）にフォーカスがある間は Ctrl+V を奪わない', (tester) async {
      await pumpHomeScreen(tester, size: wide);
      final reader = _FakeClipboardImageReader(() async => null);
      clipboardImageReader = reader;

      // `/` で検索欄（TextField）にフォーカスを移す。
      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      await tester.pump();
      expect(
        tester.binding.focusManager.primaryFocus?.debugLabel,
        'filterSearch',
      );
      expect(isFocusOnTextInput(), isTrue);

      await pressPasteShortcut(tester);

      expect(reader.calls, 0, reason: '入力欄自身の貼り付けが優先される');
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('検索欄では Ctrl+V が実際に入力欄へのテキスト貼り付けとして働く', (tester) async {
      await pumpHomeScreen(tester, size: wide);
      final reader = _FakeClipboardImageReader(() async => null);
      clipboardImageReader = reader;
      // OS のクリップボード（テキスト）をモックする。入力欄の貼り付けは
      // Clipboard.getData（プラットフォームチャネル）を読む。
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.getData') {
            return <String, dynamic>{'text': 'protan'};
          }
          if (call.method == 'Clipboard.hasStrings') {
            return <String, dynamic>{'value': true};
          }
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      await tester.pump();
      expect(isFocusOnTextInput(), isTrue);
      final searchField = find.byWidgetPredicate(
          (w) => w is TextField && w.focusNode?.debugLabel == 'filterSearch');
      expect(tester.widget<TextField>(searchField).controller!.text, isEmpty);

      await pressPasteShortcut(tester);
      await tester.pump();

      expect(tester.widget<TextField>(searchField).controller!.text, 'protan',
          reason: 'キーが画像貼り付けに取られず、入力欄のネイティブ貼り付けに届く');
      expect(reader.calls, 0);
    });

    testWidgets('キーを押しっぱなしにしたリピートでは貼り付けを繰り返さない', (tester) async {
      await pumpHomeScreen(tester, size: wide);
      final reader = _FakeClipboardImageReader(() async => null);
      clipboardImageReader = reader;
      _suppressFlutterErrorReporting();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
      await tester.pump();
      expect(reader.calls, 1);
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyV);
        await tester.pump();
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(reader.calls, 1, reason: 'リピートは includeRepeats: false で無視される');
    });

    testWidgets('「貼り付け」ボタンで同じ経路を通り、押したあとも Ctrl+V が効く', (tester) async {
      _suppressFlutterErrorReporting();
      final harness = await pumpHomeScreen(tester, size: wide);
      final reader = _FakeClipboardImageReader(() async => null);
      clipboardImageReader = reader;

      final button =
          find.widgetWithText(OutlinedButton, ja.imageSourcePasteButton);
      expect(button, findsOneWidget);
      await tester.tap(button);
      await tester.pump();
      await tester.pump();

      expect(reader.calls, 1);
      // 画面のロケールは ja（pumpHomeScreen の既定）。
      expect(find.text(ja.imageSourcePasteNoImage), findsOneWidget);
      expect(harness.imageSource.hasUserImage, isFalse);

      // フォーカスを「貼り付け」ボタンの中に確実に置く（タップでフォーカスが
      // 移るかはプラットフォーム次第なので、明示的に要求する）。
      final buttonElement = tester.element(button);
      bool isInsideButton(BuildContext? context) {
        if (context == null) return false;
        var found = false;
        context.visitAncestorElements((element) {
          if (identical(element, buttonElement)) {
            found = true;
            return false;
          }
          return true;
        });
        return found;
      }

      FocusManager.instance.rootScope.descendants
          .firstWhere((node) => isInsideButton(node.context))
          .requestFocus();
      await tester.pump();
      expect(
          isInsideButton(FocusManager.instance.primaryFocus?.context), isTrue,
          reason: 'フォーカスは「貼り付け」ボタンの中にある');
      expect(isFocusOnInteractiveControl(), isTrue,
          reason: '/ ↑↓ ←→ ならガードされる状態');
      expect(isFocusOnTextInput(), isFalse);

      // その状態でも（貼り付けのガードはテキスト入力のみ）キーボードの貼り付けが効く。
      await pressPasteShortcut(tester);
      expect(reader.calls, 2);
    });

    testWidgets('ボタンのツールチップにキー表記が出る', (tester) async {
      await pumpHomeScreen(tester, size: wide);

      final tooltip = tester.widget<Tooltip>(find.ancestor(
        of: find.widgetWithText(OutlinedButton, ja.imageSourcePasteButton),
        matching: find.byType(Tooltip),
      ));
      expect(tooltip.message, contains(pasteShortcutLabel()));
      expect(pasteShortcutLabel(), 'Ctrl+V',
          reason: 'flutter test の既定プラットフォームは macOS ではない');
    });

    testWidgets('画像貼り付け後、フィルタを切り替えても原画はユーザー画像のまま', (tester) async {
      final harness = await pumpHomeScreen(tester, size: wide);
      final bytes = await tester.runAsync(_validPngBytes);
      clipboardImageReader = _FakeClipboardImageReader(() async => bytes);

      await pressPasteShortcut(tester);
      await _waitUntil(tester, () => harness.imageSource.hasUserImage);
      await tester.pump();
      harness.visionState.select('cataract');
      await tester.pump();

      expect(harness.imageSource.isUsingUserImage, isTrue,
          reason: '貼り付けた画像も #78 のユーザー画像と同じ扱い（自動追従で外れない）');
    });
  });
}
