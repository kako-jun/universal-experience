// プレビューが「固まった」ように見える不具合の回帰テスト（#185）。
//
// 実機報告: フィルタの付け外しを繰り返していたら、フィルタが反映されなくなり、プレビューの
// 画像もずっと変わらなかった。
//
// 調べた結果:
// - sensus の starbursts は明るい画素の数に比例して重く、明るいサンプル（info_board 等）に
//   1024px で掛けると 1 回の CPU 描画に数十秒かかる。ネイティブの描画は途中で止められず、
//   BeforeAfterView は描画を 1 本ずつ流すので、その間は何を操作してもプレビューが変わらず、
//   描画中の表示も無く、止まっているのと見分けがつかなかった。
// - 対処（このファイルが固定する挙動）:
//   - 1 回の描画が [kPreviewBusyThreshold] を越えたら「描画中…」を出す
//   - 重い入力は先に [kProvisionalPreviewSize] で描いて仮表示する（札は「低解像度の仮表示」）
//   - 描画結果を LRU で覚え、同じ入力に戻ったらすぐ表示する（長い描画の最中でも）
//   - 元画像の読み込みを after の直列描画から外す（サンプルを替えたら元画像はすぐ替わる）
// - Dart 側の段取り（世代管理・保留の集約）は、付ける/外す/全解除/強度変更/フォーカス移動/
//   原画比較/サンプル切替をシード固定でランダムに繰り返しても、最後は最新の入力に追いつく
//   （下の性質テスト。`UE_SLOW_TESTS=1` で 8 シード × 300 手、通常は 2 シード × 120 手）。
//
// 実ブリッジは呼べないので、読み込み・描画はフェイク（遅延つき）に差し替える。

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/models/preview_image_source.dart';
import 'package:universal_experience/models/sample_catalog.dart';
import 'package:universal_experience/rendering/cpu_vision_renderer.dart';
import 'package:universal_experience/services/filter_list_selection.dart';
import 'package:universal_experience/services/preview_diagnostics.dart';
import 'package:universal_experience/services/preview_selection.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';
import 'package:universal_experience/ui/widgets/preview_rendering.dart';

import 'support/home_screen_harness.dart';

class _MemorySink implements PreviewDiagnosticsSink {
  final lines = <String>[];
  @override
  void write(String line) => lines.add(line);
}

/// 描画結果の画像に、何から描いたかの札を付ける。キャッシュは複製（`clone`）を返すので、
/// 同一性でなく「同じ画像の複製か」（[ui.Image.isCloneOf]）で引く。
class _Tags<T> {
  final _entries = <(ui.Image, T)>[];
  void operator []=(ui.Image image, T tag) => _entries.add((image, tag));
  T? operator [](ui.Image image) {
    for (final (img, tag) in _entries.reversed) {
      if (identical(img, image) || img.isCloneOf(image)) return tag;
    }
    return null;
  }
}

void main() {
  setUp(installHomeScreenFixtures);
  tearDown(resetHomeScreenFixtures);

  const wide = Size(1400, 1000);

  final beforeTag = _Tags<PreviewImageSource>();
  final afterTag = _Tags<Object>();

  /// 低解像度の仮表示の描画か（入力の一辺が [kProvisionalPreviewSize]）。
  bool isProvisional(ui.Image source) =>
      source.width == kProvisionalPreviewSize;

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

  /// 読み込み・描画のフェイク。starbursts を含むフル解像度の描画だけ、テストが
  /// 完了させるまで終わらない（実機の数十秒の代わり）。低解像度の仮表示はすぐ終わる。
  /// 描画器の呼び出し（仮表示か・何を描いたか）を [calls] に残す。
  ({List<Completer<void>> slow, List<(bool, Object)> calls}) installSlowFakes() {
    final slow = <Completer<void>>[];
    final calls = <(bool, Object)>[];
    previewSourceImageLoader = (source, size) async {
      final img = fixturePreviewImage();
      beforeTag[img] = source;
      return img;
    };
    afterImageRenderer = (source, filter, strength) async {
      if (filter == null) return source;
      calls.add((isProvisional(source), (filter, strength)));
      if (isStarbursts(filter) && !isProvisional(source)) {
        final c = Completer<void>();
        slow.add(c);
        await c.future;
      }
      final img = fixturePreviewImage();
      afterTag[img] = (filter, strength);
      return img;
    };
    CpuVisionRenderer.pipelineApplier = (source, steps) async {
      calls.add((isProvisional(source), List<VisionStep>.of(steps)));
      if (steps.any((s) => isStarbursts(s.filter)) && !isProvisional(source)) {
        final c = Completer<void>();
        slow.add(c);
        await c.future;
      }
      final img = fixturePreviewImage();
      afterTag[img] = List<VisionStep>.of(steps);
      return img;
    };
    return (slow: slow, calls: calls);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
  }

  const rendering = '描画中…';
  const provisional = '描画中…（低解像度の仮表示）';
  final exportButton = find.byIcon(Icons.download_outlined);

  group('長い描画の間は「描画中…」を出し、終われば最新の選択に追いつく', () {
    testWidgets('starbursts を重ねて明るいサンプルへ切り替わる手順', (tester) async {
      final fakes = installSlowFakes();
      final slow = fakes.slow;
      final h = await pumpHomeScreen(tester, size: wide);
      final vs = h.visionState;

      // 1. 近視（推奨サンプルの info_board へ追従）。普段の描画はすぐ終わり、札は出ない。
      //    重くない入力なので、低解像度の仮表示も描かない。
      vs.toggle('myopia');
      await settle(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(rendering), findsNothing);
      expect(h.imageSource.selectedSampleId, 'info_board');
      expect(fakes.calls.where((c) => c.$1), isEmpty);
      final settled = shownImages(tester);

      // 2. starbursts を重ねる（推奨サンプルへ追従する）。重い入力なので、先に低解像度で
      //    描いて仮表示し、フル解像度の描画は終わらないまま。
      vs.toggle('starbursts');
      await settle(tester);
      expect(slow, hasLength(1));
      expect(fakes.calls.where((c) => c.$1), hasLength(1),
          reason: '仮表示を 1 回描いた');
      expect(find.text(provisional), findsOneWidget);
      expect(exportButton, findsNothing, reason: '仮表示は書き出さない');
      expect(afterTag[shownImages(tester)[1]], previewPipelineSteps(vs));
      expect(shownImages(tester)[1], isNot(same(settled[1])));

      // 3. その描画が終わらない間に、近視へフォーカスを戻し（明るい info_board へ追従）、
      //    強度も変える。元画像の読み込みは after の描画を待たないので、元画像はすぐ
      //    info_board になる。after の要求は保留に集約される（描画は 1 本ずつ）。
      vs.focusLayer('myopia');
      vs.setLayerStrength('myopia', 0.4);
      await settle(tester);
      expect(h.imageSource.selectedSampleId, 'info_board');
      expect(beforeTag[shownImages(tester)[0]], h.imageSource.current,
          reason: '元画像は after の重い描画を待たずに替わる');
      expect(slow, hasLength(1), reason: '描画は 1 本ずつ。後の要求は保留に集約される');
      await tester.pump(kPreviewBusyThreshold * 2);
      expect(find.text(provisional), findsOneWidget);

      // 4. 長い描画が終わると、保留していた最新の要求（これも starbursts を含む）が流れ、
      //    また仮表示 → フル解像度。札は消えずに出たまま。
      slow.removeAt(0).complete();
      await settle(tester);
      expect(slow, hasLength(1));
      expect(find.text(provisional), findsOneWidget);

      // 5. 最後の描画が終わると札が消え、before / after は最新の選択どおりになる。
      slow.removeAt(0).complete();
      await settle(tester);
      expect(find.text(rendering), findsNothing);
      expect(find.text(provisional), findsNothing);
      expect(exportButton, findsOneWidget);
      final images = shownImages(tester);
      expect(beforeTag[images[0]], h.imageSource.current);
      expect(afterTag[images[1]], expectedAfterTag(h));
      expect(tester.takeException(), isNull);
    });

    testWidgets('仮表示の無い長い描画では「描画中…」を出す（しきい値の前は出さない）',
        (tester) async {
      final gate = Completer<void>();
      var armed = false;
      previewSourceImageLoader = (source, size) async => fixturePreviewImage();
      afterImageRenderer = (source, filter, strength) async {
        if (armed) await gate.future;
        return filter == null ? source : fixturePreviewImage();
      };
      final h = await pumpHomeScreen(tester, size: wide);
      h.visionState.toggle('myopia');
      await settle(tester);
      armed = true;
      h.visionState.setLayerStrength('myopia', 0.3);
      await tester.pump();
      await tester.pump(kPreviewBusyThreshold ~/ 2);
      expect(find.text(rendering), findsNothing);
      await tester.pump(kPreviewBusyThreshold);
      expect(find.text(rendering), findsOneWidget);
      gate.complete();
      await settle(tester);
      expect(find.text(rendering), findsNothing);
    });

    testWidgets('速い描画が続くだけ（スライダーのドラッグ）では札を出さない', (tester) async {
      // 1 回 300ms の描画が、途切れずに続く（列はずっと空にならない）。
      previewSourceImageLoader = (source, size) async => fixturePreviewImage();
      afterImageRenderer = (source, filter, strength) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return filter == null ? source : fixturePreviewImage();
      };
      final h = await pumpHomeScreen(tester, size: wide);
      h.visionState.toggle('myopia');
      await tester.pump(const Duration(seconds: 1));
      var everShown = false;
      for (var i = 0; i < 30; i++) {
        h.visionState.setLayerStrength('myopia', (i % 20) / 20);
        await tester.pump(const Duration(milliseconds: 100));
        everShown |= find.text(rendering).evaluate().isNotEmpty;
      }
      expect(everShown, isFalse);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('描画器が例外を投げたら失敗として報告し、保留していた最新の要求で描き直す',
        (tester) async {
      // 描画器の例外は `_rebuild` の中で失敗表示になる（段取りは正常に終わる）経路。
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
      await settle(tester);
      h.visionState.setLayerStrength('myopia', 0.3);
      await tester.pump();
      h.visionState.setLayerStrength('myopia', 0.6);
      await tester.pump(kPreviewBusyThreshold * 2);
      expect(find.text(rendering), findsOneWidget);

      first.complete();
      await settle(tester);
      expect(tester.takeException(), isA<StateError>());
      expect(find.text(rendering), findsNothing);
      expect(afterTag[shownImages(tester)[1]], expectedAfterTag(h),
          reason: '失敗した描画の後ろに保留していた最新の要求が描かれている');
    });

    testWidgets('描画の段取りそのものが例外で終わっても、保留の要求は流れ、札は残らない',
        (tester) async {
      // `_rebuild` 自体が（描画器の外で）例外を投げる経路。修正前は保留の要求が
      // 例外で飛ばされ、次の操作まで最新の選択に追いつかなかった。
      final gate = Completer<void>();
      var armed = false;
      debugBeforeAfterRebuildHook = () async {
        if (!armed) return;
        armed = false;
        await gate.future;
        throw StateError('rebuild boom');
      };
      addTearDown(() => debugBeforeAfterRebuildHook = null);
      previewSourceImageLoader = (source, size) async => fixturePreviewImage();
      afterImageRenderer = (source, filter, strength) async {
        if (filter == null) return source;
        final img = fixturePreviewImage();
        afterTag[img] = (filter, strength);
        return img;
      };
      final h = await pumpHomeScreen(tester, size: wide);
      h.visionState.toggle('myopia');
      await settle(tester);

      armed = true;
      h.visionState.setLayerStrength('myopia', 0.3);
      await tester.pump();
      h.visionState.setLayerStrength('myopia', 0.6);
      await tester.pump(kPreviewBusyThreshold * 2);
      expect(find.text(rendering), findsOneWidget);

      gate.complete();
      await settle(tester);
      expect(tester.takeException(), isA<StateError>());
      expect(find.text(rendering), findsNothing);
      expect(afterTag[shownImages(tester)[1]], (h.visionState.build(), 0.6),
          reason: '例外の後ろに保留していた最新の要求が描かれている');
    });
  });

  group('描画結果のキャッシュ（#185 (b)）', () {
    testWidgets('付ける → 外す → 付けるで描き直さない', (tester) async {
      final fakes = installSlowFakes();
      final h = await pumpHomeScreen(tester, size: wide);
      final vs = h.visionState;
      h.imageSource.selectSample('info_board');
      await settle(tester);
      vs.toggle('myopia');
      await settle(tester);
      vs.toggle('dry_eye');
      await settle(tester);
      final rendered = fakes.calls.length;
      final sample = h.imageSource.current;

      vs.toggle('dry_eye');
      await settle(tester);
      expect(h.imageSource.current, sample);
      expect(afterTag[shownImages(tester)[1]], expectedAfterTag(h));
      vs.toggle('dry_eye');
      await settle(tester);
      expect(afterTag[shownImages(tester)[1]], expectedAfterTag(h));
      expect(fakes.calls.length, rendered, reason: '2 回目以降はキャッシュから出す');
    });

    testWidgets('長い描画の最中でも、キャッシュにある入力へ戻せばすぐ表示する', (tester) async {
      final fakes = installSlowFakes();
      final h = await pumpHomeScreen(tester, size: wide);
      final vs = h.visionState;
      vs.toggle('myopia');
      await settle(tester);
      final myopiaOnly = expectedAfterTag(h);
      final sample = h.imageSource.selectedSampleId;

      // starbursts を重ねる（フル解像度の描画は終わらない）。フォーカスを近視に戻して
      // サンプルを元に戻してから、starbursts を外す。
      vs.toggle('starbursts');
      await settle(tester);
      vs.focusLayer('myopia');
      await settle(tester);
      expect(h.imageSource.selectedSampleId, sample);
      expect(fakes.slow, hasLength(1));
      vs.remove('starbursts');
      await settle(tester);
      expect(afterTag[shownImages(tester)[1]], myopiaOnly,
          reason: '終わらない描画を待たずに、キャッシュから近視だけの結果を出す');
      expect(find.text(rendering), findsNothing);
      expect(find.text(provisional), findsNothing);

      // 取り残された描画が終わっても、表示は近視だけのまま。
      fakes.slow.removeAt(0).complete();
      await settle(tester);
      expect(afterTag[shownImages(tester)[1]], myopiaOnly);
      expect(tester.takeException(), isNull);
    });
  });

  group('キャッシュ命中と走っている描画が重なるとき（#185、2 巡目レビュー）', () {
    testWidgets('キャッシュ命中で札を消した後に来た要求でも、走っている描画を待つ間は「描画中…」を出し、最後は追いつく',
        (tester) async {
      final fakes = installSlowFakes();
      final h = await pumpHomeScreen(tester, size: wide);
      final vs = h.visionState;
      h.imageSource.selectSample('info_board'); // 手動で選ぶと推奨サンプルへの追従が止まる
      await settle(tester);
      vs.toggle('myopia');
      await settle(tester);

      // 近視 + starbursts のフル解像度の描画が走ったまま、starbursts を外す（キャッシュ命中で
      // 近視だけの結果がすぐ出る）。
      vs.toggle('starbursts');
      await settle(tester);
      expect(fakes.slow, hasLength(1));
      vs.remove('starbursts');
      await settle(tester);
      expect(find.text(rendering), findsNothing);

      // キャッシュに無い強度へ変える。走っている描画が終わるまで描けないので、札を出す。
      vs.setLayerStrength('myopia', 0.35);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(find.text(rendering), findsOneWidget,
          reason: '走っている描画を待つ間も「描画中…」を出す（出ないと #185 の再発）');

      fakes.slow.removeAt(0).complete();
      await settle(tester);
      expect(find.text(rendering), findsNothing);
      expect(afterTag[shownImages(tester)[1]], expectedAfterTag(h));
      expect(expectedAfterTag(h), (const VisionFilter.myopia(), 0.35));
    });

    testWidgets('低解像度の仮表示を描いている間にキャッシュから表示したら、後から届いた仮表示で上書きしない',
        (tester) async {
      final provisionalGate = Completer<void>();
      previewSourceImageLoader = (source, size) async => fixturePreviewImage();
      afterImageRenderer = (source, filter, strength) async {
        if (filter == null) return source;
        final img = fixturePreviewImage();
        afterTag[img] = (filter, strength);
        return img;
      };
      CpuVisionRenderer.pipelineApplier = (source, steps) async {
        if (isProvisional(source)) await provisionalGate.future;
        final img = fixturePreviewImage();
        afterTag[img] = List<VisionStep>.of(steps);
        return img;
      };
      final h = await pumpHomeScreen(tester, size: wide);
      final vs = h.visionState;
      h.imageSource.selectSample('info_board');
      await settle(tester);
      vs.toggle('myopia');
      await settle(tester);
      final myopiaOnly = expectedAfterTag(h);

      vs.toggle('starbursts'); // 仮表示の描画が終わらない
      await settle(tester);
      vs.remove('starbursts'); // キャッシュ命中で近視だけを表示
      await settle(tester);
      expect(afterTag[shownImages(tester)[1]], myopiaOnly);

      provisionalGate.complete();
      await settle(tester);
      expect(afterTag[shownImages(tester)[1]], myopiaOnly,
          reason: '古い入力の仮表示でキャッシュからの表示を上書きしない');
      expect(find.text(provisional), findsNothing);
      expect(exportButton, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('元画像の読み込み（#185 (c)）', () {
    testWidgets('読み込みが長引いたら元画像側に札を出し、終われば消す', (tester) async {
      final gates = <PreviewImageSource, Completer<void>>{};
      previewSourceImageLoader = (source, size) async {
        final gate = gates[source];
        if (gate != null) await gate.future;
        final img = fixturePreviewImage();
        beforeTag[img] = source;
        return img;
      };
      final h = await pumpHomeScreen(tester, size: wide);
      await settle(tester);
      final next = kSampleCatalog
          .firstWhere((e) => e.id != h.imageSource.selectedSampleId)
          .id;
      gates[SamplePreviewImageSource(next)] = Completer<void>();
      h.imageSource.selectSample(next);
      await tester.pump();
      await tester.pump(kPreviewBusyThreshold * 2);
      expect(find.text('画像を読み込み中…'), findsOneWidget);
      gates[SamplePreviewImageSource(next)]!.complete();
      await settle(tester);
      expect(find.text('画像を読み込み中…'), findsNothing);
      expect(beforeTag[shownImages(tester)[0]], SamplePreviewImageSource(next));
    });
  });

  group('診断ログ（Before/After）', () {
    testWidgets('長い描画は stalled → recovered、描画器の例外は型名だけ記録する',
        (tester) async {
      final sink = _MemorySink();
      PreviewDiagnostics.sink = sink;
      addTearDown(() => PreviewDiagnostics.sink = null);
      final fakes = installSlowFakes();
      final h = await pumpHomeScreen(tester, size: wide);
      h.visionState.toggle('myopia');
      await settle(tester);
      h.visionState.toggle('starbursts');
      await settle(tester);
      await tester.pump(const Duration(seconds: 11));
      final stalled = sink.lines.where((l) => l.contains('preview_stalled'));
      expect(stalled, hasLength(1));
      expect(stalled.single, contains('view=before_after stage=render'));
      expect(stalled.single, contains('filter=myopia+starbursts'));
      fakes.slow.removeAt(0).complete();
      await settle(tester);
      expect(sink.lines.last, contains('preview_recovered view=before_after'));
      expect(sink.lines.last, contains('outcome=done'));

      afterImageRenderer = (source, filter, strength) async =>
          throw StateError('failed at /mnt/secret/photo.png');
      h.visionState.remove('starbursts');
      h.visionState.setLayerStrength('myopia', 0.9);
      await settle(tester);
      expect(tester.takeException(), isA<StateError>());
      final failed = sink.lines.lastWhere((l) => l.contains('preview_failed'));
      expect(failed, contains('view=before_after'));
      expect(failed, contains('stage=render'));
      expect(failed, contains('error=StateError'));
      expect(failed, isNot(contains('secret')));
    });
  });

  // 付け外しを高速・ランダムに繰り返しても、最後は最新の入力に追いつく（#185 の調査で
  // 再現しなかった経路を固定する）。
  final slowTests = Platform.environment['UE_SLOW_TESTS'] == '1';
  final seeds = slowTests ? 8 : 2;
  final stepCount = slowTests ? 300 : 120;
  for (var seed = 0; seed < seeds; seed++) {
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

      for (var step = 0; step < stepCount; step++) {
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
      for (var i = 0; i < 60; i++) {
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
