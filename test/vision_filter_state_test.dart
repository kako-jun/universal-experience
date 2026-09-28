// VisionFilterState の単体テスト。#60 で追加した挙動のうち、他のテスト
// ファイルで直接カバーされていないものに絞る:
// - selectPreset は strength を 1.0 に戻す（#60。推奨値の導入は #77）。
// - プリセット選択中に setParam/setStrength/randomizeSeed を呼ぶと、
//   プリセットの選択表示（selectedPresetId）だけが解除され、フィルタ自体の
//   選択は残る（#60）。
// - selectColorVisionType(type, catalogId) は catalogId が必須（none を除く）。
//
// 選択の起源（isColorQuickSelection/colorVisionType）まわりの契約は
// test/color_vision_selection_test.dart と test/experience_presets_test.dart
// が担うので、ここでは重複させない。

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/services/vision_filter_state.dart';

void main() {
  late VisionFilterState state;

  setUp(() {
    state = VisionFilterState();
  });

  group('selectPreset の strength リセット (#60)', () {
    test('advanced で strength を変えたあとにプリセットを選ぶと 1.0 に戻る', () {
      state.select('starbursts');
      state.setStrength(0.3);
      expect(state.strength, 0.3);

      state.selectPreset('meniere', 'vertigo');

      expect(state.strength, 1.0);
    });
  });

  group('プリセット選択中の customize (#60)', () {
    test('setParam を呼ぶと selectedPresetId は解除されるが selectedId は残る', () {
      state.selectPreset('bppv', 'bppv_rotation');
      expect(state.selectedPresetId, 'bppv');

      // bppv_rotation 自体は parameters を持たないが、契約検証には任意の
      // パラメータ名で十分（setParam は名前の妥当性を検証しない）。
      state.setParam('dummy', 1.0);

      expect(state.selectedPresetId, isNull,
          reason: 'strength/param を手動で弄った時点でプリセットそのものではなくなる');
      expect(state.selectedId, 'bppv_rotation',
          reason: 'フィルタの選択自体は解除しない（プリセットのフィルタを起点に'
              'カスタマイズしているだけ）');
    });

    test('setStrength を呼んでも selectedPresetId は解除されるが selectedId は残る', () {
      state.selectPreset('meniere', 'vertigo');
      expect(state.selectedPresetId, 'meniere');

      state.setStrength(0.5);

      expect(state.selectedPresetId, isNull);
      expect(state.selectedId, 'vertigo');
    });

    test('プリセット選択中でなければ setParam/setStrength は何もしない（例外にならない）', () {
      state.select('starbursts');
      expect(state.selectedPresetId, isNull);

      state.setStrength(0.7);
      state.setParam('numRays', 8);

      expect(state.selectedPresetId, isNull);
      expect(state.selectedId, 'starbursts');
    });

    test('randomizeSeed を呼んでも selectedPresetId は解除されるが selectedId は残る', () {
      // meniere/bppv/vestibular_neuritis のプリセットはどれも seed パラメータを
      // 持たないため、seed を持つカタログエントリ（cataract）を使って
      // プリセット経由の選択を模す。
      state.selectPreset('dummy-preset', 'cataract');
      expect(state.selectedPresetId, 'dummy-preset');

      state.randomizeSeed('seed');

      expect(state.selectedPresetId, isNull);
      expect(state.selectedId, 'cataract');
    });
  });

  group('selectColorVisionType の catalogId 必須チェック', () {
    test('type が none 以外で catalogId を省略すると ArgumentError', () {
      expect(
        () => state.selectColorVisionType(ColorVisionType.protanopia),
        throwsArgumentError,
      );
    });

    test('type が none なら catalogId を省略できる', () {
      state.select('starbursts');

      state.selectColorVisionType(ColorVisionType.none);

      expect(state.selectedId, isNull);
      expect(state.isColorQuickSelection, isFalse);
      expect(state.colorVisionType, isNull);
    });
  });
}
