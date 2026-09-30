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
import 'package:universal_experience/services/filter_service.dart';
import 'package:universal_experience/services/vision_filter_metadata.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/services/vision_layer.dart';
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

    test('その filter id を advanced で既に記憶していても、プリセットは推奨値を優先する', () {
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
      visionFilterRecommendedStrengthProvider = (filter) => filter ==
              const VisionFilter.tunnelVision(
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

    // #117: 色覚クイック選択の強度は -opia=1.0 / -omaly=0.6（recommendedStrength）
    // から始まり（sensus の推奨値は使わない）、記憶はキー（別名 id ?? カタログ id）
    // ごとに 1 つ。別名（-omaly）と本体（-opia）は別の記憶を持つ。
    test('色覚クイック選択は -opia 1.0 / -omaly 0.6 から始まり、キーごとに記憶する', () {
      visionFilterRecommendedStrengthProvider = (_) => 0.3; // 使われない
      state.selectColorVisionType(ColorVisionType.protanopia, 'protanopia');
      expect(state.strength, 1.0);

      state.setStrength(0.2);
      state.selectColorVisionType(ColorVisionType.none);
      state.selectColorVisionType(ColorVisionType.protanopia, 'protanopia');
      expect(state.strength, 0.2, reason: '外して戻しても記憶は残る');

      state.selectColorVisionType(ColorVisionType.protanomaly, 'protanopia');
      expect(state.strength, kAnomalyDefaultSeverity,
          reason: '-omaly は別キー（protanomaly）なので -opia の記憶を継がない');
      expect(state.strengthForKey('protanopia'), 0.2);
    });
  });

  group('層と強度の導出（#117）', () {
    test('select は advanced 起源の層を 1 つ作り、それにフォーカスする', () {
      state.select('cataract');

      expect(state.layers, hasLength(1));
      expect(state.layers.single.id, 'cataract');
      expect(state.layers.single.origin, VisionLayerOrigin.advanced);
      expect(state.layers.single.variantId, isNull);
      expect(state.focusedId, 'cataract');
      expect(state.focusedLayer, same(state.layers.single));
    });

    test('別のフィルタを選ぶと層は置き換わる（単一選択の挙動は変わらない）', () {
      state.select('cataract');
      state.select('myopia');
      expect([for (final l in state.layers) l.id], ['myopia']);

      state.selectColorVisionType(ColorVisionType.tritanopia, 'tritanopia');
      expect([for (final l in state.layers) l.id], ['tritanopia']);
      expect(state.layers.single.origin, VisionLayerOrigin.quick);

      state.clear();
      expect(state.layers, isEmpty);
      expect(state.focusedId, isNull);
    });

    test('-omaly のクイック選択は別名（variantId）を持つ層になる', () {
      state.selectColorVisionType(
          ColorVisionType.deuteranomaly, 'deuteranopia');

      final layer = state.layers.single;
      expect(layer.id, 'deuteranopia');
      expect(layer.variantId, 'deuteranomaly');
      expect(layer.strengthKey, 'deuteranomaly');
    });

    test('記憶が無い層の強度は推奨強度を導出するだけで、記憶へは書かない', () {
      visionFilterRecommendedStrengthProvider = (_) => 0.45;

      state.select('starbursts');
      expect(state.strength, 0.45);
      state.selectColorVisionType(
          ColorVisionType.deuteranomaly, 'deuteranopia');
      expect(state.strength, kAnomalyDefaultSeverity);

      expect(state.strengthByKey, isEmpty);
    });

    test('記憶があれば推奨強度より優先される（推奨値が変わっても記憶は動かない）', () {
      visionFilterRecommendedStrengthProvider = (_) => 0.45;
      state.select('starbursts');
      state.setStrength(0.9);

      visionFilterRecommendedStrengthProvider = (_) => 0.1;

      expect(state.strength, 0.9);
      expect(state.strengthByKey, {'starbursts': 0.9});
    });

    test('同じ色覚 id の advanced 選択とクイック選択は強度の記憶を共有する', () {
      state.select('protanopia');
      state.setStrength(0.3);

      state.selectColorVisionType(ColorVisionType.protanopia, 'protanopia');

      expect(state.strength, 0.3);
      state.setStrength(0.7);
      state.select('protanopia');
      expect(state.strength, 0.7);
      expect(state.strengthByKey, {'protanopia': 0.7});
    });

    test('setStrength は 0..1 に丸めて記憶し、1 回だけ通知する', () {
      state.select('cataract');
      var notified = 0;
      state.addListener(() => notified++);

      state.setStrength(1.8);
      expect(state.strength, 1.0);
      state.setStrength(-0.2);
      expect(state.strength, 0.0);

      expect(state.strengthByKey, {'cataract': 0.0});
      expect(notified, 2);
    });

    test('setStrengthForKey は選択に関わらず記憶へ書き、選択は動かさない', () {
      state.select('cataract');

      state.setStrengthForKey('protanomaly', 0.25);

      expect(state.strengthForKey('protanomaly'), 0.25);
      expect(state.focusedId, 'cataract');
      expect(state.strength, 1.0, reason: '選択中の層は cataract のまま');
    });

    test('未選択のとき setStrength / setParam / randomizeSeed は何もしない（通知もしない）', () {
      var notified = 0;
      state.addListener(() => notified++);

      state.setStrength(0.3);
      state.setParam('axisDeg', 10.0);
      state.randomizeSeed('seed');

      expect(state.strengthByKey, isEmpty);
      expect(state.layers, isEmpty);
      expect(notified, 0);
    });

    test('selectPreset はそのキーの記憶を消して、推奨強度の導出に戻す', () {
      visionFilterRecommendedStrengthProvider = (_) => 0.6;
      state.select('vertigo');
      state.setStrength(0.9);
      state.setStrengthForKey('protanopia', 0.2);

      state.selectPreset('meniere', 'vertigo');

      expect(state.strengthByKey, {'protanopia': 0.2},
          reason: 'vertigo の記憶だけが消える');
      expect(state.strength, 0.6);
    });

    test('resetToRecommended はフォーカス中のキーの記憶だけを消す', () {
      visionFilterRecommendedStrengthProvider = (_) => 0.4;
      state.select('astigmatism');
      state.setStrength(0.9);
      state.setStrengthForKey('protanopia', 0.2);

      state.resetToRecommended();

      expect(state.strengthByKey, {'protanopia': 0.2});
      expect(state.strength, 0.4);
    });

    test('snapshot は層・フォーカス・記憶を写し、restore で別インスタンスへ戻る', () {
      state.selectColorVisionType(ColorVisionType.tritanomaly, 'tritanopia');
      state.setStrength(0.35);
      state.setStrengthForKey('myopia', 0.8);

      final snap = state.snapshot();
      final other = VisionFilterState()..restore(snap);

      expect(snap.layers.single.variantId, 'tritanomaly');
      expect(snap.focusedId, 'tritanopia');
      expect(snap.strengthByKey, {'tritanomaly': 0.35, 'myopia': 0.8});
      expect(other.colorVisionType, ColorVisionType.tritanomaly);
      expect(other.strength, 0.35);
      expect(other.strengthForKey('myopia'), 0.8);
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
        state.paramValue(state.selectedEntry!.parameters
            .firstWhere((p) => p.name == 'axisDeg')),
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
