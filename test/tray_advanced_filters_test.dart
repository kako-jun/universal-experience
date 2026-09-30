// トレイの「高度なフィルタ」カテゴリ別サブメニューと、トレイ⇔ウィンドウ内 UI の
// 双方向同期（#65）。
//
// 純粋層（buildTrayMenuSpec / buildAdvancedFiltersSubmenu）と、`tray_manager` の
// MethodChannel をモックした TrayService の両方を検証する。ネイティブのクリックは
// `onTrayMenuItemClick`（`{'id': id}`）を Flutter 側の channel へ流して再現する
// （tray_manager が受け取る経路そのまま）。
//
// フィルタの切替が click-through 等のウィンドウ状態（#63）に触れないことも、
// LoupeWindowController の状態と通知回数で確かめる。

import 'dart:ui' show Locale;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/l10n/l10n_extensions.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/models/vision_filter_catalog.dart';
import 'package:universal_experience/services/filter_list_selection.dart';
import 'package:universal_experience/services/filter_service.dart';
import 'package:universal_experience/services/loupe_window_controller.dart';
import 'package:universal_experience/services/tray_service.dart';
import 'package:universal_experience/services/vision_filter_state.dart';

import 'support/vision_filter_metadata_fixture.dart';

final AppLocalizations _ja = lookupAppLocalizations(const Locale('ja'));
final AppLocalizations _en = lookupAppLocalizations(const Locale('en'));

List<TrayMenuEntry> _flatten(List<TrayMenuEntry> entries) => [
      for (final e in entries) ...[e, ..._flatten(e.children)],
    ];

TrayMenuEntry _advanced(List<TrayMenuEntry> spec) =>
    spec.singleWhere((e) => e.key == kAdvancedFiltersKey);

List<TrayMenuEntry> _leaves(List<TrayMenuEntry> spec) =>
    _flatten([_advanced(spec)])
        .where((e) => e.kind == TrayMenuKind.applyListEntry)
        .toList();

List<TrayMenuEntry> _spec({
  TrayMenuLabels? labels,
  FilterListEntry? selected,
  bool advancedSelected = false,
}) =>
    buildTrayMenuSpec(
      loupeVisible: true,
      labels: labels ?? trayMenuLabelsFrom(_ja),
      appMode: AppMode.settings,
      alwaysOnTop: false,
      clickThrough: false,
      selectedListEntry: selected,
      advancedSelected: advancedSelected,
    );

FilterListEntry _row(String key) =>
    kFilterListEntries.firstWhere((e) => e.key == key);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installVisionFilterMetadataFixture);
  tearDown(resetVisionFilterMetadataProviders);

  group('「高度なフィルタ」サブメニューの構造（純粋層）', () {
    test('7 カテゴリのサブメニューに、統合一覧の全行が 1 回ずつ並ぶ', () {
      final advanced = _advanced(_spec());
      expect(advanced.kind, TrayMenuKind.submenu);
      expect(advanced.label, '高度なフィルタ');
      expect(
          advanced.children.map((c) => c.kind).toSet(), {TrayMenuKind.submenu});
      expect(advanced.children.length, VisionFilterCategory.values.length);

      final leaves = _leaves(_spec());
      expect(leaves.map((e) => e.listEntryKey).toList(),
          kFilterListEntries.map((e) => e.key).toList());
      expect(leaves.length, 33);
    });

    test('カテゴリのサブメニューには、そのカテゴリの行だけが入る', () {
      for (final category in VisionFilterCategory.values) {
        final sub = _advanced(_spec())
            .children
            .singleWhere((c) => c.key == categorySubmenuKey(category));
        expect(sub.children.map((c) => c.listEntryKey).toList(), [
          for (final e in kFilterListEntries)
            if (e.category == category) e.key,
        ]);
      }
    });

    test('全項目（サブメニュー内も）のキーは一意で、ラベルは解決済みの表示名', () {
      final all = _flatten(_spec()).where((e) => e.key != null).toList();
      expect(all.map((e) => e.key).toSet().length, all.length);

      final labels = trayMenuLabelsFrom(_ja);
      for (final e in _leaves(_spec())) {
        final row = _row(e.listEntryKey!);
        expect(e.label, filterListEntryName(_ja, row));
        expect(e.label, isNot(row.catalogId),
            reason: '${row.key} の表示名が id のフォールバックになっている');
      }
      for (final c in _advanced(_spec()).children) {
        final category = VisionFilterCategory.values
            .singleWhere((v) => categorySubmenuKey(v) == c.key);
        expect(c.label, visionCategoryName(_ja, category));
        expect(c.label, labels.categoryLabel(category));
      }
    });

    test('選択中の行だけにチェックが付く（色覚の -omaly 行も）', () {
      for (final key in [
        'catalog:starbursts',
        'cv:tritanomaly',
        'cv:protanopia'
      ]) {
        final checked = _leaves(_spec(selected: _row(key)))
            .where((e) => e.checked)
            .map((e) => e.listEntryKey)
            .toList();
        expect(checked, [key]);
      }
      expect(_leaves(_spec()).where((e) => e.checked), isEmpty);
    });

    test('advanced 選択中は「フィルタを解除」にチェックを付けない', () {
      TrayMenuEntry clear(List<TrayMenuEntry> s) =>
          s.singleWhere((e) => e.key == kClearFilterKey);
      expect(clear(_spec()).checked, isTrue);
      expect(clear(_spec(advancedSelected: true)).checked, isFalse);
    });

    test('ja / en の両方で全ラベルが埋まり、id の素通しにならない', () {
      for (final l10n in [_ja, _en]) {
        final labels = trayMenuLabelsFrom(l10n);
        expect(labels.advancedFilters, isNotEmpty);
        expect(labels.advancedFilters, l10n.trayAdvancedFilters);
        for (final category in VisionFilterCategory.values) {
          expect(labels.categoryLabels[category], isNotEmpty);
        }
        for (final entry in kVisionFilterCatalog) {
          expect(labels.catalogNames[entry.id], isNotEmpty);
        }
        for (final type in ColorVisionType.values) {
          if (type == ColorVisionType.none) continue;
          expect(labels.filterLabels[type], isNotEmpty);
        }
      }
      expect(_ja.trayAdvancedFilters, isNot(_en.trayAdvancedFilters));
    });

    test('children を含めて値等価になる', () {
      expect(_spec(selected: _row('catalog:starbursts')),
          equals(_spec(selected: _row('catalog:starbursts'))));
      expect(_spec(selected: _row('catalog:starbursts')),
          isNot(equals(_spec(selected: _row('catalog:myopia')))));
    });
  });

  group('TrayService ⇔ ウィンドウ内 UI の同期（MethodChannel モック）', () {
    late List<MethodCall> calls;
    late FilterService filterService;
    late VisionFilterState visionState;
    late LoupeWindowController loupeWindow;
    late TrayService tray;
    late int loupeNotifications;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      calls = [];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(const MethodChannel('tray_manager'),
          (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(
          const MethodChannel('tray_manager'), null));

      filterService = FilterService();
      visionState = VisionFilterState();
      loupeWindow = LoupeWindowController();
      loupeNotifications = 0;
      loupeWindow.addListener(() => loupeNotifications++);
      tray = TrayService(
        filterService: filterService,
        visionFilterState: visionState,
        loupeWindow: loupeWindow,
        iconPath: 'assets/tray/tray_icon.png',
        labels: trayMenuLabelsFrom(_ja),
        tooltip: _ja.trayTooltip,
        onShowLoupe: () async {},
        onHideLoupe: () async {},
        onOpenSettings: () async {},
        onQuit: () async {},
      );
      await tray.init();
      expect(tray.isAvailable, isTrue);
      addTearDown(tray.dispose);
    });

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    int menuSends() => calls.where((c) => c.method == 'setContextMenu').length;

    /// 最後にネイティブへ送られたメニュー（JSON）。
    Map<String, dynamic> lastMenu() {
      final call = calls.lastWhere((c) => c.method == 'setContextMenu');
      return Map<String, dynamic>.from((call.arguments as Map)['menu'] as Map);
    }

    Map<String, dynamic>? find(Map<String, dynamic> menu, String key) {
      for (final raw in (menu['items'] as List? ?? const [])) {
        final item = Map<String, dynamic>.from(raw as Map);
        if (item['key'] == key) return item;
        final sub = item['submenu'];
        if (sub != null) {
          final hit = find(Map<String, dynamic>.from(sub as Map), key);
          if (hit != null) return hit;
        }
      }
      return null;
    }

    bool checked(String key) => find(lastMenu(), key)!['checked'] == true;

    /// ネイティブのメニュー項目クリックを再現する。
    Future<void> click(String key) async {
      final id = find(lastMenu(), key)!['id'] as int;
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'tray_manager',
        const StandardMethodCodec()
            .encodeMethodCall(MethodCall('onTrayMenuItemClick', {'id': id})),
        (_) {},
      );
      await settle();
    }

    test('メニューはネイティブへ入れ子のサブメニューとして送られる', () {
      final advanced = find(lastMenu(), kAdvancedFiltersKey)!;
      expect(advanced['type'], 'submenu');
      expect(advanced['label'], '高度なフィルタ');
      final category = find(
          lastMenu(), categorySubmenuKey(VisionFilterCategory.vestibular))!;
      expect(category['type'], 'submenu');
      final leaf = find(lastMenu(), 'list_catalog:vertigo')!;
      expect(leaf['label'], filterListEntryName(_ja, _row('catalog:vertigo')));
    });

    test('トレイで advanced を選ぶと VisionFilterState が変わり、チェックが移る', () async {
      await click('list_catalog:starbursts');
      expect(visionState.selectedId, 'starbursts');
      expect(visionState.isColorQuickSelection, isFalse);
      expect(checked('list_catalog:starbursts'), isTrue);
      expect(checked(kClearFilterKey), isFalse);

      await click('list_catalog:myopia');
      expect(visionState.selectedId, 'myopia');
      expect(checked('list_catalog:myopia'), isTrue);
      expect(checked('list_catalog:starbursts'), isFalse);
    });

    test('トレイで色覚（-omaly 含む）を選ぶと FilterService も同じ入口で更新される', () async {
      await click('list_cv:tritanomaly');
      expect(visionState.isColorQuickSelection, isTrue);
      expect(visionState.colorVisionType, ColorVisionType.tritanomaly);
      expect(filterService.currentFilter, ColorVisionType.tritanomaly);
      expect(checked('list_cv:tritanomaly'), isTrue);

      // トップレベルのクイック項目とサブメニュー内の色覚行は同じ選択を指す。
      await click('list_cv:protanopia');
      expect(checked(colorVisionEntryKey(ColorVisionType.protanopia)), isTrue);
      expect(checked('list_cv:protanopia'), isTrue);
    });

    test('ウィンドウ内 UI での選択がトレイのチェックに反映される（UI → トレイ）', () async {
      visionState.select('starbursts');
      await settle();
      expect(checked('list_catalog:starbursts'), isTrue);

      visionState.selectPreset('labyrinthitis', 'vertigo');
      await settle();
      expect(
          [for (final e in kFilterListEntries) checked('list_${e.key}')]
              .where((c) => c),
          isEmpty,
          reason: 'プリセット選択中は一覧の行を点灯させない（ウィンドウ内一覧と同じ）');
      expect(checked(kClearFilterKey), isFalse);

      visionState.clear();
      await settle();
      expect(checked(kClearFilterKey), isTrue);
    });

    test('解除するとすべてのチェックが外れ、解除項目にチェックが付く', () async {
      await click('list_catalog:starbursts');
      await click(kClearFilterKey);
      expect(visionState.selectedId, isNull);
      expect(checked(kClearFilterKey), isTrue);
      expect(checked('list_catalog:starbursts'), isFalse);
    });

    test('フィルタ切替は click-through / 最前面 / モードに触れない（#63）', () async {
      await loupeWindow.load();
      final before = (
        loupeWindow.clickThrough,
        loupeWindow.alwaysOnTop,
        loupeWindow.appMode,
      );
      loupeNotifications = 0;

      await click('list_catalog:starbursts');
      await click('list_cv:deuteranomaly');
      await click('list_catalog:vertigo');
      visionState.select('myopia');
      await click(kClearFilterKey);

      expect((
        loupeWindow.clickThrough,
        loupeWindow.alwaysOnTop,
        loupeWindow.appMode,
      ), before);
      expect(loupeNotifications, 0, reason: 'LoupeWindowController は一度も通知されない');
    });

    test('選択が変わらない再通知ではネイティブへメニューを送り直さない', () async {
      await click('list_catalog:starbursts');
      final sends = menuSends();

      // スライダー操作など、メニューの見た目に関係しない変化の連発。
      visionState
        ..setStrength(0.4)
        ..setStrength(0.5)
        ..setParam('numRays', 12);
      await settle();
      expect(menuSends(), sends);

      // 選択が変わればちゃんと送る。
      visionState.select('myopia');
      await settle();
      expect(menuSends(), sends + 1);
    });

    test('選択済みの行の再クリックでも、見た目を合わせるために送り直す', () async {
      await click('list_catalog:starbursts');
      final sends = menuSends();
      await click('list_catalog:starbursts');
      expect(menuSends(), greaterThan(sends));
      expect(checked('list_catalog:starbursts'), isTrue);
    });

    test('言語が変わるとサブメニューの文言も差し替わり、チェックは保たれる (#82)', () async {
      await click('list_catalog:starbursts');

      await tray.updateLocalization(
        labels: trayMenuLabelsFrom(_en),
        tooltip: _en.trayTooltip,
      );

      expect(
          find(lastMenu(), kAdvancedFiltersKey)!['label'], 'Advanced filters');
      expect(
          find(lastMenu(),
              categorySubmenuKey(VisionFilterCategory.vestibular))!['label'],
          visionCategoryName(_en, VisionFilterCategory.vestibular));
      expect(find(lastMenu(), 'list_catalog:starbursts')!['label'],
          filterListEntryName(_en, _row('catalog:starbursts')));
      expect(checked('list_catalog:starbursts'), isTrue);
      expect(lastMenu().toString(), isNot(contains('高度なフィルタ')));
    });
  });
}
