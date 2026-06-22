import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';

import '../models/disability_type.dart';
import 'filter_service.dart';

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
///    と [FilterService] に橋渡しする。
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
/// **メインウィンドウを閉じてもトレイに最小化されるだけで、終了しない。**
/// 明示的な終了はトレイの "終了" 項目 (または OS) のみ。
/// これは `main.dart` で `windowManager.setPreventClose(true)` +
/// `onWindowClose` → `windowManager.hide()` として実装する。純粋関数
/// [resolveCloseAction] がこの判断を表現・テストする。
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

  /// 特定の色覚フィルタを即適用する。
  applyColorVisionFilter,

  /// フィルタ解除。
  clearFilter,

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
    this.colorVisionType,
    this.checked = false,
  });

  /// 区切り線を作る便宜コンストラクタ。
  const TrayMenuEntry.separator()
      : kind = TrayMenuKind.separator,
        key = null,
        label = null,
        colorVisionType = null,
        checked = false;

  final TrayMenuKind kind;

  /// クリック識別用の安定キー。区切り線では null。
  final String? key;

  /// 表示ラベル。区切り線では null。
  final String? label;

  /// [kind] が [TrayMenuKind.applyColorVisionFilter] のとき適用する色覚タイプ。
  /// それ以外は null。
  final ColorVisionType? colorVisionType;

  /// チェック表示するか (アクティブなフィルタ / ルーペ表示状態の目印)。
  final bool checked;

  @override
  bool operator ==(Object other) =>
      other is TrayMenuEntry &&
      other.kind == kind &&
      other.key == key &&
      other.label == label &&
      other.colorVisionType == colorVisionType &&
      other.checked == checked;

  @override
  int get hashCode => Object.hash(kind, key, label, colorVisionType, checked);

  @override
  String toString() => 'TrayMenuEntry(kind: $kind, key: $key, label: $label, '
      'colorVisionType: $colorVisionType, checked: $checked)';
}

/// トレイから直接ワンクリック切替できる色覚フィルタの一覧。
///
/// 全フィルタ catalogue は設定 UI (#16) にある。トレイはメニューを短く保つため
/// よく使う色覚シミュレーションのみを出す。
/// [ColorVisionType.none] は「フィルタ解除」項目が担うため意図的に除外する。
List<ColorVisionType> quickColorVisionFilters() => const <ColorVisionType>[
      ColorVisionType.protanopia,
      ColorVisionType.deuteranopia,
      ColorVisionType.tritanopia,
      ColorVisionType.achromatopsia,
    ];

/// トレイメニューの表示文言を 1 つにまとめた値オブジェクト (#18)。
///
/// 純粋データ層 ([buildTrayMenuSpec]) は **文言を自前で持たない**。i18n の解決は
/// UI/副作用層 ([TrayService]) の責務で、起動時ロケールの `AppLocalizations` から
/// 文字列を取り出してここに詰めて渡す（context を持てないトレイ層の作法）。
/// color-vision フィルタのラベルは id ごとに [filterLabels] で引く。
@immutable
class TrayMenuLabels {
  const TrayMenuLabels({
    required this.showLoupe,
    required this.hideLoupe,
    required this.clearFilter,
    required this.openSettings,
    required this.quit,
    required this.filterLabels,
  });

  /// ルーペ窓を表示する項目のラベル（非表示状態のトグルに使う）。
  final String showLoupe;

  /// ルーペ窓を隠す項目のラベル（表示状態のトグルに使う）。
  final String hideLoupe;

  /// フィルタ解除項目のラベル。
  final String clearFilter;

  /// 設定を開く項目のラベル。
  final String openSettings;

  /// 終了項目のラベル。
  final String quit;

  /// color-vision id → 表示ラベル。[quickColorVisionFilters] の各型をカバーする。
  final Map<ColorVisionType, String> filterLabels;

  /// ルーペ窓トグルのラベルを表示状態に応じて返す。
  String toggleLabel({required bool loupeVisible}) =>
      loupeVisible ? hideLoupe : showLoupe;

  /// 指定 color-vision 型のラベル（未登録なら id をフォールバック表示）。
  String filterLabel(ColorVisionType type) => filterLabels[type] ?? type.id;
}

/// 色覚フィルタ項目の安定キー (フィルタ id から導出)。
String colorVisionEntryKey(ColorVisionType type) => 'filter_${type.id}';

// フィルタ以外の項目の安定キー。
const String kToggleLoupeKey = 'toggle_loupe';
const String kClearFilterKey = 'clear_filter';
const String kOpenSettingsKey = 'open_settings';
const String kQuitKey = 'quit';

/// トレイメニュー全体を純粋データとして組み立てる。
///
/// [loupeVisible] がトグルのラベルを、[activeFilter] がアクティブな
/// クイックフィルタへのチェック表示を制御する。表示文言は呼び出し側が i18n
/// 解決して [labels] で渡す（純粋層は文言を持たない: #18）。
List<TrayMenuEntry> buildTrayMenuSpec({
  required bool loupeVisible,
  required TrayMenuLabels labels,
  ColorVisionType activeFilter = ColorVisionType.none,
}) {
  return <TrayMenuEntry>[
    TrayMenuEntry(
      kind: TrayMenuKind.toggleLoupe,
      key: kToggleLoupeKey,
      label: labels.toggleLabel(loupeVisible: loupeVisible),
      checked: loupeVisible,
    ),
    const TrayMenuEntry.separator(),
    for (final f in quickColorVisionFilters())
      TrayMenuEntry(
        kind: TrayMenuKind.applyColorVisionFilter,
        key: colorVisionEntryKey(f),
        label: labels.filterLabel(f),
        colorVisionType: f,
        checked: f == activeFilter,
      ),
    TrayMenuEntry(
      kind: TrayMenuKind.clearFilter,
      key: kClearFilterKey,
      label: labels.clearFilter,
      checked: activeFilter == ColorVisionType.none,
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
    required this.filterService,
    required this.iconPath,
    required this.labels,
    required this.tooltip,
    required this.onShowLoupe,
    required this.onHideLoupe,
    required this.onOpenSettings,
    required this.onQuit,
    bool loupeVisible = true,
  }) : _loupeVisible = loupeVisible;

  /// アクティブな色覚フィルタの選択状態 (#14)。
  final FilterService filterService;

  /// トレイアイコンのアセットパス (PNG)。`assets/tray/` 参照。
  final String iconPath;

  /// トレイメニューの i18n 解決済み文言 (#18)。起動時ロケールで解決して渡す。
  final TrayMenuLabels labels;

  /// トレイアイコンのツールチップ（= アプリ名、i18n 解決済み）。
  final String tooltip;

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
  Future<void> init() async {
    if (!isTraySupportedPlatform) {
      return;
    }
    try {
      trayManager.addListener(this);
      await trayManager.setIcon(iconPath);
      await trayManager.setToolTip(tooltip);
      await _rebuildMenu();
      _initialised = true;
    } catch (error, stack) {
      // GNOME 拡張無し・ヘッドレス・アイコン欠落など。ログして継続する。
      _initialised = false;
      debugPrint('TrayService.init failed (tray unavailable): $error\n$stack');
    }
  }

  /// 現在の状態からネイティブメニューを再構築する。
  Future<void> refresh() async {
    if (!_initialised) return;
    await _rebuildMenu();
  }

  Future<void> _rebuildMenu() async {
    final spec = buildTrayMenuSpec(
      loupeVisible: _loupeVisible,
      labels: labels,
      activeFilter: filterService.currentFilter,
    );
    final menu = Menu(items: spec.map(_toMenuItem).toList());
    try {
      await trayManager.setContextMenu(menu);
    } catch (error) {
      debugPrint('TrayService.setContextMenu failed: $error');
    }
  }

  MenuItem _toMenuItem(TrayMenuEntry entry) {
    if (entry.kind == TrayMenuKind.separator) {
      return MenuItem.separator();
    }
    if (entry.checked) {
      return MenuItem.checkbox(
        key: entry.key,
        label: entry.label ?? '',
        checked: true,
        onClick: (_) => _handleClick(entry),
      );
    }
    return MenuItem(
      key: entry.key,
      label: entry.label,
      onClick: (_) => _handleClick(entry),
    );
  }

  Future<void> _handleClick(TrayMenuEntry entry) async {
    switch (entry.kind) {
      case TrayMenuKind.toggleLoupe:
        await _toggleLoupe();
        break;
      case TrayMenuKind.applyColorVisionFilter:
        final type = entry.colorVisionType;
        if (type != null) {
          filterService.applyFilter(type);
          await refresh();
        }
        break;
      case TrayMenuKind.clearFilter:
        filterService.deactivate();
        await refresh();
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

  /// トレイアイコン・リスナを後始末する。
  Future<void> dispose() async {
    if (!isTraySupportedPlatform) return;
    try {
      trayManager.removeListener(this);
      await trayManager.destroy();
    } catch (_) {
      // 後始末失敗は無視する。
    }
  }
}
