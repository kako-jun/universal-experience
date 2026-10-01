// HomeScreen がフィルタ選択の変化に応じて ImageSourceState.selectedSampleId を
// 自動追従させることの回帰テスト（#78）。
//
// home_screen.dart の `_followRecommendedSample`（VisionFilterState への
// リスナー、`_persistFilterState` と同じ subscribe-once パターン）が、
// フィルタの選択が変わるたびに `recommendedSampleIdForFilter` の結果で
// `ImageSourceState.followRecommendedSample` を呼ぶことを確認する。
// 既存の home_screen_preview_*.dart とは別ファイルにして、それらとの
// コンフリクトを避けている。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/models/sample_catalog.dart';
import 'package:universal_experience/services/image_source_state.dart';
import 'package:universal_experience/services/vision_filter_state.dart';

import 'support/color_vision_select.dart';
import 'support/home_screen_harness.dart';
import 'support/sample_image_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 体験プリセット・メタデータ・プレビューの読み込み/適用は、ハーネスの fixture
  // （Rust 非依存）に揃える（#127, #131）。
  setUp(installHomeScreenFixtures);
  tearDown(resetHomeScreenFixtures);

  /// HomeScreen を組み、状態（フィルタ選択・画像供給源）を返す。
  Future<({VisionFilterState vision, ImageSourceState imageSource})> pumpHome(
    WidgetTester tester,
  ) async {
    final h = await pumpHomeScreen(tester, size: const Size(1200, 4000));
    return (vision: h.visionState, imageSource: h.imageSource);
  }

  testWidgets('色覚クイック選択でフィルタを切り替えると selectedSampleId が推奨サンプルに追従する',
      (tester) async {
    final (vision: visionState, imageSource: imageSourceState) =
        await pumpHome(tester);

    selectColorVisionKey(visionState, 'protanopia');
    await tester.pump();

    expect(imageSourceState.selectedSampleId,
        recommendedSampleIdForFilter('protanopia'));
    expect(imageSourceState.isFollowingRecommended, isTrue);

    selectColorVisionKey(visionState, 'deuteranopia');
    await tester.pump();

    expect(imageSourceState.selectedSampleId,
        recommendedSampleIdForFilter('deuteranopia'));
  });

  testWidgets('advanced カタログでフィルタを切り替えても selectedSampleId が追従する',
      (tester) async {
    final (vision: visionState, imageSource: imageSourceState) =
        await pumpHome(tester);

    visionState.replaceWith('night_blindness');
    await tester.pump();

    expect(imageSourceState.selectedSampleId,
        recommendedSampleIdForFilter('night_blindness'));
  });

  testWidgets(
      'ユーザー画像を選んでいる間はフィルタを切り替えても自動切り替えが働かない'
      '（#78）', (tester) async {
    final (vision: visionState, imageSource: imageSourceState) =
        await pumpHome(tester);

    await tester.runAsync(() async {
      final image = await generateSampleImage(4);
      imageSourceState.setUserImage(image);
    });
    await tester.pump();
    expect(imageSourceState.isUsingUserImage, isTrue);

    selectColorVisionKey(visionState, 'protanopia');
    await tester.pump();

    // ユーザー画像を見ている間は HomeScreen 側のリスナーが
    // followRecommendedSample を呼んでも no-op になり続ける。
    expect(imageSourceState.isUsingUserImage, isTrue,
        reason: 'フィルタ変更でユーザー画像が勝手に外れてはいけない');
  });
}
