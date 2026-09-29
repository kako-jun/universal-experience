// ImageSourceState（#78）のテスト。
//
// サンプル/ユーザー画像の切替、自動追従（followRecommendedSample）と
// 手動選択の相互排他、「おすすめに戻す」、ユーザー画像の世代管理・dispose
// （#58/#85 と同じ規律）を検証する。

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/models/preview_image_source.dart';
import 'package:universal_experience/models/sample_catalog.dart';
import 'package:universal_experience/services/image_source_state.dart';

import 'support/sample_image_generator.dart';

/// [SchedulerBinding.addPostFrameCallback]（#78 レビュー S3 の遅延 dispose）を
/// 実際に発火させる。プレーンな `ImageSourceState`（購読するウィジェットを
/// 持たない）に対する `notifyListeners()` はどの Element も dirty にしない
/// ため、`tester.pump()` 単体では `hasScheduledFrame` が false のままで
/// `handleDrawFrame`（post-frame callback の発火点）自体が走らない
/// （`TestWidgetsFlutterBinding.pump()` の実装参照）。明示的に
/// `scheduleFrame()` を呼んでから pump することで、production で
/// `notifyListeners()` が購読ウィジェットの再 build を予約する状況を模す。
Future<void> pumpPostFrameCallbacks(WidgetTester tester) async {
  SchedulerBinding.instance.scheduleFrame();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('初期状態', () {
    test('既定は kDefaultSampleId・サンプルモード・自動追従', () {
      final state = ImageSourceState();
      expect(state.selectedSampleId, kDefaultSampleId);
      expect(state.isUsingUserImage, isFalse);
      expect(state.hasUserImage, isFalse);
      expect(state.isFollowingRecommended, isTrue);
      expect(state.current, const SamplePreviewImageSource(kDefaultSampleId));
    });

    test('initialSampleId を指定できる', () {
      final state = ImageSourceState(initialSampleId: 'chart');
      expect(state.selectedSampleId, 'chart');
      expect(state.current, const SamplePreviewImageSource('chart'));
    });
  });

  group('selectSample（手動選択）', () {
    test('サンプルを切り替え、自動追従を止める', () {
      final state = ImageSourceState();
      var notified = 0;
      state.addListener(() => notified++);

      state.selectSample('night_scene');

      expect(state.selectedSampleId, 'night_scene');
      expect(state.isFollowingRecommended, isFalse);
      expect(state.current, const SamplePreviewImageSource('night_scene'));
      expect(notified, 1);
    });

    test('既に手動選択済みの同じサンプルを再選択しても notify しない（#78 レビュー nit）',
        () {
      final state = ImageSourceState();
      state.selectSample('night_scene');
      var notified = 0;
      state.addListener(() => notified++);

      state.selectSample('night_scene');

      expect(notified, 0);
    });

    test('自動追従中に現在のサンプルを選び直すと、手動選択（自動追従オフ）に'
        '切り替わる（notify する）', () {
      final state = ImageSourceState(initialSampleId: 'chart');
      expect(state.isFollowingRecommended, isTrue);
      var notified = 0;
      state.addListener(() => notified++);

      state.selectSample('chart');

      expect(notified, 1, reason: '自動追従がオフになるという実質的な状態変化がある');
      expect(state.isFollowingRecommended, isFalse);
    });
  });

  group('followRecommendedSample（フィルタ変更時の自動追従）', () {
    test('自動追従が有効なら、選ばれているサンプルを更新する', () {
      final state = ImageSourceState();
      state.followRecommendedSample('info_board');
      expect(state.selectedSampleId, 'info_board');
      expect(state.isFollowingRecommended, isTrue);
    });

    test('手動選択のあとは no-op（#78: 手で選んだら自動切り替えを止める）', () {
      final state = ImageSourceState();
      state.selectSample('chart');
      state.followRecommendedSample('night_scene');
      expect(state.selectedSampleId, 'chart',
          reason: '手動選択後は followRecommendedSample が無視されるべき');
    });

    test('同じ id への追従は notify しない', () {
      final state = ImageSourceState(initialSampleId: 'chart');
      var notified = 0;
      state.addListener(() => notified++);
      state.followRecommendedSample('chart');
      expect(notified, 0);
    });
  });

  group('resetToRecommended（おすすめに戻す）', () {
    test('手動選択を解除し自動追従を再開する', () {
      final state = ImageSourceState();
      state.selectSample('chart');
      expect(state.isFollowingRecommended, isFalse);

      state.resetToRecommended('route_map');

      expect(state.selectedSampleId, 'route_map');
      expect(state.isFollowingRecommended, isTrue);
      // 以後は再び自動追従する。
      state.followRecommendedSample('night_scene');
      expect(state.selectedSampleId, 'night_scene');
    });
  });

  group('ユーザー画像: 読み込み・世代管理・dispose（#58/#85 と同じ規律）', () {
    test('setUserImage でユーザー画像モードに切り替わる', () async {
      final state = ImageSourceState();
      final image = await generateSampleImage(4);
      var notified = 0;
      state.addListener(() => notified++);

      state.setUserImage(image);

      expect(state.isUsingUserImage, isTrue);
      expect(state.hasUserImage, isTrue);
      expect(notified, 1);
      final source = state.current;
      expect(source, isA<UserPreviewImageSource>());
      expect((source as UserPreviewImageSource).image, same(image));
      expect(source.generation, 1);
    });

    testWidgets('新しい画像を読み込むと古い画像は dispose される。generation が増える',
        (tester) async {
      await tester.pumpWidget(const SizedBox());
      final state = ImageSourceState();
      final first = await generateSampleImage(4);
      final second = await generateSampleImage(4);
      state.setUserImage(first);
      final firstGeneration =
          (state.current as UserPreviewImageSource).generation;

      state.setUserImage(second);
      // #78 レビュー S3: dispose は次フレームまで遅延する。
      await pumpPostFrameCallbacks(tester);

      expect(first.debugDisposed, isTrue, reason: '差し替えられた旧ユーザー画像は dispose される');
      expect(second.debugDisposed, isFalse);
      final secondGeneration =
          (state.current as UserPreviewImageSource).generation;
      expect(secondGeneration, greaterThan(firstGeneration));
    });

    testWidgets(
        'S3: 旧ユーザー画像の dispose は同期的には起きず、次フレームまで遅延する',
        (tester) async {
      await tester.pumpWidget(const SizedBox());
      final state = ImageSourceState();
      final first = await generateSampleImage(4);
      final second = await generateSampleImage(4);
      state.setUserImage(first);

      state.setUserImage(second);
      // pump する前は、BeforeAfterView._rebuild が fitImageToSquare で
      // first をまだ参照中かもしれないため、同期的にはまだ dispose されない
      // （#78 レビュー S3 のレースを避けるための意図的な遅延）。
      expect(first.debugDisposed, isFalse,
          reason: 'pump 前はまだ dispose されていないべき');

      await pumpPostFrameCallbacks(tester);

      expect(first.debugDisposed, isTrue, reason: '次フレームで dispose される');
    });

    test('フィルタが変わっても followRecommendedSample はユーザー画像を邪魔しない（#78）', () async {
      final state = ImageSourceState();
      final image = await generateSampleImage(4);
      state.setUserImage(image);

      state.followRecommendedSample('night_scene');

      expect(state.isUsingUserImage, isTrue);
      expect(state.current, isA<UserPreviewImageSource>());
    });

    test('resetToRecommended はユーザー画像を破棄せず、サンプル表示に戻すだけ', () async {
      final state = ImageSourceState();
      final image = await generateSampleImage(4);
      addTearDown(() {
        if (!image.debugDisposed) image.dispose();
      });
      state.setUserImage(image);

      state.resetToRecommended('chart');

      expect(state.isUsingUserImage, isFalse);
      expect(state.hasUserImage, isTrue, reason: '画像自体はまだ保持されている');
      expect(image.debugDisposed, isFalse);
      expect(state.current, const SamplePreviewImageSource('chart'));
    });

    test('useLoadedUserImage で読み込み済みのユーザー画像に戻れる（再選択不要）', () async {
      final state = ImageSourceState();
      final image = await generateSampleImage(4);
      addTearDown(image.dispose);
      state.setUserImage(image);
      final generationBefore =
          (state.current as UserPreviewImageSource).generation;
      state.resetToRecommended('chart');

      state.useLoadedUserImage();

      expect(state.isUsingUserImage, isTrue);
      final source = state.current as UserPreviewImageSource;
      expect(source.image, same(image));
      expect(source.generation, generationBefore,
          reason: '同じ画像に戻るだけなので generation は変わらない（再デコード/再 dispose なし）');
    });

    test('useLoadedUserImage は画像が無ければ no-op', () {
      final state = ImageSourceState();
      var notified = 0;
      state.addListener(() => notified++);
      state.useLoadedUserImage();
      expect(notified, 0);
      expect(state.isUsingUserImage, isFalse);
    });

    testWidgets('clearUserImage は画像を dispose し、フォールバックのサンプルに戻す',
        (tester) async {
      await tester.pumpWidget(const SizedBox());
      final state = ImageSourceState();
      final image = await generateSampleImage(4);
      state.setUserImage(image);
      await tester.pump();

      state.clearUserImage('info_board');
      // #78 レビュー S3: こちらも次フレームまで遅延する。
      await pumpPostFrameCallbacks(tester);

      expect(image.debugDisposed, isTrue);
      expect(state.hasUserImage, isFalse);
      expect(state.isUsingUserImage, isFalse);
      expect(state.isFollowingRecommended, isTrue);
      expect(state.current, const SamplePreviewImageSource('info_board'));
    });

    test('dispose() は保持中のユーザー画像を dispose する', () async {
      final state = ImageSourceState();
      final image = await generateSampleImage(4);
      state.setUserImage(image);

      state.dispose();

      expect(image.debugDisposed, isTrue);
    });

    test('ユーザー画像が無いまま dispose() しても例外にならない', () {
      final state = ImageSourceState();
      expect(state.dispose, returnsNormally);
    });
  });
}
