// tunnel_vision 警告閾値のドリフト検知 integration test（#161）。
//
// `lib/models/vision_filter_contract_notes.dart` の `kStrengthCautionByFilterId`
// は tunnel_vision の警告閾値 0.8 を、sensus-core の可視半径の式
//   inner_r = (1 - strength) * 0.5,  outer_r = inner_r + 0.05
// （半径は画像の半対角線 `max_r` で正規化した比。`src/vision/field.rs`）に
// 依存して決めている（0.8 のとき可視半径 0.1）。sensus が式を変えると閾値の根拠が
// 黙って崩れるので、実ブリッジで実際に適用して可視半径を測り、式と一致することを
// 確認する。
//
// 測定方法: 全面が一様な白（255,255,255,255）の 1280x720（16:9）画像に
// `apply_vision_cpu_rgba8` で tunnel_vision(Darken) を適用し、画像中心の水平行を
// 中心から右へ走査する。
//  - 可視半径 = 最初に「白から変化した」ピクセルまでの距離 / max_r（Darken は
//    `fade == 0`（r <= inner_r）のピクセルに触れないので、変化が始まる位置が inner_r）。
//    スムースステップの立ち上がりは緩やかで、最初の 8bit 変化は inner_r より
//    数 px 先に出るため、許容誤差を 0.005（≒3.7px）とする。
//  - 完全暗転半径 = 画像隅（r > outer_r が確実）のピクセルと同値になる最初の位置 /
//    max_r（= outer_r）。可視半径との差が帯の幅 0.05 になることも確認する。
//  - 面積: 白のまま残ったピクセル数が円 π(inner_r·max_r)² に一致すること。
// 許容誤差は上記の通り半径で 0.005、面積比で 20%（半径が数 px 大きく測れると小円では面積が 1 割超増える）。式が意味のある形で変わる
// （係数 0.5 の変更、max_r の正規化の変更、帯の幅の変更）と落ちる。
//
// 実行: `flutter test integration_test/tunnel_vision_threshold_drift_test.dart -d macos`
// デスクトップでは複数ファイルを 1 回で渡せない既知の制約があるため、CI でも個別実行。

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:universal_experience/models/vision_filter_contract_notes.dart';
import 'package:universal_experience/services/native_bridge_service.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';

const int _w = 1280;
const int _h = 720;
final double _maxR = math.sqrt((_w / 2) * (_w / 2) + (_h / 2) * (_h / 2));

/// 0.8 付近の強度で、式 (1 - s) * 0.5 を確認する。
const List<double> _strengths = [0.7, 0.79, 0.8, 0.81, 0.9];

class _Measured {
  _Measured(this.visibleR, this.darkR, this.untouchedPixels);
  final double visibleR;
  final double darkR;
  final int untouchedPixels;
}

Future<_Measured> _measure(double strength) async {
  final src = Uint8List(_w * _h * 4)..fillRange(0, _w * _h * 4, 255);
  final out = await applyVisionCpuRgba8(
    filter: const VisionFilter.tunnelVision(
      fieldLossMode: VisionFieldLossMode.darken,
    ),
    rgba8: src,
    width: _w,
    height: _h,
    strength: strength,
  );
  expect(out.length, src.length);

  int px(int x, int y, int c) => out[(y * _w + x) * 4 + c];
  bool isWhite(int x, int y) =>
      px(x, y, 0) == 255 && px(x, y, 1) == 255 && px(x, y, 2) == 255;

  const cx = _w ~/ 2;
  const cy = _h ~/ 2;
  final cornerR = px(0, 0, 0);
  final cornerG = px(0, 0, 1);
  final cornerB = px(0, 0, 2);

  int? visibleX;
  int? darkX;
  for (var x = cx; x < _w; x++) {
    if (visibleX == null && !isWhite(x, cy)) visibleX = x - cx;
    if (darkX == null &&
        px(x, cy, 0) == cornerR &&
        px(x, cy, 1) == cornerG &&
        px(x, cy, 2) == cornerB) {
      darkX = x - cx;
    }
  }
  expect(visibleX, isNotNull, reason: 'strength=$strength: 変化したピクセルが無い');
  expect(darkX, isNotNull, reason: 'strength=$strength: 完全暗転域に届かない');

  var untouched = 0;
  for (var y = 0; y < _h; y++) {
    for (var x = 0; x < _w; x++) {
      if (isWhite(x, y)) untouched++;
    }
  }
  return _Measured(visibleX! / _maxR, darkX! / _maxR, untouched);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final ok = await initNativeBridge();
    if (!ok) {
      fail('initNativeBridge() failed; check RustLib bundling (#55)');
    }
  });

  test('警告閾値は 0.8 のまま（このテストの前提）', () {
    expect(kStrengthCautionByFilterId['tunnel_vision']?.threshold, 0.8);
  });

  for (final s in _strengths) {
    testWidgets('strength=$s: 可視半径が (1-s)*0.5、帯の幅が 0.05（sensus 式との一致）',
        (tester) async {
      final m = await _measure(s);
      final innerR = (1.0 - s) * 0.5;

      expect(m.visibleR, closeTo(innerR, 0.005),
          reason: '可視半径が式 (1-s)*0.5 からずれた: sensus の式が変わった疑い');
      expect(m.darkR - m.visibleR, closeTo(0.05, 0.005),
          reason: '遷移帯の幅が 0.05 から外れた');

      final expectedArea = math.pi * math.pow(innerR * _maxR, 2);
      expect(m.untouchedPixels / expectedArea, closeTo(1.0, 0.2),
          reason: '無変化領域の面積が円 π(inner_r·max_r)² と合わない');
    });
  }

  testWidgets('閾値 0.8 の前提: 可視半径 0.1、16:9 で幅の約 1 割強、強度に対し単調減少',
      (tester) async {
    final at79 = await _measure(0.79);
    final at80 = await _measure(0.8);
    final at81 = await _measure(0.81);

    expect(at80.visibleR, closeTo(0.1, 0.005));
    // 可視円の直径が画像幅に占める比（コメントの「幅の約 1 割」）。
    final diameterOverWidth = 2 * at80.visibleR * _maxR / _w;
    expect(diameterOverWidth, inInclusiveRange(0.10, 0.13));

    expect(at79.visibleR, greaterThan(at80.visibleR));
    expect(at80.visibleR, greaterThan(at81.visibleR));
  });
}
