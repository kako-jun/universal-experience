// 実ブリッジ smoke test (#85)。
//
// widget test (test/before_after_view_test.dart, test/cpu_vision_renderer_test.dart)
// は CpuVisionRenderer.applier をフェイクに差し替えて世代管理・dispose の規約や
// ui.Image ⇄ raw RGBA8 の往復変換だけを検証しているため、実際に sensus-core の
// CPU apply()（applyVisionCpuRgba8）が kVisionFilterCatalog の全 30 種で例外なく
// 動くことまでは検知できない。本テストは実ネイティブライブラリをロードし、
// CpuVisionRenderer.apply() を通じて本物のブリッジ呼び出しを行う。
//
// 実行: `flutter test integration_test/cpu_preview_all_filters_test.dart -d macos`
// 他の integration_test ファイルと同様、デスクトップでは 1 回の `flutter test
// integration_test` 呼び出しに複数ファイルを渡すと2番目以降のアプリ起動が失敗する
// 既知の制約があるため、CI でも個別コマンドとして実行する。

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:universal_experience/models/vision_filter_catalog.dart';
import 'package:universal_experience/rendering/cpu_vision_renderer.dart';
import 'package:universal_experience/services/native_bridge_service.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';

Future<ui.Image> _decodeFile(String path) async {
  final Uint8List bytes = await File(path).readAsBytes();
  final ui.Codec codec = await ui.instantiateImageCodec(bytes);
  final ui.FrameInfo frame = await codec.getNextFrame();
  return frame.image;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final ok = await initNativeBridge();
    if (!ok) {
      fail('initNativeBridge() failed; check RustLib bundling (#55)');
    }
  });

  group('CpuVisionRenderer.apply(): kVisionFilterCatalog 全 30 種', () {
    for (final entry in kVisionFilterCatalog) {
      testWidgets('${entry.id}: 実ブリッジで例外なく描画でき、strength=1.0 で出力が入力と異なる',
          (tester) async {
        // VisionFilterState.select() がカタログの defaultValue で payload を
        // 埋めるので、payload 付きフィルタも UI と同じ経路で実インスタンス化する
        // （手書きの座標値をここで重複定義しない。
        // experience_presets_smoke_test.dart と同じパターン）。
        final state = VisionFilterState()..select(entry.id);
        final filter = state.build();
        expect(filter, isNotNull, reason: '${entry.id} が build() できなかった');

        // 色覚デバイスで最も差が出やすいサンプル（色相スイープ + 明度ランプ +
        // 原色スウォッチ）を共有する。輝度の高い領域を含むため、閾値依存の
        // フィルタ（starbursts 等）も strength=1.0 で効果が現れる。
        //
        // サイズは production と同じ [BeforeAfterView.canonicalSampleSize]
        // （#85 レビュー S4）を使う。sensus の disk blur 系
        // （myopia/hyperopia/presbyopia/astigmatism）は半径を「画像サイズ ×
        // 固定比率」で決め、半径が 1px 未満だと楕円カーネルが中心 1 点のみに
        // 退化して strength=1.0 でも完全な no-op になる
        // （`build_ellipse_spans` の `<=1.0` 判定、sensus-core
        // src/vision/common.rs）。比率が最小の astigmatism/presbyopia
        // （1.1%）でも canonical サイズなら半径 11px 超と余裕がある——
        // ただし sensus 側で比率定数（`*_MAX_RADIUS_RATIO`）が変わったり、
        // canonical サイズ自体を大きく下げたりすると再び no-op になり得る点は
        // 変わらないので、この定数に依存していることを忘れないこと。
        final src = await BeforeAfterView.generateSampleImage(
          BeforeAfterView.canonicalSampleSize,
        );
        addTearDown(src.dispose);

        final out = await CpuVisionRenderer.apply(src, filter!, 1.0);
        addTearDown(out.dispose);

        expect(out.width, BeforeAfterView.canonicalSampleSize,
            reason: entry.id);
        expect(out.height, BeforeAfterView.canonicalSampleSize,
            reason: entry.id);

        final srcPixels = await CpuVisionRenderer.imageToRgba8(src);
        final outPixels = await CpuVisionRenderer.imageToRgba8(out);
        expect(
          outPixels,
          isNot(equals(srcPixels)),
          reason: '${entry.id}: strength=1.0 で出力が原画と一致している '
              '(sensus_core::apply が no-op になっている疑い)',
        );
      });
    }
  });

  group('CpuVisionRenderer.apply(): protanopia の数値的な健全性 (#85 レビュー S7)', () {
    testWidgets('strength=0.0 は原画とバイト単位で一致する', (tester) async {
      final src = await BeforeAfterView.generateSampleImage(
        BeforeAfterView.canonicalSampleSize,
      );
      addTearDown(src.dispose);

      final out = await CpuVisionRenderer.apply(
        src,
        const VisionFilter.protanopia(),
        0.0,
      );
      addTearDown(out.dispose);

      final srcPixels = await CpuVisionRenderer.imageToRgba8(src);
      final outPixels = await CpuVisionRenderer.imageToRgba8(out);
      expect(outPixels, equals(srcPixels),
          reason: 'strength=0.0 は sensus 側の normalize_strength で恒等変換になるはず');
    });

    testWidgets('strength=1.0 と strength=0.6 は出力が異なる', (tester) async {
      final src = await BeforeAfterView.generateSampleImage(
        BeforeAfterView.canonicalSampleSize,
      );
      addTearDown(src.dispose);

      final outFull = await CpuVisionRenderer.apply(
        src,
        const VisionFilter.protanopia(),
        1.0,
      );
      addTearDown(outFull.dispose);
      final outPartial = await CpuVisionRenderer.apply(
        src,
        const VisionFilter.protanopia(),
        0.6,
      );
      addTearDown(outPartial.dispose);

      final fullPixels = await CpuVisionRenderer.imageToRgba8(outFull);
      final partialPixels = await CpuVisionRenderer.imageToRgba8(outPartial);
      expect(partialPixels, isNot(equals(fullPixels)),
          reason: 'strength の違いが出力に反映されていない');
    });

    testWidgets('strength=1.0 で変化したピクセルの割合が下限を超える', (tester) async {
      final src = await BeforeAfterView.generateSampleImage(
        BeforeAfterView.canonicalSampleSize,
      );
      addTearDown(src.dispose);

      final out = await CpuVisionRenderer.apply(
        src,
        const VisionFilter.protanopia(),
        1.0,
      );
      addTearDown(out.dispose);

      final srcPixels = await CpuVisionRenderer.imageToRgba8(src);
      final outPixels = await CpuVisionRenderer.imageToRgba8(out);
      expect(outPixels.length, srcPixels.length);

      var changedPixels = 0;
      final totalPixels = srcPixels.length ~/ 4;
      for (var i = 0; i < srcPixels.length; i += 4) {
        if (srcPixels[i] != outPixels[i] ||
            srcPixels[i + 1] != outPixels[i + 1] ||
            srcPixels[i + 2] != outPixels[i + 2]) {
          changedPixels++;
        }
      }
      final changedRatio = changedPixels / totalPixels;
      // サンプル画像は色相スイープ（あらゆる色相を含む）なので、protanopia
      // （赤系統を大きく圧縮する）は大部分のピクセルで何らかの変化を起こす
      // はず。しきい値は「ごく一部のピクセルしか変わっていない」退行
      // （例: 誤って一部領域にしか適用されない）を検知できる程度に控えめに
      // 取ってある。
      expect(changedRatio, greaterThan(0.3),
          reason: '変化したピクセルの割合が低すぎる（$changedRatio）: '
              'protanopia が一部にしか効いていない疑い');
    });

    testWidgets(
        'strength=1.0 の出力は既存 golden 参照（protanopia_ref.png）と'
        'ほぼバイト一致する', (tester) async {
      // protanopia_ref.png は rust/src/golden_gen.rs が
      // apply_vision_cpu_rgba8（= 本テストが呼ぶのと同じ Rust 関数）で
      // protanopia_input.png から生成した参照。Dart 側の往復変換
      // （straight RGBA8 の premultiply/un-premultiply、#85 レビュー S1）は
      // 両画像とも alpha==255 なら恒等変換のはずなので、ここでバイト単位
      // （小さな丸め誤差のみ許容）の一致を確認する。
      final input = await _decodeFile('test/golden/protanopia_input.png');
      addTearDown(input.dispose);
      final ref = await _decodeFile('test/golden/protanopia_ref.png');
      addTearDown(ref.dispose);
      expect(input.width, ref.width);
      expect(input.height, ref.height);

      final out = await CpuVisionRenderer.apply(
        input,
        const VisionFilter.protanopia(),
        1.0,
      );
      addTearDown(out.dispose);

      final outPixels = await CpuVisionRenderer.imageToRgba8(out);
      final refPixels = await CpuVisionRenderer.imageToRgba8(ref);
      expect(outPixels.length, refPixels.length);

      var maxDiff = 0;
      for (var i = 0; i < outPixels.length; i++) {
        final d = (outPixels[i] - refPixels[i]).abs();
        if (d > maxDiff) maxDiff = d;
      }
      expect(maxDiff, lessThanOrEqualTo(1),
          reason: 'CpuVisionRenderer 経由の protanopia 出力が golden 参照と'
              '乖離している（maxDiff=$maxDiff）');
    });
  });
}
