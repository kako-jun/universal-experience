import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/services/color_vision_selection.dart';
import 'package:universal_experience/services/filter_service.dart';
import 'package:universal_experience/services/tray_service.dart';
import 'package:universal_experience/services/vision_filter_state.dart';

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
);

void main() {
  // TrayService.init() は（ネイティブ初期化が失敗する場合も）内部で
  // `tray_manager` の MethodChannel を触るため、WidgetsFlutterBinding の
  // 初期化を要する（#60、'TrayService の filterService/visionFilterState
  // listener' グループ参照）。
  TestWidgetsFlutterBinding.ensureInitialized();

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
      final spec = buildTrayMenuSpec(loupeVisible: true, labels: _labels);
      final kinds = spec.map((e) => e.kind).toSet();

      expect(kinds, contains(TrayMenuKind.toggleLoupe));
      expect(kinds, contains(TrayMenuKind.applyColorVisionFilter));
      expect(kinds, contains(TrayMenuKind.clearFilter));
      expect(kinds, contains(TrayMenuKind.openSettings));
      expect(kinds, contains(TrayMenuKind.quit));
      expect(kinds, contains(TrayMenuKind.separator));
    });

    test('クイックフィルタごとに apply 項目が 1 つずつ並ぶ', () {
      final spec = buildTrayMenuSpec(loupeVisible: true, labels: _labels);
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
      final spec = buildTrayMenuSpec(loupeVisible: true, labels: _labels);
      final keys = interactive(spec).map((e) => e.key).toList();

      expect(keys.every((k) => k != null && k.isNotEmpty), isTrue);
      expect(keys.toSet().length, keys.length, reason: 'キーは一意であること');
    });

    test('トグルのラベルとチェックがルーペ表示状態を反映する', () {
      final visible = buildTrayMenuSpec(loupeVisible: true, labels: _labels)
          .firstWhere((e) => e.kind == TrayMenuKind.toggleLoupe);
      final hidden = buildTrayMenuSpec(loupeVisible: false, labels: _labels)
          .firstWhere((e) => e.kind == TrayMenuKind.toggleLoupe);

      expect(visible.label, 'ルーペ窓を隠す');
      expect(visible.checked, isTrue);
      expect(hidden.label, 'ルーペ窓を表示');
      expect(hidden.checked, isFalse);
    });

    test('アクティブなフィルタだけがチェックされる', () {
      final spec = buildTrayMenuSpec(
        loupeVisible: true,
        labels: _labels,
        activeFilter: ColorVisionType.deuteranopia,
      );

      final checked = spec
          .where(
              (e) => e.kind == TrayMenuKind.applyColorVisionFilter && e.checked)
          .map((e) => e.colorVisionType)
          .toList();

      expect(checked, [ColorVisionType.deuteranopia]);
    });

    test('フィルタ解除はフィルタ無しのときだけチェックされる', () {
      final active = buildTrayMenuSpec(loupeVisible: true, labels: _labels)
          .firstWhere((e) => e.kind == TrayMenuKind.clearFilter);
      final inactive = buildTrayMenuSpec(
        loupeVisible: true,
        labels: _labels,
        activeFilter: ColorVisionType.protanopia,
      ).firstWhere((e) => e.kind == TrayMenuKind.clearFilter);

      expect(active.checked, isTrue);
      expect(inactive.checked, isFalse);
    });

    test('末尾は終了項目', () {
      final spec = buildTrayMenuSpec(loupeVisible: true, labels: _labels);
      expect(spec.last.kind, TrayMenuKind.quit);
    });

    test('注入したラベルがメニュー項目に反映される', () {
      final spec = buildTrayMenuSpec(
        loupeVisible: true,
        labels: _labels,
        activeFilter: ColorVisionType.protanopia,
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
      filterService = FilterService();
      visionFilterState = VisionFilterState();
      trayService = TrayService(
        filterService: filterService,
        visionFilterState: visionFilterState,
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
}
