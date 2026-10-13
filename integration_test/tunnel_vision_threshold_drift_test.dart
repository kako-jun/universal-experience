// tunnel_vision 警告閾値のドリフト検知 integration test（#161）。
//
// `lib/models/vision_filter_contract_notes.dart` の `kStrengthCautionByFilterId`
// は tunnel_vision の警告閾値（0.8）を、sensus-core の可視半径の式
//   inner_r = (1 - strength) * 0.5,  outer_r = inner_r + 0.05
// （半径は画像の半対角線 `max_r` で正規化した比。`src/vision/field.rs`）に
// 依存して決めている。sensus が式を変えると閾値の根拠が黙って崩れるので、
// 実ブリッジで適用して半径を測り、式と一致することを確認する。
//
// 測定方法: 全面が一様な白の 2560x1440（16:9）画像に `apply_vision_cpu_rgba8`
// で tunnel_vision(Darken) を適用する。白では Darken の出力は
// `pack_u8(linear_to_srgb(1 - s*fade))` になり、fade は inner_r..outer_r の
// スムースステップ（fade=0.5 は r = inner_r + 帯幅/2 ちょうど）。
//  - 半減半径: 中心から右（水平行）・下（垂直列）へ走査し、値が
//    round(255*linear_to_srgb(1 - s/2)) 以下になる最初の画素の距離 / max_r。
//    期待は inner_r + 0.025。画素単位の離散化（ceil）を含め ±1px で一致を要求する。
//    係数 0.5 と帯幅の両方に感度があり、8bit 飽和には依存しない。
//  - 白から最初に変化する画素は inner_r より手前には来ない（>= inner_r - 0.5px）。
//  - 面積: 白のまま残る画素数 / 円 π(inner_r·max_r)² が 1.01..1.11（実値は
//    1.02..1.09。立ち上がりの緩やかな裾が数 px 乗る分だけ 1 を超える）。
//    水平・垂直の異方的な変化の検知を兼ねる。
// 係数 ±2%・帯幅 ±10% の変化は全強度で落ちる（numpy シミュレーション。強度 0.9 の
// 「係数 +2%」は半減半径では 1px 未満の差で漏れるが、面積比 1.126 > 1.11 で落ちる）。
// ±1px の窓について: 実際の式でも強度 0.7 / 0.81 / 0.9 では誤差が既に −1px
// （閾値を丸めて <= で比較するため、その側の余裕は 0px）。CI が OS 差で −2px に
// 揺れたら窓を [−2, +1] に広げる。その場合、帯幅 ±5% は 1〜2 強度で漏れ得る。
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

const int _w = 2560;
const int _h = 1440;
final double _maxR = math.sqrt((_w / 2) * (_w / 2) + (_h / 2) * (_h / 2));

/// sensus の linear → sRGB（標準ガンマ）。
double _linearToSrgb(double c) =>
    c <= 0.0031308 ? c * 12.92 : 1.055 * math.pow(c, 1 / 2.4) - 0.055;

class _Measured {
  _Measured(this.halfX, this.halfY, this.firstX, this.firstY, this.untouched);

  /// 半減点（値が round(255*srgb(1 - s/2)) 以下になる最初の画素）までの距離 px。
  final int halfX; // 水平（中心から右）
  final int halfY; // 垂直（中心から下）
  /// 白から最初に変化した画素までの距離 px。
  final int firstX;
  final int firstY;
  final int untouched;
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

  final halfValue = (_linearToSrgb(1.0 - strength / 2) * 255).round();

  const cx = _w ~/ 2;
  const cy = _h ~/ 2;
  int? scan(int n, int Function(int) at, bool Function(int) hit) {
    for (var i = 0; i < n; i++) {
      if (hit(at(i))) return i;
    }
    return null;
  }

  final halfX = scan(_w - cx, (i) => px(cx + i, cy, 0), (v) => v <= halfValue);
  final halfY = scan(_h - cy, (i) => px(cx, cy + i, 0), (v) => v <= halfValue);
  final firstX = scan(_w - cx, (i) => px(cx + i, cy, 0), (v) => v < 255);
  final firstY = scan(_h - cy, (i) => px(cx, cy + i, 0), (v) => v < 255);
  expect(halfX, isNotNull, reason: 'strength=$strength: 水平に半減点が無い');
  expect(halfY, isNotNull, reason: 'strength=$strength: 垂直に半減点が無い');
  expect(firstX, isNotNull, reason: 'strength=$strength: 水平に変化が無い');
  expect(firstY, isNotNull, reason: 'strength=$strength: 垂直に変化が無い');

  var untouched = 0;
  for (var y = 0; y < _h; y++) {
    for (var x = 0; x < _w; x++) {
      if (isWhite(x, y)) untouched++;
    }
  }
  return _Measured(halfX!, halfY!, firstX!, firstY!, untouched);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final ok = await initNativeBridge();
    if (!ok) {
      fail('initNativeBridge() failed; check RustLib bundling (#55)');
    }
  });

  // アプリの警告閾値そのもの。値が変わってもその強度で式を検証する。
  final threshold = kStrengthCautionByFilterId['tunnel_vision']!.threshold;
  final strengths = <double>[
    0.5,
    0.7,
    threshold - 0.01,
    threshold,
    threshold + 0.01,
    0.9
  ];

  for (final s in strengths) {
    testWidgets(
        'strength=$s: 半減半径 = inner_r + 0.025（±1px）、最初の変化は inner_r 以降、面積が円に近い',
        (tester) async {
      final m = await _measure(s);
      final innerPx = (1.0 - s) * 0.5 * _maxR;
      // 半減点は fade=0.5 の r = inner_r + 帯幅/2。画素は整数なので ceil が期待値。
      final halfPx = innerPx + 0.025 * _maxR;
      final expected = halfPx.ceil();

      expect((m.halfX - expected).abs(), lessThanOrEqualTo(1),
          reason: '水平の半減半径 ${m.halfX}px が期待 $expected px（式 '
              '(1-s)*0.5 + 0.05/2）から外れた: sensus の式が変わった疑い');
      expect((m.halfY - expected).abs(), lessThanOrEqualTo(1),
          reason: '垂直の半減半径 ${m.halfY}px が期待 $expected px から外れた'
              '（異方的な変化の疑い）');
      expect(m.firstX, greaterThanOrEqualTo(innerPx - 0.5),
          reason: '白からの最初の変化が inner_r より手前に来た（水平）');
      expect(m.firstY, greaterThanOrEqualTo(innerPx - 0.5),
          reason: '白からの最初の変化が inner_r より手前に来た（垂直）');

      final ratio = m.untouched / (math.pi * innerPx * innerPx);
      expect(ratio, inInclusiveRange(1.01, 1.11),
          reason: '無変化領域の面積比 $ratio が円 π(inner_r·max_r)² から外れた');
    });
  }

  testWidgets('警告閾値の前提: 閾値で可視円の直径が幅の 10-13%、強度に対し単調減少', (tester) async {
    final at = await _measure(threshold);
    final lower = await _measure(threshold - 0.01);
    final higher = await _measure(threshold + 0.01);

    // 完全に見える円（最初の変化まで）の直径が画像幅に占める比（コメントの「幅の約 1 割」）。
    final diameterOverWidth = 2 * at.firstX / _w;
    expect(diameterOverWidth, inInclusiveRange(0.10, 0.13));

    expect(lower.halfX, greaterThan(at.halfX));
    expect(at.halfX, greaterThan(higher.halfX));
  });
}
