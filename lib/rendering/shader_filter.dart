import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'color_matrices.g.dart';

/// 失敗した Future をキャッシュに残さない汎用の single-flight メモ化キャッシュ
/// （#58 レビュー S1）。
///
/// 素朴な `Map<K, Future<V>> ??=` キャッシュは、一度失敗した Future もそのまま
/// キャッシュし続けてしまうため、一時的な asset ロード失敗（I/O エラー等）が
/// 永続化し、以後すべての呼び出しが同じ失敗を再生するだけになる。本クラスは
/// 失敗を検知したらそのキーを即座に削除し、次回呼び出しで [create] を再実行
/// できるようにする。`ui.FragmentProgram` のような engine 依存の型を持ち出さず
/// 汎用にしてあるのは、`flutter test` から実 asset ロードなしに単体テストできる
/// ようにするため（クラス自体は汎用ユーティリティなので `@visibleForTesting`
/// は付けない。テスト専用の観測用フィールドである [debugLength] にのみ付ける
/// — #58 レビュー nit）。
class SingleFlightCache<K, V> {
  final Map<K, Future<V>> _entries = <K, Future<V>>{};

  /// [key] に対応する進行中/完了済みの Future を返す。無ければ [create] を呼んで
  /// キャッシュする。[create] が返す Future が失敗したら、そのキーのキャッシュを
  /// 削除する（次回呼び出しは新しい Future で再試行できる）。
  Future<V> get(K key, Future<V> Function() create) {
    final cached = _entries[key];
    if (cached != null) return cached;

    final future = create();
    _entries[key] = future;
    // 失敗を観測してキャッシュを剥がすための副チェーン。`onError` はここで
    // エラーを飲み込む（rethrow しない）ことでこの副チェーン自体は正常終了とし、
    // 「誰も listen していない Future の unhandled error」を起こさない。
    // 呼び出し元が await する元の `future` はここでは変更されないため、
    // 失敗はそちらには変わらずそのまま伝わる。
    future.then((_) {}, onError: (Object error) {
      if (identical(_entries[key], future)) {
        _entries.remove(key);
      }
    });
    return future;
  }

  /// 現在キャッシュされているキー数（テスト用）。
  @visibleForTesting
  int get debugLength => _entries.length;
}

/// FragmentProgram (Impeller GPU シェーダ) で sensus 由来の視覚フィルタを
/// `ui.Image` に適用するヘルパ。
///
/// 色覚 3 型（protanopia/deuteranopia/tritanopia）+ achromatopsia が実描画対応
/// 済み（#59）。配線の骨格は #11 のゴールのまま:
///   FragmentProgram.fromAsset → fragmentShader() → setFloat で uniform を積む
///   → setImageSampler(0, src) → PictureRecorder.drawRect(Paint..shader) → toImage。
///
/// 色行列系（protanopia/deuteranopia/tritanopia）の uniform 順序は各 `.frag` の
/// 宣言順に厳密一致させる:
///   [uStrength, uMatrix0..uMatrix8, uResolution_x, uResolution_y]（float 12 本）
///   + setImageSampler(0, src)。achromatopsia は
///   [uStrength, uRWeight, uGWeight, uBWeight, uResolution_x, uResolution_y]。
class ShaderFilter {
  ShaderFilter._();

  static const String _protanopiaAsset = 'shaders/protanopia.frag';
  static const String _deuteranopiaAsset = 'shaders/deuteranopia.frag';
  static const String _tritanopiaAsset = 'shaders/tritanopia.frag';
  static const String _achromatopsiaAsset = 'shaders/achromatopsia.frag';

  /// sensus_core の `resolve_severity_matrix`（`pub(crate)` で ue から直接呼べない）
  /// と**同じ計算**を Dart で再現する: [grid]（severity=0.0..1.0 を 0.1 刻みで
  /// 汲み出した 11 個の解決済み 3x3 行列、行優先・9 要素、
  /// `lib/rendering/color_matrices.g.dart` 参照）に対し、[strength] が属する
  /// グリッド区間（`[i0/10, (i0+1)/10]`）だけを要素ごとに線形補間する
  /// （**11 点を跨いで全域を単一直線で結ぶ旧実装の線形補間とは異なる** — #56/#59
  /// で判明した不一致の原因そのもの）。
  ///
  /// [strength] は NaN→0、範囲外は 0.0..1.0 に clamp（sensus の
  /// `normalize_strength`/NaN 分岐と同じ挙動）。`grid.length` は必ず 11
  /// （呼び出し側の契約。テストでも生成物でもこの前提が崩れることはない）。
  ///
  /// `test/color_matrix_interpolation_test.dart` が、rust 側で sensus CPU から
  /// 直接汲み出した strength=0/0.25/0.5/0.75/1.0 の行列 fixture と本メソッドの
  /// 出力を突き合わせ、この再実装が正本と一致することを検証する。
  @visibleForTesting
  static List<double> resolveSeverityMatrix(
    List<List<double>> grid,
    double strength,
  ) {
    assert(grid.length == 11, 'severity grid must have exactly 11 points');
    final double s = strength.isNaN ? 0.0 : strength.clamp(0.0, 1.0);
    final double scaled = s * 10.0;
    final int i0 = scaled.floor().clamp(0, 10);
    final double frac = scaled - i0;
    if (frac <= 0.0 || i0 >= 10) {
      return List<double>.from(grid[i0]);
    }
    final List<double> lo = grid[i0];
    final List<double> hi = grid[i0 + 1];
    return List<double>.generate(9, (i) => lo[i] + (hi[i] - lo[i]) * frac);
  }

  /// [grid]（[resolveSeverityMatrix] 参照）で解決した行列を uMatrix として
  /// [shaderAsset] に適用する、色覚 3 型共通の内部ヘルパ。
  static Future<ui.Image> _applyMachadoGpu(
    ui.Image src,
    String shaderAsset,
    List<List<double>> grid,
    double strength,
  ) {
    final double s = strength.isNaN ? 0.0 : strength.clamp(0.0, 1.0);
    final List<double> matrix = resolveSeverityMatrix(grid, s);
    final List<double> scalarUniforms = <double>[s, ...matrix];
    return applyColorFilterGpu(src, shaderAsset, scalarUniforms);
  }

  /// protanopia フィルタを GPU で [src] に適用し、新しい [ui.Image] を返す。
  ///
  /// [strength] は 0.0..=1.0 (0.0=原画, 1.0=完全適用)。[protanopiaColorMatrixGrid]
  /// を sensus と同じ区分線形補間（[resolveSeverityMatrix]）で解決した行列を
  /// `uMatrix` として渡す。
  static Future<ui.Image> applyProtanopiaGpu(
    ui.Image src,
    double strength,
  ) {
    return _applyMachadoGpu(
      src,
      _protanopiaAsset,
      protanopiaColorMatrixGrid,
      strength,
    );
  }

  /// deuteranopia フィルタを GPU で [src] に適用する。[applyProtanopiaGpu] と同じ
  /// 契約・同じ補間方式（[deuteranopiaColorMatrixGrid] を使う）。
  static Future<ui.Image> applyDeuteranopiaGpu(
    ui.Image src,
    double strength,
  ) {
    return _applyMachadoGpu(
      src,
      _deuteranopiaAsset,
      deuteranopiaColorMatrixGrid,
      strength,
    );
  }

  /// tritanopia フィルタを GPU で [src] に適用する。[applyProtanopiaGpu] と同じ
  /// 契約・同じ補間方式（[tritanopiaColorMatrixGrid] を使う）。
  static Future<ui.Image> applyTritanopiaGpu(
    ui.Image src,
    double strength,
  ) {
    return _applyMachadoGpu(
      src,
      _tritanopiaAsset,
      tritanopiaColorMatrixGrid,
      strength,
    );
  }

  /// achromatopsia フィルタを GPU で [src] に適用する。
  ///
  /// Machado severity テーブルを持たず、`achromatopsia.frag` がシェーダ内で
  /// `uStrength` を直接使って固定重み（[achromatopsiaRWeight] 等、BT.709
  /// photopic luminance）とのブレンドを行うため、[resolveSeverityMatrix] の
  /// ような補間は不要（重みは strength に依存しない定数）。
  static Future<ui.Image> applyAchromatopsiaGpu(
    ui.Image src,
    double strength,
  ) {
    final double s = strength.isNaN ? 0.0 : strength.clamp(0.0, 1.0);
    final List<double> scalarUniforms = <double>[
      s,
      achromatopsiaRWeight,
      achromatopsiaGWeight,
      achromatopsiaBWeight,
    ];
    return applyColorFilterGpu(src, _achromatopsiaAsset, scalarUniforms);
  }

  // ロード済み FragmentProgram を asset パスでキャッシュ（並行ロードの重複を避ける）。
  // 失敗した Future を残さない SingleFlightCache を使う（#58 レビュー S1）。
  @visibleForTesting
  static final SingleFlightCache<String, ui.FragmentProgram> programCache =
      SingleFlightCache<String, ui.FragmentProgram>();

  static Future<ui.FragmentProgram> _loadProgram(String asset) {
    return programCache.get(asset, () => ui.FragmentProgram.fromAsset(asset));
  }

  /// 色変換系フィルタ（色行列 / luma 重み）を GPU で [src] に適用する汎用経路。
  ///
  /// protanopia/deuteranopia/tritanopia/achromatopsia のように **解像度を最後の
  /// 2 uniform に持つ** `.frag`（`[..scalars.., uResolution_x, uResolution_y]`）を対象に、
  /// [scalarUniforms]（= 正本 `vision_uniforms()` が返す末尾の解像度を含まない flat 配列、
  /// 例: `[uStrength, uMatrix0..8]` や `[uStrength, uRWeight, uGWeight, uBWeight]`）を
  /// `setFloat(0..)` で積み、続けて `setFloat(n, w)` / `setFloat(n+1, h)` を積んで
  /// `setImageSampler(0, src)` する。
  ///
  /// 色行列・luma 重みを Dart 側に**書かない**こと（正本は sensus_core）。本メソッドは
  /// golden テストが正本由来の uniforms（`test/golden/color_uniforms.json`）を流し込む
  /// ためのもので、ハードコードを増やさない。空間・時間依存フィルタ（blur/glaucoma/
  /// vertigo 等）はこのレイアウト前提（末尾が解像度）と適用モデルが異なるため対象外。
  static Future<ui.Image> applyColorFilterGpu(
    ui.Image src,
    String shaderAsset,
    List<double> scalarUniforms,
  ) async {
    final ui.FragmentProgram program = await _loadProgram(shaderAsset);
    final ui.FragmentShader shader = program.fragmentShader();

    final double w = src.width.toDouble();
    final double h = src.height.toDouble();

    for (int i = 0; i < scalarUniforms.length; i++) {
      final double v = scalarUniforms[i];
      // 非有限 uniform が GPU に流れて描画が壊れるのを防ぐ（NaN/Inf→0.0）。
      shader.setFloat(i, v.isFinite ? v : 0.0);
    }
    shader.setFloat(scalarUniforms.length, w);
    shader.setFloat(scalarUniforms.length + 1, h);
    shader.setImageSampler(0, src);

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    final ui.Paint paint = ui.Paint()..shader = shader;
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, w, h), paint);
    final ui.Picture picture = recorder.endRecording();
    try {
      return await picture.toImage(src.width, src.height);
    } finally {
      picture.dispose();
      shader.dispose();
    }
  }
}
