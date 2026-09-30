// 複数層の PNG 書き出しの中身（#121）。
//
// `planExport` / `buildLayeredExportCaption` が、重ねている層から
// - 症状の行（層ごとに 名前 + その層の強度）
// - 受診喚起（緊急度は最大、escalation は段ごとに併合して重複を 1 行に）
// - 実験的の注記（どれか 1 層でも実験的なら）
// - 「シミュレーション（近似）」（常に）
// - ファイル名の症状 id（適用順、強度の % なし）
// を決めることと、強度 0 の層は数えない方針、1 層は従来の書き出しと同一であることを確かめる。
// さらに BeforeAfterView の書き出しボタンから、その内容が実際に焼き込み・保存へ渡ることを
// widget test で確かめる。

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/models/preview_image_source.dart';
import 'package:universal_experience/rendering/cpu_vision_renderer.dart';
import 'package:universal_experience/services/export_layers.dart';
import 'package:universal_experience/services/export_service.dart';
import 'package:universal_experience/services/vision_filter_metadata.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';

import 'support/sample_image_generator.dart';
import 'support/vision_filter_metadata_fixture.dart';

const _suddenHearing =
    'a sudden drop in hearing, especially in one ear (possible sudden sensorineural hearing loss)';

UrgencyEscalation _esc(Urgency u, String c) =>
    UrgencyEscalation(urgency: u, condition: c);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final en = lookupAppLocalizations(const Locale('en'));
  final ja = lookupAppLocalizations(const Locale('ja'));

  setUp(installVisionFilterMetadataFixture);
  tearDown(() {
    resetVisionFilterMetadataProviders();
    previewSourceImageLoader = BeforeAfterView.loadPreviewSourceImage;
    afterImageRenderer = BeforeAfterView.renderAfter;
    exportImageComposer = composeExportImage;
    pngSaver = savePng;
    CpuVisionRenderer.pipelineApplier = CpuVisionRenderer.applyPipeline;
  });

  /// [ids] を順に足した状態（層は段順に並ぶ）の書き出し用の値。
  List<ExportLayer> layersOf(
    List<String> ids, {
    Map<String, double> strengths = const {},
  }) {
    final state = VisionFilterState();
    for (final id in ids) {
      state.toggle(id);
    }
    strengths.forEach(state.setLayerStrength);
    return exportLayersOf(state);
  }

  ExportPlan plan(
    AppLocalizations l10n,
    List<ExportLayer>? layers, {
    String? filterId = 'protanopia',
    ColorVisionType? colorVisionType = ColorVisionType.protanopia,
    VisionFilter? filter = const VisionFilter.protanopia(),
    double strength = 1.0,
  }) =>
      planExport(
        l10n,
        layers: layers,
        filterId: filterId,
        colorVisionType: colorVisionType,
        filter: filter,
        strength: strength,
        isoDate: '2026-06-23',
      );

  group('buildLayeredExportCaption: 症状の行', () {
    test('層ごとに 名前 と その層の強度 が適用順に並ぶ', () {
      final layers = layersOf(
        ['protanopia', 'myopia', 'vertigo'],
        strengths: {'myopia': 0.5, 'protanopia': 0.25},
      );
      final caption =
          buildLayeredExportCaption(en, layers: layers, isoDate: '2026-06-23');

      expect([
        for (final l in caption.layers) l.name
      ], [
        en.filterVertigo,
        en.filterMyopia,
        en.filterProtanopia
      ], reason: '段順（運動 → 光学 → 色覚）。選んだ順には依存しない');
      expect([
        for (final l in caption.layers) l.strengthLabel
      ], [
        en.strengthLabel(100),
        en.strengthLabel(50),
        en.strengthLabel(25),
      ]);
      expect(caption.isoDate, '2026-06-23');
    });

    test('文言は言語に従う（ja）', () {
      final layers = layersOf(['protanopia', 'myopia']);
      final caption =
          buildLayeredExportCaption(ja, layers: layers, isoDate: '2026-06-23');

      expect([for (final l in caption.layers) l.name],
          [ja.filterMyopia, ja.filterProtanopia]);
      expect(caption.simulationNotice, ja.exportSimulationNotice);
      expect(caption.simulationNotice, isNot(en.exportSimulationNotice));
    });

    test('「シミュレーション（近似）」は喚起が無くても常に焼き込む', () {
      final layers = layersOf(['protanopia', 'myopia']);
      final caption =
          buildLayeredExportCaption(en, layers: layers, isoDate: '2026-06-23');

      expect(caption.simulationNotice, en.exportSimulationNotice);
      expect(caption.urgencyMessage, isNull);
      expect(caption.escalationGroups, isEmpty);
      expect(caption.disclaimer, isNull);
    });
  });

  group('buildLayeredExportCaption: 受診喚起の合成', () {
    test('緊急度は各層の最大（emergency が 1 層でもあれば emergency）', () {
      visionFilterUrgencyProvider = (f) => switch (f) {
            VisionFilter_Vertigo() => Urgency.earlyConsultation,
            VisionFilter_Myopia() => Urgency.emergency,
            _ => Urgency.none,
          };
      final caption = buildLayeredExportCaption(en,
          layers: layersOf(['protanopia', 'myopia', 'vertigo']),
          isoDate: '2026-06-23');

      expect(caption.urgencyMessage, en.consultEmergency);
      expect(caption.disclaimer, en.consultDisclaimerShort);
    });

    test('最大が earlyConsultation なら、その文言', () {
      visionFilterUrgencyProvider = (f) => switch (f) {
            VisionFilter_Vertigo() => Urgency.earlyConsultation,
            _ => Urgency.none,
          };
      final caption = buildLayeredExportCaption(en,
          layers: layersOf(['protanopia', 'vertigo']), isoDate: '2026-06-23');

      expect(caption.urgencyMessage, en.consultEarly);
    });

    test('escalation は段ごとに併合し、同じ条件は 1 行（適用順で最初に現れた順）', () {
      final shared = _esc(Urgency.emergency, _suddenHearing);
      visionFilterUrgencyEscalationProvider = (f) => switch (f) {
            VisionFilter_Vertigo() => [
                shared,
                _esc(Urgency.earlyConsultation, 'persists over days'),
              ],
            VisionFilter_Myopia() => [
                shared,
                _esc(Urgency.emergency, 'with speech trouble'),
              ],
            _ => const [],
          };
      final caption = buildLayeredExportCaption(en,
          layers: layersOf(['protanopia', 'myopia', 'vertigo']),
          isoDate: '2026-06-23');

      expect(caption.escalationGroups, hasLength(2));
      expect(caption.escalationGroups[0].header, en.escalationHeaderEmergency);
      expect(
          caption.escalationGroups[0].lines,
          [
            en.escalationConditionHearingSuddenOneEar,
            'with speech trouble',
          ],
          reason: '重複の shared は 1 行。vertigo（先）→ myopia（後）の順');
      expect(caption.escalationGroups[1].header, en.escalationHeaderEarly);
      expect(caption.escalationGroups[1].lines, ['persists over days']);
    });

    test('同じ条件文でも段が違えば別の行として残る', () {
      visionFilterUrgencyEscalationProvider = (f) => switch (f) {
            VisionFilter_Vertigo() => [
                _esc(Urgency.earlyConsultation, 'same words'),
              ],
            VisionFilter_Myopia() => [_esc(Urgency.emergency, 'same words')],
            _ => const [],
          };
      final caption = buildLayeredExportCaption(en,
          layers: layersOf(['myopia', 'vertigo']), isoDate: '2026-06-23');

      expect(caption.escalationGroups, hasLength(2));
      expect(caption.escalationGroups[0].lines, ['same words']);
      expect(caption.escalationGroups[1].lines, ['same words']);
    });

    test('緊急度が none でも escalation だけで喚起が出る（喚起文なし・免責あり）', () {
      visionFilterUrgencyEscalationProvider = (f) => switch (f) {
            VisionFilter_Myopia() => [_esc(Urgency.emergency, _suddenHearing)],
            _ => const [],
          };
      final caption = buildLayeredExportCaption(en,
          layers: layersOf(['protanopia', 'myopia']), isoDate: '2026-06-23');

      expect(caption.urgencyMessage, isNull);
      expect(caption.escalationGroups, hasLength(1));
      expect(caption.disclaimer, en.consultDisclaimerShort);
    });
  });

  group('buildLayeredExportCaption: 実験的の注記', () {
    test('どれか 1 層でも実験的（四色覚）なら添える', () {
      final caption = buildLayeredExportCaption(en,
          layers: layersOf(['tetrachromacy', 'myopia']), isoDate: '2026-06-23');

      expect(caption.experimentalNotice, en.exportExperimentalNotice);
      expect(caption.simulationNotice, en.exportSimulationNotice,
          reason: '近似の注記も同時に焼き込む');
    });

    test('実験的の層が無ければ添えない', () {
      final caption = buildLayeredExportCaption(en,
          layers: layersOf(['protanopia', 'myopia']), isoDate: '2026-06-23');

      expect(caption.experimentalNotice, isNull);
    });
  });

  group('planExport: 層の数による分岐', () {
    test('2 層以上: 層ごとの行・適用順の id・強度の % なし', () {
      final p = plan(en, layersOf(['protanopia', 'myopia']));

      expect(p.caption.layers, hasLength(2));
      expect(p.symptomId, 'myopia-protanopia');
      expect(p.strengthPercent, isNull);
      expect(
        exportFilename(
          symptomId: p.symptomId,
          strengthPercent: p.strengthPercent,
          isoDate: '2026-06-23',
        ),
        'ue-myopia-protanopia-2026-06-23.png',
      );
    });

    test('色覚の別名（-omaly）の層は、別名の id でファイル名に入る', () {
      final state = VisionFilterState()
        ..toggle('myopia')
        ..toggle('protanopia', variantId: 'protanomaly');
      final p = plan(en, exportLayersOf(state));

      expect(p.symptomId, 'myopia-protanomaly');
    });

    test('層の値が無い（単一層）: 引数のフォーカス値で従来どおり', () {
      final p = plan(en, null);
      final legacy = buildExportCaption(
        en,
        filterId: 'protanopia',
        colorVisionType: ColorVisionType.protanopia,
        filter: const VisionFilter.protanopia(),
        strength: 1.0,
        isoDate: '2026-06-23',
      );

      expect(p.caption.layers, isEmpty);
      expect(p.caption.symptomLabel, legacy.symptomLabel);
      expect(p.caption.strengthLabel, legacy.strengthLabel);
      expect(p.symptomId, 'protanopia');
      expect(p.strengthPercent, 100);
    });

    test('1 層（本番の経路 planExport）: キャプション・ファイル名が、従来の書き出しの値と一致する', () {
      final layers = layersOf(['protanopia'], strengths: {'protanopia': 0.6});
      final p = plan(en, layers, strength: 0.6);

      // 従来（#121 以前）の単一層の書き出しが作っていた値を、文言ごと直接書いたもの。
      // 新しい構築関数を通さずに、本番の 1 層の結果と突き合わせる。
      final legacy = ExportCaption(
        symptomLabel: en.filterProtanopia,
        strengthLabel: 'Strength: 60%',
        isoDate: '2026-06-23',
        simulationNotice: 'Simulation (approximation)',
      );
      expect(p.caption.layers, isEmpty, reason: '1 層は層ごとの行にしない（従来どおりの 2 行）');
      expect(p.caption.symptomLabel, legacy.symptomLabel);
      expect(p.caption.strengthLabel, legacy.strengthLabel);
      expect(p.caption.isoDate, legacy.isoDate);
      expect(p.caption.simulationNotice, legacy.simulationNotice);
      expect(p.caption.experimentalNotice, isNull);
      expect(p.caption.urgencyMessage, isNull);
      expect(p.caption.escalationGroups, isEmpty);
      expect(p.caption.disclaimer, isNull);

      // ファイル名（従来と同じ `ue-<id>-<強度>pct-<日付>`）。
      expect(
        exportFilename(
          symptomId: p.symptomId,
          strengthPercent: p.strengthPercent,
          isoDate: '2026-06-23',
        ),
        'ue-protanopia-60pct-2026-06-23.png',
      );
    });
  });

  group('強度 0 の層は書き出しに数えない（方針）', () {
    test('effectiveExportLayers は強度 0 の層だけを除く', () {
      final layers = layersOf(
        ['protanopia', 'myopia', 'vertigo'],
        strengths: {'myopia': 0.0},
      );
      expect(layers, hasLength(3), reason: '層としては残る');
      expect([for (final l in effectiveExportLayers(layers)) l.layer.id],
          ['vertigo', 'protanopia']);
    });

    test('症状の行・ファイル名から除く', () {
      final layers = layersOf(
        ['protanopia', 'myopia', 'vertigo'],
        strengths: {'myopia': 0.0},
      );
      final p = plan(en, layers);

      expect([for (final l in p.caption.layers) l.name],
          [en.filterVertigo, en.filterProtanopia]);
      expect(p.symptomId, 'vertigo-protanopia');
    });

    test('表示が 0% になる強度（0.004）も数えない。1% になる強度（0.006）は数える', () {
      final layers = layersOf(
        ['protanopia', 'myopia', 'vertigo'],
        strengths: {'myopia': 0.004, 'vertigo': 0.006},
      );
      expect([
        for (final l in effectiveExportLayers(layers)) l.layer.id
      ], [
        'vertigo',
        'protanopia'
      ], reason: '整数パーセントに丸めて 0 になる層は、「0%」の行を出さず数えない');

      final p = plan(en, layers);
      expect([for (final l in p.caption.layers) l.name],
          [en.filterVertigo, en.filterProtanopia]);
      expect(p.caption.layers.first.strengthLabel, en.strengthLabel(1));
      expect(
          p.caption.layers.any((l) => l.strengthLabel == en.strengthLabel(0)),
          isFalse);
      expect(p.symptomId, 'vertigo-protanopia');
    });

    test('受診喚起から除く（強度 0 の層の緊急度・escalation は焼き込まない）', () {
      visionFilterUrgencyProvider = (f) => switch (f) {
            VisionFilter_Myopia() => Urgency.emergency,
            _ => Urgency.none,
          };
      visionFilterUrgencyEscalationProvider = (f) => switch (f) {
            VisionFilter_Myopia() => [_esc(Urgency.emergency, _suddenHearing)],
            _ => const [],
          };
      final layers = layersOf(
        ['protanopia', 'myopia', 'vertigo'],
        strengths: {'myopia': 0.0},
      );
      final p = plan(en, layers);

      expect(p.caption.urgencyMessage, isNull);
      expect(p.caption.escalationGroups, isEmpty);
      expect(p.caption.disclaimer, isNull);
    });

    test('実験的の注記からも除く', () {
      final layers = layersOf(
        ['tetrachromacy', 'myopia'],
        strengths: {'tetrachromacy': 0.0},
      );
      final p = plan(en, layers);

      expect(p.caption.experimentalNotice, isNull);
    });

    test('強度 0 を除いて 1 層になったら、その層の単一層の書き出し', () {
      final layers = layersOf(
        ['protanopia', 'myopia'],
        strengths: {'myopia': 0.0, 'protanopia': 0.4},
      );
      // フォーカス中の値は強度 0 の myopia だが、画像に効いている protanopia が書き出される。
      final p = plan(
        en,
        layers,
        filterId: 'myopia',
        colorVisionType: null,
        filter: const VisionFilter.myopia(),
        strength: 0.0,
      );

      expect(p.caption.layers, isEmpty);
      expect(p.caption.symptomLabel, en.filterProtanopia);
      expect(p.caption.strengthLabel, en.strengthLabel(40));
      expect(p.symptomId, 'protanopia');
      expect(p.strengthPercent, 40);
    });

    test('全層が強度 0（画像は原画のまま）: フォーカス値の単一層の書き出し（従来どおり）', () {
      final layers = layersOf(
        ['protanopia', 'myopia'],
        strengths: {'myopia': 0.0, 'protanopia': 0.0},
      );
      final p = plan(en, layers, strength: 0.0);

      expect(p.caption.layers, isEmpty);
      expect(p.symptomId, 'protanopia');
      expect(p.strengthPercent, 0);
    });

    test('表示強度が 0% の層しかない（0.004 のみ）: 従来どおりフォーカス中の層のキャプション', () {
      final layers = layersOf(
        ['protanopia', 'myopia'],
        strengths: {'myopia': 0.004, 'protanopia': 0.004},
      );
      expect(effectiveExportLayers(layers), isEmpty);

      final p = plan(en, layers, strength: 0.004);

      expect(p.caption.layers, isEmpty, reason: '層ごとの行にはせず、フォーカス中の層の 2 行');
      expect(p.caption.symptomLabel, en.filterProtanopia);
      expect(p.caption.strengthLabel, en.strengthLabel(0));
      expect(p.symptomId, 'protanopia');
      expect(p.strengthPercent, 0);
    });

    test('全層が強度 0: 喚起・実験的の注記・ファイル名はフォーカス中の層の値（従来どおり）', () {
      visionFilterUrgencyProvider = (f) => switch (f) {
            VisionFilter_Myopia() => Urgency.emergency,
            VisionFilter_Vertigo() => Urgency.earlyConsultation,
            _ => Urgency.none,
          };
      visionFilterUrgencyEscalationProvider = (f) => switch (f) {
            VisionFilter_Myopia() => [_esc(Urgency.emergency, _suddenHearing)],
            _ => const [],
          };
      final layers = layersOf(
        ['tetrachromacy', 'myopia', 'vertigo'],
        strengths: {'tetrachromacy': 0.0, 'myopia': 0.0, 'vertigo': 0.0},
      );

      // フォーカスが myopia（強度 0）: 喚起は myopia のもの。実験的（tetrachromacy）の注記は出ない。
      final onMyopia = plan(
        en,
        layers,
        filterId: 'myopia',
        colorVisionType: null,
        filter: const VisionFilter.myopia(),
        strength: 0.0,
      );
      expect(onMyopia.caption.layers, isEmpty);
      expect(onMyopia.caption.symptomLabel, en.filterMyopia);
      expect(onMyopia.caption.strengthLabel, en.strengthLabel(0));
      expect(onMyopia.caption.urgencyMessage, en.consultEmergency);
      expect(onMyopia.caption.escalationGroups.single.lines,
          [en.escalationConditionHearingSuddenOneEar]);
      expect(onMyopia.caption.experimentalNotice, isNull);
      expect(onMyopia.symptomId, 'myopia');
      expect(onMyopia.strengthPercent, 0);

      // フォーカスが tetrachromacy（実験的・強度 0）: 注記はフォーカス層のもの。喚起は無い。
      final onTetra = plan(
        en,
        layers,
        filterId: 'tetrachromacy',
        colorVisionType: null,
        filter: const VisionFilter.tetrachromacy(),
        strength: 0.0,
      );
      expect(onTetra.caption.experimentalNotice, en.exportExperimentalNotice);
      expect(onTetra.caption.urgencyMessage, isNull);
      expect(onTetra.symptomId, 'tetrachromacy');
    });

    test('原画比較中（bypass）は層が無い扱い', () {
      final state = VisionFilterState()
        ..toggle('protanopia')
        ..toggle('myopia');
      expect(exportLayersOf(state), hasLength(2));
      state.acquireBypass('test');
      expect(exportLayersOf(state), isEmpty);
    });
  });

  group('BeforeAfterView の書き出しボタン（複数層）', () {
    Widget localized(Widget child) => MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        );

    Future<({ExportCaption? caption, String? filename})> runExport(
      WidgetTester tester,
      VisionFilterState state,
    ) async {
      late ui.Image before, after, composedStub;
      await tester.runAsync(() async {
        before = await generateSampleImage(4);
        after = await generateSampleImage(4);
        composedStub = await generateSampleImage(4);
      });
      previewSourceImageLoader = (source, size) => Future.value(before);
      afterImageRenderer = (source, filter, strength) => Future.value(after);
      CpuVisionRenderer.pipelineApplier = (source, steps) async => after;

      ExportCaption? captured;
      exportImageComposer = (base, caption) async {
        captured = caption;
        return composedStub;
      };
      String? savedFilename;
      pngSaver = (bytes, filename) async {
        savedFilename = filename;
        return '/fake/downloads/$filename';
      };

      final focusId = state.focusedId!;
      await tester.pumpWidget(localized(BeforeAfterView(
        filter:
            state.buildLayer(state.layers.firstWhere((l) => l.id == focusId)),
        filterId: focusId,
        strength: 1.0,
        steps: state.pipelineSteps(),
        exportLayers: exportLayersOf(state),
        imageSource: const SamplePreviewImageSource('test'),
        sampleSize: 16,
      )));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byTooltip(en.exportButtonTooltip));
      await tester.runAsync(() async {
        for (var i = 0; i < 50; i++) {
          if (savedFilename != null) return;
          await tester.pump(const Duration(milliseconds: 20));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump();
      return (caption: captured, filename: savedFilename);
    }

    testWidgets('3 層: 層ごとの行・合成した喚起・適用順のファイル名（強度の % なし）を渡す', (tester) async {
      visionFilterUrgencyProvider = (f) => switch (f) {
            VisionFilter_Vertigo() => Urgency.earlyConsultation,
            VisionFilter_Myopia() => Urgency.emergency,
            _ => Urgency.none,
          };
      visionFilterUrgencyEscalationProvider = (f) => switch (f) {
            VisionFilter_Myopia() => [_esc(Urgency.emergency, _suddenHearing)],
            _ => const [],
          };
      final state = VisionFilterState()
        ..toggle('protanopia')
        ..toggle('myopia')
        ..toggle('vertigo');
      state.setLayerStrength('myopia', 0.5);

      final r = await runExport(tester, state);

      expect(r.caption, isNotNull);
      expect([for (final l in r.caption!.layers) l.name],
          [en.filterVertigo, en.filterMyopia, en.filterProtanopia]);
      expect(r.caption!.layers[1].strengthLabel, en.strengthLabel(50));
      expect(r.caption!.urgencyMessage, en.consultEmergency);
      expect(r.caption!.escalationGroups.single.lines,
          [en.escalationConditionHearingSuddenOneEar]);
      expect(r.caption!.simulationNotice, en.exportSimulationNotice);
      expect(r.filename, startsWith('ue-vertigo-myopia-protanopia-'));
      expect(r.filename, isNot(contains('pct')));
      expect(r.filename, endsWith('.png'));
    });

    testWidgets('描画中に親が層を差し替えても、画像に写っている層の集合・強度を焼く', (tester) async {
      late ui.Image before, after1, after2, composedStub;
      await tester.runAsync(() async {
        before = await generateSampleImage(4);
        after1 = await generateSampleImage(4);
        after2 = await generateSampleImage(4);
        composedStub = await generateSampleImage(4);
      });
      previewSourceImageLoader = (source, size) => Future.value(before);
      final renders = <Completer<ui.Image>>[];
      CpuVisionRenderer.pipelineApplier = (source, steps) {
        final c = Completer<ui.Image>();
        renders.add(c);
        return c.future;
      };
      ExportCaption? captured;
      exportImageComposer = (base, caption) async {
        captured = caption;
        return composedStub;
      };
      String? savedFilename;
      pngSaver = (bytes, filename) async {
        savedFilename = filename;
        return '/fake/downloads/$filename';
      };

      Widget viewOf(VisionFilterState state) => localized(BeforeAfterView(
            filter: state.buildLayer(state.layers.first),
            filterId: state.layers.first.id,
            strength: 1.0,
            steps: state.pipelineSteps(),
            exportLayers: exportLayersOf(state),
            imageSource: const SamplePreviewImageSource('test'),
            sampleSize: 16,
          ));

      // 画像に写る層: protanopia 100% + myopia 50%。
      final drawn = VisionFilterState()
        ..toggle('protanopia')
        ..toggle('myopia');
      drawn.setLayerStrength('myopia', 0.5);
      await tester.pumpWidget(viewOf(drawn));
      for (var i = 0; i < 5 && renders.isEmpty; i++) {
        await tester.pump();
      }
      expect(renders, hasLength(1), reason: '1 回目の描画が await 中');

      // 描画中に親が層を足す（vertigo）。描画は待避されるだけで、1 回目の世代は最新のまま。
      final newer = VisionFilterState()
        ..toggle('protanopia')
        ..toggle('myopia')
        ..toggle('vertigo');
      await tester.pumpWidget(viewOf(newer));
      renders[0].complete(after1);
      for (var i = 0; i < 5 && renders.length < 2; i++) {
        await tester.pump();
      }
      expect(renders, hasLength(2), reason: '待避された 2 回目の描画が始まる（まだ await 中）');

      await tester.pump(); // 1 回目の結果の setState を描画へ反映する
      // 表示中の画像は 1 回目（2 層）。2 回目の描画が終わる前に書き出す。
      await tester.tap(find.byTooltip(en.exportButtonTooltip));
      await tester.runAsync(() async {
        for (var i = 0; i < 50; i++) {
          if (savedFilename != null) return;
          await tester.pump(const Duration(milliseconds: 20));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump();

      expect([
        for (final l in captured!.layers) l.name
      ], [
        en.filterMyopia,
        en.filterProtanopia
      ], reason: '画像に写っている 2 層だけ。後から足された vertigo は焼かない');
      expect(captured!.layers[0].strengthLabel, en.strengthLabel(50));
      expect(savedFilename, startsWith('ue-myopia-protanopia-'));

      renders[1].complete(after2);
      await tester.pump();
      await tester.pump();
    });

    testWidgets('フィルタ 1 本の経路（steps なし）: 描画中に親が強度・フィルタを変えても、画像に写った値を焼く',
        (tester) async {
      late ui.Image before, after1, after2, composedStub;
      await tester.runAsync(() async {
        before = await generateSampleImage(4);
        after1 = await generateSampleImage(4);
        after2 = await generateSampleImage(4);
        composedStub = await generateSampleImage(4);
      });
      previewSourceImageLoader = (source, size) => Future.value(before);
      final renders = <Completer<ui.Image>>[];
      afterImageRenderer = (source, filter, strength) {
        final c = Completer<ui.Image>();
        renders.add(c);
        return c.future;
      };
      ExportCaption? captured;
      exportImageComposer = (base, caption) async {
        captured = caption;
        return composedStub;
      };
      String? savedFilename;
      pngSaver = (bytes, filename) async {
        savedFilename = filename;
        return '/fake/downloads/$filename';
      };

      Widget viewOf({
        required VisionFilter filter,
        required String filterId,
        required ColorVisionType type,
        required double strength,
      }) =>
          localized(BeforeAfterView(
            filter: filter,
            filterId: filterId,
            colorVisionType: type,
            strength: strength,
            imageSource: const SamplePreviewImageSource('test'),
            sampleSize: 16,
          ));

      // 画像に写る値: protanopia 60%。
      await tester.pumpWidget(viewOf(
        filter: const VisionFilter.protanopia(),
        filterId: 'protanopia',
        type: ColorVisionType.protanopia,
        strength: 0.6,
      ));
      for (var i = 0; i < 5 && renders.isEmpty; i++) {
        await tester.pump();
      }
      expect(renders, hasLength(1), reason: '1 回目の描画が await 中');

      // 描画中に親が別のフィルタ・強度へ変える。1 回目の世代は最新のまま完了し得る。
      await tester.pumpWidget(viewOf(
        filter: const VisionFilter.deuteranopia(),
        filterId: 'deuteranopia',
        type: ColorVisionType.deuteranopia,
        strength: 0.3,
      ));
      renders[0].complete(after1);
      for (var i = 0; i < 5 && renders.length < 2; i++) {
        await tester.pump();
      }
      expect(renders, hasLength(2), reason: '待避された 2 回目の描画が始まる（まだ await 中）');

      await tester.pump(); // 1 回目の結果の setState を描画へ反映する
      await tester.tap(find.byTooltip(en.exportButtonTooltip));
      await tester.runAsync(() async {
        for (var i = 0; i < 50; i++) {
          if (savedFilename != null) return;
          await tester.pump(const Duration(milliseconds: 20));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump();

      expect(captured, isNotNull);
      expect(captured!.layers, isEmpty);
      expect(captured!.symptomLabel, en.filterProtanopia,
          reason: '画像に写っているフィルタ。後から渡された deuteranopia ではない');
      expect(captured!.strengthLabel, en.strengthLabel(60),
          reason: '画像に写っている強度。後から渡された 30% ではない');
      expect(savedFilename, startsWith('ue-protanopia-60pct-'));

      renders[1].complete(after2);
      await tester.pump();
      await tester.pump();
    });

    testWidgets('実験的の層を含む 2 層: 実験的の注記を渡す', (tester) async {
      final state = VisionFilterState()
        ..toggle('myopia')
        ..toggle('tetrachromacy');

      final r = await runExport(tester, state);

      expect(r.caption!.experimentalNotice, en.exportExperimentalNotice);
      expect(r.filename, startsWith('ue-myopia-tetrachromacy-'));
    });
  });
}
