import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/l10n/l10n_extensions.dart';
import 'package:universal_experience/models/preview_image_source.dart';
import 'package:universal_experience/services/color_vision_compare.dart';
import 'package:universal_experience/services/export_service.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';
import 'package:universal_experience/ui/widgets/color_vision_compare_view.dart';

import 'support/vision_filter_metadata_fixture.dart';

/// 色覚 4 型の一覧比較ビュー（2×2、#84）のテスト。
///
/// 実ブリッジ（sensus の CPU `apply()`）は `flutter test` では呼べないので、描画は
/// `afterImageRenderer` のフェイク（型ごとに決まった単色を返す）に差し替える。
/// 書き出しは合成・エンコード（実エンジン）まで本物を通し、保存（`pngSaver`）だけを
/// 差し替えて、保存された PNG を実際にデコードして画素で確かめる。

const int _kSize = 96;

/// 型ごとの単色（フェイクの描画結果）。4 色とも互いに異なる。
const Map<String, int> _kCellColor = <String, int>{
  'protanopia': 0xFFCC3333,
  'deuteranopia': 0xFF33CC33,
  'tritanopia': 0xFF3333CC,
  'achromatopsia': 0xFF999999,
};

List<FlutterErrorDetails> _suppressFlutterErrorReporting() {
  final reported = <FlutterErrorDetails>[];
  final originalOnError = FlutterError.onError;
  FlutterError.onError = reported.add;
  addTearDown(() => FlutterError.onError = originalOnError);
  return reported;
}

Future<ui.Image> _solid(int size, int argb) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    ui.Paint()..color = ui.Color(argb),
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(size, size);
  } finally {
    picture.dispose();
  }
}

Future<({int width, int height, Uint8List rgba})> _decodePng(
    Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final result = (
    width: image.width,
    height: image.height,
    rgba: data!.buffer.asUint8List(),
  );
  image.dispose();
  codec.dispose();
  return result;
}

int _argbAt(({int width, int height, Uint8List rgba}) img, int x, int y) {
  final o = (y * img.width + x) * 4;
  return (img.rgba[o + 3] << 24) |
      (img.rgba[o] << 16) |
      (img.rgba[o + 1] << 8) |
      img.rgba[o + 2];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const jaLocale = Locale('ja');
  const enLocale = Locale('en');

  late Map<String, ui.Image> masters;

  /// フィルタから決まった単色の master（型ごと）の複製を返す。
  String idOf(VisionFilter filter) => kColorVisionCompareEntries
      .firstWhere((e) => colorVisionCompareFilter(e) == filter)
      .id;

  setUp(() {
    installVisionFilterMetadataFixture();
  });

  tearDown(() {
    previewSourceImageLoader = BeforeAfterView.loadPreviewSourceImage;
    afterImageRenderer = BeforeAfterView.renderAfter;
    exportImageComposer = composeExportImage;
    pngSaver = savePng;
    folderRevealer = revealInFolder;
    resetVisionFilterMetadataProviders();
  });

  Widget localized(Widget child, {Locale locale = enLocale}) => MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  Widget view(double strength) => ColorVisionCompareView(
        strength: strength,
        imageSource: const SamplePreviewImageSource('test'),
        sampleSize: _kSize,
      );

  /// master 画像と、読み込み・描画のフェイクを組む。描画の呼び出し（型・強さ）を
  /// [calls] に記録し、[gate] があれば呼び出し番号ごとに待たせられる。
  Future<
      ({
        List<({String id, double strength})> calls,
        List<ui.Image> returned,
        int Function() maxActive,
      })> installFakes(
    WidgetTester tester, {
    Future<void>? Function(int callNumber)? gate,
    Object? Function(int callNumber)? failOn,
  }) async {
    final built = <String, ui.Image>{};
    late ui.Image beforeMaster;
    await tester.runAsync(() async {
      for (final e in _kCellColor.entries) {
        built[e.key] = await _solid(_kSize, e.value);
      }
      beforeMaster = await _solid(_kSize, 0xFFFFFFFF);
    });
    masters = built;
    addTearDown(() {
      for (final m in built.values) {
        m.dispose();
      }
      beforeMaster.dispose();
    });

    final calls = <({String id, double strength})>[];
    final returned = <ui.Image>[];
    var active = 0;
    var maxActive = 0;
    previewSourceImageLoader = (source, size) async => beforeMaster.clone();
    afterImageRenderer = (source, filter, strength) async {
      final n = calls.length + 1;
      calls.add((id: idOf(filter!), strength: strength));
      active++;
      if (active > maxActive) maxActive = active;
      try {
        final wait = gate?.call(n);
        if (wait != null) await wait;
        final failure = failOn?.call(n);
        if (failure != null) throw failure;
        final image = masters[idOf(filter)]!.clone();
        returned.add(image);
        return image;
      } finally {
        active--;
      }
    };
    return (calls: calls, returned: returned, maxActive: () => maxActive);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump();
    }
  }

  /// 書き出しの完了（保存 or SnackBar）を実時間で待つ。
  Future<void> waitFor(WidgetTester tester, bool Function() done) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 100; i++) {
        if (done()) return;
        await tester.pump(const Duration(milliseconds: 20));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('描画', () {
    testWidgets('4 型をカタログ順に、同じ強さで 1 回ずつ描画する', (tester) async {
      final fakes = await installFakes(tester);
      await tester.pumpWidget(localized(view(0.6)));
      await settle(tester);

      expect(fakes.calls, [
        (id: 'protanopia', strength: 0.6),
        (id: 'deuteranopia', strength: 0.6),
        (id: 'tritanopia', strength: 0.6),
        (id: 'achromatopsia', strength: 0.6),
      ]);
      expect(find.byType(PreviewImageView), findsNWidgets(4));
    });

    testWidgets('各セルに型名の見出しがある（en / ja）', (tester) async {
      await installFakes(tester);
      for (final locale in [enLocale, jaLocale]) {
        await tester.pumpWidget(localized(view(1.0), locale: locale));
        await settle(tester);
        final l10n = lookupAppLocalizations(locale);
        for (final entry in kColorVisionCompareEntries) {
          expect(find.text(visionFilterName(l10n, entry.id)), findsOneWidget,
              reason: '${locale.languageCode}: ${entry.id}');
        }
        expect(find.text(l10n.compareSharedStrengthNote(100)), findsOneWidget);
      }
    });

    testWidgets('各セルの Semantics ラベルは「型名 + 強さ」（en / ja）', (tester) async {
      final handle = tester.ensureSemantics();
      await installFakes(tester);
      for (final locale in [enLocale, jaLocale]) {
        await tester.pumpWidget(localized(view(0.6), locale: locale));
        await settle(tester);
        final l10n = lookupAppLocalizations(locale);
        for (final entry in kColorVisionCompareEntries) {
          final label = l10n.compareCellSemanticsLabel(
              visionFilterName(l10n, entry.id), 60);
          expect(find.bySemanticsLabel(label), findsOneWidget,
              reason: '${locale.languageCode}: $label');
        }
      }
      handle.dispose();
    });

    testWidgets('強さを変えると 4 型とも新しい強さで描き直す', (tester) async {
      final fakes = await installFakes(tester);
      await tester.pumpWidget(localized(view(0.6)));
      await settle(tester);
      await tester.pumpWidget(localized(view(0.2)));
      await settle(tester);

      expect(fakes.calls.length, 8);
      expect(fakes.calls.skip(4).map((c) => c.strength), everyElement(0.2));
      expect(fakes.calls.skip(4).map((c) => c.id), [
        'protanopia',
        'deuteranopia',
        'tritanopia',
        'achromatopsia',
      ]);
      final en = lookupAppLocalizations(enLocale);
      expect(find.text(en.compareSharedStrengthNote(20)), findsOneWidget);
      expect(find.text(en.compareSharedStrengthNote(60)), findsNothing);
    });
  });

  group('直列・最新優先', () {
    testWidgets('描画中に強さが変わっても描画は同時に走らず、最後は最新の強さになる', (tester) async {
      final first = Completer<void>();
      final fakes = await installFakes(
        tester,
        gate: (n) => n == 1 ? first.future : null,
      );
      await tester.pumpWidget(localized(view(0.3)));
      await tester.pump();
      expect(fakes.calls.length, 1, reason: '1 型目の描画中で止まっている');

      // 描画中に強さを変える。進行中の 1 本が終わるまで新しい描画は始まらない。
      await tester.pumpWidget(localized(view(0.9)));
      await tester.pump();
      expect(fakes.calls.length, 1);

      first.complete();
      await settle(tester);

      // 古い強さの残り 3 型は描かれず、最新の強さで 4 型がやり直される。
      expect(fakes.calls, [
        (id: 'protanopia', strength: 0.3),
        (id: 'protanopia', strength: 0.9),
        (id: 'deuteranopia', strength: 0.9),
        (id: 'tritanopia', strength: 0.9),
        (id: 'achromatopsia', strength: 0.9),
      ]);
      expect(fakes.maxActive(), 1);

      // 打ち切られた古い結果は破棄されている。表示は最新の強さ。
      expect(fakes.returned.first.debugDisposed, isTrue);
      final en = lookupAppLocalizations(enLocale);
      expect(find.text(en.compareSharedStrengthNote(90)), findsOneWidget);
    });

    testWidgets('連続して強さを変えても、保留は最新の 1 件に畳まれる', (tester) async {
      final first = Completer<void>();
      final fakes = await installFakes(
        tester,
        gate: (n) => n == 1 ? first.future : null,
      );
      await tester.pumpWidget(localized(view(0.1)));
      await tester.pump();
      await tester.pumpWidget(localized(view(0.4)));
      await tester.pump();
      await tester.pumpWidget(localized(view(0.7)));
      await tester.pump();
      first.complete();
      await settle(tester);

      expect(fakes.calls.map((c) => c.strength).toSet(), {0.1, 0.7},
          reason: '途中の 0.4 は描かれない');
      expect(fakes.calls.length, 5);
      expect(fakes.maxActive(), 1);
    });

    testWidgets('描画中に外されても例外を出さず、結果の画像を破棄する', (tester) async {
      final first = Completer<void>();
      final fakes = await installFakes(
        tester,
        gate: (n) => n == 1 ? first.future : null,
      );
      await tester.pumpWidget(localized(view(0.5)));
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      first.complete();
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(fakes.calls.length, 1, reason: '外れたあとは残りの型を描かない');
      expect(fakes.returned.single.debugDisposed, isTrue);
    });
  });

  group('失敗', () {
    testWidgets('描画が失敗したら失敗を表示して書き出しは出さず、次の変更で復帰する', (tester) async {
      _suppressFlutterErrorReporting();
      var broken = true;
      await installFakes(
        tester,
        failOn: (n) => (broken && n == 2) ? StateError('boom') : null,
      );
      final en = lookupAppLocalizations(enLocale);

      await tester.pumpWidget(localized(view(0.5)));
      await settle(tester);
      expect(find.text(en.previewFailed), findsNWidgets(4));
      expect(find.byTooltip(en.exportButtonTooltip), findsNothing);
      expect(find.byType(PreviewImageView), findsNothing);

      broken = false;
      await tester.pumpWidget(localized(view(0.8)));
      await settle(tester);
      expect(find.text(en.previewFailed), findsNothing);
      expect(find.byType(PreviewImageView), findsNWidgets(4));
      expect(find.byTooltip(en.exportButtonTooltip), findsOneWidget);
    });

    testWidgets('画像の読み込みが失敗しても失敗表示になる', (tester) async {
      _suppressFlutterErrorReporting();
      await installFakes(tester);
      previewSourceImageLoader =
          (source, size) => Future<ui.Image>.error(StateError('no image'));
      await tester.pumpWidget(localized(view(0.5)));
      await settle(tester);
      final en = lookupAppLocalizations(enLocale);
      expect(find.text(en.previewFailed), findsNWidgets(4));
      expect(find.byTooltip(en.exportButtonTooltip), findsNothing);
    });
  });

  group('書き出し', () {
    Future<void> tapExport(WidgetTester tester) async {
      final en = lookupAppLocalizations(enLocale);
      await tester.tap(find.byTooltip(en.exportButtonTooltip));
    }

    testWidgets(
        '4 セルを 1 枚の PNG にして保存する。各セルは型ごとの画素で、'
        'キャプションに型名・同じ強さ・シミュレーション注記が焼き込まれる', (tester) async {
      await installFakes(tester);
      final captions = <ExportCaption>[];
      final composedSizes = <ui.Size>[];
      final perCell = <ui.Image>[];
      exportImageComposer = (base, caption) async {
        captions.add(caption);
        final composed = await composeExportImage(base, caption);
        composedSizes.add(
            ui.Size(composed.width.toDouble(), composed.height.toDouble()));
        // 単独で書き出したときの画素（比較用）。
        perCell.add(await composeExportImage(base, caption));
        return composed;
      };
      addTearDown(() {
        for (final i in perCell) {
          i.dispose();
        }
      });
      String? savedFilename;
      Uint8List? savedBytes;
      pngSaver = (bytes, filename) async {
        savedBytes = bytes;
        savedFilename = filename;
        return '/fake/Downloads/$filename';
      };

      await tester.pumpWidget(localized(view(0.6)));
      await settle(tester);
      await tapExport(tester);
      await waitFor(tester, () => savedBytes != null);

      final en = lookupAppLocalizations(enLocale);
      // キャプション: カタログ順の型名・全セル同じ強さ・シミュレーション注記。
      expect(captions.map((c) => c.symptomLabel), [
        for (final e in kColorVisionCompareEntries) visionFilterName(en, e.id),
      ]);
      expect(captions.map((c) => c.strengthLabel),
          everyElement(en.strengthLabel(60)));
      expect(captions.map((c) => c.simulationNotice),
          everyElement(en.exportSimulationNotice));
      expect(captions.map((c) => c.experimentalNotice), everyElement(isNull),
          reason: '2×2 の 4 型は実験的ではない');

      expect(savedFilename, isNotNull);
      expect(
        savedFilename,
        matches(RegExp(
            r'^ue-color-vision-compare-60pct-\d{4}-\d{2}-\d{2}_\d{6}\.png$')),
      );

      // 保存された PNG を実際にデコードして画素で確かめる。
      final png = await tester.runAsync(() => _decodePng(savedBytes!));
      final img = png!;
      final layout = compareGridLayout(composedSizes);
      expect(img.width, layout.size.width.toInt());
      expect(img.height, layout.size.height.toInt());

      final centers = <int>[];
      for (var i = 0; i < 4; i++) {
        final ox = layout.origins[i].dx.toInt();
        final oy = layout.origins[i].dy.toInt();
        // 画像部分は型ごとの単色そのもの。
        final id = kColorVisionCompareEntries[i].id;
        centers.add(_argbAt(img, ox + _kSize ~/ 2, oy + _kSize ~/ 2));
        expect(centers.last, _kCellColor[id], reason: 'セル $i ($id) の画像部分');

        // セル全体（画像 + 帯）の不透明画素は、単独で書き出したときと同じ。
        final cellPng = await tester.runAsync(() async {
          final bytes = await encodeImagePng(perCell[i]);
          return _decodePng(bytes!);
        });
        final cell = cellPng!;
        var white = 0;
        for (var y = 0; y < cell.height; y++) {
          for (var x = 0; x < cell.width; x++) {
            final expected = _argbAt(cell, x, y);
            if (expected >>> 24 == 0xFF) {
              expect(_argbAt(img, ox + x, oy + y), expected,
                  reason: 'セル $i の不透明画素 ($x,$y)');
            }
            if (y >= _kSize && expected == 0xFFFFFFFF) white++;
          }
        }
        expect(white, greaterThan(0), reason: 'セル $i の帯にキャプションが焼き込まれている');
      }
      expect(centers.toSet().length, 4, reason: '4 セルの色は互いに異なる');

      // 成功の通知。
      await waitFor(tester, () => find.byType(SnackBar).evaluate().isNotEmpty);
      expect(find.text(en.exportSuccess('/fake/Downloads/$savedFilename')),
          findsOneWidget);
    });

    testWidgets('書き出しのキャプションは、描画済みの強さから作る（表示より先に進んだ強さは使わない）', (tester) async {
      final pending = Completer<void>();
      // 1〜4 回目（強さ 1.0）は即完了、5 回目（強さ 0.5 の再描画）は止めておく。
      await installFakes(tester, gate: (n) => n >= 5 ? pending.future : null);
      final captions = <ExportCaption>[];
      exportImageComposer = (base, caption) async {
        captions.add(caption);
        return composeExportImage(base, caption);
      };
      String? savedFilename;
      pngSaver = (bytes, filename) async {
        savedFilename = filename;
        return '/fake/Downloads/$filename';
      };

      await tester.pumpWidget(localized(view(1.0)));
      await settle(tester);
      await tester.pumpWidget(localized(view(0.5)));
      await tester.pump();

      await tapExport(tester);
      await waitFor(tester, () => savedFilename != null);

      final en = lookupAppLocalizations(enLocale);
      expect(captions, hasLength(4));
      expect(captions.map((c) => c.strengthLabel),
          everyElement(en.strengthLabel(100)));
      expect(savedFilename, contains('100pct'));
      expect(savedFilename, isNot(contains('50pct')));

      pending.complete();
      await settle(tester);
    });

    testWidgets('保存に失敗したら失敗を SnackBar で知らせ、次の書き出しができる', (tester) async {
      await installFakes(tester);
      var fail = true;
      var saved = 0;
      pngSaver = (bytes, filename) async {
        if (fail) throw StateError('disk full');
        saved++;
        return '/fake/Downloads/$filename';
      };

      await tester.pumpWidget(localized(view(0.6)));
      await settle(tester);
      await tapExport(tester);
      final en = lookupAppLocalizations(enLocale);
      await waitFor(
          tester, () => find.text(en.exportFailure).evaluate().isNotEmpty);
      expect(find.text(en.exportFailure), findsOneWidget);
      expect(saved, 0);

      // 失敗のあとも書き出しボタンは押せる。
      fail = false;
      await tapExport(tester);
      await waitFor(tester, () => saved > 0);
      expect(saved, 1);
    });

    testWidgets('合成に失敗しても失敗を知らせ、表示中の画像は生きている', (tester) async {
      await installFakes(tester);
      exportImageComposer =
          (base, caption) async => throw StateError('compose failed');
      pngSaver = (bytes, filename) async => fail('保存まで進んではいけない');

      await tester.pumpWidget(localized(view(0.6)));
      await settle(tester);
      await tapExport(tester);
      final en = lookupAppLocalizations(enLocale);
      await waitFor(
          tester, () => find.text(en.exportFailure).evaluate().isNotEmpty);
      expect(find.text(en.exportFailure), findsOneWidget);
      expect(find.byType(PreviewImageView), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    });

    testWidgets('「フォルダで表示」は保存先を開く', (tester) async {
      await installFakes(tester);
      String? savedPath;
      pngSaver = (bytes, filename) async {
        savedPath = '/fake/Downloads/$filename';
        return savedPath!;
      };
      final revealed = <String>[];
      folderRevealer = (path) async {
        revealed.add(path);
        return true;
      };

      await tester.pumpWidget(localized(view(0.6)));
      await settle(tester);
      await tapExport(tester);
      await waitFor(tester, () => savedPath != null);
      final en = lookupAppLocalizations(enLocale);
      await waitFor(
          tester, () => find.text(en.exportRevealAction).evaluate().isNotEmpty);

      await tester.tap(find.text(en.exportRevealAction));
      await tester.pump();
      expect(revealed, [savedPath]);
    });
  });
}
