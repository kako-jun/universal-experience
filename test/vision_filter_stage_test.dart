// 段（stage）表と適用順（#117 / ADR「4. 適用順は段で決める」）のテスト。

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/models/vision_filter_catalog.dart';
import 'package:universal_experience/models/vision_filter_stage.dart';

void main() {
  test('カタログの 30 フィルタがすべて、ちょうど 1 つの段に入る', () {
    final tableIds = [
      for (final stage in VisionFilterStage.values)
        ...kVisionFilterStageOrder[stage]!,
    ];

    expect(kVisionFilterCatalog, hasLength(30));
    expect(tableIds, hasLength(30));
    expect(tableIds.toSet(), hasLength(30), reason: '同じ id が複数の段に入っていない');
    expect(tableIds.toSet(), {for (final e in kVisionFilterCatalog) e.id});
  });

  test('段の宣言順が適用順で、全段が表に載っている', () {
    expect(
        kVisionFilterStageOrder.keys.toSet(), VisionFilterStage.values.toSet());
    expect(VisionFilterStage.values, [
      VisionFilterStage.motion,
      VisionFilterStage.optics,
      VisionFilterStage.media,
      VisionFilterStage.retina,
      VisionFilterStage.visualField,
      VisionFilterStage.perception,
      VisionFilterStage.colorVision,
    ]);
  });

  test('段内の順は sensus の宣言順（ue のカタログの表示順とは別）', () {
    expect(kVisionFilterStageOrder[VisionFilterStage.optics], [
      'myopia',
      'hyperopia',
      'astigmatism',
      'presbyopia',
      'cataract',
      'photophobia',
      'diplopia',
      'starbursts',
      'eye_strain',
      'dry_eye',
    ]);
    expect(kVisionFilterStageOrder[VisionFilterStage.colorVision], [
      'protanopia',
      'deuteranopia',
      'tritanopia',
      'achromatopsia',
      'tetrachromacy',
    ]);
  });

  test('visionFilterApplyOrder は 0..29 の一意な通し番号で、段をまたいで単調', () {
    final orders = <int>[];
    for (final stage in VisionFilterStage.values) {
      for (final id in kVisionFilterStageOrder[stage]!) {
        orders.add(visionFilterApplyOrder(id)!);
      }
    }
    expect(orders, List<int>.generate(30, (i) => i));
  });

  test('visionFilterStageOf は表どおりの段を返し、表に無い id は null', () {
    expect(visionFilterStageOf('vertigo'), VisionFilterStage.motion);
    expect(visionFilterStageOf('myopia'), VisionFilterStage.optics);
    expect(visionFilterStageOf('floaters'), VisionFilterStage.media);
    expect(visionFilterStageOf('detail_loss'), VisionFilterStage.retina);
    expect(visionFilterStageOf('tunnel_vision'), VisionFilterStage.visualField);
    expect(visionFilterStageOf('teichopsia'), VisionFilterStage.perception);
    expect(visionFilterStageOf('tetrachromacy'), VisionFilterStage.colorVision);
    expect(visionFilterStageOf('removed_in_sensus'), isNull);
    expect(visionFilterApplyOrder('removed_in_sensus'), isNull);
  });

  test('色覚は最後の段で、グループはカタログの colorVision カテゴリと一致する', () {
    final colorVisionIds = {
      for (final e in kVisionFilterCatalog)
        if (e.category == VisionFilterCategory.colorVision) e.id,
    };
    expect(colorVisionIds, hasLength(5));
    expect(colorVisionIds,
        kVisionFilterStageOrder[VisionFilterStage.colorVision]!.toSet());
    for (final e in kVisionFilterCatalog) {
      expect(isVisionColorGroupId(e.id), colorVisionIds.contains(e.id),
          reason: e.id);
    }
    expect(isVisionColorGroupId('removed_in_sensus'), isFalse);

    final lastNonColor = kVisionFilterCatalog
        .where((e) => !colorVisionIds.contains(e.id))
        .map((e) => visionFilterApplyOrder(e.id)!)
        .reduce((a, b) => a > b ? a : b);
    final firstColor = colorVisionIds
        .map((id) => visionFilterApplyOrder(id)!)
        .reduce((a, b) => a < b ? a : b);
    expect(firstColor, greaterThan(lastNonColor));
  });

  test('同時に重ねられる層の上限は 5', () {
    expect(kMaxVisionLayers, 5);
  });
}
