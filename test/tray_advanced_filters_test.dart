// トレイの「高度なフィルタ」カテゴリ別サブメニュー（チェック式の多選択、#121）と、
// トレイ⇔ウィンドウ内 UI の双方向同期（#65）。
//
// 純粋層（buildTrayMenuSpec / buildAdvancedFiltersSubmenu）と、`tray_manager` の
// MethodChannel をモックした TrayService の両方を検証する。ネイティブのクリックは
// `onTrayMenuItemClick`（`{'id': id}`）を Flutter 側の channel へ流して再現する
// （tray_manager が受け取る経路そのまま）。
//
// フィルタの切替が click-through 等のウィンドウ状態（#63）に触れないことも、
// LoupeWindowController の状態と通知回数で確かめる。

import 'dart:ui' show Locale;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/l10n/l10n_extensions.dart';
import 'package:universal_experience/models/vision_filter_catalog.dart';
import 'package:universal_experience/services/filter_list_selection.dart';
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
  Set<String> checked = const {},
  Set<String> disabled = const {},
  bool hasLayers = false,
}) =>
    buildTrayMenuSpec(
      loupeVisible: true,
      labels: labels ?? trayMenuLabelsFrom(_ja),
      appMode: AppMode.settings,
      alwaysOnTop: false,
      clickThrough: false,
      checkedListEntryKeys: checked,
      disabledListEntryKeys: disabled,
      hasLayers: hasLayers,
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

    test('渡したキーの行すべてにチェックが付く（複数可。色覚の -omaly 行も）', () {
      const keys = {'catalog:starbursts', 'cv:tritanomaly', 'catalog:vertigo'};
      final checked = _leaves(_spec(checked: keys, hasLayers: true))
          .where((e) => e.checked)
          .map((e) => e.listEntryKey)
          .toSet();
      expect(checked, keys);
      expect(_leaves(_spec()).where((e) => e.checked), isEmpty);
    });

    test('上限で足せない行だけが灰色になり、チェック済みの行は灰色にしない', () {
      const off = {'catalog:myopia', 'cv:protanopia'};
      final leaves = _leaves(_spec(
          checked: {'catalog:starbursts'}, disabled: off, hasLayers: true));
      expect(leaves.where((e) => !e.enabled).map((e) => e.listEntryKey).toSet(),
          off);
      expect(leaves.singleWhere((e) => e.checked).enabled, isTrue);
      // 色覚のクイック項目にも、同じキーで灰色が出る。
      final quick = _spec(disabled: off)
          .where((e) => e.kind == TrayMenuKind.applyColorVisionFilter)
          .toList();
      expect(
          quick.where((e) => !e.enabled).map((e) => e.colorVisionKey).toList(),
          ['protanopia']);
      expect(_leaves(_spec()).every((e) => e.enabled), isTrue);
    });

    test('層があるときは「フィルタを解除」にチェックを付けない', () {
      TrayMenuEntry clear(List<TrayMenuEntry> s) =>
          s.singleWhere((e) => e.key == kClearFilterKey);
      expect(clear(_spec()).checked, isTrue);
      expect(clear(_spec(hasLayers: true)).checked, isFalse);
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
        // 色覚 7 種（-opia 4 + -omaly 3）すべてに表示名がある。
        for (final key in [
          ...kColorVisionQuickCatalogIds,
          for (final a in kVisionAliases) a.id,
        ]) {
          expect(labels.filterLabels[key], isNotEmpty);
          expect(labels.filterLabels[key], visionFilterName(l10n, key));
        }
      }
      expect(_ja.trayAdvancedFilters, isNot(_en.trayAdvancedFilters));
    });

    test('children を含めて値等価になる（チェック・灰色の違いも区別する）', () {
      expect(_spec(checked: {'catalog:starbursts'}),
          equals(_spec(checked: {'catalog:starbursts'})));
      expect(_spec(checked: {'catalog:starbursts'}),
          isNot(equals(_spec(checked: {'catalog:myopia'}))));
      expect(_spec(disabled: {'catalog:starbursts'}), isNot(equals(_spec())));
    });
  });

  group('TrayService ⇔ ウィンドウ内 UI の同期（MethodChannel モック）', () {
    late List<MethodCall> calls;
    late VisionFilterState visionState;
    late LoupeWindowController loupeWindow;
    late TrayService tray;
    late int loupeNotifications;

    /// 非 null の間、setContextMenu の完了を止める（送信中の状態を作る）。
    Completer<void>? sendGate;

    setUp(() async {
      sendGate = null;
      SharedPreferences.setMockInitialValues({});
      calls = [];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(const MethodChannel('tray_manager'),
          (call) async {
        calls.add(call);
        final gate = sendGate;
        if (gate != null && call.method == 'setContextMenu') {
          await gate.future;
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(
          const MethodChannel('tray_manager'), null));

      visionState = VisionFilterState();
      loupeWindow = LoupeWindowController();
      loupeNotifications = 0;
      loupeWindow.addListener(() => loupeNotifications++);
      tray = TrayService(
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

    bool disabled(String key) => find(lastMenu(), key)!['disabled'] == true;

    List<String> layerIds() => [for (final l in visionState.layers) l.id];

    /// トレイの一覧の行のうち、いまチェックされているキー（`list_` を除く）。
    Set<String> checkedRows() => {
          for (final e in kFilterListEntries)
            if (checked('list_${e.key}')) e.key,
        };

    test('トレイで advanced を選ぶと足され、別の行を選ぶと重なってチェックが増える', () async {
      await click('list_catalog:starbursts');
      expect(layerIds(), ['starbursts']);
      expect(checked('list_catalog:starbursts'), isTrue);
      expect(checked(kClearFilterKey), isFalse);

      await click('list_catalog:myopia');
      expect(layerIds().toSet(), {'starbursts', 'myopia'});
      expect(checked('list_catalog:myopia'), isTrue);
      expect(checked('list_catalog:starbursts'), isTrue,
          reason: '別の行を選んでも、前の行は外れずに重なる');
    });

    test('チェック済みの行をもう一度押すと外れる', () async {
      await click('list_catalog:starbursts');
      await click('list_catalog:myopia');

      await click('list_catalog:starbursts');
      expect(layerIds(), ['myopia']);
      expect(checked('list_catalog:starbursts'), isFalse);
      expect(checked('list_catalog:myopia'), isTrue);

      await click('list_catalog:myopia');
      expect(visionState.layers, isEmpty);
      expect(checked(kClearFilterKey), isTrue);
    });

    test('トレイで色覚（-omaly 含む）を選ぶと、variantId 付きの層が足される', () async {
      await click('list_cv:tritanomaly');
      expect(layerIds(), ['tritanopia']);
      expect(visionState.focusedLayer!.variantId, 'tritanomaly');
      expect(visionState.focusedVariantId, 'tritanomaly');
      expect(checked('list_cv:tritanomaly'), isTrue);
      expect(checked('list_cv:tritanopia'), isFalse,
          reason: '別名の行だけが点灯し、同じカタログ id の -opia 行は点灯しない');
      // クイック 4 項目に tritanomaly は無いので、トップレベルでは何も点灯しない。
      expect([
        for (final f in quickColorVisionFilters())
          if (checked(colorVisionEntryKey(f))) f
      ], isEmpty);
    });

    test('色覚は排他: 別の色覚を選ぶと置き換わり、他の層は残る', () async {
      await click('list_catalog:myopia');
      await click(colorVisionEntryKey('protanopia'));
      expect(layerIds().toSet(), {'myopia', 'protanopia'});
      // トップレベルのクイック項目とサブメニュー内の色覚行は同じ層を指す。
      expect(checked(colorVisionEntryKey('protanopia')), isTrue);
      expect(checked('list_cv:protanopia'), isTrue);

      await click(colorVisionEntryKey('deuteranopia'));
      expect(layerIds().toSet(), {'myopia', 'deuteranopia'});
      expect(checked(colorVisionEntryKey('protanopia')), isFalse);
      expect(checked('list_cv:protanopia'), isFalse);
      expect(checked(colorVisionEntryKey('deuteranopia')), isTrue);
      expect(checked('list_catalog:myopia'), isTrue);
    });

    test('色覚は排他: -omaly と -opia も互いに置き換わる', () async {
      await click('list_cv:protanomaly');
      expect(checked('list_cv:protanomaly'), isTrue);

      await click(colorVisionEntryKey('deuteranopia'));
      expect(layerIds(), ['deuteranopia']);
      expect(visionState.focusedLayer!.variantId, isNull);
      expect(checked('list_cv:protanomaly'), isFalse);

      await click('list_cv:deuteranomaly');
      expect(layerIds(), ['deuteranopia']);
      expect(visionState.focusedLayer!.variantId, 'deuteranomaly');
      expect(checked('list_cv:deuteranomaly'), isTrue);
      expect(checked(colorVisionEntryKey('deuteranopia')), isFalse,
          reason: '同じカタログ id でも variantId が違う行は別の行');
    });

    test('色覚のクイック項目をもう一度押すと、その色覚だけが外れる', () async {
      await click('list_catalog:myopia');
      await click(colorVisionEntryKey('protanopia'));
      await click(colorVisionEntryKey('protanopia'));

      expect(layerIds(), ['myopia']);
      expect(checked(colorVisionEntryKey('protanopia')), isFalse);
    });

    test('ウィンドウ内 UI での足し引きがトレイのチェックに反映される（UI → トレイ）', () async {
      visionState.toggle('starbursts');
      visionState.toggle('myopia');
      await settle();
      expect(checkedRows(), {'catalog:starbursts', 'catalog:myopia'});

      visionState.remove('starbursts');
      await settle();
      expect(checkedRows(), {'catalog:myopia'});

      visionState.clear();
      await settle();
      expect(checkedRows(), isEmpty);
      expect(checked(kClearFilterKey), isTrue);
    });

    test('体験プリセットは、その層の行に点灯する', () async {
      visionState.selectPreset('labyrinthitis', 'vertigo');
      await settle();

      expect(checkedRows(), {'catalog:vertigo'});
      expect(checked(kClearFilterKey), isFalse);
    });

    test('解除はすべての層を外し、解除項目にチェックが付く', () async {
      await click('list_catalog:starbursts');
      await click('list_catalog:myopia');
      await click(colorVisionEntryKey('protanopia'));
      expect(visionState.layers.length, 3);

      await click(kClearFilterKey);
      expect(visionState.layers, isEmpty);
      expect(checkedRows(), isEmpty);
      expect(checked(kClearFilterKey), isTrue);
    });

    group('重ねられる上限（5 層）', () {
      setUp(() async {
        for (final id in [
          'starbursts',
          'myopia',
          'vertigo',
          'cataract',
          'glaucoma'
        ]) {
          visionState.toggle(id);
        }
        await settle();
        expect(visionState.layers.length, 5);
      });

      test('足せない行は灰色になり、チェック済みの行は外せる', () async {
        expect(disabled('list_catalog:floaters'), isTrue);
        // 色覚も、色覚の層が無いので足せない。
        expect(disabled(colorVisionEntryKey('protanopia')), isTrue);
        expect(disabled('list_cv:tritanomaly'), isTrue);
        // チェック済みの行は灰色にしない。
        expect(disabled('list_catalog:starbursts'), isFalse);
        expect(checked('list_catalog:starbursts'), isTrue);
        // クイック項目以外の項目（解除）は影響を受けない。
        expect(disabled(kClearFilterKey), isFalse);

        await click('list_catalog:starbursts');
        expect(visionState.layers.length, 4);
        expect(disabled('list_catalog:floaters'), isFalse,
            reason: '1 つ外せば、灰色だった行は足せるようになる');
      });

      test('灰色の行は押しても何も起きない（状態もメニューも変わらない）', () async {
        final before = layerIds();
        await click('list_catalog:floaters');
        expect(layerIds(), before);
        expect(checked('list_catalog:floaters'), isFalse);
      });

      test('色覚の層があるときは、上限でも別の色覚へ置き換えられる（灰色にしない）', () async {
        visionState.remove('glaucoma');
        await click(colorVisionEntryKey('protanopia'));
        await settle();
        expect(visionState.layers.length, 5);

        // 色覚以外の足せない行は灰色、色覚の行は置き換えになるので灰色にしない。
        expect(disabled('list_catalog:floaters'), isTrue);
        expect(disabled(colorVisionEntryKey('deuteranopia')), isFalse);
        expect(disabled('list_cv:tritanomaly'), isFalse);

        await click(colorVisionEntryKey('deuteranopia'));
        expect(visionState.layers.length, 5);
        expect(layerIds(), contains('deuteranopia'));
        expect(layerIds(), isNot(contains('protanopia')));
      });
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
      visionState.toggle('myopia');
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
      visionState.replaceWith('myopia');
      await settle();
      expect(menuSends(), sends + 1);
    });

    test('行の再クリックのたびに、見た目を状態に合わせるために送り直す', () async {
      await click('list_catalog:starbursts');
      var sends = menuSends();
      await click('list_catalog:starbursts');
      expect(menuSends(), greaterThan(sends));
      expect(checked('list_catalog:starbursts'), isFalse);

      sends = menuSends();
      await click('list_catalog:starbursts');
      expect(menuSends(), greaterThan(sends));
      expect(checked('list_catalog:starbursts'), isTrue);
    });

    test('送信中に A→B→A と変わっても、最後の状態がネイティブに残る', () async {
      visionState.toggle('starbursts'); // A（送信完了済み）
      await settle();
      expect(checked('list_catalog:starbursts'), isTrue);

      sendGate = Completer<void>();
      visionState.toggle('myopia'); // B（送信中で完了しない）
      await settle();
      visionState.remove('myopia'); // 再び A
      await settle();
      sendGate!.complete();
      await settle();

      expect(checked('list_catalog:starbursts'), isTrue,
          reason: '最後に送ったメニューが最新の状態（A）を指す');
      expect(checked('list_catalog:myopia'), isFalse);
    });

    test('色覚の base 型を高度なフィルタ側から足しても、トップレベルの同名項目に点灯する', () async {
      visionState.toggle('protanopia');
      await settle();

      expect(checked(colorVisionEntryKey('protanopia')), isTrue);
      expect(checked('list_cv:protanopia'), isTrue);
      expect(checked(kClearFilterKey), isFalse);

      // 色覚ではない advanced を足しても、トップレベルの色覚は増えない。
      visionState.toggle('myopia');
      await settle();
      expect([
        for (final f in quickColorVisionFilters())
          if (checked(colorVisionEntryKey(f))) f
      ], [
        'protanopia'
      ]);
    });

    test('言語が変わるとサブメニューの文言も差し替わり、チェックは保たれる (#82)', () async {
      await click('list_catalog:starbursts');
      await click('list_catalog:myopia');

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
      expect(checked('list_catalog:myopia'), isTrue);
      expect(lastMenu().toString(), isNot(contains('高度なフィルタ')));
    });

    test('言語が変わっても、上限で灰色の行は灰色のまま (#82)', () async {
      for (final id in [
        'starbursts',
        'myopia',
        'vertigo',
        'cataract',
        'glaucoma'
      ]) {
        visionState.toggle(id);
      }
      await settle();
      expect(disabled('list_catalog:floaters'), isTrue);

      await tray.updateLocalization(
        labels: trayMenuLabelsFrom(_en),
        tooltip: _en.trayTooltip,
      );
      expect(disabled('list_catalog:floaters'), isTrue);
      expect(disabled('list_catalog:starbursts'), isFalse);
    });
  });
}
