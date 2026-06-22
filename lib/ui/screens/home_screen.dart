import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/disability_type.dart';
import '../../services/filter_service.dart';
import '../../services/settings_service.dart';
import '../widgets/before_after_view.dart';
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Bridge FilterService selection/intensity changes into SettingsService so
    // the last filter + intensity are persisted (#17). Subscribe once.
    final filterService = context.read<FilterService>();
    if (!identical(filterService, _filterService)) {
      _filterService?.removeListener(_persistFilterState);
      _filterService = filterService;
      _filterService!.addListener(_persistFilterState);
    }
  }

  void _persistFilterState() {
    final settings = context.read<SettingsService>();
    final filterService = _filterService;
    if (filterService == null) return;
    settings.setFilterType(filterService.currentFilter);
    settings.setIntensity(filterService.intensity);
  }

  @override
  void dispose() {
    _filterService?.removeListener(_persistFilterState);
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

  Widget _buildPreviewSection() {
    return Consumer<FilterService>(
      builder: (context, filterService, _) {
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
                  filterType: filterService.currentFilter,
                  intensity: filterService.intensity,
                ),
                if (!BeforeAfterView.canRender(
                    filterService.currentFilter)) ...[
                  const SizedBox(height: 12),
                  Text(
                    l10n.previewUnsupportedNote,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
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
                  l10n.prevalenceLabel(filter.prevalence),
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
