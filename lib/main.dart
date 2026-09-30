import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io' show Platform;
// AppLifecycleListener.onExitRequested の戻り値型（AppExitResponse）は dart:ui
// 由来で、package:flutter/material.dart からは再エクスポートされない。
import 'dart:ui' show AppExitResponse;

import 'l10n/app_localizations.dart';
import 'l10n/l10n_extensions.dart';
import 'l10n/locale_resolution.dart';
import 'models/disability_type.dart';
import 'models/sample_catalog.dart';
import 'services/color_vision_selection.dart';
import 'services/experience_source.dart' show isValidExperiencePreset;
import 'services/filter_service.dart';
import 'services/image_source_state.dart';
import 'services/vision_filter_state.dart';
import 'services/hotkey_actions.dart';
import 'services/hotkey_service.dart';
import 'services/loupe_window_controller.dart';
import 'services/tray_locale_sync.dart';
import 'services/tray_service.dart';
import 'services/native_bridge_service.dart';
import 'services/settings_service.dart';
import 'services/vision_filter_store.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme/app_theme.dart';
import 'ui/widgets/loupe_hud.dart';

/// ルーペ窓の挙動 (#14) を集約したコントローラ。
/// 最小サイズ・状態遷移(normal/maximized/fullscreen)・枠ポリシー・
/// 透過/最前面/クリックスルーの責務を持つ (詳細は docs/ARCHITECTURE.md)。
final LoupeWindowController loupeWindow = LoupeWindowController();

/// トレイとウィンドウ UI で共有する FilterService。
/// トレイのクイックフィルタとウィンドウ内のドロップダウンが同じ状態を見るよう、
/// アプリ最上位で 1 つだけ生成する (#15)。
final FilterService filterService = FilterService();

/// トレイとウィンドウ UI で共有する VisionFilterState（プレビューの選択の
/// 唯一の正本、#60）。[filterService] と同じ理由でアプリ最上位に 1 つだけ
/// 生成する — 色覚のクイック選択はトレイ・ウィンドウ内どちらから行っても
/// `lib/services/color_vision_selection.dart` の `selectColorVision` を経由して
/// 同じインスタンスを更新する必要があるため（#60）。
final VisionFilterState visionFilterState = VisionFilterState();

/// [visionFilterState]（選んだフィルタ・payload・強度）の永続化（#65）。
/// [buildRootApp] が復元して購読を張り、終了シーケンス（トレイの終了・ウィンドウ
/// クローズ・`onExitRequested`）で [VisionFilterStore.flush] する。
final VisionFilterStore visionFilterStore = VisionFilterStore();

/// ホットキー「押している間だけ原画」（#63）用の bypass holder トークン
/// （#79）。`VisionFilterState.acquireBypass`/`releaseBypass` は入力元ごとに
/// holder を持つため、ルーペ HUD（`loupe_hud.dart`）側の holder と衝突しない
/// よう、ホットキー用に 1 つだけ生成して使い回す。
final Object _hotkeyBypassSource = Object();

/// トレイとウィンドウ UI で共有する [ImageSourceState]（プレビュー原画の選択の
/// 唯一の正本、#78）。[filterService]/[visionFilterState] と同じ理由で
/// アプリ最上位に 1 つだけ生成する。初期サンプルは [buildRootApp] が
/// 起動時の選択済みフィルタ（[selectColorVision] でシードした直後の
/// `visionFilterState.selectedId`）の推奨サンプルに合わせる。
final ImageSourceState imageSourceState = ImageSourceState();

/// トレイアイコンの Flutter アセットパス。`tray_manager` の `setIcon` が
/// `data/flutter_assets/` 配下のこのパスを解決する。Windows でより精細に
/// するなら `assets/tray/tray_icon.ico` を追加して分岐すればよい。
/// 詳細は docs/ARCHITECTURE.md「タスクトレイ (#15)」参照。
const String _trayIconPath = 'assets/tray/tray_icon.png';

/// OS からの終了要求（macOS の Cmd+Q / メニューバーの「終了」/ ログアウト等）を
/// 捕捉し、[FilterService.flush] を挟んでから終了を許可する。
/// トレイ経由・ウィンドウクローズ経由の flush（[_setUpTray] /
/// `onQuit`）は window_manager のクローズイベントしか見ておらず、Cmd+Q や
/// ログアウトはそれらを経由せず直接プロセス終了に向かうため、二重の安全網として
/// 別途これが要る。`main()` 内のローカル変数にすると `main()` の関数フレームが
/// 終わった時点で参照が切れ GC されうるため、トップレベル変数として保持する。
late final AppLifecycleListener appLifecycleListener;

/// タスクトレイ常駐 (#15)。トレイ非対応環境では init() が no-op になる。
///
/// ルーペ窓 (= メインウィンドウ) の表示/非表示は windowManager 経由。
/// `LoupeWindowController` (#14) は枠/モード/透過の責務で show/hide を持たないため、
/// ここで windowManager.show()/hide() を注入する。
///
/// トレイ文言を起動時ロケールの [AppLocalizations] で解決して渡すため (#18)、
/// 構築は settings 読込後の [main] 内で行う（top-level だと locale が未確定）。
late final TrayService trayService;

/// グローバルホットキー (#63)。トレイと同じくデスクトップのみ init() する。
late final HotkeyService hotkeyService;

/// トレイの文言を画面の言語へ追従させる購読 (#82)。トレイを初期化した後に
/// [main] が開始する（アプリの寿命と同じなので dispose しない）。
late final TrayLocaleSync trayLocaleSync;

/// トレイ・ホットキーの可用性をまとめて provide する値オブジェクト (#63)。
///
/// `Provider<bool>.value` は型が汎用的すぎて他の bool provider と衝突しうる
/// ため使わず、この専用クラスにまとめて 1 つの Provider で供給する
/// （`WindowModePanel` が読む）。
@immutable
class WindowModeUiContext {
  const WindowModeUiContext({
    required this.trayAvailable,
    required this.hotkeyStatus,
  });

  final bool trayAvailable;
  final HotkeyStatus hotkeyStatus;
}

/// トレイメニュー文言を起動時ロケールで解決して [TrayService] を構築する (#18)。
///
/// トレイは BuildContext を持てないため、解決済みロケール（永続化設定 → 無ければ
/// システム）の `AppLocalizations`（`lookupAppLocalizations`）から文言を取る。
/// 起動後に言語が変わったときの差し替えは [TrayLocaleSync]（#82）。
TrayService _buildTrayService(SettingsService settings) {
  final locale = resolveSupportedLocale(settings.locale);
  final l10n = lookupAppLocalizations(locale);
  return TrayService(
    filterService: filterService,
    visionFilterState: visionFilterState,
    loupeWindow: loupeWindow,
    iconPath: _trayIconPath,
    labels: trayMenuLabelsFrom(l10n),
    tooltip: l10n.trayTooltip,
    onShowLoupe: () async {
      await windowManager.show();
      await windowManager.focus();
    },
    onHideLoupe: () async {
      await windowManager.hide();
    },
    onOpenSettings: () async {
      // 設定 (フィルタ選択 UI) はメインウィンドウ内にあるため、ウィンドウを表示する。
      await windowManager.show();
      await windowManager.focus();
    },
    onQuit: () async {
      // デバウンス中の intensity 永続化（#57）を、実タイマーの発火を待たず
      // 確定させてから終了する（待たないと直近のスライダー操作が失われうる）。
      await filterService.flush();
      await visionFilterStore.flush();
      // トレイアイコンを破棄し、prevent-close を解除してから実際に終了する。
      await trayService.dispose();
      await hotkeyService.dispose();
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        await windowManager.setPreventClose(false);
        await windowManager.destroy();
      }
    },
  );
}

/// アプリのルート Widget を組み立てる (#55)。Rust ブリッジ初期化・設定復元・
/// 共有 `filterService`/`visionFilterState` のシードまでを担い、`main()` と
/// （実プロセスで `main()` 相当の起動経路を踏みたい）
/// `integration_test/app_bootstrap_test.dart` の両方から呼ばれる唯一の
/// bootstrap 関数。
///
/// 戻り値は `({Widget app, bool bridgeReady})` レコード。呼び出し側は
/// `bridgeReady` を見て分岐する（Widget のランタイム型 `is NativeBridgeErrorApp`
/// を見て分岐する必要がない）。
///
/// - [initBridge] は既定で `initNativeBridge()`
///   （services/native_bridge_service.dart）。失敗時（native lib が壊れている・
///   同梱されていない等。#52 の実害: プリセット欄が本番で例外表示になっていた）は
///   クラッシュさせず、`bridgeReady: false` と [NativeBridgeErrorApp] を返す。
///   以降 [settings] の読込・`filterService` のシードも行わない（Rust ブリッジに
///   依存する機能を使わせないための最小構成）。integration test がテストダブルの
///   `initBridge` を注入して失敗系を確認できるよう関数として差し替え可能にしてある。
/// - 成功時は [settings]（未指定なら新規 `SettingsService()`）を読み込み、
///   トップレベル共有の `filterService`（#15、トレイとウィンドウ内 UI が同じ
///   インスタンスを見る）に永続化済みの per-type 強度（#57）を読み込んでから、
///   復元済みのフィルタ種別を `selectColorVision`（#60）で一度だけ適用して
///   `bridgeReady: true` と [UniversalExperienceApp] を返す。`filterService`
///   と `visionFilterState` の両方が同じ値になる。intensity 自体は
///   `filterService.load()` が
///   `FilterService` 自身の永続化ストアから復元する（`settings.intensity` は
///   #57 で撤去済み。旧キーからの移行はしない）。
///
/// - 続けて [VisionFilterStore]（#65）が前回の選択・payload・強度を復元する
///   （[store] 未指定ならトップレベルの [visionFilterStore]）。
///
/// windowManager / trayService の初期化はここでは行わない。それらは
/// `main()` 内に閉じたままにする（test/widget_test.dart のコメント参照）。
Future<({Widget app, bool bridgeReady})> buildRootApp({
  Future<bool> Function() initBridge = initNativeBridge,
  SettingsService? settings,
  VisionFilterStore? store,
}) async {
  if (!await initBridge()) {
    return (app: const NativeBridgeErrorApp(), bridgeReady: false);
  }

  // Restore persisted settings (theme mode / last filter / locale) before
  // building the app so the first frame already reflects the user's choices
  // (#17/#18, settings_service.dart).
  final s = settings ?? SettingsService();
  await s.load();

  // Restore the shared FilterService's (#15) own per-type intensity store
  // (#57) before seeding it with the restored filter type. The old
  // single-value key (if any leftover on disk) is not migrated:
  // the app is pre-release, so there are no existing users to preserve it
  // for; load() just deletes it.
  await filterService.load();

  // Seed the shared FilterService and VisionFilterState (#15/#60) from the
  // restored settings (#17) so the previously selected filter is reflected on
  // startup — through selectColorVision (#60), the single entry point that
  // keeps both services in sync, same as FilterBrowser/tray. No explicit
  // intensity override here (#57): the type's own remembered/recommended
  // strength (just loaded above) is used instead of resetting it.
  //
  // #78: on a genuine first launch (s.isFirstRun — see that getter's doc),
  // seed deuteranomaly (at its recommended strength, same mechanism as any
  // other type) instead of s.filterType, and persist that choice immediately
  // so isFirstRun is false on every later launch. A later explicit "Normal
  // vision" pick persists `none` normally from then on (setFilterType's
  // no-op guard no longer short-circuits once the in-memory type has moved
  // off its struct default).
  final seedType =
      s.isFirstRun ? ColorVisionType.deuteranomaly : s.filterType;
  selectColorVision(filterService, visionFilterState, seedType);
  if (s.isFirstRun) {
    await s.setFilterType(seedType);
  }

  // #65: 前回の選択・payload・強度を復元し、以後の変更の保存を始める。上の
  // 色覚シードの**後**に行い、保存があればそちらを優先する（advanced /
  // 体験プリセット / 色覚クイック選択のいずれで終了しても、その選択のまま起動
  // する）。保存が無い・壊れている・カタログと合わない部分は既定値に落ち、
  // 起動は止まらない。色覚クイック選択に戻した場合は、トレイとウィンドウ内 UI の
  // 両方が見る filterService も同じ型に合わせる。
  final restored = await (store ?? visionFilterStore).restoreAndBind(
    visionFilterState,
    isValidPreset: isValidExperiencePreset,
  );
  final restoredColorType = visionFilterState.colorVisionType;
  if (restored && restoredColorType != null) {
    filterService.applyFilter(restoredColorType);
  }

  // #78: seed the initial sample from the just-restored/seeded filter
  // selection's recommendation, so the preview never starts on a sample that
  // doesn't match the selected filter. followRecommendedSample (not
  // selectSample) — this is auto-follow doing its normal job, not a manual
  // pick, so auto-follow must stay enabled afterward.
  imageSourceState.followRecommendedSample(
    recommendedSampleIdForFilter(visionFilterState.selectedId),
  );

  return (app: UniversalExperienceApp(settings: s), bridgeReady: true);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // macOS の Cmd+Q・メニューバーの「終了」・ログアウト等（window_manager の
  // クローズイベントを経由しない終了経路）でも intensity のデバウンス永続化
  // （#57）を取りこぼさないための保険。トレイ・ウィンドウクローズ
  // 経由の flush はそのまま残す。
  appLifecycleListener = AppLifecycleListener(
    onExitRequested: () async {
      await filterService.flush();
      await visionFilterStore.flush();
      return AppExitResponse.exit;
    },
  );

  // buildRootApp() が Rust ブリッジ初期化・設定復元・filterService のシードを
  // 行い、成功/失敗いずれの場合も表示すべき Widget を bridgeReady と共に返す（#55）。
  final settings = SettingsService();
  final result = await buildRootApp(settings: settings);
  if (!result.bridgeReady) {
    runApp(result.app);
    return;
  }

  // ここに到達した時点で settings は buildRootApp() 内で load() 済み
  // （同一インスタンスなので、以下の trayService/windowManager も復元済みの値を見る）。

  // Build the tray with labels resolved for the startup locale (#18). Must run
  // after settings.load() so the persisted language (if any) is honoured.
  trayService = _buildTrayService(settings);

  // Initialize window manager for desktop platforms
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();

    // 永続化済みのアプリモード・最前面固定・クリックスルー (#63) を復元する。
    // WindowOptions の backgroundColor 構築より前に読む必要がある。
    await loupeWindow.load();

    // ルーペ窓の起動オプション。サイズ・最小サイズ・透過の既定は
    // LoupeWindowPolicy に集約 (testable な純粋ロジック)。
    // - backgroundColor: 起動モード (#63) に応じて決める。設定モード（既定）は
    //   不透明、ルーペモードは透過（枠の外は透け、枠の中だけフィルタ描画する）。
    // マルチモニタ: 第1弾はメインモニタのみ対象 (docs/ARCHITECTURE.md 参照)。
    // window_manager の backgroundColor は非 null の Color のため、
    // 透過 ON のとき transparent、OFF のとき不透明黒を渡す。
    final windowOptions = WindowOptions(
      size: LoupeWindowPolicy.defaultSize,
      minimumSize: LoupeWindowPolicy.minimumSize,
      center: true,
      // 色の例外（DESIGN.md）: OS ウィンドウの下地色。Flutter のテーマが
      // 立ち上がる前に window_manager へ渡す値で、ロールを引けない。
      backgroundColor: LoupeWindowPolicy.transparentForMode(loupeWindow.appMode)
          ? Colors.transparent
          : Colors.black,
      skipTaskbar: false,
      title: 'Universal Experience',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      // 最小サイズ・最前面・枠ポリシーを適用 (#14/#63)。
      await loupeWindow.initialize();
      await windowManager.show();
      await windowManager.focus();
    });

    // タスクトレイ常駐 + クローズ・ポリシー (#15)。
    await _setUpTray();

    // 言語ピッカー・OS のロケール変更でトレイの文言を作り直す (#82)。
    trayLocaleSync = TrayLocaleSync(
      settings: settings,
      initial: resolveSupportedLocale(settings.locale),
      apply: (locale) {
        final l10n = lookupAppLocalizations(locale);
        return trayService.updateLocalization(
          labels: trayMenuLabelsFrom(l10n),
          tooltip: l10n.trayTooltip,
        );
      },
    )..start();

    // グローバルホットキー (#63)。トレイ初期化の後に登録する
    // （非常口アクションがトレイ経由の showAndFocusLoupe を使うため）。
    hotkeyService = HotkeyService();
    final hotkeyActions = HotkeyActions(
      // #60 の唯一の入口（selectColorVision/deactivateColorVision）を経由する。
      // filterService.deactivate() + visionFilterState.clear() と同じフィールド
      // をクリアする実装だが、規律に合わせて置き換える。
      deactivateFilters: () =>
          deactivateColorVision(filterService, visionFilterState),
      setClickThrough: loupeWindow.setClickThrough,
      setAlwaysOnTop: loupeWindow.setAlwaysOnTop,
      getClickThrough: () => loupeWindow.clickThrough,
      // #79: ホットキー専用の holder（_hotkeyBypassSource）で acquire/release
      // する。emergencyExit だけは誰が保持していても解除する clearBypass を使う。
      acquireBypass: () => visionFilterState.acquireBypass(_hotkeyBypassSource),
      releaseBypass: () => visionFilterState.releaseBypass(_hotkeyBypassSource),
      clearBypass: visionFilterState.clearBypass,
      isBypassHeldByHotkey: () =>
          visionFilterState.isHeldBy(_hotkeyBypassSource),
      showAndFocusLoupe: trayService.onShowLoupe,
      toggleLoupeVisible: trayService.toggleLoupeVisible,
      setLoupeVisible: trayService.setLoupeVisible,
    );
    await hotkeyService.init({
      AppHotkeyAction.toggleClickThrough: HotkeyHandlers(
        onKeyDown: () => unawaited(hotkeyActions.toggleClickThrough()),
      ),
      AppHotkeyAction.holdOriginal: HotkeyHandlers(
        onKeyDown: hotkeyActions.holdOriginalKeyDown,
        onKeyUp: hotkeyActions.holdOriginalKeyUp,
      ),
      AppHotkeyAction.emergencyExit: HotkeyHandlers(
        onKeyDown: () => unawaited(hotkeyActions.emergencyExit()),
      ),
      AppHotkeyAction.toggleLoupeVisibility: HotkeyHandlers(
        onKeyDown: () => unawaited(hotkeyActions.toggleLoupeVisible()),
      ),
    });

    // 永続化されたクリックスルー ON を、トレイ・ホットキーの初期化が終わった
    // 今の時点で適用する (#63)。診断ログのタイミングを揃えるため、この順序
    // 自体は変えていない。
    await loupeWindow.restorePersistedClickThrough();

    runApp(UniversalExperienceApp(
      settings: settings,
      trayAvailable: trayService.isAvailable,
      hotkeyStatus: HotkeyStatus(
        registered: hotkeyService.registeredActions,
        failed: hotkeyService.failedActions,
        bindings: hotkeyService.activeBindings,
      ),
    ));
    return;
  }

  runApp(result.app);
}

/// トレイを初期化し、ウィンドウのクローズ・ポリシーを適用する (#15)。
///
/// ## クローズ・ポリシー
/// メインウィンドウを閉じても**終了せず、トレイに最小化**する。これにより
/// アプリはバックグラウンドに残り、トレイメニューから復帰できる。明示的な
/// 終了はトレイの "終了" 項目のみ。
///
/// ただしトレイが立ち上がらなかった環境ではウィンドウが復帰不能になるため、
/// [resolveCloseAction] がフォールバックを表現する: トレイが無い場合は
/// クローズ = 終了。よって分岐先（トレイに隠すか・実際に終了するか）は
/// トレイ初期化の成否で決める。いずれの分岐も、実際にウィンドウが閉じる/
/// 隠れる前に `windowManager.setPreventClose(true)` でいったん介入する
/// （#57: トレイ不可時の「クローズ=終了」経路でも intensity のデバウンス
/// 書き込み（[FilterService.flush]）を取りこぼさないため）。
Future<void> _setUpTray() async {
  await trayService.init();

  final closeAction =
      resolveCloseAction(trayAvailable: trayService.isAvailable);
  await windowManager.setPreventClose(true);
  windowManager.addListener(
    _AppWindowListener(
      onClose: () async {
        if (closeAction == CloseAction.hideToTray) {
          // 終了ではなく非表示にする。トレイ側のトグルラベルが次回正しくなるよう
          // 表示状態を同期する。
          await windowManager.hide();
          await trayService.setLoupeVisible(false);
          return;
        }
        // トレイ非対応環境: ウィンドウを閉じる = アプリを終了する（最終結果は
        // 元の実装と同じ）。デバウンス中の intensity 永続化（#57）を
        // 取りこぼさないよう、実際に閉じる前に flush する。flush が万一失敗
        // しても（`FilterService.flush` 自体は内部で握りつぶすが、念のため）
        // ウィンドウを閉じずに固まらないよう、実際の終了は finally で行う。
        try {
          await filterService.flush();
          await visionFilterStore.flush();
        } finally {
          await windowManager.setPreventClose(false);
          await windowManager.destroy();
        }
      },
    ),
  );
}

/// window_manager のクローズイベントを close-to-tray ハンドラに橋渡しする。
class _AppWindowListener extends WindowListener {
  _AppWindowListener({required this.onClose});

  final Future<void> Function() onClose;

  @override
  void onWindowClose() {
    onClose();
  }
}

class UniversalExperienceApp extends StatelessWidget {
  const UniversalExperienceApp({
    super.key,
    required this.settings,
    this.trayAvailable = false,
    this.hotkeyStatus = const HotkeyStatus(),
  });

  /// Pre-loaded settings service (theme mode / last filter type / locale).
  final SettingsService settings;

  /// トレイが使える環境か (#63)。`WindowModePanel` がクリックスルーの復帰手段
  /// ヒントの表示判定に使う。デスクトップ初期化を経由しない widget test
  /// （`UniversalExperienceApp(settings: settings)`）がそのまま動くよう、
  /// 既定値は「トレイ無し」という最も安全側にしてある。
  final bool trayAvailable;

  /// グローバルホットキーの登録結果 (#63)。同じ理由で既定値は「ホットキー無し」。
  final HotkeyStatus hotkeyStatus;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // SettingsService is created+loaded in main() so the first frame uses
        // restored values; provide the existing instance (not a fresh one).
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        // トレイ (#15) と共有する単一の FilterService を供給する。新しい
        // インスタンスを作らず、トレイのクイックフィルタとウィンドウ内の
        // ドロップダウンが同じ状態を見るようトップレベルの 1 個を使い回す。
        // 復元した設定 (#17) によるシードは main() 内で適用済み。
        ChangeNotifierProvider<FilterService>.value(value: filterService),
        // VisionFilterState (#16) drives the filter-selection / parameter UI,
        // and is the preview's single source of truth (#60). Same top-level
        // singleton reasoning as filterService above — provide the existing
        // instance, not a fresh one, so it stays the same one the tray and
        // selectColorVision (#60) update.
        ChangeNotifierProvider<VisionFilterState>.value(
          value: visionFilterState,
        ),
        // プレビュー原画（サンプル/ユーザー画像）の選択 (#78)。同じ理由で
        // トップレベルの 1 個を使い回す。
        ChangeNotifierProvider<ImageSourceState>.value(
          value: imageSourceState,
        ),
        // ルーペ窓のモード/最前面/クリックスルー (#63)。同じ理由でトップレベルの
        // 1 個を使い回す（トレイ・main() の起動シーケンスと同じインスタンス）。
        ChangeNotifierProvider<LoupeWindowController>.value(value: loupeWindow),
        // トレイ/ホットキーの可用性 (#63)。汎用的な Provider<bool> は他の bool
        // provider と衝突しうるため使わず、専用の値オブジェクトにまとめて供給する。
        Provider<WindowModeUiContext>.value(
          value: WindowModeUiContext(
            trayAvailable: trayAvailable,
            hotkeyStatus: hotkeyStatus,
          ),
        ),
      ],
      // Rebuild MaterialApp when the persisted theme mode changes.
      child: Consumer<SettingsService>(
        builder: (context, settings, _) {
          return MaterialApp(
            onGenerateTitle: (context) =>
                AppLocalizations.of(context)!.appTitle,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            // OS のハイコントラスト設定（MediaQuery.highContrast）が有効なとき
            // だけ自動で切り替わる（DESIGN.md）。
            highContrastTheme: AppTheme.highContrastTheme,
            highContrastDarkTheme: AppTheme.highContrastDarkTheme,
            themeMode: settings.themeMode,
            // i18n (#18/#82). locale = null はシステム追従。AppBar の言語
            // ピッカー（`LanguageDialog`）が SettingsService.setLocale で切り替える。
            //
            // 選んだ言語は resolveSupportedLocale を通す。「自動」
            // （null）のときは localeListResolutionCallback が OS の言語リストを
            // 同じ関数で解決する。トレイ（TrayLocaleSync）も同じ関数なので
            // 画面とトレイの言語はずれない。
            locale: settings.locale == null
                ? null
                : resolveSupportedLocale(settings.locale),
            localeListResolutionCallback: (locales, _) =>
                resolveSupportedLocale(null, systemLocales: locales),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            // #79: LoupeHud は HomeScreen とは別の最上位レイヤとして Stack で
            // 重ねる。将来のライブキャプチャ（#1）がキャプチャ・フィルタ対象
            // から HUD を除外しやすいよう、意図的に独立させてある
            // （`lib/ui/widgets/loupe_hud.dart` の module doc 参照）。
            home: const Stack(
              children: [
                HomeScreen(),
                LoupeHud(),
              ],
            ),
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}

/// Rust ブリッジの初期化失敗時 (#55) に `UniversalExperienceApp` の代わりに
/// 表示するエラー画面。`initNativeBridge()` が false を返したときだけ使う。
///
/// `VisionFilterState` / `FilterService` 等の状態も `SettingsService` も
/// 一切構築しない（Rust ブリッジに依存する機能を使わせないための最小構成）。
/// ロケールはシステム追従（設定の読込前なので永続化ロケールは見られない）が、
/// [locale] を渡せばテスト等から明示的に固定できる（未指定時は
/// [resolveSupportedLocale] のフォールバックに従う）。
class NativeBridgeErrorApp extends StatelessWidget {
  const NativeBridgeErrorApp({super.key, this.locale});

  /// 表示に使うロケール。null ならシステム追従（[resolveSupportedLocale]）。
  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: locale,
      // OS の言語が変わったら表示中のエラー画面も追従する（UniversalExperienceApp と
      // 同じ関数）。
      localeListResolutionCallback: (locales, _) =>
          resolveSupportedLocale(null, systemLocales: locales),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      debugShowCheckedModeBanner: false,
      home: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context)!;
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.nativeBridgeInitFailed,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
