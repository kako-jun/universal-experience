import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/disability_type.dart';
import '../../models/vision_filter_catalog.dart';
import '../../services/filter_service.dart';
import '../../services/preview_selection.dart';
import '../../services/settings_service.dart';
import '../../services/vision_filter_state.dart';
import '../widgets/before_after_view.dart';
import '../widgets/experience_presets.dart';
import '../widgets/filter_selector.dart';
import '../widgets/intensity_slider.dart';
import '../widgets/filter_catalog_selector.dart';
import '../widgets/filter_param_panel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  FilterService? _filterService;

  /// The [FilterService.currentFilter] value last mirrored into
  /// [VisionFilterState] by [_syncVisionFilterState] (#60). `null` before the
  /// first sync. Guards the mirroring to the *edges* of `currentFilter`
  /// changing — not every [FilterService] notification (e.g. `setIntensity`
  /// dragging the color-vision slider also notifies) — so an advanced/preset
  /// selection made in the meantime isn't clobbered by an unrelated intensity
  /// tick.
  ColorVisionType? _syncedColorType;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Bridge FilterService selection changes into SettingsService (#17) and
    // into VisionFilterState (#60, the preview's single source of truth).
    // Subscribe once.
    final filterService = context.read<FilterService>();
    if (!identical(filterService, _filterService)) {
      _filterService?.removeListener(_onFilterServiceChanged);
      _filterService = filterService;
      _filterService!.addListener(_onFilterServiceChanged);
      // Reflect the already-seeded startup filter (main.dart restores it
      // before HomeScreen is built, so no notification fires for it) into
      // the preview. Can't call _onFilterServiceChanged() synchronously here:
      // didChangeDependencies runs during the first build
      // (StatefulElement._firstBuild), and _persistFilterState /
      // _syncVisionFilterState notify other ChangeNotifiers
      // (SettingsService / VisionFilterState) — triggering
      // "setState() or markNeedsBuild() called during build". Defer to right
      // after the first frame instead.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onFilterServiceChanged();
      });
    }
  }

  void _onFilterServiceChanged() {
    _persistFilterState();
    _syncVisionFilterState();
  }

  // Only filterType is persisted through SettingsService. Intensity is owned
  // and persisted by FilterService itself (its own debounced SharedPreferences
  // store, #57) precisely so that dragging the slider — which fires this
  // listener on every tick via FilterService.notifyListeners — never reaches
  // SettingsService.notifyListeners, which the MaterialApp Consumer
  // (main.dart) rebuilds on. setFilterType's own no-op guard (unchanged type)
  // keeps this a no-op while only intensity is changing.
  void _persistFilterState() {
    final settings = context.read<SettingsService>();
    final filterService = _filterService;
    if (filterService == null) return;
    settings.setFilterType(filterService.currentFilter);
  }

  /// Mirrors the color-vision quick selection (`FilterSelector`/tray, both
  /// funnel through the single shared [FilterService]) into
  /// [VisionFilterState] (#60) — the preview's single source of truth. Only
  /// touches [VisionFilterState] when [FilterService.currentFilter] itself
  /// changed (see [_syncedColorType]), so it never overrides an advanced
  /// catalog or experience-preset selection made independently of the
  /// color-vision section.
  void _syncVisionFilterState() {
    final filterService = _filterService;
    if (filterService == null) return;
    final type = filterService.currentFilter;
    if (type == _syncedColorType) return;
    _syncedColorType = type;

    final visionState = context.read<VisionFilterState>();
    if (type == ColorVisionType.none) {
      // Only clear if the current selection is itself a color-vision quick
      // pick — an unrelated advanced/preset selection must stay untouched.
      if (visionState.isColorQuickSelection) visionState.clear();
      return;
    }
    // type != ColorVisionType.none here (excluded above), so
    // visionFilterForColorVisionType always returns non-null.
    final catalogId =
        visionFilterCatalogId(visionFilterForColorVisionType(type)!);
    if (catalogId != null) {
      visionState.selectColorVisionType(catalogId);
    }
  }

  @override
  void dispose() {
    _filterService?.removeListener(_onFilterServiceChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          const _ThemeModeButton(),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showAboutDialog(context),
            tooltip: l10n.aboutTooltip,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _buildHeaderSection(l10n),
              const SizedBox(height: 32),
              _buildFilterSection(l10n),
              const SizedBox(height: 24),
              _buildControlsSection(l10n),
              const SizedBox(height: 24),
              _buildPreviewSection(),
              const SizedBox(height: 32),
              _buildAdvancedSection(l10n),
              const SizedBox(height: 32),
              _buildExperiencePresetsSection(l10n),
              const SizedBox(height: 32),
              _buildInfoSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderSection(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.headerTagline,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.indigo.shade700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.headerSubtitle,
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterSection(AppLocalizations l10n) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.visibility, color: Colors.indigo.shade600),
                const SizedBox(width: 12),
                Text(
                  l10n.colorVisionSectionTitle,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const FilterSelector(),
            const SizedBox(height: 16),
            Text(
              l10n.colorVisionSectionNote,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsSection(AppLocalizations l10n) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune, color: Colors.indigo.shade600),
                const SizedBox(width: 12),
                Text(
                  l10n.intensitySectionTitle,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const IntensitySlider(),
          ],
        ),
      ),
    );
  }

  /// プレビューのカード（#60）。
  ///
  /// 描画対象は常に [VisionFilterState] の現在の選択（色覚クイック選択・
  /// advanced カタログ・体験プリセットのいずれで選んでも、最終的にここへ
  /// 書き込まれる — [_syncVisionFilterState] / `ExperiencePresets` /
  /// `FilterCatalogSelector` 参照）。strength は `previewStrength`
  /// （`lib/services/preview_selection.dart`）で 1 か所に集約した判定に従う。
  Widget _buildPreviewSection() {
    return Consumer2<VisionFilterState, FilterService>(
      builder: (context, visionState, filterService, _) {
        final theme = Theme.of(context);
        final l10n = AppLocalizations.of(context)!;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.compare, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Text(
                      l10n.previewSectionTitle,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                BeforeAfterView(
                  filter: visionState.build(),
                  filterId: visionState.selectedId,
                  strength: previewStrength(visionState, filterService),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Advanced（sensus 全 30 フィルタ）セクション。既存の色覚 7 種 UI とは別系統。
  Widget _buildAdvancedSection(AppLocalizations l10n) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.science_outlined, color: Colors.indigo.shade600),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.advancedSectionTitle,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.advancedSectionNote,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 20),
            const FilterCatalogSelector(),
            const Divider(height: 32),
            const FilterParamPanel(),
          ],
        ),
      ),
    );
  }

  /// 体験プリセット集 (#19) セクション。sensus の experiences() を消費し、
  /// 複合体験（前庭性めまい系 4 種）をタップで視覚フィルタに適用する。聴覚再生は
  /// 本 Issue 非スコープで、聴覚を含む体験は注記に留める。
  Widget _buildExperiencePresetsSection(AppLocalizations l10n) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: Colors.indigo.shade600),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.experienceSectionTitle,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.experienceSectionNote,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 20),
            const ExperiencePresets(),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoSection() {
    return Consumer<FilterService>(
      builder: (context, filterService, _) {
        final filter = filterService.currentFilter;

        if (filter == ColorVisionType.none) {
          return const SizedBox.shrink();
        }

        final l10n = AppLocalizations.of(context)!;
        return Card(
          color: Colors.blue.shade50,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info, color: Colors.blue.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        colorVisionTypeName(l10n, filter),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  colorVisionTypeDescription(l10n, filter),
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.blue.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.prevalenceLabel(colorVisionTypePrevalence(l10n, filter)),
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.blue.shade700,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAboutDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showAboutDialog(
      context: context,
      applicationName: l10n.appTitle,
      applicationVersion: '0.1.0',
      applicationIcon: const Icon(Icons.accessibility_new, size: 48),
      children: [
        Text(l10n.aboutBody),
        const SizedBox(height: 16),
        Text(l10n.aboutPhases),
      ],
    );
  }
}

/// AppBar action that cycles the persisted theme mode (system → light → dark →
/// system) and shows the current mode's icon. Writes through to
/// [SettingsService] so the choice survives restarts (#17).
class _ThemeModeButton extends StatelessWidget {
  const _ThemeModeButton();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer<SettingsService>(
      builder: (context, settings, _) {
        final (IconData icon, String label) = switch (settings.themeMode) {
          ThemeMode.system => (Icons.brightness_auto, l10n.themeTooltipSystem),
          ThemeMode.light => (Icons.light_mode, l10n.themeTooltipLight),
          ThemeMode.dark => (Icons.dark_mode, l10n.themeTooltipDark),
        };
        return IconButton(
          icon: Icon(icon),
          tooltip: l10n.themeTooltipHint(label),
          onPressed: () => settings.setThemeMode(_next(settings.themeMode)),
        );
      },
    );
  }

  ThemeMode _next(ThemeMode mode) => switch (mode) {
        ThemeMode.system => ThemeMode.light,
        ThemeMode.light => ThemeMode.dark,
        ThemeMode.dark => ThemeMode.system,
      };
}
