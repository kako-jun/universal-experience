// FilterSelector（色覚のクイック選択チップ）の単体テスト（#60）。
//
// 「Normal vision」（[ColorVisionType.none]）チップは、他の色覚チップと違い
// `VisionFilterState.isColorQuickSelection` ではなく
// `VisionFilterState.selectedId == null`（＝何も選択されていない）で点灯を
// 判定する。advanced/プリセットを選択中に「Normal vision」を押すと、
// `VisionFilterState.selectColorVisionType` が既存の選択を常に上書きするため、
// それらの選択もすべて消える（意図した挙動）。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/l10n/l10n_extensions.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/services/color_vision_selection.dart';
import 'package:universal_experience/services/filter_service.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/ui/widgets/filter_selector.dart';

import 'support/vision_filter_metadata_fixture.dart';

void main() {
  late FilterService filterService;
  late VisionFilterState visionState;
  late AppLocalizations en;

  setUp(() {
    installVisionFilterMetadataFixture();
    filterService = FilterService();
    visionState = VisionFilterState();
    en = lookupAppLocalizations(const Locale('en'));
  });
  tearDown(resetVisionFilterMetadataProviders);

  Future<void> pumpSelector(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<FilterService>.value(value: filterService),
          ChangeNotifierProvider<VisionFilterState>.value(value: visionState),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: FilterSelector()),
        ),
      ),
    );
    await tester.pump();
  }

  bool chipSelected(WidgetTester tester, ColorVisionType type) =>
      tester
          .widget<FilterChip>(find.ancestor(
            of: find.text(colorVisionTypeName(en, type)),
            matching: find.byType(FilterChip),
          ))
          .selected;

  testWidgets('初期状態（何も選択していない）では Normal vision チップが点灯する',
      (tester) async {
    await pumpSelector(tester);

    expect(chipSelected(tester, ColorVisionType.none), isTrue);
    expect(chipSelected(tester, ColorVisionType.protanopia), isFalse);
  });

  testWidgets('protanopia を選ぶと Normal vision は消え protanopia が点灯する',
      (tester) async {
    await pumpSelector(tester);

    await tester.tap(find.text(colorVisionTypeName(en, ColorVisionType.protanopia)));
    await tester.pump();

    expect(chipSelected(tester, ColorVisionType.none), isFalse);
    expect(chipSelected(tester, ColorVisionType.protanopia), isTrue);
  });

  testWidgets('advanced を選択中は Normal vision も他の色覚チップも点灯しない',
      (tester) async {
    visionState.select('starbursts');
    await pumpSelector(tester);

    expect(chipSelected(tester, ColorVisionType.none), isFalse,
        reason: 'selectedId が starbursts で null ではないため');
    expect(chipSelected(tester, ColorVisionType.protanopia), isFalse);
  });

  testWidgets(
      'advanced 選択中に Normal vision を押すと advanced の選択も含めてすべて消える '
      '（意図した挙動）', (tester) async {
    visionState.select('starbursts');
    await pumpSelector(tester);
    expect(visionState.selectedId, 'starbursts');

    await tester.tap(find.text(colorVisionTypeName(en, ColorVisionType.none)));
    await tester.pump();

    expect(visionState.selectedId, isNull);
    expect(chipSelected(tester, ColorVisionType.none), isTrue);
  });

  testWidgets('解除ボタンで色覚選択を戻すと Normal vision が点灯する', (tester) async {
    selectColorVision(filterService, visionState, ColorVisionType.protanopia);
    await pumpSelector(tester);
    expect(chipSelected(tester, ColorVisionType.protanopia), isTrue);

    await tester.tap(find.text(en.clearFilter));
    await tester.pump();

    expect(visionState.selectedId, isNull);
    expect(chipSelected(tester, ColorVisionType.none), isTrue);
    expect(chipSelected(tester, ColorVisionType.protanopia), isFalse);
  });
}
