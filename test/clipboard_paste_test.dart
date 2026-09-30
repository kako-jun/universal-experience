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

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
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

/// 呼び出し回数を数え、返す中身をテストごとに差し替えられるフェイクのリーダ。
class _FakeClipboardImageReader implements ClipboardImageReader {
  _FakeClipboardImageReader(this.onRead);

  Future<Uint8List?> Function() onRead;
  int calls = 0;

  @override
  Future<Uint8List?> readImageBytes() {
    calls++;
    return onRead();
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
          home: Scaffold(body: SizedBox()),
        ),
      );
    }

    Future<bool?> paste(
      WidgetTester tester,
      ImageSourceState imageSourceState,
    ) async {
      await tester.pumpWidget(localized(imageSourceState));
      final context = tester.element(find.byType(SizedBox));
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
        expect(pasteShortcutLabel(), 'Cmd+V');

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

      // ボタンにフォーカスが残っていても（貼り付けのガードはテキスト入力のみ）
      // キーボードの貼り付けが効く。
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
