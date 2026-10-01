import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/sample_catalog.dart';
import '../../services/app_shortcuts.dart';
import '../../services/color_vision_compare.dart';
import '../../services/export_layers.dart';
import '../../services/filter_list_selection.dart';
import '../../services/image_source_state.dart';
import '../../services/loupe_window_controller.dart';
import '../../services/preview_selection.dart';
import '../../services/settings_service.dart';
import '../../services/vision_filter_state.dart';
import '../widgets/adjust_panel.dart';
import '../widgets/before_after_view.dart';
import '../widgets/color_vision_compare_view.dart';
import '../widgets/filter_browser.dart';
import '../widgets/filter_list_tile.dart';
import '../widgets/image_source_picker.dart';
import '../widgets/language_dialog.dart';
import '../widgets/layer_chip_strip.dart';
import '../widgets/welcome_banner.dart';
import '../widgets/window_mode_panel.dart';

/// これ以上の幅（dp）で 3 カラム（選ぶ / 見る / 調整）、未満で縦に並べる（#72）。
const double kWideLayoutBreakpoint = 1000;

/// 狭幅レイアウトの内容の最大幅。
const double _kNarrowContentMaxWidth = 800;

/// 狭幅でのプレビューカードの最大幅。プレビュー（正方形の 2 枚が横並び）の
/// 高さを抑え、800x700 でも最初の画面に収める。
const double _kNarrowPreviewMaxWidth = 560;

/// プレビュー画像（Before / After 各 1 枚の正方形）の一辺の下限（#130）。高さが足りなくても
/// これより小さくはしない（使い物にならない小ささになるより、縦にスクロールさせる）。
const double kMinPreviewPaneSide = 160;

/// プレビューカードのうち、画像以外が縦に使う高さ（dp、#130）。カード上端から画像の上端
/// まで（余白・見出しの行 + 「2×2 で比較」・画像の見出し行 48・余白）と、画像の下端から選択欄の
/// 下端まで（`ImageSourcePicker`。サンプルのチップが 3 行ほど折り返す）、選択欄の下の余白 16 の
/// 合計。実フォントでの実測は日本語で約 324、英語（チップが長く折り返しが 1 行増える）で約 348。
/// この値は実測に余裕（英語で約 12）を足した値で、実測の最大より大きくしてある。
/// 画像の一辺は「本体領域の高さ - この値」までに抑えて、既定のウィンドウ（800x600）でも選択欄の
/// 下端が最初のビューポートに収まるようにする。
/// 実測を超えてチップが折り返す（文字サイズ拡大など）ときは、選択欄が下にはみ出し、スクロールで届く。
const double _kPreviewChromeHeight = 360;

/// ウィンドウ（本体領域）の高さ [viewportHeight] に収まる、プレビュー画像の一辺の上限（#130）。
/// 下限は [kMinPreviewPaneSide]。余裕のある高さでは画像の自然な大きさより大きい値になり、
/// 実際には効かない。
double previewPaneSideFor(double viewportHeight) =>
    (viewportHeight - _kPreviewChromeHeight)
        .floorToDouble()
        .clamp(kMinPreviewPaneSide, double.infinity);

/// 狭幅で一覧が使う高さ（一覧は内側でスクロールする）。
const double _kNarrowBrowserHeight = 560;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  VisionFilterState? _visionFilterStateForImageSource;

  /// 統合フィルタ一覧の検索語・カテゴリ・検索欄フォーカス（#72）。`/` で検索欄へ
  /// 移し、↑↓ で今見えている行を送るために、画面が保持する。ウェルカム
  /// バナーの「ほかの見え方を選ぶ」もここへフォーカスを移す。
  final FilterBrowserController _browser = FilterBrowserController();

  /// アプリ内ショートカット（`/` ↑↓ ←→ Esc、#63）の受け口となる FocusNode。
  /// 一覧の行をタップしたあとにフォーカスをここへ戻し、行（`InkResponse`）に
  /// フォーカスが残って ↑↓ ←→ が効かなくなるのを防ぐ。
  final FocusNode _shortcutFocus = FocusNode(debugLabel: 'homeShortcuts');

  /// 「2×2 で比較」（色覚 4 型の一覧比較、#84）を選んでいるか。切替は色覚カテゴリを
  /// 選んでいる間だけ出る。色覚以外を選んでいる間は Before / After を出すが、
  /// この値は保持する（色覚に戻ると、直前に選んだ表示に戻る）。
  bool _compareColorVision = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // （選択状態の保存は VisionFilterStore の責務で、この画面は関与しない。#60/#124）

    // #78: switch the preview's sample to the newly-selected filter's
    // recommendation whenever the selection changes (`ImageSourceState`
    // itself no-ops unless auto-follow is active and no user image is
    // loaded — see that class's doc). Subscribe once.
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
          recommendedSampleIdForFilter(visionState.focusedId),
        );
  }

  @override
  void dispose() {
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
          // テキスト入力中だけ奪わない（`/` 自体が入力文字になる）。ボタン・チップ等の
          // クリック後（フォーカスが残る）でも検索欄へ移れるよう、↑↓・←→ より狭いガード
          // （isFocusOnTextInput 参照、#141）。
          FocusFilterSearchIntent:
              TextInputAwareCallbackAction<FocusFilterSearchIntent>(
            onInvoke: (_) {
              _browser.focusSearch();
              return null;
            },
          ),
          // ↑↓: 一覧の行の間でフォーカスだけを動かす（選択は変えない。足し引きは行の
          // Space/Enter、#120）。行にフォーカスがある間も受ける（ListTile の標準の移動だと、
          // 上限で無効の行や絞り込みの外へ出てしまうため）。ボタン・入力欄など行以外の
          // 操作部品の上では奪わない。
          //
          // 例外として、検索欄にフォーカスがある間の ↓ だけは奪い、今見えている先頭の行へ
          // フォーカスを移す（行の先頭での ↑ は検索欄へ戻る。#141）。
          CycleFilterIntent: _RowAwareCycleAction(
            isRowFocused: () => _browser.isRowFocused,
            isSearchDown: () => _browser.isSearchDownEnabled,
            onInvoke: (intent) {
              if (_browser.isSearchFocused) {
                _browser.focusFirstRow();
                return null;
              }
              // 行にフォーカスが無いときは、調整中の層の行から送る（先頭からではなく）。
              final focused = context.read<VisionFilterState>().focusedLayer;
              _browser.moveRowFocus(
                forward: intent.forward,
                from: focused == null ? null : filterListEntryForLayer(focused),
              );
              return null;
            },
          ),
          AdjustStrengthIntent:
              InteractiveFocusAwareCallbackAction<AdjustStrengthIntent>(
            onInvoke: (intent) {
              adjustPreviewStrength(
                context.read<VisionFilterState>(),
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
                            ? _buildWide(constraints.maxWidth,
                                previewPaneSideFor(constraints.maxHeight))
                            : _buildNarrow(
                                previewPaneSideFor(constraints.maxHeight)),
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
  Widget _buildWide(double width, double maxPaneSide) {
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
                child: _browserCard(),
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
                        _previewCard(maxPaneSide),
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
  Widget _buildNarrow(double maxPaneSide) {
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
                  child: _previewCard(maxPaneSide),
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

  /// 広幅の左カラム・狭幅の末尾で共通。一覧の行（体験プリセットの行も同じ
  /// `FilterListTile`）からの ←→ を受け口へ固定する走査方針を付ける（#84）。
  Widget _browserCard() => FocusTraversalGroup(
        policy: _ListExitToShortcutsPolicy(_shortcutFocus),
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilterBrowser(
              controller: _browser,
              onActivated: _shortcutFocus.requestFocus,
            ),
          ),
        ),
      );

  /// 中央「見る」: Before / After とサンプル切替（#72）。描画対象は常に
  /// [VisionFilterState] の現在の選択（#60）。strength は [previewStrength] に
  /// 集約した判定に従う。[VisionFilterState.focusedVariantId] も渡し、色覚
  /// クイック選択のときは見出し・export の caption・ファイル名に -omaly の
  /// 名前を正しく出す。
  ///
  /// 層の集合に色覚層がある間は「2×2 で比較」の切替を出し、ON の間は
  /// Before / After の代わりに色覚 4 型の 2×2（[ColorVisionCompareView]、#84）を
  /// 出す。強さは色覚層の強度を 4 セル共通で使い、他の層（色覚より前の段）は先に 1 回だけ
  /// 適用した土台にする（#122、[colorVisionCompareInputOf]）。原画に戻すホットキー
  /// （bypass）は 2×2 にもそのまま効く（強度 0・土台なし）。
  Widget _previewCard(double maxPaneSide) {
    return Consumer2<VisionFilterState, ImageSourceState>(
      builder: (context, visionState, imageSourceState, _) {
        final theme = Theme.of(context);
        final l10n = AppLocalizations.of(context)!;
        // 「2×2 で比較」は、層の集合に色覚層があるときだけ出す（#122）。他の層を重ねていても
        // 出せて、そのとき 4 枚は「色覚以外の層を先に適用した画像」の上に色覚 4 型を 1 つずつ
        // 適用したもの。色覚層が無ければ切替も 2×2 も出ない（compareInput が null）。
        final compareInput = colorVisionCompareInputOf(visionState);
        final canCompare = compareInput != null;
        final comparing = canCompare && _compareColorVision;
        final strength = previewStrength(visionState);
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
                        // 2×2 の間は Before / After ではないので、見出しも実態に合わせる。
                        comparing
                            ? l10n.compareSectionTitle
                            : l10n.previewSectionTitle,
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
                    if (canCompare)
                      FilterChip(
                        label: Text(l10n.compareToggleLabel),
                        tooltip: l10n.compareToggleTooltip,
                        selected: _compareColorVision,
                        onSelected: (value) =>
                            setState(() => _compareColorVision = value),
                      ),
                  ],
                ),
                // 重ねている層のチップ帯（#120）。2 層以上のときだけ出る（1 層以下は高さ 0）。
                if (visionState.layers.length > 1) ...[
                  const SizedBox(height: 12),
                  const LayerChipStrip(),
                ],
                const SizedBox(height: 12),
                ImageSourcePicker(
                  child: comparing
                      ? ColorVisionCompareView(
                          strength: compareInput.strength,
                          baseSteps: compareInput.baseSteps,
                          baseLayers: compareInput.baseLayers,
                          imageSource: imageSourceState.current,
                        )
                      : BeforeAfterView(
                          filter: visionState.build(),
                          filterId: visionState.selectedId,
                          strength: strength,
                          variantId: visionState.focusedVariantId,
                          // 層が複数のときだけ合成経路（#119）。1 層以下は従来の
                          // 単一フィルタ経路のまま。
                          steps: visionState.layers.length > 1
                              ? previewPipelineSteps(visionState)
                              : null,
                          // 複数層の見出し・HUD は名前の要約にする（#120）。
                          layerNames: visionState.layers.length > 1
                              ? [
                                  for (final layer in visionState.layers)
                                    visionLayerDisplayName(l10n, layer),
                                ]
                              : null,
                          layerIds: visionState.layers.length > 1
                              ? [
                                  for (final layer in visionState.layers)
                                    layer.id,
                                ]
                              : null,
                          // 書き出しは全層の値から作る（#121）。
                          exportLayers: visionState.layers.length > 1
                              ? exportLayersOf(visionState)
                              : null,
                          imageSource: imageSourceState.current,
                          maxPaneSide: maxPaneSide,
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

/// ↑↓ の行移動（[CycleFilterIntent]）。[isFocusOnInteractiveControl] が true の間は
/// 無効（[InteractiveFocusAwareCallbackAction] と同じ）だが、フォーカスが一覧の行
/// （[FilterBrowserController.isRowFocused]）にあるときは例外として有効にする。
/// もう 1 つの例外が検索欄の ↓（#141）: 検索欄にフォーカスがあり、IME 変換中でなく、
/// フォーカスできる行があるときだけ有効にして先頭の行へ送る（[isSearchDown]）。
class _RowAwareCycleAction extends CallbackAction<CycleFilterIntent> {
  _RowAwareCycleAction({
    required this.isRowFocused,
    required this.isSearchDown,
    required super.onInvoke,
  });

  final bool Function() isRowFocused;

  /// 検索欄の ↓ を先頭行への移動として受けてよいか（#141）。
  final bool Function() isSearchDown;

  @override
  bool isEnabled(CycleFilterIntent intent) =>
      isRowFocused() ||
      (intent.forward && isSearchDown()) ||
      !isFocusOnInteractiveControl();
}

/// 「選ぶ」カード（広幅は左カラム、狭幅は末尾）用のフォーカス走査。標準（読み順）と同じだが、**一覧の行にフォーカスが
/// ある間の ←→ は、常に画面のショートカット受け口へ出る**（#84）。
///
/// 標準の方向フォーカス移動のままだと、行から → で出た先が「隣のカラムの、たまたま縦位置が
/// 重なるコントロール」になり、ウィンドウの高さや中央カラムの内容（色覚を選ぶと出る
/// 「2×2 で比較」の切替で見出しが少し高くなる、など）で変わる。そうなると、行を Enter で
/// 選んだあとの → → ←→ で強度に届くかどうかが偶然で決まる。ここで出先を固定すれば、
/// 1 回目の ←→ は強度を動かさず（行から出るだけ）、次の ←→ から必ず強度が動く。
/// 他カラムのコントロールへは Tab で入る。検索欄・カテゴリのチップなど行以外は標準のまま。
class _ListExitToShortcutsPolicy extends ReadingOrderTraversalPolicy {
  _ListExitToShortcutsPolicy(this._shortcutFocus);

  final FocusNode _shortcutFocus;

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final horizontal = direction == TraversalDirection.left ||
        direction == TraversalDirection.right;
    final onRow =
        currentNode.context?.findAncestorWidgetOfExactType<FilterListTile>() !=
            null;
    if (horizontal && onRow) {
      _shortcutFocus.requestFocus();
      return true;
    }
    return super.inDirection(currentNode, direction);
  }
}
