// ImageSourcePicker（#78）のテスト。
//
// - loadUserImageBytes / pickAndLoadUserImage（ファイル選択・ドロップ共通の
//   デコード〜ImageSourceState.setUserImage 経路）を、file_selector/
//   desktop_drop の実プラットフォームチャネルなしで検証する。
// - ウィジェット自体（サンプルチップ・「おすすめに戻す」・drop target への
//   onDragDone 直接呼び出し）も検証する。
//
// file_selector の実ダイアログ・desktop_drop の実 OS ドラッグイベントは
// platform channel を要するため flutter test では踏めない —
// pickImageBytes（本ファイル/production の @visibleForTesting seam）を
// フェイクに差し替え、DropTarget.onDragDone はウィジェットツリーから見つけて
// 合成した DropDoneDetails で直接呼ぶことで、どちらも同じデコード経路
// （loadUserImageBytes）を通ることを実ブリッジなしで確認する。

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/l10n/l10n_extensions.dart';
import 'package:universal_experience/models/sample_catalog.dart';
import 'package:universal_experience/services/image_source_state.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';
import 'package:universal_experience/ui/widgets/image_source_picker.dart';

/// `loadUserImageBytes` の decode 失敗は `FlutterError.reportError` で報告
/// される（before_after_view.dart の generator/renderer 失敗と同じ規律）。
/// 意図的に失敗させるテストがそれでテスト失敗にならないよう差し替える
/// （before_after_view_test.dart の同名ヘルパと同じ理由）。
void _suppressFlutterErrorReporting() {
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (_) {};
  addTearDown(() => FlutterError.onError = originalOnError);
}

Future<Uint8List> _validPngBytes() async {
  final image = await BeforeAfterView.generateSampleImage(8);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final en = lookupAppLocalizations(const Locale('en'));

  Widget localized(Widget child, {ImageSourceState? imageSourceState}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ImageSourceState>.value(
          value: imageSourceState ?? ImageSourceState(),
        ),
        ChangeNotifierProvider<VisionFilterState>(
          create: (_) => VisionFilterState(),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );
  }

  group('loadUserImageBytes', () {
    testWidgets('有効な画像バイト列は ImageSourceState.setUserImage に渡る',
        (tester) async {
      final imageSourceState = ImageSourceState();
      await tester.pumpWidget(localized(
        const SizedBox(),
        imageSourceState: imageSourceState,
      ));
      final context = tester.element(find.byType(SizedBox));

      // PNG エンコード/デコードは実エンジンの非同期処理のため runAsync が要る
      // （before_after_view_test.dart の pumpUntilText と同じ理由）。
      await tester.runAsync(() async {
        final bytes = await _validPngBytes();
        await loadUserImageBytes(context, bytes);
      });

      expect(imageSourceState.isUsingUserImage, isTrue);
      expect(imageSourceState.hasUserImage, isTrue);
    });

    testWidgets('不正なバイト列は SnackBar (imageSourcePickFailed) を出し、画像は読み込まない',
        (tester) async {
      _suppressFlutterErrorReporting();
      final imageSourceState = ImageSourceState();
      await tester.pumpWidget(localized(
        const SizedBox(),
        imageSourceState: imageSourceState,
      ));
      final context = tester.element(find.byType(SizedBox));

      await tester.runAsync(() async {
        await loadUserImageBytes(
          context,
          Uint8List.fromList([1, 2, 3, 4, 5]),
        );
      });
      await tester.pump();

      expect(imageSourceState.hasUserImage, isFalse);
      expect(find.text(en.imageSourcePickFailed), findsOneWidget);
    });
  });

  group('pickAndLoadUserImage', () {
    tearDown(() {
      pickImageBytes = () async => null;
    });

    testWidgets('ピッカーがキャンセルされたら（null）何もしない', (tester) async {
      final imageSourceState = ImageSourceState();
      pickImageBytes = () async => null;
      await tester.pumpWidget(localized(
        const SizedBox(),
        imageSourceState: imageSourceState,
      ));
      final context = tester.element(find.byType(SizedBox));

      await tester.runAsync(() => pickAndLoadUserImage(context));

      expect(imageSourceState.hasUserImage, isFalse);
    });

    testWidgets('ピッカーが返したバイト列を読み込む', (tester) async {
      final imageSourceState = ImageSourceState();
      await tester.pumpWidget(localized(
        const SizedBox(),
        imageSourceState: imageSourceState,
      ));
      final context = tester.element(find.byType(SizedBox));

      await tester.runAsync(() async {
        final bytes = await _validPngBytes();
        pickImageBytes = () async => bytes;
        await pickAndLoadUserImage(context);
      });

      expect(imageSourceState.hasUserImage, isTrue);
    });
  });

  group('ImageSourcePicker ウィジェット', () {
    testWidgets('7 件のサンプルチップが表示され、選択中のものだけ selected になる',
        (tester) async {
      final imageSourceState = ImageSourceState(initialSampleId: 'chart');
      await tester.pumpWidget(localized(
        const ImageSourcePicker(child: SizedBox()),
        imageSourceState: imageSourceState,
      ));
      await tester.pump();

      for (final entry in kSampleCatalog) {
        final chip = tester.widget<ChoiceChip>(
          find.widgetWithText(ChoiceChip, sampleImageName(en, entry.id)),
        );
        expect(chip.selected, entry.id == 'chart', reason: entry.id);
      }
    });

    testWidgets('チップをタップすると selectSample が呼ばれ、「おすすめに戻す」が現れる',
        (tester) async {
      final imageSourceState = ImageSourceState(initialSampleId: 'chart');
      await tester.pumpWidget(localized(
        const ImageSourcePicker(child: SizedBox()),
        imageSourceState: imageSourceState,
      ));
      await tester.pump();

      expect(find.text(en.imageSourceResetToRecommended), findsNothing);

      await tester.tap(find.widgetWithText(
        ChoiceChip,
        sampleImageName(en, 'night_scene'),
      ));
      await tester.pump();

      expect(imageSourceState.selectedSampleId, 'night_scene');
      expect(imageSourceState.isFollowingRecommended, isFalse);
      expect(find.text(en.imageSourceResetToRecommended), findsOneWidget);

      await tester.tap(find.text(en.imageSourceResetToRecommended));
      await tester.pump();

      expect(imageSourceState.isFollowingRecommended, isTrue);
      expect(find.text(en.imageSourceResetToRecommended), findsNothing);
    });

    testWidgets('「自分の画像」チップは読み込み後にだけ現れ、選択状態を示す',
        (tester) async {
      final imageSourceState = ImageSourceState();
      await tester.pumpWidget(localized(
        const ImageSourcePicker(child: SizedBox()),
        imageSourceState: imageSourceState,
      ));
      await tester.pump();
      expect(find.text(en.imageSourceYourPhotoChipLabel), findsNothing);

      await tester.runAsync(() async {
        final image = await BeforeAfterView.generateSampleImage(4);
        imageSourceState.setUserImage(image);
      });
      await tester.pump();

      final chip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, en.imageSourceYourPhotoChipLabel),
      );
      expect(chip.selected, isTrue);
    });

    testWidgets('DropTarget にドロップすると loadUserImageBytes 経由でユーザー画像になる',
        (tester) async {
      final imageSourceState = ImageSourceState();
      await tester.pumpWidget(localized(
        const ImageSourcePicker(child: SizedBox()),
        imageSourceState: imageSourceState,
      ));
      await tester.pump();

      final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));

      await tester.runAsync(() async {
        final bytes = await _validPngBytes();
        final droppedFile = DropItemFile.fromData(bytes, name: 'photo.png');
        dropTarget.onDragDone!(DropDoneDetails(
          files: [droppedFile],
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ));
        // onDragDone 内の非同期処理（デコード）が終わるまで少し待つ。
        for (var i = 0; i < 20; i++) {
          if (imageSourceState.hasUserImage) break;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump();

      expect(imageSourceState.hasUserImage, isTrue);
      expect(imageSourceState.isUsingUserImage, isTrue);
    });
  });
}
