// VisionFilterState の単体テスト。#60/#77 で追加した挙動のうち、他のテスト
// ファイルで直接カバーされていないものに絞る:
// - selectPreset は strength を sensus の推奨値に戻す（#60 で入れた「1.0 に戻す」
//   を #77 で置き換えた）。
// - フィルタ id ごとに強度・パラメータを記憶し、初めて選ぶフィルタは推奨値
//   （recommended_strength）から始まる（#77）。
// - 「推奨値に戻す」（resetToRecommended）は強度・パラメータの両方を戻す（#77）。
// - プリセット選択中に setParam/setStrength/randomizeSeed を呼ぶと、
//   プリセットの選択表示（selectedPresetId）だけが解除され、フィルタ自体の
//   選択は残る（#60）。
// - selectColorVisionType(type, catalogId) は catalogId が必須（none を除く）。
//
// 選択の起源（isColorQuickSelection/colorVisionType）まわりの契約は
// test/color_vision_selection_test.dart と test/experience_presets_test.dart
// が担うので、ここでは重複させない。
//
// urgency/urgency_escalation/recommended_strength は sensus ブリッジ（#76/#77）
// を要求するため、実ブリッジ非対応の flutter test ではフィクスチャに差し替える
// （test/support/vision_filter_metadata_fixture.dart）。

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/services/vision_filter_metadata.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';

import 'support/vision_filter_metadata_fixture.dart';

void main() {
  late VisionFilterState state;

  setUp(() {
    installVisionFilterMetadataFixture();
    state = VisionFilterState();
  });
  tearDown(resetVisionFilterMetadataProviders);

  group('selectPreset の strength リセット (#60/#77)', () {
    test('advanced で strength を変えたあとにプリセットを選ぶと推奨値に戻る', () {
      visionFilterRecommendedStrengthProvider = (_) => 0.6;
      state.select('starbursts');
      state.setStrength(0.3);
      expect(state.strength, 0.3);

      state.selectPreset('meniere', 'vertigo');

      expect(state.strength, 0.6);
    });

    test('その filter id を advanced で既に記憶していても、プリセットは推奨値を優先する',
        () {
      visionFilterRecommendedStrengthProvider = (_) => 0.6;
      // advanced 経由で vertigo を選び、独自に 0.9 へカスタマイズして記憶させる。
      state.select('vertigo');
      state.setStrength(0.9);
      state.clear();

      // プリセット経由で同じカタログ id (vertigo) を選ぶと、advanced の記憶
      // （0.9）ではなく推奨値（0.6）になる（#77: プリセットは代表的な程度を
      // 常に見せる）。
      state.selectPreset('meniere', 'vertigo');

      expect(state.strength, 0.6);
    });
  });

  group('フィルタごとの強度・パラメータの記憶 (#77)', () {
    test('初めて選ぶフィルタは推奨値から始まる', () {
      visionFilterRecommendedStrengthProvider = (filter) =>
          filter == const VisionFilter.tunnelVision(
                  fieldLossMode: VisionFieldLossMode.darken)
              ? 0.5
              : 1.0;

      state.select('tunnel_vision');

      expect(state.strength, 0.5);
    });

    test('強度・パラメータを変更後、別フィルタへ切り替えてから戻すと保持されている', () {
      state.select('astigmatism');
      state.setStrength(0.8);
      state.setParam('axisDeg', 45.0);

      state.select('cataract'); // 別フィルタへ切り替え
      expect(state.strength, 1.0); // cataract は初めてなので推奨値（fixture既定1.0）

      state.select('astigmatism'); // astigmatism に戻す

      expect(state.strength, 0.8);
      expect(
        state.paramValue(state.selectedEntry!.parameters
            .firstWhere((p) => p.name == 'axisDeg')),
        45.0,
      );
    });

    test('randomizeSeed で更新した seed もフィルタ切り替え後に保持される', () {
      state.select('cataract');
      state.randomizeSeed('seed');
      final seed = state.paramValue(state.selectedEntry!.parameters.first);

      state.select('astigmatism');
      state.select('cataract');

      expect(state.paramValue(state.selectedEntry!.parameters.first), seed);
    });

    // #76 レビュー N10: このテストの意図は「色覚クイック選択でもプレビュー
    // 強度が #77 のフィルタ別記憶に従う」ことではない — production の
    // プレビュー強度は色覚クイック選択のとき常に FilterService のタイプ別
    // 記憶（#57）を使い、この state.strength は使われない
    // （`preview_selection.dart` の `previewStrength` 参照）。ここで見たいのは
    // 「selectColorVisionType も内部的には _selectInternal を経由するので、
    // 同じ記憶ロジック（_strengthById）が selectColorVisionType 経由でも
    // 一貫して働く」という、実装の共有経路そのものの回帰である
    // （advanced 経由の select() と選択元が違うだけで、記憶の仕組みは
    // 分岐させていないことの検証）。
    test('色覚クイック選択（selectColorVisionType）経由でも _strengthById の記憶ロジックは一貫して働く', () {
      visionFilterRecommendedStrengthProvider = (_) => 0.6;
      state.selectColorVisionType(ColorVisionType.protanopia, 'protanopia');
      expect(state.strength, 0.6);

      state.setStrength(0.2);
      state.selectColorVisionType(ColorVisionType.none);
      state.selectColorVisionType(ColorVisionType.protanopia, 'protanopia');

      expect(state.strength, 0.2);
    });
  });

  group('resetToRecommended (#77)', () {
    test('強度・パラメータを推奨値・既定値に戻す', () {
      visionFilterRecommendedStrengthProvider = (_) => 0.4;
      state.select('astigmatism');
      state.setStrength(0.9);
      state.setParam('axisDeg', 10.0);

      state.resetToRecommended();

      expect(state.strength, 0.4);
      expect(
        state.paramValue(
            state.selectedEntry!.parameters.firstWhere((p) => p.name == 'axisDeg')),
        90.0, // カタログの axisDeg 既定値
      );
    });

    test('未選択なら何もしない（例外にならない）', () {
      expect(state.selectedId, isNull);
      expect(() => state.resetToRecommended(), returnsNormally);
      expect(state.selectedId, isNull);
    });

    test('プリセット選択中に呼ぶとプリセットの選択表示は解除される', () {
      state.selectPreset('meniere', 'vertigo');
      expect(state.selectedPresetId, 'meniere');

      state.resetToRecommended();

      expect(state.selectedPresetId, isNull);
      expect(state.selectedId, 'vertigo');
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
