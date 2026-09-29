// VisionFilterState の bypass（#63「押している間だけ原画」ホットキー用、#79 で
// 入力元ごとの保持（holder）に変更）の単体テスト。

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/services/vision_filter_state.dart';

import 'support/vision_filter_metadata_fixture.dart';

void main() {
  setUp(installVisionFilterMetadataFixture);
  tearDown(resetVisionFilterMetadataProviders);

  group('VisionFilterState.acquireBypass / releaseBypass', () {
    test('既定は false', () {
      final state = VisionFilterState();
      expect(state.bypassed, isFalse);
    });

    test('acquireBypass すると notifyListeners され、bypassed が true になる', () {
      final state = VisionFilterState();
      var notified = 0;
      state.addListener(() => notified++);

      state.acquireBypass('a');

      expect(state.bypassed, isTrue);
      expect(notified, 1);
    });

    test('同じ holder を再度 acquire しても notify しない（冪等）', () {
      final state = VisionFilterState();
      var notified = 0;
      state.addListener(() => notified++);

      state.acquireBypass('a');
      expect(notified, 1);
      state.acquireBypass('a');
      expect(notified, 1, reason: '同じ holder の再 acquire は no-op');
    });

    test('保持していない holder を release しても notify しない（冪等）', () {
      final state = VisionFilterState();
      var notified = 0;
      state.addListener(() => notified++);

      state.releaseBypass('a');

      expect(notified, 0);
      expect(state.bypassed, isFalse);
    });

    test('releaseBypass すると bypassed が false に戻る', () {
      final state = VisionFilterState();
      state.acquireBypass('a');
      expect(state.bypassed, isTrue);

      state.releaseBypass('a');
      expect(state.bypassed, isFalse);
    });

    test('選択状態・パラメータ・strength は一切変更しない', () {
      final state = VisionFilterState()
        ..select('cataract')
        ..setStrength(0.42);

      state.acquireBypass('a');

      expect(state.selectedId, 'cataract');
      expect(state.strength, 0.42);
      expect(state.build(), isNotNull);

      state.releaseBypass('a');
      expect(state.selectedId, 'cataract');
      expect(state.strength, 0.42);
    });
  });

  group('入力元ごとの保持 (#79 レビュー M3)', () {
    test('2 つの holder が保持している間は、片方を release しても bypassed のまま', () {
      final state = VisionFilterState();

      // ホットキー押下 → HUD 押下。
      state.acquireBypass('hotkey');
      expect(state.bypassed, isTrue);
      state.acquireBypass('hud');
      expect(state.bypassed, isTrue);

      // HUD を離す。ホットキーがまだ保持しているので bypassed のまま。
      state.releaseBypass('hud');
      expect(state.bypassed, isTrue, reason: 'ホットキーがまだ保持している');

      // ホットキーも離せば、ようやく false。
      state.releaseBypass('hotkey');
      expect(state.bypassed, isFalse);
    });

    test('逆順（HUD 押下 → ホットキー押下 → ホットキーを離す）でも同様', () {
      final state = VisionFilterState();

      state.acquireBypass('hud');
      expect(state.bypassed, isTrue);
      state.acquireBypass('hotkey');
      expect(state.bypassed, isTrue);

      state.releaseBypass('hotkey');
      expect(state.bypassed, isTrue, reason: 'HUD がまだ保持している');

      state.releaseBypass('hud');
      expect(state.bypassed, isFalse);
    });
  });

  group('clearBypass (#79)', () {
    test('複数 holder があっても一括で解除する', () {
      final state = VisionFilterState();
      state.acquireBypass('hotkey');
      state.acquireBypass('hud');
      expect(state.bypassed, isTrue);

      state.clearBypass();

      expect(state.bypassed, isFalse);
    });

    test('保持者が居ないときは notify しない（no-op）', () {
      final state = VisionFilterState();
      var notified = 0;
      state.addListener(() => notified++);

      state.clearBypass();

      expect(notified, 0);
    });
  });

  group('明示的な選択操作は全 holder を解除する (#63/#79)', () {
    test('select() は bypassed を false にする', () {
      final state = VisionFilterState()..acquireBypass('a');
      state.select('cataract');
      expect(state.bypassed, isFalse);
    });

    test('selectColorVisionType() (非 none) は bypassed を false にする', () {
      final state = VisionFilterState()..acquireBypass('a');
      state.selectColorVisionType(ColorVisionType.protanopia, 'protanopia');
      expect(state.bypassed, isFalse);
    });

    test('selectColorVisionType(none) は bypassed を false にする', () {
      final state = VisionFilterState()..acquireBypass('a');
      state.selectColorVisionType(ColorVisionType.none);
      expect(state.bypassed, isFalse);
    });

    test('selectPreset() は bypassed を false にする', () {
      final state = VisionFilterState()..acquireBypass('a');
      state.selectPreset('meniere', 'vertigo');
      expect(state.bypassed, isFalse);
    });

    test('clear() は bypassed を false にする', () {
      final state = VisionFilterState()
        ..select('cataract')
        ..acquireBypass('a');
      state.clear();
      expect(state.bypassed, isFalse);
    });

    test('setStrength() は bypassed を false にする', () {
      final state = VisionFilterState()
        ..select('cataract')
        ..acquireBypass('a');
      state.setStrength(0.5);
      expect(state.bypassed, isFalse);
    });

    test('setParam() は bypassed を false にする', () {
      final state = VisionFilterState()
        ..select('cataract')
        ..acquireBypass('a');
      state.setParam('seed', BigInt.from(42));
      expect(state.bypassed, isFalse);
    });

    test('randomizeSeed() は bypassed を false にする', () {
      final state = VisionFilterState()
        ..select('cataract')
        ..acquireBypass('a');
      state.randomizeSeed('seed');
      expect(state.bypassed, isFalse);
    });

    test('複数 holder があっても、選択操作は一括で解除する', () {
      final state = VisionFilterState()
        ..acquireBypass('hotkey')
        ..acquireBypass('hud');
      expect(state.bypassed, isTrue);

      state.select('cataract');

      expect(state.bypassed, isFalse);
    });
  });
}
