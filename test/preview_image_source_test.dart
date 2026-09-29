// PreviewImageSource（#78）の値型としての等価性契約のテスト。
//
// BeforeAfterView の didUpdateWidget/_rebuild の reuseBefore 判定はこの
// ==/hashCode に依存する（#58/#85 の世代管理と同じ規律）ので、契約自体を
// 独立して固定する。

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/models/preview_image_source.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SamplePreviewImageSource', () {
    test('同じ sampleId は等しい', () {
      expect(
        const SamplePreviewImageSource('chart'),
        const SamplePreviewImageSource('chart'),
      );
      expect(
        const SamplePreviewImageSource('chart').hashCode,
        const SamplePreviewImageSource('chart').hashCode,
      );
    });

    test('異なる sampleId は等しくない', () {
      expect(
        const SamplePreviewImageSource('chart'),
        isNot(const SamplePreviewImageSource('route_map')),
      );
    });

    test('UserPreviewImageSource とは等しくない', () async {
      final image = await BeforeAfterView.generateSampleImage(4);
      addTearDown(image.dispose);
      expect(
        const SamplePreviewImageSource('chart'),
        isNot(UserPreviewImageSource(image, 0)),
      );
    });
  });

  group('UserPreviewImageSource', () {
    test('generation が同じなら image オブジェクトが違っても等しい', () async {
      final imageA = await BeforeAfterView.generateSampleImage(4);
      final imageB = await BeforeAfterView.generateSampleImage(4);
      addTearDown(imageA.dispose);
      addTearDown(imageB.dispose);

      expect(
        UserPreviewImageSource(imageA, 3),
        UserPreviewImageSource(imageB, 3),
        reason: 'ui.Image に意味のある値等価性はないため generation だけで比較する',
      );
      expect(
        UserPreviewImageSource(imageA, 3).hashCode,
        UserPreviewImageSource(imageB, 3).hashCode,
      );
    });

    test('generation が異なれば等しくない（同じ image オブジェクトでも）', () async {
      final image = await BeforeAfterView.generateSampleImage(4);
      addTearDown(image.dispose);
      expect(
        UserPreviewImageSource(image, 1),
        isNot(UserPreviewImageSource(image, 2)),
      );
    });
  });
}
