// after 画像の描画結果の LRU（#185 (b)）: 鍵の同値・件数の上限・複製のやり取り・
// 元画像ごとの破棄。

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/models/preview_image_source.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/widgets/preview_rendering.dart';

import 'support/home_screen_harness.dart';

void main() {
  const sample = SamplePreviewImageSource('info_board');
  const filter = VisionFilter.myopia();

  PreviewRenderKey single(double strength,
          {PreviewImageSource source = sample, int size = 1024}) =>
      PreviewRenderKey.single(
          source: source, size: size, filter: filter, strength: strength);

  test('鍵は元画像・解像度・フィルタ・強度（または合成ステップ列）が同じなら同じ', () {
    expect(single(0.5), single(0.5));
    expect(single(0.5).hashCode, single(0.5).hashCode);
    expect(single(0.5), isNot(single(0.6)));
    expect(single(0.5), isNot(single(0.5, size: 512)));
    expect(single(0.5),
        isNot(single(0.5, source: const SamplePreviewImageSource('chart'))));
    const steps = [VisionStep(filter: filter, strength: 0.5)];
    final a = PreviewRenderKey.pipeline(
        source: sample, size: 1024, steps: List.of(steps));
    final b = PreviewRenderKey.pipeline(
        source: sample, size: 1024, steps: List.of(steps));
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(single(0.5)));
  });

  test('lookup / store は複製をやり取りし、呼び出し側の画像には触れない', () {
    final cache = PreviewRenderCache();
    addTearDown(cache.clear);
    final image = fixturePreviewImage();
    cache.store(single(0.5), image);
    image.dispose();
    final hit = cache.lookup(single(0.5))!;
    expect(hit.debugDisposed, isFalse, reason: '渡した画像を捨てても、キャッシュの分は生きている');
    hit.dispose();
    final again = cache.lookup(single(0.5))!;
    expect(again.debugDisposed, isFalse, reason: '受け取った複製を捨てても、キャッシュの分は生きている');
    again.dispose();
    expect(cache.lookup(single(0.9)), isNull);
  });

  test('上限を越えたら最も長く使っていないものから捨てる', () {
    final cache = PreviewRenderCache(capacity: 3);
    addTearDown(cache.clear);
    for (final s in [0.1, 0.2, 0.3]) {
      final img = fixturePreviewImage();
      cache.store(single(s), img);
      img.dispose();
    }
    cache.lookup(single(0.1))!.dispose(); // 0.1 を最近使ったことにする
    final img = fixturePreviewImage();
    cache.store(single(0.4), img);
    img.dispose();
    expect(cache.length, 3);
    expect(cache.lookup(single(0.2)), isNull, reason: '最も古い 0.2 が捨てられる');
    for (final s in [0.1, 0.3, 0.4]) {
      final hit = cache.lookup(single(s));
      expect(hit, isNotNull, reason: '$s');
      hit!.dispose();
    }
  });

  test('上限の既定は 6 件（1024px で約 24 MiB）', () {
    expect(kPreviewRenderCacheCapacity, 6);
  });

  test('retainWhere で読み込んだ画像の分だけを捨てられる', () {
    final cache = PreviewRenderCache();
    addTearDown(cache.clear);
    final userImage = fixturePreviewImage();
    addTearDown(userImage.dispose);
    final user = UserPreviewImageSource(userImage, 1);
    for (final key in [single(0.5), single(0.5, source: user)]) {
      final img = fixturePreviewImage();
      cache.store(key, img);
      img.dispose();
    }
    cache.retainWhere((k) => k.source is! UserPreviewImageSource);
    expect(cache.length, 1);
    cache.lookup(single(0.5))!.dispose();
  });

  test('clear で全部捨てる', () {
    final cache = PreviewRenderCache();
    final img = fixturePreviewImage();
    cache.store(single(0.5), img);
    img.dispose();
    cache.clear();
    expect(cache.length, 0);
    expect(cache.lookup(single(0.5)), isNull);
  });
}
