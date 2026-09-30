import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/rendering/cpu_vision_renderer.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';

/// CpuVisionRenderer の往復変換（`ui.Image` ⇄ raw RGBA8）の忠実性テスト（#85）。
///
/// `CpuVisionRenderer.apply()` 自体は実ブリッジ（`applyVisionCpuRgba8`）を必要と
/// するため、native lib をロードしない `flutter test` では呼べない（実描画の
/// 検証は `integration_test/cpu_preview_all_filters_test.dart` が担う）。
/// 本ファイルはブリッジを挟まない往復変換部分（`imageToRgba8`/
/// `premultiplyStraightRgba8`/`rgba8ToImage`）のみを検証する。
///
/// ## alpha の扱い（#85、訂正）
///
/// Flutter の `ui.Image` は premultiplied alpha で GPU テクスチャを保持する
/// （`ImageByteFormat.rawRgba` で読む生バイト列、`PixelFormat.rgba8888` で
/// 書き込む生バイト列のいずれも premultiplied）。sensus（`image` crate 経由）は
/// straight（非 premultiplied）alpha を前提にした画素処理を行うため、
/// `CpuVisionRenderer` は境界で明示的に変換する: 入力は
/// `ImageByteFormat.rawStraightRgba` で straight を読み（[imageToRgba8]）、
/// 出力は `premultiplyStraightRgba8` で premultiplied に変換してから `ui.Image`
/// を組み立てる（[rgba8ToImage]）。alpha==255（このアプリが実運用で扱う画像は
/// ほぼ全て不透明）では premultiply は恒等変換になるため、以下の「往復して
/// バイト完全一致」テストは alpha==255 の入力に対する検証であり、
/// alpha<255 の透過ピクセルに対する変換の正しさは別途
/// 「透過ピクセルを含む往復」テストで検証する。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ui.Image> decodeFile(String path) async {
    final Uint8List bytes = await File(path).readAsBytes();
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    return frame.image;
  }

  group('imageToRgba8 / rgba8ToImage の往復', () {
    test('既存 golden 参照 PNG を往復させてもバイト単位で一致する', () async {
      final ui.Image original =
          await decodeFile('test/golden/protanopia_ref.png');
      addTearDown(original.dispose);

      final Uint8List originalRgba8 =
          await CpuVisionRenderer.imageToRgba8(original);

      final ui.Image roundTripped = await CpuVisionRenderer.rgba8ToImage(
        originalRgba8,
        original.width,
        original.height,
      );
      addTearDown(roundTripped.dispose);

      expect(roundTripped.width, original.width);
      expect(roundTripped.height, original.height);

      final Uint8List roundTrippedRgba8 =
          await CpuVisionRenderer.imageToRgba8(roundTripped);

      expect(
        roundTrippedRgba8,
        equals(originalRgba8),
        reason: 'golden PNG は alpha==255（不透明）のみなので premultiply は'
            '恒等変換になり、sRGB/linear 変換や再圧縮も挟まないため、'
            'バイト単位で完全一致するはず（#85 の数値一致調査。alpha<255 の'
            'ケースは下の「透過ピクセルを含む往復」テストを参照）',
      );
    });

    test('raw RGBA8 のバイト数は width*height*4 と一致する', () async {
      final ui.Image image =
          await decodeFile('test/golden/protanopia_input.png');
      addTearDown(image.dispose);

      final Uint8List rgba8 = await CpuVisionRenderer.imageToRgba8(image);
      expect(rgba8.length, image.width * image.height * 4);
    });

    test('透過ピクセル（alpha=128 の既知の色）を含む往復で straight alpha が保たれる', () async {
      // 1x1 の半透明ピクセル。straight alpha 前提で描画する: Canvas に
      // Paint(color) で塗ると Skia は不透明色×アルファのブレンドで
      // 内部的に premultiply して合成するため、ここでは
      // `CpuVisionRenderer.rgba8ToImage`（premultiply 済みの
      // ImageDescriptor.raw 経路）を直接使って、straight な色 (200, 100, 50,
      // 128) を意図通りに埋め込んだ画像を作る。
      const straightR = 200, straightG = 100, straightB = 50, alpha = 128;
      final straightIn = Uint8List.fromList(
        [straightR, straightG, straightB, alpha],
      );

      final image = await CpuVisionRenderer.rgba8ToImage(straightIn, 1, 1);
      addTearDown(image.dispose);

      final straightOut = await CpuVisionRenderer.imageToRgba8(image);

      // premultiply→(GPU 内部表現)→imageToRgba8 の straight 変換という
      // 8bit 整数の往復を経るため、丸め誤差 1 まで許容する。alpha は
      // premultiply/straight 変換のどちらでも変化しないので厳密一致。
      expect(straightOut[3], alpha, reason: 'alpha 自体は変換で変わらない');
      expect((straightOut[0] - straightR).abs(), lessThanOrEqualTo(1),
          reason: 'R: straight 往復の丸め誤差は 1 まで');
      expect((straightOut[1] - straightG).abs(), lessThanOrEqualTo(1),
          reason: 'G: straight 往復の丸め誤差は 1 まで');
      expect((straightOut[2] - straightB).abs(), lessThanOrEqualTo(1),
          reason: 'B: straight 往復の丸め誤差は 1 まで');
    });
  });

  group('premultiplyStraightRgba8', () {
    test('alpha==255 は恒等変換（かつ新しいバッファを確保しない fast path）', () {
      final straight =
          Uint8List.fromList([255, 255, 255, 255, 10, 20, 30, 255]);
      final out = CpuVisionRenderer.premultiplyStraightRgba8(straight);
      expect(out, equals(straight));
      expect(identical(out, straight), isTrue,
          reason: '全ピクセル不透明なら straight をそのまま返す fast path が働いているはず');
    });

    test(
        '1ピクセルでも alpha<255 が混ざっていれば fast path を使わず新しい'
        'バッファを返す', () {
      final straight = Uint8List.fromList([
        255, 255, 255, 255, // 不透明
        10, 20, 30, 128, // 半透明が1ピクセル混ざる
      ]);
      final out = CpuVisionRenderer.premultiplyStraightRgba8(straight);
      expect(identical(out, straight), isFalse);
    });

    test('alpha==0 は RGB がすべて 0 になる', () {
      final straight = Uint8List.fromList([255, 0, 0, 0]);
      final out = CpuVisionRenderer.premultiplyStraightRgba8(straight);
      expect(out, equals(Uint8List.fromList([0, 0, 0, 0])));
    });

    test('alpha==128 は round(straight * alpha / 255) になる', () {
      // 200*128=25600, +127=25727, ~/255=100（255*100=25500, 余り227）。
      // 100*128=12800, +127=12927, ~/255=50（255*50=12750, 余り177）。
      // 50*128=6400, +127=6527, ~/255=25（255*25=6375, 余り152）。
      final straight = Uint8List.fromList([200, 100, 50, 128]);
      final out = CpuVisionRenderer.premultiplyStraightRgba8(straight);
      expect(out, equals(Uint8List.fromList([100, 50, 25, 128])));
    });
  });

  group('rgba8ToImage の失敗', () {
    test('バッファ長が width*height*4 と食い違うと例外になる（ハングしない）', () async {
      // decodeImageFromPixels（コールバック API）はデコード失敗時にコール
      // バックが一度も呼ばれず Future が永久に解決しないことがあった。
      // ImmutableBuffer/ImageDescriptor/instantiateCodec ベースの現在の実装は
      // 失敗が普通の例外として Future の rejection で伝わることを確認する
      // （テストがハングしてタイムアウトするのではなく、明示的に失敗として
      // 検出できる）。
      final tooShort = Uint8List(4); // 100x100x4 バイト必要なところ 4 バイトのみ。
      await expectLater(
        CpuVisionRenderer.rgba8ToImage(tooShort, 100, 100),
        throwsA(anything),
      );
    });
  });

  group('applier seam', () {
    tearDown(() {
      CpuVisionRenderer.applier = CpuVisionRenderer.apply;
    });

    test('既定値は CpuVisionRenderer.apply 自身', () {
      expect(CpuVisionRenderer.applier, same(CpuVisionRenderer.apply));
    });

    test('フェイクに差し替えて元へ戻せる（#58 と同じ @visibleForTesting seam パターン）', () async {
      var called = false;
      CpuVisionRenderer.applier = (source, filter, strength) async {
        called = true;
        return source;
      };
      expect(CpuVisionRenderer.applier, isNot(same(CpuVisionRenderer.apply)));

      final dummy = await decodeFile('test/golden/protanopia_input.png');
      addTearDown(dummy.dispose);
      // フェイクは source をそのまま返すだけなので、filter/strength の実値は
      // この呼び出し経路の確認には関係ない（任意の定数でよい）。
      await CpuVisionRenderer.applier(
        dummy,
        const VisionFilter.protanopia(),
        1.0,
      );
      expect(called, isTrue);
    });
  });

  group('pipelineApplier seam（複数ステップ、#118）', () {
    tearDown(() {
      CpuVisionRenderer.pipelineApplier = CpuVisionRenderer.applyPipeline;
    });

    test('既定値は CpuVisionRenderer.applyPipeline 自身で、単一版の seam とは独立', () {
      expect(CpuVisionRenderer.pipelineApplier,
          same(CpuVisionRenderer.applyPipeline));
      expect(CpuVisionRenderer.applier, same(CpuVisionRenderer.apply));
    });

    test('seam の型の契約: フェイクへ差し替えて呼べる', () async {
      // 注: フェイクを直接呼ぶだけなので、実際の呼び出し側の配線（layers 順・強度・
      // payload を渡す）は検証しない。それは production の呼び出し元ができる #119 で
      // テストする。ここでは seam の型（ui.Image, List<VisionStep>）→ ui.Image の契約だけを固定する。
      var called = false;
      CpuVisionRenderer.pipelineApplier = (source, steps) async {
        called = true;
        return source;
      };
      expect(CpuVisionRenderer.pipelineApplier,
          isNot(same(CpuVisionRenderer.applyPipeline)));

      final dummy = await decodeFile('test/golden/protanopia_input.png');
      addTearDown(dummy.dispose);
      final out = await CpuVisionRenderer.pipelineApplier(
        dummy,
        const [VisionStep(filter: VisionFilter.myopia(), strength: 0.8)],
      );
      expect(called, isTrue);
      expect(identical(out, dummy), isTrue);
    });
  });

  group('VisionStep の等値性', () {
    test('payload（astigmatism の axisDeg）と強度の違いを区別し、同値は等しい', () {
      const base = VisionStep(
        filter: VisionFilter.astigmatism(axisDeg: 30),
        strength: 0.4,
      );
      expect(
        base,
        const VisionStep(
          filter: VisionFilter.astigmatism(axisDeg: 30),
          strength: 0.4,
        ),
      );
      expect(
        base.hashCode,
        const VisionStep(
          filter: VisionFilter.astigmatism(axisDeg: 30),
          strength: 0.4,
        ).hashCode,
      );
      expect(
        base,
        isNot(const VisionStep(
          filter: VisionFilter.astigmatism(axisDeg: 45),
          strength: 0.4,
        )),
        reason: 'payload が違えば別ステップ',
      );
      expect(
        base,
        isNot(const VisionStep(
          filter: VisionFilter.astigmatism(axisDeg: 30),
          strength: 0.5,
        )),
        reason: '強度が違えば別ステップ',
      );
      expect(
        const [
          VisionStep(filter: VisionFilter.myopia(), strength: 0.8),
          VisionStep(filter: VisionFilter.protanopia(), strength: 1.0),
        ],
        isNot(equals(const [
          VisionStep(filter: VisionFilter.protanopia(), strength: 1.0),
          VisionStep(filter: VisionFilter.myopia(), strength: 0.8),
        ])),
        reason: '並びの順が違う列は等しくない',
      );
    });
  });
}
