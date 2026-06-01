import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/services/tray_service.dart';

void main() {
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

  group('trayToggleLabel', () {
    test('表示中は隠すラベル', () {
      expect(trayToggleLabel(loupeVisible: true), 'ルーペ窓を隠す');
    });

    test('非表示中は表示ラベル', () {
      expect(trayToggleLabel(loupeVisible: false), 'ルーペ窓を表示');
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
      final spec = buildTrayMenuSpec(loupeVisible: true);
      final kinds = spec.map((e) => e.kind).toSet();

      expect(kinds, contains(TrayMenuKind.toggleLoupe));
      expect(kinds, contains(TrayMenuKind.applyColorVisionFilter));
      expect(kinds, contains(TrayMenuKind.clearFilter));
      expect(kinds, contains(TrayMenuKind.openSettings));
      expect(kinds, contains(TrayMenuKind.quit));
      expect(kinds, contains(TrayMenuKind.separator));
    });

    test('クイックフィルタごとに apply 項目が 1 つずつ並ぶ', () {
      final spec = buildTrayMenuSpec(loupeVisible: true);
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
      final spec = buildTrayMenuSpec(loupeVisible: true);
      final keys = interactive(spec).map((e) => e.key).toList();

      expect(keys.every((k) => k != null && k.isNotEmpty), isTrue);
      expect(keys.toSet().length, keys.length, reason: 'キーは一意であること');
    });

    test('トグルのラベルとチェックがルーペ表示状態を反映する', () {
      final visible = buildTrayMenuSpec(loupeVisible: true)
          .firstWhere((e) => e.kind == TrayMenuKind.toggleLoupe);
      final hidden = buildTrayMenuSpec(loupeVisible: false)
          .firstWhere((e) => e.kind == TrayMenuKind.toggleLoupe);

      expect(visible.label, 'ルーペ窓を隠す');
      expect(visible.checked, isTrue);
      expect(hidden.label, 'ルーペ窓を表示');
      expect(hidden.checked, isFalse);
    });

    test('アクティブなフィルタだけがチェックされる', () {
      final spec = buildTrayMenuSpec(
        loupeVisible: true,
        activeFilter: ColorVisionType.deuteranopia,
      );

      final checked = spec
          .where((e) =>
              e.kind == TrayMenuKind.applyColorVisionFilter && e.checked)
          .map((e) => e.colorVisionType)
          .toList();

      expect(checked, [ColorVisionType.deuteranopia]);
    });

    test('フィルタ解除はフィルタ無しのときだけチェックされる', () {
      final active = buildTrayMenuSpec(loupeVisible: true)
          .firstWhere((e) => e.kind == TrayMenuKind.clearFilter);
      final inactive = buildTrayMenuSpec(
        loupeVisible: true,
        activeFilter: ColorVisionType.protanopia,
      ).firstWhere((e) => e.kind == TrayMenuKind.clearFilter);

      expect(active.checked, isTrue);
      expect(inactive.checked, isFalse);
    });

    test('末尾は終了項目', () {
      final spec = buildTrayMenuSpec(loupeVisible: true);
      expect(spec.last.kind, TrayMenuKind.quit);
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
}
