// HomeScreen のプレビュー（_buildPreviewSection の Consumer<VisionFilterState>
// → BeforeAfterView）が、VisionFilterState.setStrength（強度の唯一の正本）に
// 追従することの回帰テスト（#57）。
//
// #57 の要点は「強度の通知が SettingsService（延いては MaterialApp）には伝播せず、
// Consumer を使う場所には正しく伝わる」こと（intensity_rebuild_test.dart 参照）。
// その「正しく伝わる」側を、状態 1 系統になった今も画面で確認しておく。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';

import 'support/color_vision_select.dart';
import 'support/home_screen_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 体験プリセット・メタデータ・プレビューの読み込み/適用は、ハーネスの fixture
  // （Rust 非依存）に揃える（#127, #131）。
  setUp(installHomeScreenFixtures);
  tearDown(resetHomeScreenFixtures);

  testWidgets(
      'VisionFilterState.setStrength のあと、プレビューの BeforeAfterView.strength が追従する',
      (WidgetTester tester) async {
    // HomeScreen は縦に長い ListView。全セクションが一度に Element 化されるよう
    // 十分に高いビューポートにする（scroll 不要）。
    final h = await pumpHomeScreen(
      tester,
      size: const Size(1200, 4000),
      select: (s) => selectColorVisionKey(s, 'protanopia'),
    );
    final visionState = h.visionState;

    BeforeAfterView currentPreview() =>
        tester.widget<BeforeAfterView>(find.byType(BeforeAfterView));

    expect(currentPreview().strength, visionState.strength);
    expect(currentPreview().strength, 1.0); // protanopia の既定強度

    visionState.setStrength(0.33);
    await tester.pump();

    expect(currentPreview().strength, 0.33);
    expect(currentPreview().strength, visionState.strength);
  });

  testWidgets('強度スライダーをドラッグすると VisionFilterState.bypassed が解除される（#63）',
      (WidgetTester tester) async {
    final h = await pumpHomeScreen(
      tester,
      size: const Size(1200, 4000),
      select: (s) {
        selectColorVisionKey(s, 'protanopia');
        s.acquireBypass('test');
      },
    );
    final visionState = h.visionState;
    expect(visionState.bypassed, isTrue);

    // 調整パネルの強度スライダー（#120 で 1 本に統合）が唯一の Slider。
    final sliderFinder = find.byType(Slider);
    // 1200x4000 の 3 カラム（#72）では右カラム「調整」の先頭付近にあり、
    // スクロールせずに hit test できる。
    expect(sliderFinder, findsOneWidget);

    await tester.drag(sliderFinder, const Offset(60, 0));
    await tester.pump();

    expect(visionState.bypassed, isFalse);
  });
}
