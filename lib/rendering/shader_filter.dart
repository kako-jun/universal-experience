import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

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
/// MVP では protanopia 1 枚のみ。配線は #11 のゴール:
///   FragmentProgram.fromAsset → fragmentShader() → setFloat で uniform を積む
///   → setImageSampler(0, src) → PictureRecorder.drawRect(Paint..shader) → toImage。
///
/// uniform 順序は shaders/protanopia.frag の宣言順に厳密一致させる:
///   [uStrength, uMatrix0..uMatrix8, uResolution_x, uResolution_y]（float 12 本）
///   + setImageSampler(0, src)。
class ShaderFilter {
  ShaderFilter._();

  static const String _protanopiaAsset = 'shaders/protanopia.frag';

  /// protanopia の Machado 2009 severity=1.0 行列 (行優先 3x3)。
  ///
  /// 値は sensus_core `PROTANOPIA_MATRIX` / 元 .frag コメントと同値。
  ///
  /// **既知の制約（#56 で判明、#59 に引き継ぎ）**: sensus 0.6 は `strength` を
  /// Machado 11 段 severity テーブルから**グリッド間の区分線形補間**した解決済み
  /// 行列を返すようになった（sensus#165）。11 個の固定点（グリッド）間だけを
  /// 線形補間するため、全域を単一の直線で結ぶ本メソッドの単純な線形補間とは
  /// 一致しない。この解決は `visionUniforms()`（FRB 経由で
  /// sensus-core を呼ぶ）でしか取得できないが、`ShaderFilter` はプレーンな
  /// `flutter test`（ネイティブブリッジ未初期化のホスト実行）からも呼ばれる。
  /// `RustLib.init()` は `initNativeBridge()` 経由で `main()` /
  /// `integration_test/`（`-d macos`、ネイティブ lib を同梱する
  /// `flutter build macos` 相当のビルドを経由）からしか呼ばれず、cargokit の
  /// ネイティブ lib ビルドを経ないプレーンな `flutter test` では
  /// `RustLib.init()` 自体が失敗する（#56 で実測確認済み。CI の `check` ジョブも
  /// `flutter build macos --debug` より前に `flutter test` を走らせる順序）。
  /// そのため本メソッドは、visionUniforms() を直接呼ばず、severity=1.0 の
  /// 単一行列を Dart 側で `strength` に**線形**補間する（sensus 0.6 より前の
  /// `protanopia.frag` が行っていたのと同じ式。0.6 の `.frag` 自体はコード
  /// 生成で sensus の GLSL をそのまま転写するため、もうこの blend を行わない
  /// ——シェーダ側の `uStrength` は未使用の参考値になった）。
  /// **中間 strength（0.0 と 1.0 以外）の見え方は sensus 正本の Machado
  /// テーブル補間と一致しない**。ブリッジ経由の解決値を使う本格対応
  /// （テスト側でネイティブ lib を用意する試験基盤の整備を含む）は #59。
  static const List<double> _protanopiaMatrix = <double>[
    0.152286, 1.052583, -0.204868, //
    0.114503, 0.786281, 0.099216, //
    -0.003882, -0.048116, 1.051998, //
  ];

  static const List<double> _identityMatrix3x3 = <double>[
    1.0, 0.0, 0.0, //
    0.0, 1.0, 0.0, //
    0.0, 0.0, 1.0, //
  ];

  /// protanopia フィルタを GPU で [src] に適用し、新しい [ui.Image] を返す。
  ///
  /// [strength] は 0.0..=1.0 (0.0=原画, 1.0=完全適用)。単位行列と
  /// [_protanopiaMatrix] を [strength] で線形補間した行列を `uMatrix` として渡す
  /// （中間 strength が sensus 正本と一致しない制約は [_protanopiaMatrix] の
  /// doc コメント参照）。
  static Future<ui.Image> applyProtanopiaGpu(
    ui.Image src,
    double strength,
  ) async {
    // sensus の normalize_strength 相当 (NaN→0, 0..=1 clamp)。非有限 uniform が
    // GPU に流れて画面が壊れるのを防ぐ。
    final double s = strength.isNaN ? 0.0 : strength.clamp(0.0, 1.0);
    final List<double> blendedMatrix = List<double>.generate(9, (i) {
      final double identity = _identityMatrix3x3[i];
      return identity + (_protanopiaMatrix[i] - identity) * s;
    });
    final List<double> scalarUniforms = <double>[s, ...blendedMatrix];
    return applyColorFilterGpu(src, _protanopiaAsset, scalarUniforms);
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
