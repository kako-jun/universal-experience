// VisionFilterState.bypassed（#63、「押している間だけ原画」ホットキー用）の単体テスト。

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/services/vision_filter_state.dart';

void main() {
  group('VisionFilterState.setBypassed', () {
    test('既定は false', () {
      final state = VisionFilterState();
      expect(state.bypassed, isFalse);
    });

    test('true にすると notifyListeners される', () {
      final state = VisionFilterState();
      var notified = 0;
      state.addListener(() => notified++);

      state.setBypassed(true);

      expect(state.bypassed, isTrue);
      expect(notified, 1);
    });

    test('同じ値を再設定しても notify しない（no-op ガード）', () {
      final state = VisionFilterState();
      var notified = 0;
      state.addListener(() => notified++);

      state.setBypassed(false); // 既定と同じ値
      expect(notified, 0);

      state.setBypassed(true);
      expect(notified, 1);
      state.setBypassed(true); // 既に true
      expect(notified, 1);
    });

    test('選択状態・パラメータ・strength は一切変更しない', () {
      final state = VisionFilterState()
        ..select('cataract')
        ..setStrength(0.42);

      state.setBypassed(true);

      expect(state.selectedId, 'cataract');
      expect(state.strength, 0.42);
      expect(state.build(), isNotNull);

      state.setBypassed(false);
      expect(state.selectedId, 'cataract');
      expect(state.strength, 0.42);
    });
  });

  group('明示的な選択操作は bypassed を解除する (#63)', () {
    test('select() は bypassed を false にする', () {
      final state = VisionFilterState()..setBypassed(true);
      state.select('cataract');
      expect(state.bypassed, isFalse);
    });

    test('selectColorVisionType() (非 none) は bypassed を false にする', () {
      final state = VisionFilterState()..setBypassed(true);
      state.selectColorVisionType(ColorVisionType.protanopia, 'protanopia');
      expect(state.bypassed, isFalse);
    });

    test('selectColorVisionType(none) は bypassed を false にする', () {
      final state = VisionFilterState()..setBypassed(true);
      state.selectColorVisionType(ColorVisionType.none);
      expect(state.bypassed, isFalse);
    });

    test('selectPreset() は bypassed を false にする', () {
      final state = VisionFilterState()..setBypassed(true);
      state.selectPreset('meniere', 'vertigo');
      expect(state.bypassed, isFalse);
    });

    test('clear() は bypassed を false にする', () {
      final state = VisionFilterState()
        ..select('cataract')
        ..setBypassed(true);
      state.clear();
      expect(state.bypassed, isFalse);
    });

    test('setStrength() は bypassed を false にする', () {
      final state = VisionFilterState()
        ..select('cataract')
        ..setBypassed(true);
      state.setStrength(0.5);
      expect(state.bypassed, isFalse);
    });

    test('setParam() は bypassed を false にする', () {
      final state = VisionFilterState()
        ..select('cataract')
        ..setBypassed(true);
      state.setParam('seed', BigInt.from(42));
      expect(state.bypassed, isFalse);
    });

    test('randomizeSeed() は bypassed を false にする', () {
      final state = VisionFilterState()
        ..select('cataract')
        ..setBypassed(true);
      state.randomizeSeed('seed');
      expect(state.bypassed, isFalse);
    });
  });
}
