import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/l10n/l10n_extensions.dart';
import 'package:universal_experience/models/preview_image_source.dart';
import 'package:universal_experience/rendering/cpu_vision_renderer.dart';
import 'package:universal_experience/services/color_vision_compare.dart';
import 'package:universal_experience/services/export_service.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
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
    CpuVisionRenderer.pipelineApplier = CpuVisionRenderer.applyPipeline;
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

    testWidgets('再描画中は、セルのラベルと「同じ強さ」の注記が画像の強さのまま（新しい強さが古い画像に被らない）',
        (tester) async {
      final handle = tester.ensureSemantics();
      final pending = Completer<void>();
      // 1〜4 回目（強さ 1.0）は即完了、5 回目（強さ 0.5 の再描画）は止めておく。
      await installFakes(tester, gate: (n) => n >= 5 ? pending.future : null);
      final en = lookupAppLocalizations(enLocale);
      String label(int percent) => en.compareCellSemanticsLabel(
          visionFilterName(en, kColorVisionCompareEntries.first.id), percent);

      await tester.pumpWidget(localized(view(1.0)));
      await settle(tester);
      expect(find.text(en.compareSharedStrengthNote(100)), findsOneWidget);

      await tester.pumpWidget(localized(view(0.5)));
      await tester.pump();
      // 表示中の画像は 100% のまま。
      expect(find.text(en.compareSharedStrengthNote(100)), findsOneWidget);
      expect(find.text(en.compareSharedStrengthNote(50)), findsNothing);
      expect(find.bySemanticsLabel(label(100)), findsOneWidget);
      expect(find.bySemanticsLabel(label(50)), findsNothing);

      pending.complete();
      await settle(tester);
      expect(find.text(en.compareSharedStrengthNote(50)), findsOneWidget);
      expect(find.text(en.compareSharedStrengthNote(100)), findsNothing);
      expect(find.bySemanticsLabel(label(50)), findsOneWidget);
      expect(find.bySemanticsLabel(label(100)), findsNothing);
      handle.dispose();
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

    testWidgets('失敗したセルの Semantics ラベルは「描画に失敗」の文言になる（en / ja）', (tester) async {
      _suppressFlutterErrorReporting();
      final handle = tester.ensureSemantics();
      await installFakes(tester, failOn: (n) => StateError('boom'));
      for (final locale in [enLocale, jaLocale]) {
        await tester.pumpWidget(localized(view(0.6), locale: locale));
        await settle(tester);
        final l10n = lookupAppLocalizations(locale);
        for (final entry in kColorVisionCompareEntries) {
          final name = visionFilterName(l10n, entry.id);
          expect(
              find.bySemanticsLabel(l10n.compareCellFailedSemanticsLabel(name)),
              findsOneWidget,
              reason: '${locale.languageCode}: $name は失敗文言');
          expect(
              find.bySemanticsLabel(l10n.compareCellSemanticsLabel(name, 60)),
              findsNothing,
              reason: '失敗したセルを「強さ 60%」と読み上げない');
        }
      }
      handle.dispose();
    });

    testWidgets('再描画の失敗は、新しい描画が控えている間は出さない（失敗表示の点滅防止）', (tester) async {
      _suppressFlutterErrorReporting();
      final first = Completer<void>();
      final second = Completer<void>();
      await installFakes(
        tester,
        gate: (n) => n == 1 ? first.future : (n == 2 ? second.future : null),
        failOn: (n) => n == 1 ? StateError('boom') : null,
      );
      final en = lookupAppLocalizations(enLocale);

      await tester.pumpWidget(localized(view(0.3)));
      await tester.pump();
      // 描画中に強さが変わる（新しい描画が控える）。
      await tester.pumpWidget(localized(view(0.9)));
      await tester.pump();

      // 進行中の描画が失敗で終わる。控えの描画があるので失敗は出ない。
      first.complete();
      await tester.pump();
      await tester.pump();
      // 控えの描画は 2 回目の呼び出しで止めてあるので、失敗が出るなら今ここで見える。
      expect(find.text(en.previewFailed), findsNothing);

      second.complete();
      await settle(tester);
      expect(find.text(en.previewFailed), findsNothing);
      expect(find.byType(PreviewImageView), findsNWidgets(4),
          reason: '控えの描画が成功して、そのまま 4 型が出る');
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
  // 他の層を重ねたとき（#122）: 4 セルは「色覚以外の層を 1 回だけ適用した土台」の上に
  // 色覚 4 型を 1 つずつ適用したもの。
  group('土台（他の層を重ねたとき、#122）', () {
    /// 土台（myopia 適用済みの代役）の色。
    const baseArgb = 0xFF205080;

    /// 型ごとのチャンネル操作（フェイクの色覚適用）。**入力画素から**出力を決めるので、
    /// セルが土台から始まったか原画から始まったかが画素に現れる。
    int tint(String id, int argb) {
      final r = (argb >> 16) & 0xFF, g = (argb >> 8) & 0xFF, b = argb & 0xFF;
      final (nr, ng, nb) = switch (id) {
        'protanopia' => (g, g, b),
        'deuteranopia' => (r, r, b),
        'tritanopia' => (r, g, g),
        _ => (g, g, g),
      };
      return 0xFF000000 | (nr << 16) | (ng << 8) | nb;
    }

    ColorVisionCompareInput inputOf(
      List<String> ids, {
      Map<String, double> strengths = const {},
    }) {
      final state = VisionFilterState();
      for (final id in ids) {
        state.toggle(id);
      }
      strengths.forEach(state.setLayerStrength);
      return colorVisionCompareInputOf(state)!;
    }

    Widget viewOf(ColorVisionCompareInput input) => ColorVisionCompareView(
          strength: input.strength,
          baseSteps: input.baseSteps,
          baseLayers: input.baseLayers,
          imageSource: const SamplePreviewImageSource('test'),
          sampleSize: _kSize,
        );

    Future<int> centerArgb(WidgetTester tester, ui.Image image) async {
      final data = await tester
          .runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba));
      final o = ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
      final b = data!.buffer.asUint8List();
      return (b[o + 3] << 24) | (b[o] << 16) | (b[o + 1] << 8) | b[o + 2];
    }

    /// 読み込み・土台（pipelineApplier）・色覚適用（afterImageRenderer）のフェイク。
    /// 色覚適用は入力画素を読んで型ごとに変換した単色を返す。
    Future<
        ({
          List<List<VisionStep>> baseCalls,
          List<ui.Image> baseReturned,
          List<({String id, double strength})> cellCalls,
          List<ui.Image> cellReturned,
        })> installBaseFakes(
      WidgetTester tester, {
      Future<void>? Function(int baseCallNumber)? gateBase,
      Object? Function(int baseCallNumber)? failBase,
    }) async {
      await installFakes(tester); // 読み込み（白の原画）だけ使う。
      late ui.Image baseMaster;
      await tester
          .runAsync(() async => baseMaster = await _solid(_kSize, baseArgb));
      addTearDown(baseMaster.dispose);

      final baseCalls = <List<VisionStep>>[];
      final baseReturned = <ui.Image>[];
      final cellCalls = <({String id, double strength})>[];
      final cellReturned = <ui.Image>[];
      CpuVisionRenderer.pipelineApplier = (source, steps) async {
        final n = baseCalls.length + 1;
        baseCalls.add(steps);
        final wait = gateBase?.call(n);
        if (wait != null) await wait;
        final failure = failBase?.call(n);
        if (failure != null) throw failure;
        final image = baseMaster.clone();
        baseReturned.add(image);
        return image;
      };
      afterImageRenderer = (source, filter, strength) async {
        final id = idOf(filter!);
        cellCalls.add((id: id, strength: strength));
        final data =
            await source.toByteData(format: ui.ImageByteFormat.rawRgba);
        final b = data!.buffer.asUint8List();
        final o = ((source.height ~/ 2) * source.width + source.width ~/ 2) * 4;
        final src =
            (b[o + 3] << 24) | (b[o] << 16) | (b[o + 1] << 8) | b[o + 2];
        final image = await _solid(source.width, tint(id, src));
        cellReturned.add(image);
        return image;
      };
      return (
        baseCalls: baseCalls,
        baseReturned: baseReturned,
        cellCalls: cellCalls,
        cellReturned: cellReturned,
      );
    }

    Future<void> settleCells(
        WidgetTester tester, List<Object?> cellCalls, int count) async {
      await waitFor(tester, () => cellCalls.length >= count);
      // 最後のセルの後の setState まで流す。
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('土台は 1 回だけ合成され、4 セルは「土台 + 各型」の画素になる（原画 + 各型ではない）',
        (tester) async {
      final fakes = await installBaseFakes(tester);
      final input = inputOf(['myopia', 'protanopia']);
      await tester.pumpWidget(localized(viewOf(input)));
      await settleCells(tester, fakes.cellCalls, 4);

      expect(fakes.baseCalls.length, 1, reason: '土台の合成は 4 セルで共有して 1 回');
      expect(fakes.baseCalls.single, input.baseSteps);
      expect(fakes.cellCalls.map((c) => c.id), [
        for (final e in kColorVisionCompareEntries) e.id,
      ]);
      expect(fakes.cellCalls.map((c) => c.strength), everyElement(1.0));
      expect(find.byType(PreviewImageView), findsNWidgets(4));

      const white = 0xFFFFFFFF;
      for (var i = 0; i < 4; i++) {
        final id = kColorVisionCompareEntries[i].id;
        final actual = await centerArgb(tester, fakes.cellReturned[i]);
        expect(actual, tint(id, baseArgb), reason: '$id は土台から始まる');
        expect(actual, isNot(tint(id, white)), reason: '$id は原画から始まっていない');
      }
    });

    testWidgets('色覚の強さだけが動いたときは、土台を再合成しない（4 セルだけ描き直す）', (tester) async {
      final fakes = await installBaseFakes(tester);
      await tester
          .pumpWidget(localized(viewOf(inputOf(['myopia', 'protanopia']))));
      await settleCells(tester, fakes.cellCalls, 4);

      final moved =
          inputOf(['myopia', 'protanopia'], strengths: {'protanopia': 0.4});
      await tester.pumpWidget(localized(viewOf(moved)));
      await settleCells(tester, fakes.cellCalls, 8);

      expect(fakes.baseCalls.length, 1, reason: '土台の入力は同じ');
      expect(fakes.cellCalls.skip(4).map((c) => c.strength), everyElement(0.4));
      // 再利用している土台は破棄されていない（4 セルとも有効な入力で描けた）。
      expect(fakes.baseReturned.single.debugDisposed, isFalse);
      for (var i = 4; i < 8; i++) {
        final id = kColorVisionCompareEntries[i - 4].id;
        expect(await centerArgb(tester, fakes.cellReturned[i]),
            tint(id, baseArgb));
      }
    });

    testWidgets('土台の層の強さが動いたら再合成する。同じ内容の別リストでは再合成しない', (tester) async {
      final fakes = await installBaseFakes(tester);
      await tester
          .pumpWidget(localized(viewOf(inputOf(['myopia', 'protanopia']))));
      await settleCells(tester, fakes.cellCalls, 4);

      // 同じ内容（別インスタンスの steps）→ 再合成しない・描き直さない。
      await tester
          .pumpWidget(localized(viewOf(inputOf(['myopia', 'protanopia']))));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(fakes.baseCalls.length, 1);
      expect(fakes.cellCalls.length, 4);

      // myopia の強さが動く → 土台を作り直す。
      await tester.pumpWidget(localized(viewOf(
          inputOf(['myopia', 'protanopia'], strengths: {'myopia': 0.5}))));
      await settleCells(tester, fakes.cellCalls, 8);
      expect(fakes.baseCalls.length, 2);
      expect(fakes.baseCalls.last.single.strength, 0.5);
      expect(fakes.baseReturned.first.debugDisposed, isTrue,
          reason: '置き換えられた古い土台は破棄される');
    });

    testWidgets('土台が空（他の層なし）なら合成は呼ばず、4 セルは原画から始まる', (tester) async {
      final fakes = await installBaseFakes(tester);
      await tester.pumpWidget(localized(viewOf(inputOf(['protanopia']))));
      await settleCells(tester, fakes.cellCalls, 4);

      expect(fakes.baseCalls, isEmpty);
      for (var i = 0; i < 4; i++) {
        final id = kColorVisionCompareEntries[i].id;
        expect(await centerArgb(tester, fakes.cellReturned[i]),
            tint(id, 0xFFFFFFFF));
      }
      final en = lookupAppLocalizations(enLocale);
      expect(
        find.textContaining(en.compareBaseNote('').split(':').first),
        findsNothing,
        reason: '土台が無ければ注記は出ない',
      );
    });

    testWidgets('土台が空の間（原画比較のホールド中など）は、保持した土台を使わず原画から描く。解除して層が同じなら再合成しない',
        (tester) async {
      final fakes = await installBaseFakes(tester);
      await tester
          .pumpWidget(localized(viewOf(inputOf(['myopia', 'protanopia']))));
      await settleCells(tester, fakes.cellCalls, 4);
      expect(fakes.baseReturned.single.debugDisposed, isFalse);

      // 空 steps（強度 0・土台なし = バイパス中の入力）。
      await tester.pumpWidget(
          localized(viewOf(const ColorVisionCompareInput(strength: 0))));
      await settleCells(tester, fakes.cellCalls, 8);
      expect(fakes.baseCalls.length, 1, reason: '空の間は合成を呼ばない');
      expect(fakes.baseReturned.single.debugDisposed, isFalse,
          reason: 'ホールド中も土台は捨てずに保持する');
      for (var i = 4; i < 8; i++) {
        final id = kColorVisionCompareEntries[i - 4].id;
        expect(await centerArgb(tester, fakes.cellReturned[i]),
            tint(id, 0xFFFFFFFF),
            reason: '$id は保持した土台ではなく原画から始まる');
      }

      // 解除（同じ層）→ 再合成しない。保持した土台から描く。
      await tester
          .pumpWidget(localized(viewOf(inputOf(['myopia', 'protanopia']))));
      await settleCells(tester, fakes.cellCalls, 12);
      expect(fakes.baseCalls.length, 1, reason: '層が変わっていなければ CPU 再合成しない');
      expect(fakes.baseReturned.single.debugDisposed, isFalse);
      for (var i = 8; i < 12; i++) {
        final id = kColorVisionCompareEntries[i - 8].id;
        expect(await centerArgb(tester, fakes.cellReturned[i]),
            tint(id, baseArgb));
      }
    });

    testWidgets('土台が空の間に層が変わってから戻ると、再合成は 1 回だけ', (tester) async {
      final fakes = await installBaseFakes(tester);
      await tester
          .pumpWidget(localized(viewOf(inputOf(['myopia', 'protanopia']))));
      await settleCells(tester, fakes.cellCalls, 4);

      await tester.pumpWidget(
          localized(viewOf(const ColorVisionCompareInput(strength: 0))));
      await settleCells(tester, fakes.cellCalls, 8);

      final changed =
          inputOf(['myopia', 'protanopia'], strengths: {'myopia': 0.5});
      await tester.pumpWidget(localized(viewOf(changed)));
      await settleCells(tester, fakes.cellCalls, 12);
      expect(fakes.baseCalls.length, 2, reason: '層が変わっていたので 1 回だけ再合成');
      expect(fakes.baseCalls.last.single.strength, 0.5);
      expect(fakes.baseReturned.first.debugDisposed, isTrue,
          reason: '置き換えられた古い土台は破棄される');
    });

    testWidgets('ソースが変わると保持していた土台を破棄し、dispose でも破棄する', (tester) async {
      final fakes = await installBaseFakes(tester);
      final input = inputOf(['myopia', 'protanopia']);
      await tester.pumpWidget(localized(viewOf(input)));
      await settleCells(tester, fakes.cellCalls, 4);

      // 空の間にソースを替える → 古い土台は捨てる。
      await tester.pumpWidget(localized(const ColorVisionCompareView(
        strength: 0,
        imageSource: SamplePreviewImageSource('other'),
        sampleSize: _kSize,
      )));
      await settleCells(tester, fakes.cellCalls, 8);
      expect(fakes.baseReturned.single.debugDisposed, isTrue,
          reason: 'ソースが変わった土台は使い回せないので捨てる');

      // 土台ありで作り直し → dispose で破棄。
      await tester.pumpWidget(localized(ColorVisionCompareView(
        strength: input.strength,
        baseSteps: input.baseSteps,
        baseLayers: input.baseLayers,
        imageSource: const SamplePreviewImageSource('other'),
        sampleSize: _kSize,
      )));
      await settleCells(tester, fakes.cellCalls, 12);
      expect(fakes.baseCalls.length, 2);
      expect(fakes.baseReturned.last.debugDisposed, isFalse);
      await tester.pumpWidget(const SizedBox());
      expect(fakes.baseReturned.last.debugDisposed, isTrue);
    });

    testWidgets('土台の注記が出る（en / ja）。土台の層の名前が適用順', (tester) async {
      await installBaseFakes(tester);
      final input = inputOf(['protanopia', 'myopia', 'vertigo']);
      for (final locale in [enLocale, jaLocale]) {
        await tester.pumpWidget(localized(viewOf(input), locale: locale));
        await waitFor(
            tester, () => find.byType(PreviewImageView).evaluate().length == 4);
        final l10n = lookupAppLocalizations(locale);
        expect(
          find.text(l10n.compareBaseNote(
              '${visionFilterName(l10n, 'vertigo')} + ${visionFilterName(l10n, 'myopia')}')),
          findsOneWidget,
          reason: locale.languageCode,
        );
      }
    });

    testWidgets('描画中に土台の入力が変わったら、古い土台の 4 セルは描かず最新の土台でやり直す', (tester) async {
      final first = Completer<void>();
      final fakes = await installBaseFakes(
        tester,
        gateBase: (n) => n == 1 ? first.future : null,
      );
      await tester
          .pumpWidget(localized(viewOf(inputOf(['myopia', 'protanopia']))));
      await tester.pump();
      await waitFor(tester, () => fakes.baseCalls.length == 1);

      await tester.pumpWidget(localized(viewOf(
          inputOf(['myopia', 'protanopia'], strengths: {'myopia': 0.5}))));
      await tester.pump();
      first.complete();
      await settleCells(tester, fakes.cellCalls, 4);

      expect(fakes.baseCalls.length, 2);
      expect(fakes.baseCalls.first.single.strength, 1.0);
      expect(fakes.baseCalls.last.single.strength, 0.5);
      expect(fakes.cellCalls.length, 4, reason: '古い土台の上では 1 セルも描かない');
      expect(fakes.baseReturned.first.debugDisposed, isTrue);
    });

    testWidgets('土台の合成が失敗したら失敗表示になり、次の変更で復帰する', (tester) async {
      _suppressFlutterErrorReporting();
      final fakes = await installBaseFakes(
        tester,
        failBase: (n) => n == 1 ? StateError('boom') : null,
      );
      final en = lookupAppLocalizations(enLocale);
      await tester
          .pumpWidget(localized(viewOf(inputOf(['myopia', 'protanopia']))));
      await waitFor(
          tester, () => find.text(en.previewFailed).evaluate().length == 4);
      expect(find.text(en.previewFailed), findsNWidgets(4));
      expect(find.byTooltip(en.exportButtonTooltip), findsNothing);
      expect(fakes.cellCalls, isEmpty);

      await tester.pumpWidget(localized(viewOf(
          inputOf(['myopia', 'protanopia'], strengths: {'myopia': 0.5}))));
      await settleCells(tester, fakes.cellCalls, 4);
      expect(find.text(en.previewFailed), findsNothing);
      expect(find.byType(PreviewImageView), findsNWidgets(4));
    });

    group('書き出し', () {
      Future<void> exportWith(
        WidgetTester tester,
        ColorVisionCompareInput input, {
        required List<ExportCaption> captions,
        required List<String> filenames,
        List<Uint8List>? pngs,
        List<ui.Size>? composedSizes,
      }) async {
        final fakes = await installBaseFakes(tester);
        exportImageComposer = (base, caption) async {
          captions.add(caption);
          final composed = await composeExportImage(base, caption);
          composedSizes?.add(
              ui.Size(composed.width.toDouble(), composed.height.toDouble()));
          return composed;
        };
        pngSaver = (bytes, filename) async {
          filenames.add(filename);
          pngs?.add(bytes);
          return '/fake/Downloads/$filename';
        };
        await tester.pumpWidget(localized(viewOf(input)));
        await settleCells(tester, fakes.cellCalls, 4);
        final en = lookupAppLocalizations(enLocale);
        await tester.tap(find.byTooltip(en.exportButtonTooltip));
        await waitFor(tester, () => filenames.isNotEmpty);
      }

      testWidgets(
          'キャプションは「土台の層の行 + そのセルの色覚の行」の複数層形式。'
          'ファイル名は比較の印 + 土台の層 id（強度の % なし）', (tester) async {
        final captions = <ExportCaption>[];
        final filenames = <String>[];
        final pngs = <Uint8List>[];
        final composedSizes = <ui.Size>[];
        await exportWith(
          tester,
          inputOf([
            'protanopia',
            'myopia',
            'vertigo'
          ], strengths: {
            'myopia': 0.5,
            'protanopia': 0.6,
          }),
          captions: captions,
          filenames: filenames,
          pngs: pngs,
          composedSizes: composedSizes,
        );

        final en = lookupAppLocalizations(enLocale);
        expect(captions, hasLength(4));
        for (var i = 0; i < 4; i++) {
          final rows = captions[i].layers;
          expect([
            for (final r in rows) r.name
          ], [
            en.filterVertigo,
            en.filterMyopia,
            visionFilterName(en, kColorVisionCompareEntries[i].id),
          ], reason: '適用順（土台の層 → そのセルの色覚）');
          expect([
            for (final r in rows) r.strengthLabel
          ], [
            en.strengthLabel(100),
            en.strengthLabel(50),
            en.strengthLabel(60),
          ]);
          expect(captions[i].simulationNotice, en.exportSimulationNotice);
        }
        expect(
          filenames.single,
          matches(RegExp(
              r'^ue-color-vision-compare-vertigo-myopia-\d{4}-\d{2}-\d{2}_\d{6}\.png$')),
        );

        // 保存された PNG の各セルの画像部分が「土台 + 各型」の画素。
        final img = (await tester.runAsync(() => _decodePng(pngs.single)))!;
        final layout = compareGridLayout(composedSizes);
        expect(img.width, layout.size.width.toInt());
        for (var i = 0; i < 4; i++) {
          final id = kColorVisionCompareEntries[i].id;
          final ox = layout.origins[i].dx.toInt();
          final oy = layout.origins[i].dy.toInt();
          expect(_argbAt(img, ox + _kSize ~/ 2, oy + _kSize ~/ 2),
              tint(id, baseArgb),
              reason: '書き出しのセル $id は土台から始まる');
        }
      });

      testWidgets('描画中に親が土台の層を差し替えても、書き出しのキャプション・ファイル名は画像に写っている土台の層のまま',
          (tester) async {
        final pending = Completer<void>();
        // 1 回目の土台は即完了、2 回目（差し替え後）は止めておく。
        final fakes = await installBaseFakes(
          tester,
          gateBase: (n) => n >= 2 ? pending.future : null,
        );
        final captions = <ExportCaption>[];
        final filenames = <String>[];
        exportImageComposer = (base, caption) async {
          captions.add(caption);
          return composeExportImage(base, caption);
        };
        pngSaver = (bytes, filename) async {
          filenames.add(filename);
          return '/fake/Downloads/$filename';
        };

        await tester
            .pumpWidget(localized(viewOf(inputOf(['myopia', 'protanopia']))));
        await settleCells(tester, fakes.cellCalls, 4);

        // 描き直し中（土台の 2 回目が止まっている）に、土台の層を差し替える
        // （層を足し、myopia の強さも変える）。
        await tester.pumpWidget(localized(viewOf(inputOf(
            ['myopia', 'vertigo', 'protanopia'],
            strengths: {'myopia': 0.5}))));
        await tester.pump();
        await waitFor(tester, () => fakes.baseCalls.length == 2);

        final en = lookupAppLocalizations(enLocale);
        await tester.tap(find.byTooltip(en.exportButtonTooltip));
        await waitFor(tester, () => filenames.isNotEmpty);

        expect(captions, hasLength(4));
        for (var i = 0; i < 4; i++) {
          final c = captions[i];
          expect([
            for (final r in c.layers) r.name
          ], [
            en.filterMyopia,
            visionFilterName(en, kColorVisionCompareEntries[i].id),
          ], reason: '画像の土台は myopia だけ（vertigo は写っていない）');
          expect(c.layers.first.strengthLabel, en.strengthLabel(100),
              reason: '画像の土台の強さ（差し替え後の 50% ではない）');
        }
        expect(
          filenames.single,
          matches(RegExp(
              r'^ue-color-vision-compare-myopia-\d{4}-\d{2}-\d{2}_\d{6}\.png$')),
          reason: 'ファイル名も画像の土台（vertigo は入らない）',
        );

        pending.complete();
        await settleCells(tester, fakes.cellCalls, 8);
      });

      testWidgets('色覚の強度 0% でも、画像と同じく色覚の行は「0%」で残す（単独の 2×2 と揃える）',
          (tester) async {
        final captions = <ExportCaption>[];
        final filenames = <String>[];
        await exportWith(
          tester,
          inputOf(['myopia', 'protanopia'], strengths: {'protanopia': 0}),
          captions: captions,
          filenames: filenames,
        );
        final en = lookupAppLocalizations(enLocale);
        expect([for (final r in captions.first.layers) r.strengthLabel],
            [en.strengthLabel(100), en.strengthLabel(0)]);
        expect(
          filenames.single,
          matches(RegExp(
              r'^ue-color-vision-compare-myopia-\d{4}-\d{2}-\d{2}_\d{6}\.png$')),
        );
      });

      testWidgets('土台が無ければ従来どおり（1 型ずつのキャプション・強度 % 付きのファイル名）', (tester) async {
        final captions = <ExportCaption>[];
        final filenames = <String>[];
        await exportWith(
          tester,
          inputOf(['protanopia'], strengths: {'protanopia': 0.6}),
          captions: captions,
          filenames: filenames,
        );
        final en = lookupAppLocalizations(enLocale);
        expect(captions.map((c) => c.layers), everyElement(isEmpty));
        expect(captions.map((c) => c.symptomLabel), [
          for (final e in kColorVisionCompareEntries)
            visionFilterName(en, e.id),
        ]);
        expect(captions.map((c) => c.strengthLabel),
            everyElement(en.strengthLabel(60)));
        expect(
          filenames.single,
          matches(RegExp(
              r'^ue-color-vision-compare-60pct-\d{4}-\d{2}-\d{2}_\d{6}\.png$')),
        );
      });

      testWidgets('層が多くても、ファイル名の症状 id は上限内で、先頭の比較の印は残る', (tester) async {
        final captions = <ExportCaption>[];
        final filenames = <String>[];
        await exportWith(
          tester,
          inputOf([
            'protanopia',
            'myopia',
            'cataract',
            'astigmatism',
            'vertigo',
          ]),
          captions: captions,
          filenames: filenames,
        );
        final name = filenames.single;
        final id = RegExp(r'^ue-(.*)-\d{4}-\d{2}-\d{2}_\d{6}\.png$')
            .firstMatch(name)!
            .group(1)!;
        expect(id.length, lessThanOrEqualTo(kMaxExportSymptomIdLength),
            reason: name);
        // 比較の印 + 土台 4 層（適用順: vertigo → myopia → cataract → astigmatism）。
        // 48 文字に収まる先頭 3 つだけ残し、落とした 2 層は `-plus2`。
        expect(id, 'color-vision-compare-vertigo-myopia-plus2');
        expect(captions.first.layers.length, 5, reason: 'キャプションの行は上限で落とさない');
      });
    });
  });
}
