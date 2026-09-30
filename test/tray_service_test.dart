import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/services/color_vision_selection.dart';
import 'package:universal_experience/services/filter_service.dart';
import 'package:universal_experience/services/loupe_window_controller.dart';
import 'package:universal_experience/services/tray_service.dart';
import 'package:universal_experience/services/vision_filter_state.dart';

import 'support/vision_filter_metadata_fixture.dart';

/// 文言は i18n 解決済みで [buildTrayMenuSpec] に注入する (#18)。純粋層のテストは
/// app_ja.arb の ja 訳と同じ文字列を渡し、メニュー構造とラベル配線を検証する。
const _labels = TrayMenuLabels(
  showLoupe: 'ルーペ窓を表示',
  hideLoupe: 'ルーペ窓を隠す',
  clearFilter: 'フィルタを解除',
  openSettings: '設定を開く…',
  quit: '終了',
  filterLabels: {
    ColorVisionType.protanopia: '1型2色覚（赤）',
    ColorVisionType.deuteranopia: '2型2色覚（緑）',
    ColorVisionType.tritanopia: '3型2色覚（青）',
    ColorVisionType.achromatopsia: '1色覚（全色盲）',
  },
  appModeLoupeLabel: 'ルーペ窓',
  alwaysOnTopLabel: '最前面に固定',
  clickThroughLabel: 'クリックスルー',
  advancedFilters: '高度なフィルタ',
);

void main() {
  // TrayService.init() は（ネイティブ初期化が失敗する場合も）内部で
  // `tray_manager` の MethodChannel を触るため、WidgetsFlutterBinding の
  // 初期化を要する（#60、'TrayService の filterService/visionFilterState
  // listener' グループ参照）。
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installVisionFilterMetadataFixture);
  tearDown(resetVisionFilterMetadataProviders);

  group('quickColorVisionFilters', () {
    test('よく使う色覚フィルタを含み none を含まない', () {
      final filters = quickColorVisionFilters();
      expect(filters, contains(ColorVisionType.protanopia));
      expect(filters, contains(ColorVisionType.deuteranopia));
      expect(filters, contains(ColorVisionType.tritanopia));
      expect(filters, contains(ColorVisionType.achromatopsia));
      expect(filters, isNot(contains(ColorVisionType.none)));
    });
  });

  group('TrayMenuLabels.toggleLabel', () {
    test('表示中は隠すラベル', () {
      expect(_labels.toggleLabel(loupeVisible: true), 'ルーペ窓を隠す');
    });

    test('非表示中は表示ラベル', () {
      expect(_labels.toggleLabel(loupeVisible: false), 'ルーペ窓を表示');
    });

    test('未登録の型は id をフォールバック表示する', () {
      expect(
          _labels.filterLabel(ColorVisionType.none), ColorVisionType.none.id);
    });
  });

  group('colorVisionEntryKey', () {
    test('フィルタ名から安定したキーを導出する', () {
      expect(
        colorVisionEntryKey(ColorVisionType.protanopia),
        'filter_protanopia',
      );
      expect(
        colorVisionEntryKey(ColorVisionType.achromatopsia),
        'filter_achromatopsia',
      );
    });
  });

  group('buildTrayMenuSpec', () {
    List<TrayMenuEntry> interactive(List<TrayMenuEntry> spec) =>
        spec.where((e) => e.kind != TrayMenuKind.separator).toList();

    test('トグル・全クイックフィルタ・解除・設定・終了が揃う', () {
      final spec = buildTrayMenuSpec(
        loupeVisible: true,
        labels: _labels,
        appMode: AppMode.settings,
        alwaysOnTop: false,
        clickThrough: false,
      );
      final kinds = spec.map((e) => e.kind).toSet();

      expect(kinds, contains(TrayMenuKind.toggleLoupe));
      expect(kinds, contains(TrayMenuKind.applyColorVisionFilter));
      expect(kinds, contains(TrayMenuKind.clearFilter));
      expect(kinds, contains(TrayMenuKind.openSettings));
      expect(kinds, contains(TrayMenuKind.quit));
      expect(kinds, contains(TrayMenuKind.separator));
    });

    test('クイックフィルタごとに apply 項目が 1 つずつ並ぶ', () {
      final spec = buildTrayMenuSpec(
        loupeVisible: true,
        labels: _labels,
        appMode: AppMode.settings,
        alwaysOnTop: false,
        clickThrough: false,
      );
      final apply = spec
          .where((e) => e.kind == TrayMenuKind.applyColorVisionFilter)
          .toList();

      expect(apply.length, quickColorVisionFilters().length);
      expect(
        apply.map((e) => e.colorVisionType).toSet(),
        quickColorVisionFilters().toSet(),
      );
    });

    test('操作可能な項目はすべて非空かつ一意のキーを持つ', () {
      final spec = buildTrayMenuSpec(
        loupeVisible: true,
        labels: _labels,
        appMode: AppMode.settings,
        alwaysOnTop: false,
        clickThrough: false,
      );
      final keys = interactive(spec).map((e) => e.key).toList();

      expect(keys.every((k) => k != null && k.isNotEmpty), isTrue);
      expect(keys.toSet().length, keys.length, reason: 'キーは一意であること');
    });

    test('トグルのラベルとチェックがルーペ表示状態を反映する', () {
      final visible = buildTrayMenuSpec(
        loupeVisible: true,
        labels: _labels,
        appMode: AppMode.settings,
        alwaysOnTop: false,
        clickThrough: false,
      ).firstWhere((e) => e.kind == TrayMenuKind.toggleLoupe);
      final hidden = buildTrayMenuSpec(
        loupeVisible: false,
        labels: _labels,
        appMode: AppMode.settings,
        alwaysOnTop: false,
        clickThrough: false,
      ).firstWhere((e) => e.kind == TrayMenuKind.toggleLoupe);

      expect(visible.label, 'ルーペ窓を隠す');
      expect(visible.checked, isTrue);
      expect(hidden.label, 'ルーペ窓を表示');
      expect(hidden.checked, isFalse);
    });

    test('チェック対象に渡した色覚だけがチェックされる（色覚は排他）', () {
      final spec = buildTrayMenuSpec(
        loupeVisible: true,
        labels: _labels,
        appMode: AppMode.settings,
        alwaysOnTop: false,
        clickThrough: false,
        checkedListEntryKeys: {
          colorVisionListEntryKey(ColorVisionType.deuteranopia)
        },
        hasLayers: true,
      );

      final checked = spec
          .where(
              (e) => e.kind == TrayMenuKind.applyColorVisionFilter && e.checked)
          .map((e) => e.colorVisionType)
          .toList();

      expect(checked, [ColorVisionType.deuteranopia]);
    });

    test('フィルタ解除は層が無いときだけチェックされる', () {
      final active = buildTrayMenuSpec(
        loupeVisible: true,
        labels: _labels,
        appMode: AppMode.settings,
        alwaysOnTop: false,
        clickThrough: false,
      ).firstWhere((e) => e.kind == TrayMenuKind.clearFilter);
      final inactive = buildTrayMenuSpec(
        loupeVisible: true,
        labels: _labels,
        appMode: AppMode.settings,
        alwaysOnTop: false,
        clickThrough: false,
        hasLayers: true,
      ).firstWhere((e) => e.kind == TrayMenuKind.clearFilter);

      expect(active.checked, isTrue);
      expect(inactive.checked, isFalse);
    });

    test('末尾は終了項目', () {
      final spec = buildTrayMenuSpec(
        loupeVisible: true,
        labels: _labels,
        appMode: AppMode.settings,
        alwaysOnTop: false,
        clickThrough: false,
      );
      expect(spec.last.kind, TrayMenuKind.quit);
    });

    test('注入したラベルがメニュー項目に反映される', () {
      final spec = buildTrayMenuSpec(
        loupeVisible: true,
        labels: _labels,
        appMode: AppMode.settings,
        alwaysOnTop: false,
        clickThrough: false,
        checkedListEntryKeys: {
          colorVisionListEntryKey(ColorVisionType.protanopia)
        },
        hasLayers: true,
      );
      String labelOf(TrayMenuKind kind) =>
          spec.firstWhere((e) => e.kind == kind).label!;

      expect(labelOf(TrayMenuKind.clearFilter), 'フィルタを解除');
      expect(labelOf(TrayMenuKind.openSettings), '設定を開く…');
      expect(labelOf(TrayMenuKind.quit), '終了');
      final proto = spec.firstWhere(
        (e) =>
            e.kind == TrayMenuKind.applyColorVisionFilter &&
            e.colorVisionType == ColorVisionType.protanopia,
      );
      expect(proto.label, '1型2色覚（赤）');
    });
  });

  group('buildTrayMenuSpec の起動モード/最前面/クリックスルー (#63)', () {
    test('appMode/alwaysOnTop/clickThrough のチェック状態を反映する', () {
      final loupeChecked = buildTrayMenuSpec(
        loupeVisible: true,
        labels: _labels,
        appMode: AppMode.loupe,
        alwaysOnTop: true,
        clickThrough: true,
      );
      expect(
        loupeChecked
            .firstWhere((e) => e.kind == TrayMenuKind.toggleAppMode)
            .checked,
        isTrue,
      );
      expect(
        loupeChecked
            .firstWhere((e) => e.kind == TrayMenuKind.toggleAlwaysOnTop)
            .checked,
        isTrue,
      );
      expect(
        loupeChecked
            .firstWhere((e) => e.kind == TrayMenuKind.toggleClickThrough)
            .checked,
        isTrue,
      );

      final settingsUnchecked = buildTrayMenuSpec(
        loupeVisible: true,
        labels: _labels,
        appMode: AppMode.settings,
        alwaysOnTop: false,
        clickThrough: false,
      );
      expect(
        settingsUnchecked
            .firstWhere((e) => e.kind == TrayMenuKind.toggleAppMode)
            .checked,
        isFalse,
      );
      expect(
        settingsUnchecked
            .firstWhere((e) => e.kind == TrayMenuKind.toggleAlwaysOnTop)
            .checked,
        isFalse,
      );
      expect(
        settingsUnchecked
            .firstWhere((e) => e.kind == TrayMenuKind.toggleClickThrough)
            .checked,
        isFalse,
      );
    });

    test('ラベルが labels 経由で反映される', () {
      final spec = buildTrayMenuSpec(
        loupeVisible: true,
        labels: _labels,
        appMode: AppMode.settings,
        alwaysOnTop: false,
        clickThrough: false,
      );
      String labelOf(TrayMenuKind kind) =>
          spec.firstWhere((e) => e.kind == kind).label!;

      expect(labelOf(TrayMenuKind.toggleAppMode), 'ルーペ窓');
      expect(labelOf(TrayMenuKind.toggleAlwaysOnTop), '最前面に固定');
      expect(labelOf(TrayMenuKind.toggleClickThrough), 'クリックスルー');
    });

    test('3項目とも安定キーを持つ', () {
      final spec = buildTrayMenuSpec(
        loupeVisible: true,
        labels: _labels,
        appMode: AppMode.settings,
        alwaysOnTop: false,
        clickThrough: false,
      );
      expect(
        spec.firstWhere((e) => e.kind == TrayMenuKind.toggleAppMode).key,
        kToggleAppModeKey,
      );
      expect(
        spec.firstWhere((e) => e.kind == TrayMenuKind.toggleAlwaysOnTop).key,
        kToggleAlwaysOnTopKey,
      );
      expect(
        spec.firstWhere((e) => e.kind == TrayMenuKind.toggleClickThrough).key,
        kToggleClickThroughKey,
      );
    });
  });

  group('resolveCloseAction (クローズ→トレイ ポリシー)', () {
    test('トレイがあればトレイに隠す', () {
      expect(resolveCloseAction(trayAvailable: true), CloseAction.hideToTray);
    });

    test('トレイが無ければ終了する', () {
      expect(resolveCloseAction(trayAvailable: false), CloseAction.exitApp);
    });
  });

  group('TrayMenuEntry', () {
    test('separator コンストラクタはキー・ラベル無しの区切り線', () {
      const entry = TrayMenuEntry.separator();
      expect(entry.kind, TrayMenuKind.separator);
      expect(entry.key, isNull);
      expect(entry.label, isNull);
    });

    test('同一内容は値等価', () {
      const a =
          TrayMenuEntry(kind: TrayMenuKind.quit, key: kQuitKey, label: '終了');
      const b =
          TrayMenuEntry(kind: TrayMenuKind.quit, key: kQuitKey, label: '終了');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('TrayService の filterService/visionFilterState listener (#60)', () {
    // TrayService.init() 自体は tray_manager のネイティブプラグインを叩く
    // ため、plain `flutter test`（platform channel 未登録）では常に例外に
    // なる。TrayService はそれを握り潰して `_initialised = false` のまま
    // 続行する契約なので、init()/dispose() 自体は widget を介さず安全に
    // 呼べる。`ChangeNotifier.hasListeners` は `@protected` でテストから
    // 直接見えないため、listener が実際に発火したことは
    // `TrayService.selectionChangedCallCount`（テスト専用フック）で確認する
    // （メニューの実際の再構築＝trayManager 呼び出しは別途 refresh() が
    // `_initialised` を見て no-op にするので、ここでは検証しない）。
    late FilterService filterService;
    late VisionFilterState visionFilterState;
    late TrayService trayService;

    setUp(() {
      visionFilterState = VisionFilterState();
      filterService = FilterService(visionState: visionFilterState);
      trayService = TrayService(
        filterService: filterService,
        visionFilterState: visionFilterState,
        loupeWindow: LoupeWindowController(),
        iconPath: 'assets/tray/tray_icon.png',
        labels: _labels,
        tooltip: 'Universal Experience',
        onShowLoupe: () async {},
        onHideLoupe: () async {},
        onOpenSettings: () async {},
        onQuit: () async {},
      );
    });

    test('init() のあと filterService/visionFilterState の変化で listener が発火する',
        () async {
      await trayService.init();
      expect(trayService.selectionChangedCallCount, 0);

      // selectColorVision は filterService と visionFilterState の両方を
      // 更新する（#60）ため、どちらにも listener を付けている以上 2 回
      // 発火する。
      selectColorVision(
          filterService, visionFilterState, ColorVisionType.protanopia);
      expect(trayService.selectionChangedCallCount, 2);

      // visionFilterState だけを更新する操作（advanced カタログの選択）は
      // +1 だけ増える。
      visionFilterState.select('starbursts');
      expect(trayService.selectionChangedCallCount, 3);

      await trayService.dispose();
    });

    test('dispose() のあとは filterService/visionFilterState の変化で listener が発火しない',
        () async {
      await trayService.init();
      await trayService.dispose();

      selectColorVision(
          filterService, visionFilterState, ColorVisionType.protanopia);

      expect(trayService.selectionChangedCallCount, 0);
    });

    test('init() 後に選択を変えても例外にならない（refresh() は _initialised を見て no-op）',
        () async {
      await trayService.init();

      // ネイティブ初期化はこの環境では必ず失敗するので trayService.isAvailable
      // は false のまま — refresh() が実際に trayManager を呼ばないことの前提。
      expect(trayService.isAvailable, isFalse);

      expect(
        () => selectColorVision(
            filterService, visionFilterState, ColorVisionType.protanopia),
        returnsNormally,
      );

      await trayService.dispose();
    });
  });

  group('TrayService.toggleLoupeVisible (#63)', () {
    test('表示中なら onHideLoupe を呼び、非表示中なら onShowLoupe を呼ぶ', () async {
      var showCalls = 0;
      var hideCalls = 0;
      final vs = VisionFilterState();
      final trayService = TrayService(
        filterService: FilterService(visionState: vs),
        visionFilterState: vs,
        loupeWindow: LoupeWindowController(),
        iconPath: 'assets/tray/tray_icon.png',
        labels: _labels,
        tooltip: 'Universal Experience',
        onShowLoupe: () async {
          showCalls++;
        },
        onHideLoupe: () async {
          hideCalls++;
        },
        onOpenSettings: () async {},
        onQuit: () async {},
      );

      // 既定は表示中 (loupeVisible: true) なので、最初の呼び出しは隠す。
      await trayService.toggleLoupeVisible();
      expect(hideCalls, 1);
      expect(showCalls, 0);

      // 次の呼び出しは表示に戻す（_toggleLoupe と同じロジックを経由する、#63）。
      await trayService.toggleLoupeVisible();
      expect(hideCalls, 1);
      expect(showCalls, 1);
    });
  });

  group('TrayService の loupeWindow listener / トレイ経由の操作 (#63)', () {
    // TrayService.init() のネイティブ初期化はこの環境では必ず失敗する
    // （#60 のグループと同じ理由）。TrayService は _initialised = false の
    // まま続行するので、実際の trayManager クリックは再現できない。
    // ここでは (1) init() が loupeWindow にも listener を付けて変化を
    // 検知すること、(2) TrayService が保持する loupeWindow 自身の
    // setAppMode/setAlwaysOnTop/setClickThrough を呼べば状態が反転する
    // こと（トレイのクリックハンドラが最終的に呼ぶのと同じメソッド）を
    // 確認する。
    test('init() のあと loupeWindow の変化で listener が発火する', () async {
      SharedPreferences.setMockInitialValues({});
      final loupeWindow = LoupeWindowController();
      final vs = VisionFilterState();
      final trayService = TrayService(
        filterService: FilterService(visionState: vs),
        visionFilterState: vs,
        loupeWindow: loupeWindow,
        iconPath: 'assets/tray/tray_icon.png',
        labels: _labels,
        tooltip: 'Universal Experience',
        onShowLoupe: () async {},
        onHideLoupe: () async {},
        onOpenSettings: () async {},
        onQuit: () async {},
      );

      await trayService.init();
      expect(trayService.selectionChangedCallCount, 0);

      await loupeWindow.setAlwaysOnTop(true);
      expect(trayService.selectionChangedCallCount, 1);

      await trayService.dispose();
    });

    test(
        'loupeWindow.setAppMode/setAlwaysOnTop/setClickThrough で '
        'トレイが参照する状態が反転する（クリックハンドラが最終的に呼ぶメソッド）', () async {
      SharedPreferences.setMockInitialValues({});
      final loupeWindow = LoupeWindowController();
      await loupeWindow.load();
      final vs = VisionFilterState();
      TrayService(
        filterService: FilterService(visionState: vs),
        visionFilterState: vs,
        loupeWindow: loupeWindow,
        iconPath: 'assets/tray/tray_icon.png',
        labels: _labels,
        tooltip: 'Universal Experience',
        onShowLoupe: () async {},
        onHideLoupe: () async {},
        onOpenSettings: () async {},
        onQuit: () async {},
      );

      expect(loupeWindow.appMode, AppMode.settings);
      await loupeWindow.setAppMode(
        loupeWindow.appMode == AppMode.loupe ? AppMode.settings : AppMode.loupe,
      );
      expect(loupeWindow.appMode, AppMode.loupe);

      expect(loupeWindow.alwaysOnTop, isFalse);
      await loupeWindow.setAlwaysOnTop(!loupeWindow.alwaysOnTop);
      expect(loupeWindow.alwaysOnTop, isTrue);

      expect(loupeWindow.clickThrough, isFalse);
      await loupeWindow.setClickThrough(!loupeWindow.clickThrough);
      expect(loupeWindow.clickThrough, isTrue);
    });
  });

  group('TrayService.updateLocalization (#82)', () {
    const enLabels = TrayMenuLabels(
      showLoupe: 'Show loupe window',
      hideLoupe: 'Hide loupe window',
      clearFilter: 'Clear filter',
      openSettings: 'Open settings…',
      quit: 'Quit',
      filterLabels: {
        ColorVisionType.protanopia: 'Protanopia',
        ColorVisionType.deuteranopia: 'Deuteranopia',
        ColorVisionType.tritanopia: 'Tritanopia',
        ColorVisionType.achromatopsia: 'Achromatopsia',
      },
      appModeLoupeLabel: 'Loupe window',
      alwaysOnTopLabel: 'Always on top',
      clickThroughLabel: 'Click-through',
      advancedFilters: 'Advanced filters',
    );

    final vs = VisionFilterState();
    TrayService buildTray() => TrayService(
          filterService: FilterService(visionState: vs),
          visionFilterState: vs,
          loupeWindow: LoupeWindowController(),
          iconPath: 'assets/tray/tray_icon.png',
          labels: _labels,
          tooltip: 'ユニバーサル・エクスペリエンス',
          onShowLoupe: () async {},
          onHideLoupe: () async {},
          onOpenSettings: () async {},
          onQuit: () async {},
        );

    test('未初期化でも文言を保持し、メニュー仕様が新しい言語のラベルになる', () async {
      final tray = buildTray();
      expect(tray.labels.quit, '終了');

      await tray.updateLocalization(
          labels: enLabels, tooltip: 'Universal Experience');

      expect(tray.labels, same(enLabels));
      expect(tray.tooltip, 'Universal Experience');
      final spec = buildTrayMenuSpec(
        loupeVisible: true,
        labels: tray.labels,
        appMode: AppMode.settings,
        alwaysOnTop: false,
        clickThrough: false,
      );
      final labels = spec.map((e) => e.label).whereType<String>().toList();
      expect(labels, contains('Hide loupe window'));
      expect(labels, contains('Protanopia'));
      expect(labels, contains('Quit'));
      expect(labels, isNot(contains('終了')));
    });

    test('初期化済みならツールチップとコンテキストメニューをネイティブへ送り直す', () async {
      // tray_manager の MethodChannel を記録用に差し替える（init を成功させる）。
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(const MethodChannel('tray_manager'),
          (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(
          const MethodChannel('tray_manager'), null));

      final tray = buildTray();
      await tray.init();
      expect(tray.isAvailable, isTrue, reason: 'モックしたチャネルで init が成功する');
      addTearDown(tray.dispose);
      expect(calls.where((c) => c.method == 'setToolTip').single.arguments,
          containsPair('toolTip', 'ユニバーサル・エクスペリエンス'));
      expect(calls.last.method, 'setContextMenu');
      expect(calls.last.arguments.toString(), contains('終了'));

      calls.clear();
      await tray.updateLocalization(
          labels: enLabels, tooltip: 'Universal Experience');

      expect(calls.map((c) => c.method), ['setToolTip', 'setContextMenu']);
      expect(calls.first.arguments,
          containsPair('toolTip', 'Universal Experience'));
      final menu = calls.last.arguments.toString();
      expect(menu, contains('Quit'));
      expect(menu, contains('Protanopia'));
      expect(menu, isNot(contains('終了')));
      expect(menu, isNot(contains('1型2色覚（赤）')));
    });
  });
}
