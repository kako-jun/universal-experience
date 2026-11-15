import '../src/rust/api/sensus_bridge.dart';

/// ライブのルーペ（#180）で、層ごとに通す GPU シェーダの計画（UI・I/O 非依存の純粋ロジック）。
///
/// 複数層は `VisionFilterState.pipelineSteps` と同じ段順の多段シェーダにする（#1 の
/// 制約）。GPU シェーダの無いフィルタ（`tools/sensus_shaders.README.md` の「Scope」で
/// 除外した 10 種）は飛ばし、HUD に「この症状は静止画プレビューのみ」と出す。

/// [filter] のシェーダアセット（`pubspec.yaml` の `flutter.shaders`）。GPU で描けない
/// フィルタは null。
String? liveShaderAssetFor(VisionFilter filter) {
  final String? name = switch (filter) {
    VisionFilter_Protanopia() => 'protanopia',
    VisionFilter_Deuteranopia() => 'deuteranopia',
    VisionFilter_Tritanopia() => 'tritanopia',
    VisionFilter_Achromatopsia() => 'achromatopsia',
    VisionFilter_Tetrachromacy() => 'tetrachromacy',
    VisionFilter_Myopia() => 'myopia',
    VisionFilter_Hyperopia() => 'hyperopia',
    VisionFilter_Presbyopia() => 'presbyopia',
    VisionFilter_Astigmatism() => 'astigmatism',
    VisionFilter_MacularDegeneration() => 'macular_degeneration',
    VisionFilter_Hemianopia() => 'hemianopia',
    VisionFilter_TunnelVision() => 'tunnel_vision',
    VisionFilter_Photophobia() => 'photophobia',
    VisionFilter_NightBlindness() => 'nyctalopia',
    VisionFilter_VestibularNeuritis() => 'vestibular_neuritis',
    VisionFilter_Diplopia() => 'diplopia',
    VisionFilter_Nystagmus() => 'nystagmus',
    VisionFilter_EyeStrain() => 'eye_strain',
    VisionFilter_ContrastSensitivity() => 'contrast_sensitivity',
    VisionFilter_Teichopsia() => 'teichopsia',
    // uint/int の uniform・第 2 サンプラ・uTime・可変長ループのため GPU 未対応。
    VisionFilter_Glaucoma() ||
    VisionFilter_Cataract() ||
    VisionFilter_Floaters() ||
    VisionFilter_Vertigo() ||
    VisionFilter_BppvRotation() ||
    VisionFilter_Starbursts() ||
    VisionFilter_DryEye() ||
    VisionFilter_Metamorphopsia() ||
    VisionFilter_DetailLoss() ||
    VisionFilter_FlickeringStars() =>
      null,
  };
  return name == null ? null : 'shaders/$name.frag';
}

/// 1 層ぶんのシェーダの通し方。
class LiveShaderPass {
  const LiveShaderPass({
    required this.filter,
    required this.asset,
    required this.strength,
  });

  final VisionFilter filter;
  final String asset;
  final double strength;
}

/// ライブで描く層（段順）と、GPU で描けないため飛ばした層。
class LiveFilterPlan {
  const LiveFilterPlan({required this.passes, required this.skipped});

  final List<LiveShaderPass> passes;
  final List<VisionFilter> skipped;
}

/// [steps]（適用順。強度 0 の層は呼び出し側で除いてある）を、シェーダの段と
/// 飛ばす層に分ける。順序は [steps] のまま保つ。
LiveFilterPlan planLiveFilters(List<VisionStep> steps) {
  final passes = <LiveShaderPass>[];
  final skipped = <VisionFilter>[];
  for (final step in steps) {
    final asset = liveShaderAssetFor(step.filter);
    if (asset == null) {
      skipped.add(step.filter);
    } else {
      passes.add(LiveShaderPass(
        filter: step.filter,
        asset: asset,
        strength: step.strength,
      ));
    }
  }
  return LiveFilterPlan(passes: passes, skipped: skipped);
}
