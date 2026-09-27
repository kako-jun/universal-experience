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
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:universal_experience/models/vision_filter_catalog.dart';
import 'package:universal_experience/rendering/cpu_vision_renderer.dart';
import 'package:universal_experience/services/native_bridge_service.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';

Future<Uint8List> _rgba(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return data!.buffer.asUint8List();
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
        // サイズは 128（64 ではなく）にしてある: sensus の disk blur 系
        // （hyperopia/presbyobia/astigmatism）は半径を「画像サイズ ×
        // 固定比率」で決め、半径が 1px 未満だと楕円カーネルが中心 1 点のみに
        // 退化して strength=1.0 でも完全な no-op になる
        // （`build_ellipse_spans` の `<=1.0` 判定、sensus-core
        // src/vision/common.rs）。astigmatism の比率が最小（1.1%）で、
        // 64px だと半径 0.7px（no-op）・128px だと半径 1.4px（有効）になる。
        final src = await BeforeAfterView.generateSampleImage(128);
        addTearDown(src.dispose);

        final out = await CpuVisionRenderer.apply(src, filter!, 1.0);
        addTearDown(out.dispose);

        expect(out.width, 128, reason: entry.id);
        expect(out.height, 128, reason: entry.id);

        final srcPixels = await _rgba(src);
        final outPixels = await _rgba(out);
        expect(
          outPixels,
          isNot(equals(srcPixels)),
          reason: '${entry.id}: strength=1.0 で出力が原画と一致している '
              '(sensus_core::apply が no-op になっている疑い)',
        );
      });
    }
  });
}
