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

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:universal_experience/models/vision_filter_catalog.dart';
import 'package:universal_experience/rendering/cpu_vision_renderer.dart';
import 'package:universal_experience/services/native_bridge_service.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';

import '../test/support/sample_image_generator.dart';

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
        // を使う。sensus の disk blur 系
        // （myopia/hyperopia/presbyopia/astigmatism）は半径を「画像サイズ ×
        // 固定比率」で決め、半径が 1px 未満だと楕円カーネルが中心 1 点のみに
        // 退化して strength=1.0 でも完全な no-op になる
        // （`build_ellipse_spans` の `<=1.0` 判定、sensus-core
        // src/vision/common.rs）。比率が最小の astigmatism/presbyopia
        // （1.1%）でも canonical サイズなら半径 11px 超と余裕がある——
        // ただし sensus 側で比率定数（`*_MAX_RADIUS_RATIO`）が変わったり、
        // canonical サイズ自体を大きく下げたりすると再び no-op になり得る点は
        // 変わらないので、この定数に依存していることを忘れないこと。
        final src = await generateSampleImage(
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

  group('CpuVisionRenderer.apply(): protanopia の数値的な健全性', () {
    testWidgets('strength=0.0 は原画とバイト単位で一致する', (tester) async {
      final src = await generateSampleImage(
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
      final src = await generateSampleImage(
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
      final src = await generateSampleImage(
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

    testWidgets('非正方形（96×64）の画像でも出力サイズが一致し例外が出ない', (tester) async {
      // canonicalSampleSize は常に正方形だが、CpuVisionRenderer.apply 自体は
      // 任意のアスペクト比を受け付ける契約（#60 の advanced カタログ結線で
      // 正方形以外の入力が来ないとは限らない）なので、非正方形でも壊れない
      // ことを実ブリッジで確かめる。
      const width = 96;
      const height = 64;
      final src = await generateSampleImage(width);
      addTearDown(src.dispose);
      // generateSampleImage は正方形しか作れないので、非正方形の入力は
      // straight RGBA8 バッファを直接組み立てて作る（alpha は全て 255）。
      final srcPixels = await CpuVisionRenderer.imageToRgba8(src);
      final nonSquareBytes = Uint8List(width * height * 4);
      for (var i = 0; i < nonSquareBytes.length; i++) {
        nonSquareBytes[i] = srcPixels[i % srcPixels.length];
      }
      final nonSquareSrc = await CpuVisionRenderer.rgba8ToImage(
        nonSquareBytes,
        width,
        height,
      );
      addTearDown(nonSquareSrc.dispose);
      expect(nonSquareSrc.width, width);
      expect(nonSquareSrc.height, height);

      final out = await CpuVisionRenderer.apply(
        nonSquareSrc,
        const VisionFilter.protanopia(),
        1.0,
      );
      addTearDown(out.dispose);

      expect(out.width, width);
      expect(out.height, height);
    });

    testWidgets('純赤 2×1 を protanopia strength=1.0 で変換すると、Rust 側で1回だけ'
        '実測した期待 RGBA とバイト一致する', (tester) async {
      // 期待値の由来: rust/ で `apply_vision_cpu_rgba8(VisionFilter::Protanopia,
      // vec![255,0,0,255, 255,0,0,255], 2, 1, 1.0)` を一時的な #[ignore] テスト
      // （実行後に削除済み、1回だけ実行）で直接呼んで
      // 得た実測値。golden PNG のようなファイル I/O を挟まないため、
      // integration_test の CWD 問題（§3 冒頭のコメント参照）に影響されない。
      const width = 2;
      const height = 1;
      final straightIn = Uint8List.fromList([
        255, 0, 0, 255, // 純赤（ピクセル1）
        255, 0, 0, 255, // 純赤（ピクセル2）
      ]);
      final src = await CpuVisionRenderer.rgba8ToImage(
        straightIn,
        width,
        height,
      );
      addTearDown(src.dispose);

      final out = await CpuVisionRenderer.apply(
        src,
        const VisionFilter.protanopia(),
        1.0,
      );
      addTearDown(out.dispose);

      final outPixels = await CpuVisionRenderer.imageToRgba8(out);
      const expectedPixels = [
        109, 95, 0, 255, // ピクセル1
        109, 95, 0, 255, // ピクセル2
      ];
      expect(outPixels, equals(expectedPixels));
    });

    // 「strength=1.0 の出力を既存 golden 参照（protanopia_ref.png）と比較する」
    // テストは実装したが、CI で PathNotFoundException になり撤去した: デスクトップの integration_test は
    // ビルド済みアプリとして起動するため、`File('test/golden/...')` のような
    // リポジトリルート相対パスは実行時カレントディレクトリと一致しない
    // （ローカルの `flutter test integration_test/... -d macos` では手元の
    // シェルの CWD と一致してたまたま通っていた）。同じ数値的主張は既に
    // 他2箇所でファイル I/O なしに検証済みなので、この項目のカバレッジは
    // 失われていない:
    //   - rust 側 `cargo test`（golden_gen::tests::protanopia_ref_matches_sensus_core）
    //     が、golden 参照 PNG と `sensus_core::apply()`（= 本テストが呼ぶのと
    //     同じ関数を薄くラップした `apply_vision_cpu_rgba8`）の出力がバイト
    //     完全一致することを検証する。
    //   - test/cpu_vision_renderer_test.dart（plain `flutter test`、CWD が
    //     リポジトリルートと一致するため file I/O が安全に使える）が、golden
    //     参照 PNG を CpuVisionRenderer の往復変換（straight⇄premultiplied）
    //     にかけてもバイト完全一致することを検証する。
  });
}
