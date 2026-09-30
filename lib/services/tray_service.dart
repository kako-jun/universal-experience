import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';

import '../models/vision_filter_catalog.dart';
import 'filter_list_selection.dart';
import 'loupe_window_controller.dart';
import 'tray_menu_labels.dart';
import 'vision_filter_state.dart';

export 'tray_menu_labels.dart';

/// タスクトレイ常駐 (#15)。
///
/// このファイルは 2 層に分かれている。
///
///  * **純粋ロジック層** — `tray_manager` に依存しないデータ表現。
///    トレイメニューに「何を出すか」を [TrayMenuKind] / [TrayMenuEntry] /
///    [quickColorVisionFilters] / [buildTrayMenuSpec] / [trayToggleLabel] /
///    [resolveCloseAction] で表す。ウィンドウシステム無しで単体テストできる
///    (`test/tray_service_test.dart`)。
///  * **[TrayService]** — `tray_manager` を叩く副作用層。上記スペックを実際の
///    [Menu] / [MenuItem] に変換し、クリックを「ウィンドウ表示/非表示コールバック」
///    と [VisionFilterState] に橋渡しする。
///
/// ## ウィンドウ表示 (ルーペ窓) の扱い
///
/// このアプリのメインウィンドウ自体がルーペ窓 (#14)。`LoupeWindowController`
/// は枠/モード/透過の責務を持つが表示/非表示 (show/hide) は持たないため、
/// トレイの「ルーペ窓を表示/隠す」は `windowManager.show()` / `hide()` を呼ぶ
/// コールバック ([onShowLoupe] / [onHideLoupe]) を main.dart から注入して実現する。
///
/// ## ウィンドウクローズ・ポリシー (ここで決定)
///
/// Universal Experience は典型的な「トレイ常駐ユーティリティ」として振る舞う。
/// **トレイが使える環境では、メインウィンドウを閉じてもトレイに最小化される
/// だけで、終了しない。** 明示的な終了はトレイの "終了" 項目 (または OS) のみ。
///
/// `windowManager.setPreventClose(true)` は（トレイの有無に関わらず）常に掛ける
/// (`main.dart` `_setUpTray`)。`onWindowClose` の中で [resolveCloseAction] の
/// 結果を見て分岐する:
///  * トレイが使える環境 (`hideToTray`) — `windowManager.hide()` するだけで
///    終了しない。
///  * トレイが立ち上がらなかった環境 (`exitApp`) — クローズ = 終了。ただし
///    intensity のデバウンス永続化 (#57) を取りこぼさないよう、実際に
///    ウィンドウを破棄する前に `VisionFilterStore.flush()` → `setPreventClose(false)`
///    → `windowManager.destroy()` の順で行う。
///
/// トレイのクリック "終了" (`onQuit`) も同じ理由で先頭に `flush()` を置く。
/// さらに、macOS の Cmd+Q やログアウトなど window_manager のクローズイベントを
/// 経由しない終了経路もあるため、`main()` で `AppLifecycleListener
/// .onExitRequested` にも同じ `flush()` を仕込んでいる（トレイ・ウィンドウ
/// クローズ経由の flush はそのまま残り、こちらは二重の安全網）。
///
/// ## プラットフォーム差 (トレイ事情は環境差が大きい)
///
///  * **Windows / macOS**: トレイ (通知領域 / メニューバー) は常に利用可能。
///  * **Linux**: 単一のトレイ標準が無い。KDE/XFCE は StatusNotifierItem を
///    標準提供するが、**GNOME は AppIndicator/KStatusNotifierItem シェル拡張が
///    必要**で、無いとアイコンが黙って出ない。検出が困難なため `tray_manager`
///    呼び出しは全て try/catch で包み、失敗してもアプリは落ちず
///    ウィンドウのみで使える。
///  * **Android/iOS**: トレイ概念が無いためトレイ設定は完全にスキップする
///    ([TrayService.isTraySupportedPlatform] が false)。Android の常駐は
///    Foreground Service (#4) でありここではスコープ外。

/// トレイメニュー項目の種別。
enum TrayMenuKind {
  /// ルーペ窓の表示/非表示トグル。
  toggleLoupe,

  /// 起動モード（設定窓/ルーペ窓）の切替 (#63)。
  toggleAppMode,

  /// 最前面固定の切替 (#63)。
  toggleAlwaysOnTop,

  /// クリックスルーの切替 (#63)。
  toggleClickThrough,

  /// 特定の色覚フィルタを足し引きする（チェック式。色覚は排他で、別の型を選ぶと置き換わる、#121）。
  applyColorVisionFilter,

  /// フィルタ解除（重ねている全層を外す）。
  clearFilter,

  /// 「高度なフィルタ」サブメニュー（カテゴリ別、#65）。[TrayMenuEntry.children]
  /// にカテゴリのサブメニュー（同じく [submenu]）、その中に [applyListEntry]
  /// 項目を持つ。自身はクリックできない。
  submenu,

  /// 統合フィルタ一覧（#72）の 1 行を足し引きする（チェック式、#65/#121）。
  applyListEntry,

  /// メインウィンドウを表示して設定を開く。
  openSettings,

  /// 区切り線 (操作不可)。
  separator,

  /// アプリ終了。
  quit,
}

/// 1 つのトレイメニュー項目を表す純粋・不変なデータ。
///
/// `tray_manager` の型に依存しないので単体テストで検証できる。
/// [TrayService] が各項目を実際の [MenuItem] に変換する。
@immutable
class TrayMenuEntry {
  const TrayMenuEntry({
    required this.kind,
    this.key,
    this.label,
    this.colorVisionKey,
    this.listEntryKey,
    this.children = const [],
    this.checked = false,
    this.enabled = true,
  });

  /// 区切り線を作る便宜コンストラクタ。
  const TrayMenuEntry.separator()
    : kind = TrayMenuKind.separator,
      key = null,
      label = null,
      colorVisionKey = null,
      listEntryKey = null,
      children = const [],
      checked = false,
      enabled = true;

  final TrayMenuKind kind;

  /// クリック識別用の安定キー。区切り線では null。
  final String? key;

  /// 表示ラベル。区切り線では null。
  final String? label;

  /// [kind] が [TrayMenuKind.applyColorVisionFilter] のとき適用する色覚のカタログ id。
  /// それ以外は null。
  final String? colorVisionKey;

  /// [kind] が [TrayMenuKind.applyListEntry] のとき選ぶ統合一覧の行
  /// （[FilterListEntry.key]）。それ以外は null。
  final String? listEntryKey;

  /// [kind] が [TrayMenuKind.submenu] のときの子項目。それ以外は空。
  final List<TrayMenuEntry> children;

  /// チェック表示するか (アクティブなフィルタ / ルーペ表示状態の目印)。
  final bool checked;

  /// 選べるか。`false` は灰色（操作不可）で出す。重ねられる上限（5 層）に達していて、
  /// 新しく足せない行が該当する（#121）。
  final bool enabled;

  @override
  bool operator ==(Object other) =>
      other is TrayMenuEntry &&
      other.kind == kind &&
      other.key == key &&
      other.label == label &&
      other.colorVisionKey == colorVisionKey &&
      other.listEntryKey == listEntryKey &&
      listEquals(other.children, children) &&
      other.checked == checked &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(
    kind,
    key,
    label,
    colorVisionKey,
    listEntryKey,
    Object.hashAll(children),
    checked,
    enabled,
  );

  @override
  String toString() =>
      'TrayMenuEntry(kind: $kind, key: $key, label: $label, '
      'colorVisionKey: $colorVisionKey, listEntryKey: $listEntryKey, '
      'children: $children, checked: $checked, enabled: $enabled)';
}

/// 色覚フィルタ項目の安定キー (カタログ id から導出)。
String colorVisionEntryKey(String catalogId) => 'filter_$catalogId';

/// 「高度なフィルタ」サブメニュー（#65）のカテゴリ項目・一覧項目の安定キー。
String categorySubmenuKey(VisionFilterCategory category) =>
    'category_${category.name}';
String listEntryMenuKey(FilterListEntry entry) => 'list_${entry.key}';

/// 色覚のクイック項目 [catalogId] に対応する統合一覧の行のキー（[FilterListEntry.key]）。
String colorVisionListEntryKey(String catalogId) => 'cv:$catalogId';

/// 「高度なフィルタ」サブメニュー（#65）を純粋データとして組み立てる。
///
/// カテゴリごとのサブメニューに、統合フィルタ一覧（[kFilterListEntries]）の行を
/// 並べる。チェック式（#121）: [checkedListEntryKeys]（[FilterListEntry.key] の集合。
/// 重ねている層に対応する行）の行にチェックを付け、[disabledListEntryKeys]（上限で
/// 新しく足せない行）の行は灰色にする。
TrayMenuEntry buildAdvancedFiltersSubmenu({
  required TrayMenuLabels labels,
  Set<String> checkedListEntryKeys = const {},
  Set<String> disabledListEntryKeys = const {},
}) {
  return TrayMenuEntry(
    kind: TrayMenuKind.submenu,
    key: kAdvancedFiltersKey,
    label: labels.advancedFilters,
    children: [
      for (final category in VisionFilterCategory.values)
        TrayMenuEntry(
          kind: TrayMenuKind.submenu,
          key: categorySubmenuKey(category),
          label: labels.categoryLabel(category),
          children: [
            for (final e in kFilterListEntries)
              if (e.category == category)
                TrayMenuEntry(
                  kind: TrayMenuKind.applyListEntry,
                  key: listEntryMenuKey(e),
                  label: labels.listEntryLabel(
                    catalogId: e.catalogId,
                    variantId: e.variantId,
                  ),
                  listEntryKey: e.key,
                  checked: checkedListEntryKeys.contains(e.key),
                  enabled: !disabledListEntryKeys.contains(e.key),
                ),
          ],
        ),
    ],
  );
}

// フィルタ以外の項目の安定キー。
const String kToggleLoupeKey = 'toggle_loupe';
const String kToggleAppModeKey = 'toggle_app_mode';
const String kToggleAlwaysOnTopKey = 'toggle_always_on_top';
const String kToggleClickThroughKey = 'toggle_click_through';
const String kClearFilterKey = 'clear_filter';
const String kAdvancedFiltersKey = 'advanced_filters';
const String kOpenSettingsKey = 'open_settings';
const String kQuitKey = 'quit';

/// トレイメニュー全体を純粋データとして組み立てる。
///
/// [loupeVisible] がトグルのラベルを制御する。[appMode]/[alwaysOnTop]/
/// [clickThrough] は起動モード・最前面・クリックスルーのチェック表示を制御する
/// （#63、UI とトレイの両方から切り替えられる受け入れ条件）。
///
/// フィルタの項目は重ねている層の集合から決める（#121）。[checkedListEntryKeys] は
/// 層に対応する一覧の行（[FilterListEntry.key]）で、色覚のクイック 4 項目と「高度な
/// フィルタ」サブメニュー（#65）の両方のチェックに使う。[disabledListEntryKeys] は
/// 上限で新しく足せない行（色覚の置き換えは含めない）。[hasLayers] が false のとき
/// だけ「フィルタを解除」にチェックを付ける。表示文言は呼び出し側が i18n 解決して
/// [labels] で渡す（純粋層は文言を持たない: #18）。
List<TrayMenuEntry> buildTrayMenuSpec({
  required bool loupeVisible,
  required TrayMenuLabels labels,
  required AppMode appMode,
  required bool alwaysOnTop,
  required bool clickThrough,
  Set<String> checkedListEntryKeys = const {},
  Set<String> disabledListEntryKeys = const {},
  bool hasLayers = false,
}) {
  return <TrayMenuEntry>[
    TrayMenuEntry(
      kind: TrayMenuKind.toggleLoupe,
      key: kToggleLoupeKey,
      label: labels.toggleLabel(loupeVisible: loupeVisible),
      checked: loupeVisible,
    ),
    const TrayMenuEntry.separator(),
    TrayMenuEntry(
      kind: TrayMenuKind.toggleAppMode,
      key: kToggleAppModeKey,
      label: labels.appModeLoupeLabel,
      checked: appMode == AppMode.loupe,
    ),
    TrayMenuEntry(
      kind: TrayMenuKind.toggleAlwaysOnTop,
      key: kToggleAlwaysOnTopKey,
      label: labels.alwaysOnTopLabel,
      checked: alwaysOnTop,
    ),
    TrayMenuEntry(
      kind: TrayMenuKind.toggleClickThrough,
      key: kToggleClickThroughKey,
      label: labels.clickThroughLabel,
      checked: clickThrough,
    ),
    const TrayMenuEntry.separator(),
    for (final f in quickColorVisionFilters())
      TrayMenuEntry(
        kind: TrayMenuKind.applyColorVisionFilter,
        key: colorVisionEntryKey(f),
        label: labels.filterLabel(f),
        colorVisionKey: f,
        listEntryKey: colorVisionListEntryKey(f),
        checked: checkedListEntryKeys.contains(colorVisionListEntryKey(f)),
        enabled: !disabledListEntryKeys.contains(colorVisionListEntryKey(f)),
      ),
    buildAdvancedFiltersSubmenu(
      labels: labels,
      checkedListEntryKeys: checkedListEntryKeys,
      disabledListEntryKeys: disabledListEntryKeys,
    ),
    TrayMenuEntry(
      kind: TrayMenuKind.clearFilter,
      key: kClearFilterKey,
      label: labels.clearFilter,
      checked: !hasLayers,
    ),
    const TrayMenuEntry.separator(),
    TrayMenuEntry(
      kind: TrayMenuKind.openSettings,
      key: kOpenSettingsKey,
      label: labels.openSettings,
    ),
    const TrayMenuEntry.separator(),
    TrayMenuEntry(
      kind: TrayMenuKind.quit,
      key: kQuitKey,
      label: labels.quit,
    ),
  ];
}

/// OS からウィンドウクローズ要求が来たときの動作。
enum CloseAction {
  /// ウィンドウを隠すがプロセス (とトレイ) は生かす。
  hideToTray,

  /// 実際にアプリを終了する。
  exitApp,
}

/// クローズ・ポリシーの純粋判定関数。
///
/// トレイから復帰できる場合だけクローズでトレイに隠す。トレイが無い環境で
/// 隠すと復帰不能になるため、その場合は終了にフォールバックする。
CloseAction resolveCloseAction({required bool trayAvailable}) =>
    trayAvailable ? CloseAction.hideToTray : CloseAction.exitApp;

/// `tray_manager` を叩くトレイラッパ (副作用層)。
class TrayService with TrayListener {
  TrayService({
    required this.visionFilterState,
    required this.loupeWindow,
    required this.iconPath,
    required TrayMenuLabels labels,
    required String tooltip,
    required this.onShowLoupe,
    required this.onHideLoupe,
    required this.onOpenSettings,
    required this.onQuit,
    bool loupeVisible = true,
  })  : _labels = labels,
        _tooltip = tooltip,
        _loupeVisible = loupeVisible;

  /// プレビューの選択の唯一の正本（#60）。トレイの項目は、メイン画面の一覧と同じ入口
  /// （`toggleFilterListEntry` / `clear`、#121）を経由してこれを更新する。チェックと灰色はこれの層の集合から決める。
  final VisionFilterState visionFilterState;

  /// ルーペ窓のモード/最前面/クリックスルー (#63)。トレイからもこれらを
  /// 切り替えられるようにする（UI とトレイの両方から操作できる、という受け入れ
  /// 条件）。listener を付けてウィンドウ内 UI（`WindowModePanel`）での変更も
  /// トレイのチェックマークへ反映する（[visionFilterState] と
  /// 同じ理由、#60 に倣う）。
  final LoupeWindowController loupeWindow;

  /// トレイアイコンのアセットパス (PNG)。`assets/tray/` 参照。
  final String iconPath;

  /// トレイメニューの i18n 解決済み文言 (#18)。起動時ロケールで解決して渡し、
  /// 言語が変わったら [updateLocalization] で差し替える (#82)。
  TrayMenuLabels get labels => _labels;
  TrayMenuLabels _labels;

  /// トレイアイコンのツールチップ（= アプリ名、i18n 解決済み）。
  /// [labels] と同じく [updateLocalization] で差し替わる (#82)。
  String get tooltip => _tooltip;
  String _tooltip;

  /// ルーペ窓を表示する (main.dart が windowManager.show を呼ぶ)。
  final Future<void> Function() onShowLoupe;

  /// ルーペ窓を隠す (main.dart が windowManager.hide を呼ぶ)。
  final Future<void> Function() onHideLoupe;

  /// "設定を開く" が選ばれたとき (main.dart がウィンドウを表示する)。
  final Future<void> Function() onOpenSettings;

  /// "終了" が選ばれたとき。
  final Future<void> Function() onQuit;

  bool _loupeVisible;
  bool _initialised = false;

  /// 現在のプラットフォームにトレイ概念があるか。
  static bool get isTraySupportedPlatform {
    try {
      return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    } catch (_) {
      return false;
    }
  }

  /// トレイ初期化に成功したか。main.dart がクローズ・ポリシー
  /// ([resolveCloseAction]) を選ぶのに使う。
  bool get isAvailable => _initialised;

  /// トレイアイコン・ツールチップ・コンテキストメニューを初期化する。
  ///
  /// どのプラットフォームでも安全に呼べる: トレイ非対応では no-op、失敗
  /// (GNOME で AppIndicator 拡張無し / ヘッドレス CI / アイコン欠落など) は
  /// 握り潰してアプリはウィンドウのみで動き続ける。
  ///
  /// [visionFilterState]/[loupeWindow] に listener を付け、
  /// ウィンドウ内 UI（[FilterBrowser]・advanced カタログ・体験プリセット・
  /// `WindowModePanel`）での選択・切替もトレイのチェックマークに反映される
  /// ようにする（#60/#63。トレイのチェックマークは [_rebuildMenu] が
  /// `visionFilterState` の層の集合や `loupeWindow.appMode` 等から決める）。
  /// トレイ自体のネイティブ初期化が失敗しても listener は付けたままにする
  /// （`refresh()` 自身が `_initialised` を見て no-op になるため無害で、
  /// コードパスを単純に保てる）。listener は [dispose] で外す。
  Future<void> init() async {
    if (!isTraySupportedPlatform) {
      return;
    }
    visionFilterState.addListener(_onSelectionChanged);
    loupeWindow.addListener(_onSelectionChanged);
    try {
      trayManager.addListener(this);
      await trayManager.setIcon(iconPath);
      await trayManager.setToolTip(_tooltip);
      await _rebuildMenu();
      _initialised = true;
    } catch (error, stack) {
      // GNOME 拡張無し・ヘッドレス・アイコン欠落など。ログして継続する。
      _initialised = false;
      debugPrint('TrayService.init failed (tray unavailable): $error\n$stack');
    }
  }

  /// [_onSelectionChanged] が呼ばれた回数。production では未使用で、
  /// `ChangeNotifier.hasListeners` が `@protected`（テストから直接見えない）
  /// ため、listener が実際に発火することを widget を介さず確認するための
  /// テスト専用フック（#60）。
  @visibleForTesting
  int selectionChangedCallCount = 0;

  /// [visionFilterState]/[loupeWindow] のどちらかが変化したときに呼ばれる
  /// （#60）。トレイのメニュー自体は非同期（`trayManager.setContextMenu`）
  /// だが listener コールバックは同期なので `unawaited` で発火だけさせる。
  void _onSelectionChanged() {
    selectionChangedCallCount++;
    unawaited(refresh());
  }

  /// 言語が変わったとき、トレイのメニュー文言とツールチップを差し替える (#82)。
  ///
  /// トレイは `BuildContext` を持てず `MaterialApp.locale` の変更を受け取れない
  /// ため、呼び出し側（`TrayLocaleSync`）が解決済みの [labels]/[tooltip] を渡す。
  /// トレイ未初期化・非対応環境では文言を保持するだけで、ネイティブは触らない
  /// （[init] が保持した文言で初期化する）。
  Future<void> updateLocalization({
    required TrayMenuLabels labels,
    required String tooltip,
  }) async {
    _labels = labels;
    _tooltip = tooltip;
    if (!_initialised) return;
    try {
      await trayManager.setToolTip(tooltip);
    } catch (error) {
      debugPrint('TrayService.setToolTip failed: $error');
    }
    await _rebuildMenu();
  }

  /// 現在の状態からネイティブメニューを再構築する。
  Future<void> refresh() async {
    if (!_initialised) return;
    await _rebuildMenu();
  }

  Future<void> _rebuildMenu() async {
    // チェックと灰色は、すべて VisionFilterState の層の集合から決める（ウィンドウ内 UI の
    // 選択がそのままトレイに出る、#65/#121）。一覧の行との対応はメイン画面の一覧と同じ
    // 判定（[layerForFilterListEntry]）なので、色覚 base 型を高度な
    // フィルタ側から足した場合も、トップレベルの同名項目と一覧の行の両方に点灯する。
    // 体験プリセットは、その層（例: 近視）の行に点灯する。
    // 灰色は上限（5 層）で新しく足せない行。色覚は置き換えになるので対象外
    // （[filterListEntryBlockReason]）。
    final checked = <String>{};
    final disabled = <String>{};
    for (final e in kFilterListEntries) {
      if (layerForFilterListEntry(visionFilterState, e) != null) {
        checked.add(e.key);
      } else if (filterListEntryBlockReason(visionFilterState, e) != null) {
        disabled.add(e.key);
      }
    }
    final spec = buildTrayMenuSpec(
      loupeVisible: _loupeVisible,
      labels: _labels,
      appMode: loupeWindow.appMode,
      alwaysOnTop: loupeWindow.alwaysOnTop,
      clickThrough: loupeWindow.clickThrough,
      checkedListEntryKeys: checked,
      disabledListEntryKeys: disabled,
      hasLayers: visionFilterState.layers.isNotEmpty,
    );
    // 変化が無いなら OS へ再送しない。スライダーのドラッグ中などに
    // visionFilterState が連続通知されても、ネイティブメニューを作り直し続けない。
    final last = _lastSpec;
    if (last != null && listEquals(last, spec)) return;
    // 送信の完了を待たずに「最後に送った構造」を更新する。完了後に更新すると、
    // 送信中に A→B→A と変わったとき、最後の A が（まだ記録が古い A と等しいため）
    // 送られず、ネイティブが B のまま残る。チャネルは送信順に処理される。
    _lastSpec = spec;
    final menu = Menu(items: spec.map(_toMenuItem).toList());
    try {
      await trayManager.setContextMenu(menu);
    } catch (error) {
      // 失敗した送信が最新なら、次の再構築で必ず再送させる（より新しい送信が
      // すでに走っているなら、その記録を消さない）。
      if (identical(_lastSpec, spec)) _lastSpec = null;
      debugPrint('TrayService.setContextMenu failed: $error');
    }
  }

  /// 最後にネイティブへ送ったメニュー構造（[_rebuildMenu] の重複送信の抑止用）。
  List<TrayMenuEntry>? _lastSpec;

  MenuItem _toMenuItem(TrayMenuEntry entry) {
    if (entry.kind == TrayMenuKind.separator) {
      return MenuItem.separator();
    }
    if (entry.kind == TrayMenuKind.submenu) {
      return MenuItem.submenu(
        key: entry.key,
        label: entry.label ?? '',
        submenu: Menu(items: entry.children.map(_toMenuItem).toList()),
      );
    }
    if (entry.checked) {
      return MenuItem.checkbox(
        key: entry.key,
        label: entry.label ?? '',
        checked: true,
        disabled: !entry.enabled,
        onClick: (_) => _handleClick(entry),
      );
    }
    return MenuItem(
      key: entry.key,
      label: entry.label,
      disabled: !entry.enabled,
      onClick: (_) => _handleClick(entry),
    );
  }

  Future<void> _handleClick(TrayMenuEntry entry) async {
    // ネイティブ側がクリックでチェック表示を先に反転させる環境でも、選択が
    // 変わらないクリック（選択済みの行の再クリック等）で見た目が食い違わない
    // よう、クリックの後は必ず構造を送り直す（[_rebuildMenu] の重複送信の抑止を外す）。
    _lastSpec = null;
    switch (entry.kind) {
      case TrayMenuKind.toggleLoupe:
        await _toggleLoupe();
        break;
      case TrayMenuKind.toggleAppMode:
        await loupeWindow.setAppMode(
          loupeWindow.appMode == AppMode.loupe
              ? AppMode.settings
              : AppMode.loupe,
        );
        await refresh();
        break;
      case TrayMenuKind.toggleAlwaysOnTop:
        await loupeWindow.setAlwaysOnTop(!loupeWindow.alwaysOnTop);
        await refresh();
        break;
      case TrayMenuKind.toggleClickThrough:
        // settings モード中の ON 拒否は setClickThrough 自身のガードに任せる。
        // クリックスルーはいつでも ON にしてよい（フォーカス復帰＋キー入力・
        // Esc の復帰経路が常にあるため）(#63)。
        await loupeWindow.setClickThrough(!loupeWindow.clickThrough);
        await refresh();
        break;
      case TrayMenuKind.applyColorVisionFilter:
        // メイン画面の色覚の行と同じ入口（足し引き。色覚は他の層を残したまま置き換わる、#121）。
        final colorEntry = _listEntryByKey(entry.listEntryKey);
        if (colorEntry != null) {
          toggleFilterListEntry(visionFilterState, colorEntry);
          await refresh();
        }
        break;
      case TrayMenuKind.clearFilter:
        visionFilterState.clear();
        await refresh();
        break;
      case TrayMenuKind.applyListEntry:
        // ウィンドウ内の統合一覧と同じ入口（足し引き、#72/#65/#121）。フィルタの切替は
        // loupeWindow（クリックスルー等、#63）に一切触れない。
        final listEntry = _listEntryByKey(entry.listEntryKey);
        if (listEntry != null) {
          toggleFilterListEntry(visionFilterState, listEntry);
          await refresh();
        }
        break;
      case TrayMenuKind.submenu:
        break;
      case TrayMenuKind.openSettings:
        await onOpenSettings();
        _loupeVisible = true;
        await refresh();
        break;
      case TrayMenuKind.quit:
        await onQuit();
        break;
      case TrayMenuKind.separator:
        break;
    }
  }

  static FilterListEntry? _listEntryByKey(String? key) {
    if (key == null) return null;
    for (final e in kFilterListEntries) {
      if (e.key == key) return e;
    }
    return null;
  }

  /// トレイの「ルーペ窓を表示/隠す」と同じロジックをホットキーからも呼べるようにする (#63)。
  Future<void> toggleLoupeVisible() => _toggleLoupe();

  Future<void> _toggleLoupe() async {
    if (_loupeVisible) {
      await onHideLoupe();
      _loupeVisible = false;
    } else {
      await onShowLoupe();
      _loupeVisible = true;
    }
    await refresh();
  }

  /// main.dart がウィンドウの実状態 (クローズ→トレイ / 手動表示) に合わせて
  /// トレイ側の表示状態を同期するためのフック。
  Future<void> setLoupeVisible(bool visible) async {
    if (_loupeVisible == visible) return;
    _loupeVisible = visible;
    await refresh();
  }

  /// 左クリックでコンテキストメニューをポップする。
  @override
  void onTrayIconMouseDown() {
    trayManager.popUpContextMenu();
  }

  /// 右クリックでもコンテキストメニューをポップする。
  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  /// トレイアイコン・リスナを後始末する。[init] で付けた
  /// [visionFilterState]/[loupeWindow] の listener も外す
  /// （#60/#63）。
  Future<void> dispose() async {
    visionFilterState.removeListener(_onSelectionChanged);
    loupeWindow.removeListener(_onSelectionChanged);
    // 破棄後の再 init で、同じ構造でも必ず送り直させる。
    _lastSpec = null;
    if (!isTraySupportedPlatform) return;
    try {
      trayManager.removeListener(this);
      await trayManager.destroy();
    } catch (_) {
      // 後始末失敗は無視する。
    }
  }
}
