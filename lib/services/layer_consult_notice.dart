import '../l10n/app_localizations.dart';
import '../l10n/l10n_extensions.dart';
import 'vision_filter_metadata.dart';
import 'vision_filter_state.dart';
import 'vision_layer.dart';

/// [layer] 単体の受診喚起（#120）。複数層の合成（`mergeConsultInputs`）ではなく、その層だけを
/// sensus の入口（[visionFilterUrgencyProvider] / [visionFilterUrgencyEscalationProvider]）に
/// 渡して解決する。出す喚起が無ければ null。
ConsultNotice? layerConsultNotice(
  AppLocalizations l10n,
  VisionFilterState state,
  VisionLayer layer,
) {
  final filter = state.buildLayer(layer);
  return resolveConsultNotice(
    l10n,
    visionFilterUrgencyProvider(filter),
    visionFilterUrgencyEscalationProvider(filter),
  );
}
