// プレビューが「固まった」ように見える不具合の回帰テスト（#185）。
//
// 実機報告: フィルタの付け外しを繰り返していたら、フィルタが反映されなくなり、プレビューの
// 画像もずっと変わらなかった。
//
// 調べた結果:
// - sensus の starbursts は明るい画素の数に比例して重く、明るいサンプル（info_board 等）に
//   1024px で掛けると 1 回の CPU 描画に数十秒かかる。ネイティブの描画は途中で止められず、
//   BeforeAfterView は描画を 1 本ずつ流すので、その間は何を操作してもプレビュー
//   （before も after も）が変わらない。描画中の表示も無く、止まっているのと見分けが
//   つかなかった。→ 描画が [kPreviewBusyThreshold] を越えたら「描画中…」を出す。
// - Dart 側の段取り（世代管理・保留の集約）は、付ける/外す/全解除/強度変更/フォーカス移動/
//   原画比較/サンプル切替をシード固定でランダムに繰り返しても、最後は最新の入力に追いつく
//   （下の性質テスト）。
//
// 実ブリッジは呼べないので、読み込み・描画はフェイク（遅延つき）に差し替える。

import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/models/preview_image_source.dart';
import 'package:universal_experience/models/sample_catalog.dart';
import 'package:universal_experience/rendering/cpu_vision_renderer.dart';
import 'package:universal_experience/services/filter_list_selection.dart';
import 'package:universal_experience/services/preview_selection.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';
import 'package:universal_experience/ui/widgets/preview_rendering.dart';

import 'support/home_screen_harness.dart';

void main() {
  setUp(installHomeScreenFixtures);
  tearDown(resetHomeScreenFixtures);

  const wide = Size(1400, 1000);

  /// 描画結果の画像に、何から描いたかの札を付ける（identity で引く）。
  final beforeTag = Expando<PreviewImageSource>('before');
  final afterTag = Expando<Object>('after');

  List<ui.Image> shownImages(WidgetTester tester) => [
        for (final v in tester
            .widgetList<PreviewImageView>(find.byType(PreviewImageView)))
          v.image!,
      ];

  /// いまの選択から期待される after の札（null は「原画のまま」）。
  Object? expectedAfterTag(HomeScreenHarness h) {
    final vs = h.visionState;
    if (vs.layers.length > 1) {
      final steps = previewPipelineSteps(vs);
      return steps.isEmpty ? null : steps;
    }
    final filter = vs.build();
    return filter == null ? null : (filter, previewStrength(vs));
  }

  bool isStarbursts(VisionFilter? f) => f is VisionFilter_Starbursts;

  group('長い描画の間は「描画中…」を出し、終われば最新の選択に追いつく', () {
    testWidgets('starbursts を重ねて明るいサンプルへ切り替わる手順', (tester) async {
      // starbursts を含む描画だけ、テストが完了させるまで終わらない（実機の数十秒の代わり）。
      final slow = <Completer<void>>[];
      previewSourceImageLoader = (source, size) async {
        final img = fixturePreviewImage();
        beforeTag[img] = source;
        return img;
      };
      afterImageRenderer = (source, filter, strength) async {
        if (isStarbursts(filter)) {
          final c = Completer<void>();
          slow.add(c);
          await c.future;
        }
        if (filter == null) return source;
        final img = fixturePreviewImage();
        afterTag[img] = (filter, strength);
        return img;
      };
      CpuVisionRenderer.pipelineApplier = (source, steps) async {
        if (steps.any((s) => isStarbursts(s.filter))) {
          final c = Completer<void>();
          slow.add(c);
          await c.future;
        }
        final img = fixturePreviewImage();
        afterTag[img] = List<VisionStep>.of(steps);
        return img;
      };

      final h = await pumpHomeScreen(tester, size: wide);
      final vs = h.visionState;

      // 1. 近視（推奨サンプルの info_board へ追従）。普段の描画はすぐ終わり、札は出ない。
      vs.toggle('myopia');
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('描画中…'), findsNothing);
      expect(h.imageSource.selectedSampleId, 'info_board');
      final settled = shownImages(tester);

      // 2. starbursts を重ねる。この描画が終わらない間に、近視へフォーカスを戻し
      //    （明るい info_board へ追従）、強度も変える。
      vs.toggle('starbursts');
      await tester.pump();
      vs.focusLayer('myopia');
      vs.setLayerStrength('myopia', 0.4);
      await tester.pump();
      expect(slow, hasLength(1), reason: '描画は 1 本ずつ。後の要求は保留に集約される');

      // しきい値の前は札を出さない。越えたら出す。その間、表示は前の描画のまま。
      await tester.pump(kPreviewBusyThreshold ~/ 2);
      expect(find.text('描画中…'), findsNothing);
      await tester.pump(kPreviewBusyThreshold);
      expect(find.text('描画中…'), findsOneWidget);
      expect(shownImages(tester)[0], same(settled[0]));
      expect(shownImages(tester)[1], same(settled[1]));

      // 3. 長い描画が終わると、保留していた最新の要求（これも starbursts を含む）が流れる。
      //    列が続く間は札を出しっぱなしにする。
      slow.removeAt(0).complete();
      await tester.pump();
      await tester.pump();
      expect(slow, hasLength(1));
      expect(find.text('描画中…'), findsOneWidget);

      // 4. 最後の描画が終わると札が消え、before / after は最新の選択どおりになる。
      slow.removeAt(0).complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('描画中…'), findsNothing);
      final images = shownImages(tester);
      expect(beforeTag[images[0]], h.imageSource.current);
      expect(afterTag[images[1]], expectedAfterTag(h));
      expect(tester.takeException(), isNull);
    });

    testWidgets('描画が例外で終わっても札は残らず、保留の要求は流れる', (tester) async {
      var calls = 0;
      final first = Completer<void>();
      previewSourceImageLoader = (source, size) async => fixturePreviewImage();
      afterImageRenderer = (source, filter, strength) async {
        calls++;
        if (calls == 2) {
          await first.future;
          throw StateError('boom');
        }
        if (filter == null) return source;
        final img = fixturePreviewImage();
        afterTag[img] = (filter, strength);
        return img;
      };
      final h = await pumpHomeScreen(tester, size: wide);
      h.visionState.toggle('myopia');
      await tester.pump();
      await tester.pump();
      h.visionState.setLayerStrength('myopia', 0.3);
      await tester.pump();
      h.visionState.setLayerStrength('myopia', 0.6);
      await tester.pump(kPreviewBusyThreshold * 2);
      expect(find.text('描画中…'), findsOneWidget);

      first.complete();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isA<StateError>());
      expect(find.text('描画中…'), findsNothing);
      expect(afterTag[shownImages(tester)[1]], expectedAfterTag(h),
          reason: '失敗した描画の後ろに保留していた最新の要求が描かれている');
    });
  });

  // 付け外しを高速・ランダムに繰り返しても、最後は最新の入力に追いつく（#185 の調査で
  // 再現しなかった経路を固定する）。
  for (var seed = 0; seed < 3; seed++) {
    testWidgets('ランダムな操作列でも最新の入力に追いつく（seed $seed）', (tester) async {
      final rng = Random(seed);
      Future<void> delay() =>
          Future<void>.delayed(Duration(milliseconds: rng.nextInt(40)));

      previewSourceImageLoader = (source, size) async {
        await delay();
        final img = fixturePreviewImage();
        beforeTag[img] = source;
        return img;
      };
      afterImageRenderer = (source, filter, strength) async {
        if (source.debugDisposed) throw StateError('disposed input');
        await delay();
        if (filter == null) return source;
        final img = fixturePreviewImage();
        afterTag[img] = (filter, strength);
        return img;
      };
      CpuVisionRenderer.pipelineApplier = (source, steps) async {
        if (source.debugDisposed) throw StateError('disposed input');
        await delay();
        final img = fixturePreviewImage();
        afterTag[img] = List<VisionStep>.of(steps);
        return img;
      };

      final h = await pumpHomeScreen(tester, size: wide);
      final vs = h.visionState;
      final holders = [Object(), Object()];

      for (var step = 0; step < 200; step++) {
        final op = rng.nextInt(100);
        if (op < 45) {
          toggleFilterListEntry(
              vs, kFilterListEntries[rng.nextInt(kFilterListEntries.length)]);
        } else if (op < 55) {
          if (vs.layers.isNotEmpty) {
            vs.remove(vs.layers[rng.nextInt(vs.layers.length)].id);
          }
        } else if (op < 70) {
          if (vs.layers.isNotEmpty) {
            vs.setLayerStrength(vs.layers[rng.nextInt(vs.layers.length)].id,
                rng.nextInt(21) / 20);
          }
        } else if (op < 75) {
          vs.clear();
        } else if (op < 80) {
          if (vs.layers.isNotEmpty) {
            vs.focusLayer(vs.layers[rng.nextInt(vs.layers.length)].id);
          }
        } else if (op < 85) {
          final holder = holders[rng.nextInt(2)];
          if (vs.isHeldBy(holder)) {
            vs.releaseBypass(holder);
          } else {
            vs.acquireBypass(holder);
          }
        } else if (op < 90) {
          h.imageSource.selectSample(
              kSampleCatalog[rng.nextInt(kSampleCatalog.length)].id);
        }
        await tester.pump(Duration(milliseconds: rng.nextInt(30)));
      }
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(tester.takeException(), isNull);
      expect(find.text('描画中…'), findsNothing);
      final view = tester.widget<BeforeAfterView>(find.byType(BeforeAfterView));
      expect(
          view.steps, vs.layers.length > 1 ? previewPipelineSteps(vs) : isNull);
      final images = shownImages(tester);
      expect(images, hasLength(2));
      expect(beforeTag[images[0]], h.imageSource.current, reason: 'before');
      expect(afterTag[images[1]], expectedAfterTag(h), reason: 'after');
    });
  }
}
