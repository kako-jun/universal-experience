import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/disability_type.dart';
import '../../models/sample_catalog.dart';
import '../../services/app_shortcuts.dart';
import '../../services/filter_service.dart';
import '../../services/image_source_state.dart';
import '../../services/loupe_window_controller.dart';
import '../../services/preview_selection.dart';
import '../../services/settings_service.dart';
import '../../services/vision_filter_state.dart';
import '../widgets/before_after_view.dart';
import '../widgets/experience_presets.dart';
import '../widgets/filter_selector.dart';
import '../widgets/image_source_picker.dart';
import '../widgets/intensity_slider.dart';
import '../widgets/filter_catalog_selector.dart';
import '../widgets/filter_param_panel.dart';
import '../widgets/welcome_banner.dart';
import '../widgets/window_mode_panel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  FilterService? _filterService;
  VisionFilterState? _visionFilterStateForImageSource;

  /// `/`（アプリ内ショートカット、#63）で advanced カタログへフォーカスを移す
  /// ための FocusNode。検索欄が無い現状は、このカタログが `/` の唯一の対象。
  final FocusNode _catalogFocusNode = FocusNode(debugLabel: 'filterCatalog');

  /// ウェルカムバナーの「ほかの見え方を選ぶ」（#78 レビュー S8/nit）で
  /// `FilterSelectorState.focusSelectedChip` を呼ぶための GlobalKey。単一の
  /// 外部 FocusNode で `FilterSelector` 全体を包むだけでは見た目に何も
  /// 起きないため、実際に選択中のチップ（無ければ先頭）へフォーカスを移し
  /// `Scrollable.ensureVisible` でスクロールする責務は `FilterSelectorState`
  /// 自身に持たせ、ここからは GlobalKey 経由で呼び出すだけにする。
  final GlobalKey<FilterSelectorState> _filterSelectorKey =
      GlobalKey<FilterSelectorState>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Bridge FilterService selection changes into SettingsService so the last
    // filter type is persisted (#17). Subscribe once.
    //
    // #60: this used to also mirror FilterService.currentFilter into
    // VisionFilterState (the preview's single source of truth) via a
    // listener here. That mirroring is gone — color-vision selection now
    // updates both services directly, at the point of the user action
    // (`lib/services/color_vision_selection.dart`'s `selectColorVision`/
    // `deactivateColorVision`, called from `FilterSelector`, the tray, and
    // `main.dart`'s startup restore). A listener-based mirror needs a
    // postFrameCallback to avoid "setState() called during build" on first
    // subscribe, and a "did the type actually change" guard to avoid
    // clobbering an advanced/preset selection on every unrelated
    // notification (e.g. dragging the intensity slider) — and even with
    // that guard, re-tapping an already-current color chip after visiting
    // advanced wouldn't resync, since the type itself hadn't changed. Direct
    // updates at the call site need neither workaround.
    final filterService = context.read<FilterService>();
    if (!identical(filterService, _filterService)) {
      _filterService?.removeListener(_persistFilterState);
      _filterService = filterService;
      _filterService!.addListener(_persistFilterState);
    }

    // #78: switch the preview's sample to the newly-selected filter's
    // recommendation whenever the selection changes (`ImageSourceState`
    // itself no-ops unless auto-follow is active and no user image is
    // loaded — see that class's doc). Same subscribe-once pattern as
    // `_filterService` above, on `VisionFilterState` instead.
    final visionState = context.read<VisionFilterState>();
    if (!identical(visionState, _visionFilterStateForImageSource)) {
      _visionFilterStateForImageSource
          ?.removeListener(_followRecommendedSample);
      _visionFilterStateForImageSource = visionState;
      visionState.addListener(_followRecommendedSample);
    }
  }

  void _followRecommendedSample() {
    final visionState = _visionFilterStateForImageSource;
    if (visionState == null) return;
    context.read<ImageSourceState>().followRecommendedSample(
          recommendedSampleIdForFilter(visionState.selectedId),
        );
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

  @override
  void dispose() {
    _filterService?.removeListener(_persistFilterState);
    _visionFilterStateForImageSource?.removeListener(_followRecommendedSample);
    _catalogFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        // キー配列非依存にするため物理キーではなく文字で判定する (#63)。
        CharacterActivator('/'): FocusFilterSearchIntent(),
        SingleActivator(LogicalKeyboardKey.arrowUp):
            CycleFilterIntent(forward: false),
        SingleActivator(LogicalKeyboardKey.arrowDown):
            CycleFilterIntent(forward: true),
        SingleActivator(LogicalKeyboardKey.arrowLeft):
            AdjustStrengthIntent(delta: -kKeyboardStrengthStep),
        SingleActivator(LogicalKeyboardKey.arrowRight):
            AdjustStrengthIntent(delta: kKeyboardStrengthStep),
        SingleActivator(LogicalKeyboardKey.escape): ReleaseClickThroughIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          FocusFilterSearchIntent:
              InteractiveFocusAwareCallbackAction<FocusFilterSearchIntent>(
            onInvoke: (_) {
              _catalogFocusNode.requestFocus();
              return null;
            },
          ),
          CycleFilterIntent:
              InteractiveFocusAwareCallbackAction<CycleFilterIntent>(
            onInvoke: (intent) {
              cycleAdvancedFilter(
                context.read<VisionFilterState>(),
                forward: intent.forward,
              );
              return null;
            },
          ),
          AdjustStrengthIntent:
              InteractiveFocusAwareCallbackAction<AdjustStrengthIntent>(
            onInvoke: (intent) {
              adjustPreviewStrength(
                context.read<VisionFilterState>(),
                context.read<FilterService>(),
                intent.delta,
              );
              return null;
            },
          ),
          ReleaseClickThroughIntent:
              CallbackAction<ReleaseClickThroughIntent>(
            onInvoke: (_) {
              final loupeWindow = context.read<LoupeWindowController>();
              if (loupeWindow.clickThrough) {
                loupeWindow.setClickThrough(false);
              }
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
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
                    const SizedBox(height: 24),
                    WelcomeBanner(
                      onChooseOtherView: () =>
                          _filterSelectorKey.currentState?.focusSelectedChip(),
                    ),
                    const SizedBox(height: 8),
                    const WindowModePanel(),
                    const SizedBox(height: 24),
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
            FilterSelector(key: _filterSelectorKey),
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
  /// 書き込まれる — 色覚クイック選択は `lib/services/color_vision_selection.dart`
  /// の `selectColorVision`/`deactivateColorVision` 経由、それ以外は
  /// `ExperiencePresets` / `FilterCatalogSelector` 参照）。strength は
  /// `previewStrength`（`lib/services/preview_selection.dart`）で 1 か所に
  /// 集約した判定に従う。[VisionFilterState.colorVisionType] も渡し、色覚
  /// クイック選択のときは見出し・export の caption・ファイル名に -omaly の
  /// 名前を正しく出す（#60。カタログは色覚を 5 種しか持たず、-omaly は
  /// base の -opia と同じカタログ id に写るため id だけでは区別できない）。
  Widget _buildPreviewSection() {
    return Consumer3<VisionFilterState, FilterService, ImageSourceState>(
      builder: (context, visionState, filterService, imageSourceState, _) {
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
                    if (visionState.bypassed) ...[
                      const SizedBox(width: 12),
                      Chip(
                        label: Text(l10n.bypassedBadgeLabel),
                        backgroundColor: theme.colorScheme.secondaryContainer,
                        labelStyle: TextStyle(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                ImageSourcePicker(
                  child: BeforeAfterView(
                    filter: visionState.build(),
                    filterId: visionState.selectedId,
                    strength: previewStrength(visionState, filterService),
                    colorVisionType: visionState.colorVisionType,
                    imageSource: imageSourceState.current,
                  ),
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
            FilterCatalogSelector(focusNode: _catalogFocusNode),
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
