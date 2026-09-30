// IntensitySlider の状態表示。色覚クイック選択が有効な間は必ず「適用中」を
// 出し、無効（何も選んでいない・advanced フィルタ / 体験プリセットを見ている）
// 間は状態表示を出さずスライダーも操作不能にする。かつて存在した「未適用」表示は、有効なら必ず
// FilterService も適用中になるため到達不能だった（#67 で撤去）。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/services/color_vision_selection.dart';
import 'package:universal_experience/services/filter_service.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/ui/widgets/intensity_slider.dart';

import 'support/vision_filter_metadata_fixture.dart';

void main() {
  const enLocale = Locale('en');
  final en = lookupAppLocalizations(enLocale);

  setUp(installVisionFilterMetadataFixture);
  tearDown(resetVisionFilterMetadataProviders);

  Widget harness(FilterService filterService, VisionFilterState visionState) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider<FilterService>.value(value: filterService),
          ChangeNotifierProvider<VisionFilterState>.value(value: visionState),
        ],
        child: const MaterialApp(
          locale: enLocale,
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: IntensitySlider()),
        ),
      );

  testWidgets('色覚を選んでいる間は「適用中」が出てスライダーを操作できる', (tester) async {
    final visionState = VisionFilterState();
    final filterService = FilterService(visionState: visionState);
    selectColorVision(filterService, visionState, ColorVisionType.protanopia);

    await tester.pumpWidget(harness(filterService, visionState));

    expect(find.text(en.intensityActive), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
  });

  testWidgets('何も選んでいない間は状態表示が無く、スライダーは操作不能', (tester) async {
    final visionState = VisionFilterState();
    final filterService = FilterService(visionState: visionState);

    await tester.pumpWidget(harness(filterService, visionState));

    expect(find.text(en.intensityActive), findsNothing);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
  });

  testWidgets('色覚を解除すると「適用中」が消えてスライダーが操作不能に戻る', (tester) async {
    final visionState = VisionFilterState();
    final filterService = FilterService(visionState: visionState);
    selectColorVision(filterService, visionState, ColorVisionType.deuteranopia);
    await tester.pumpWidget(harness(filterService, visionState));
    expect(find.text(en.intensityActive), findsOneWidget);

    deactivateColorVision(filterService, visionState);
    await tester.pump();

    expect(find.text(en.intensityActive), findsNothing);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
  });

  testWidgets('advanced フィルタを選ぶと、FilterService が色覚を覚えたままでも「適用中」は消えてスライダーは操作不能',
      (tester) async {
    final visionState = VisionFilterState();
    final filterService = FilterService(visionState: visionState);
    selectColorVision(filterService, visionState, ColorVisionType.protanopia);
    await tester.pumpWidget(harness(filterService, visionState));
    expect(find.text(en.intensityActive), findsOneWidget);

    visionState.select('myopia');
    await tester.pump();

    expect(filterService.currentFilter, ColorVisionType.protanopia);
    expect(visionState.isColorQuickSelection, isFalse);
    expect(find.text(en.intensityActive), findsNothing);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
  });

  testWidgets('体験プリセットを選ぶと、FilterService が色覚を覚えたままでも「適用中」は消えてスライダーは操作不能',
      (tester) async {
    final visionState = VisionFilterState();
    final filterService = FilterService(visionState: visionState);
    selectColorVision(filterService, visionState, ColorVisionType.protanopia);
    await tester.pumpWidget(harness(filterService, visionState));
    expect(find.text(en.intensityActive), findsOneWidget);

    visionState.selectPreset('labyrinthitis', 'vertigo');
    await tester.pump();

    expect(filterService.currentFilter, ColorVisionType.protanopia);
    expect(visionState.isColorQuickSelection, isFalse);
    expect(find.text(en.intensityActive), findsNothing);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
  });
}
