import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/sample_catalog.dart';
import '../../services/app_shortcuts.dart';
import '../../services/filter_list_selection.dart';
import '../../services/filter_service.dart';
import '../../services/image_source_state.dart';
import '../../services/loupe_window_controller.dart';
import '../../services/preview_selection.dart';
import '../../services/settings_service.dart';
import '../../services/vision_filter_state.dart';
import '../widgets/adjust_panel.dart';
import '../widgets/before_after_view.dart';
import '../widgets/filter_browser.dart';
import '../widgets/image_source_picker.dart';
import '../widgets/language_dialog.dart';
import '../widgets/welcome_banner.dart';
import '../widgets/window_mode_panel.dart';

/// これ以上の幅（dp）で 3 カラム（選ぶ / 見る / 調整）、未満で縦に並べる（#72）。
const double kWideLayoutBreakpoint = 1000;

/// 狭幅レイアウトの内容の最大幅。
const double _kNarrowContentMaxWidth = 800;

/// 狭幅でのプレビューカードの最大幅。プレビュー（正方形の 2 枚が横並び）の
/// 高さを抑え、800x700 でも最初の画面に収める。
const double _kNarrowPreviewMaxWidth = 560;

/// 狭幅で一覧が使う高さ（一覧は内側でスクロールする）。
const double _kNarrowBrowserHeight = 560;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  FilterService? _filterService;
  VisionFilterState? _visionFilterStateForImageSource;

  /// 統合フィルタ一覧の検索語・カテゴリ・検索欄フォーカス（#72）。`/` で検索欄へ
  /// 移し、↑↓ で今見えている行を送るために、画面が保持する。ウェルカム
  /// バナーの「ほかの見え方を選ぶ」もここへフォーカスを移す。
  final FilterBrowserController _browser = FilterBrowserController();

  /// アプリ内ショートカット（`/` ↑↓ ←→ Esc、#63）の受け口となる FocusNode。
  /// 一覧の行をタップしたあとにフォーカスをここへ戻し、行（`InkResponse`）に
  /// フォーカスが残って ↑↓ ←→ が効かなくなるのを防ぐ。
  final FocusNode _shortcutFocus = FocusNode(debugLabel: 'homeShortcuts');

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
    // `deactivateColorVision`, called from the unified filter list, the tray, and
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
    _browser.dispose();
    _shortcutFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        // キー配列非依存にするため物理キーではなく文字で判定する (#63)。
        const CharacterActivator('/'): const FocusFilterSearchIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowUp):
            const CycleFilterIntent(forward: false),
        const SingleActivator(LogicalKeyboardKey.arrowDown):
            const CycleFilterIntent(forward: true),
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            const AdjustStrengthIntent(delta: -kKeyboardStrengthStep),
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            const AdjustStrengthIntent(delta: kKeyboardStrengthStep),
        const SingleActivator(LogicalKeyboardKey.escape):
            const ReleaseClickThroughIntent(),
        // Cmd+V（macOS）/ Ctrl+V: クリップボードの画像を貼り付ける (#97)。
        // 割り当てがプラットフォームで変わるので const マップには入れない。
        pasteShortcutActivator(): const PasteImageIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          FocusFilterSearchIntent:
              InteractiveFocusAwareCallbackAction<FocusFilterSearchIntent>(
            onInvoke: (_) {
              _browser.focusSearch();
              return null;
            },
          ),
          CycleFilterIntent:
              InteractiveFocusAwareCallbackAction<CycleFilterIntent>(
            onInvoke: (intent) {
              final filterService = context.read<FilterService>();
              final visionState = context.read<VisionFilterState>();
              final next = nextFilterListEntry(
                _browser.visibleEntries,
                selectedFilterListEntry(visionState),
                forward: intent.forward,
              );
              if (next != null) {
                applyFilterListEntry(filterService, visionState, next);
              }
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
          // テキスト入力にフォーカスがある間は奪わない（入力欄自身の貼り付けが
          // 優先。ボタン等では奪う。isFocusOnTextInput 参照、#97）。
          PasteImageIntent: TextInputAwareCallbackAction<PasteImageIntent>(
            onInvoke: (_) {
              unawaited(pasteUserImageFromClipboard(context));
              return null;
            },
          ),
          ReleaseClickThroughIntent: CallbackAction<ReleaseClickThroughIntent>(
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
          focusNode: _shortcutFocus,
          child: Scaffold(
            appBar: AppBar(
              title: Text(l10n.appTitle),
              actions: [
                IconButton(
                  icon: const Icon(Icons.window_outlined),
                  onPressed: () => showWindowModeDialog(context),
                  tooltip: l10n.windowModeSectionTitle,
                ),
                IconButton(
                  icon: const Icon(Icons.language),
                  onPressed: () => showLanguageDialog(context),
                  tooltip: l10n.languageSectionTitle,
                ),
                const _ThemeModeButton(),
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  onPressed: () => _showAboutDialog(context),
                  tooltip: l10n.aboutTooltip,
                ),
              ],
            ),
            body: Column(
              children: [
                // クリックスルー ON の間だけ出る復帰方法の案内（#63, #72）。
                const ClickThroughRecoveryBanner(),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) =>
                        constraints.maxWidth >= kWideLayoutBreakpoint
                            ? _buildWide(constraints.maxWidth)
                            : _buildNarrow(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 3 カラム（選ぶ / 見る / 調整）。Tab 順は左 → 中央 → 右（#45）。
  Widget _buildWide(double width) {
    final leftWidth = (width * 0.24).clamp(280.0, 340.0);
    final rightWidth = (width * 0.27).clamp(300.0, 380.0);
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: leftWidth,
              child: FocusTraversalOrder(
                order: const NumericFocusOrder(1),
                child: FocusTraversalGroup(child: _browserCard()),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: FocusTraversalOrder(
                order: const NumericFocusOrder(2),
                child: FocusTraversalGroup(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _previewCard(),
                        WelcomeBanner(onChooseOtherView: _browser.focusSearch),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: rightWidth,
              child: FocusTraversalOrder(
                order: const NumericFocusOrder(3),
                child: FocusTraversalGroup(
                  child: const Card(
                    margin: EdgeInsets.zero,
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(16),
                      child: AdjustPanel(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 縦積み: 上からプレビュー → 調整 → 選択（#72）。プレビューは最初の
  /// 画面に収める。
  Widget _buildNarrow() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kNarrowContentMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: _kNarrowPreviewMaxWidth),
                  child: _previewCard(),
                ),
              ),
              WelcomeBanner(onChooseOtherView: _browser.focusSearch),
              const SizedBox(height: 16),
              const Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: AdjustPanel(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(height: _kNarrowBrowserHeight, child: _browserCard()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _browserCard() => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilterBrowser(
            controller: _browser,
            onActivated: _shortcutFocus.requestFocus,
          ),
        ),
      );

  /// 中央「見る」: Before / After とサンプル切替（#72）。描画対象は常に
  /// [VisionFilterState] の現在の選択（#60）。strength は [previewStrength] に
  /// 集約した判定に従う。[VisionFilterState.colorVisionType] も渡し、色覚
  /// クイック選択のときは見出し・export の caption・ファイル名に -omaly の
  /// 名前を正しく出す。
  Widget _previewCard() {
    return Consumer3<VisionFilterState, FilterService, ImageSourceState>(
      builder: (context, visionState, filterService, imageSourceState, _) {
        final theme = Theme.of(context);
        final l10n = AppLocalizations.of(context)!;
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        l10n.previewSectionTitle,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    if (visionState.bypassed) ...[
                      Chip(
                        label: Text(l10n.bypassedBadgeLabel),
                        backgroundColor: theme.colorScheme.secondaryContainer,
                        labelStyle: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
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
        const SizedBox(height: 16),
        Text(l10n.aboutLiveCaptureNote),
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
