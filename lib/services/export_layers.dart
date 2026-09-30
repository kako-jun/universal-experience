import '../models/vision_filter_contract_notes.dart' as contract_notes;
import '../src/rust/api/sensus_bridge.dart' show VisionFilter;
import 'vision_filter_state.dart';
import 'vision_layer.dart';

/// PNG 書き出し（#121）が、重ねている層 1 つについて描画時点で控えておく値。
///
/// 書き出しのキャプション（症状名・強度・受診喚起・実験的の注記・ファイル名）は、
/// 画像を描画した時点の値から作る（呼び出し時点の現在の選択ではなく、
/// `BeforeAfterView` の `_afterExportLayers`）。そのため名前や喚起の文言の解決に必要な
/// 入力（層・構築済みの sensus フィルタ・強度）だけを持ち、文言はここでは解決しない。
class ExportLayer {
  const ExportLayer({
    required this.layer,
    required this.filter,
    required this.strength,
  });

  /// 層（カタログ id・別名・パラメータ・起源）。
  final VisionLayer layer;

  /// [layer] から構築した sensus のフィルタ（受診喚起の取得に使う）。
  final VisionFilter filter;

  /// この層の適用強度 0.0..1.0。
  final double strength;
}

/// 書き出しのキャプションに数える層: **画像に効いている層（強度が 0 より大きい層）だけ**。
///
/// 強度 0 の層は層としては残り、上限にも数えるが、画素には何も足さない（プレビューの
/// 合成 `VisionFilterState.pipelineSteps` も除く）。画像に写っていない症状の行や受診喚起を
/// 焼き込むと、画像だけが共有されたときに実際の見え方と食い違うので、書き出しでは数えない。
///
/// 「0 より大きい」は、キャプションに出す整数パーセント（[contract_notes.strengthPercent]、
/// 四捨五入）で判定する。0.004 のような値は行に「0%」と出るだけで何も伝えないため数えない。
/// （プレビューの合成は厳密に 0 の層だけを除くので、0.5% 未満の層はごくわずかに画素へ効くが、
/// 目に見える差ではなく、0% と書かれた行も出さない。）
///
/// 表示強度（整数パーセント）が 0 の層しかない（全層が強度 0、0.004 のみ、または原画比較中）
/// ときは、この関数の結果は空になる。
/// そのとき書き出しは画像が原画のままなので、従来どおりフォーカス中の層の名前・強度・喚起で
/// キャプションを作る（`planExport`。#121 以前の単一層と同じ出力）。
List<ExportLayer> effectiveExportLayers(Iterable<ExportLayer> layers) => [
      for (final l in layers)
        if (contract_notes.strengthPercent(l.strength) > 0) l,
    ];

/// [state] の全層（適用順）を、書き出し用に控える値にする。原画比較中（bypass）は
/// 画像が原画のままなので、どの層も効いていない扱いとして空を返す。
List<ExportLayer> exportLayersOf(VisionFilterState state) {
  if (state.bypassed) return const [];
  return [
    for (final layer in state.layers)
      ExportLayer(
        layer: layer,
        filter: state.buildLayer(layer),
        strength: state.strengthOf(layer),
      ),
  ];
}
