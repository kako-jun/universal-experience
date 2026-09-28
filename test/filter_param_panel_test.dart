// FilterParamPanel の strength スライダー表示/非表示の単体テスト（#60）。
//
// 色覚クイック選択由来の選択（`VisionFilterState.isColorQuickSelection`）
// では、実際の強度は #57 のタイプ別記憶（FilterService）が決めるため、
// FilterParamPanel の strength スライダーを動かしても反映されない。
// advanced カタログ・体験プリセット由来の選択では、`VisionFilterState.
// strength` がそのまま使われるのでスライダーを表示する（`preview_selection.
// dart` の `showsAdvancedStrengthSlider`）。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/ui/widgets/filter_param_panel.dart';

void main() {
  late VisionFilterState visionState;

  setUp(() {
    visionState = VisionFilterState();
  });

  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<VisionFilterState>.value(
        value: visionState,
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: FilterParamPanel()),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('advanced カタログ由来の選択では strength スライダーを表示する', (tester) async {
    // protanopia は payload を持たないため、Slider は strength 用の 1 本だけ
    // になる（他パラメータのスライダーと混同しない）。
    visionState.select('protanopia');
    expect(visionState.isColorQuickSelection, isFalse);

    await pumpPanel(tester);

    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('体験プリセット由来の選択でも strength スライダーを表示する', (tester) async {
    visionState.selectPreset('vestibular_neuritis', 'vestibular_neuritis');
    expect(visionState.isColorQuickSelection, isFalse);

    await pumpPanel(tester);

    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('色覚クイック選択由来の選択では strength スライダーを表示しない', (tester) async {
    visionState.selectColorVisionType(ColorVisionType.protanopia, 'protanopia');
    expect(visionState.isColorQuickSelection, isTrue);

    await pumpPanel(tester);

    expect(find.byType(Slider), findsNothing);
    // urgency 表示など、パネル自体は描画され続けている（strength だけが
    // 隠れている）ことも確認する。
    expect(find.byType(FilterParamPanel), findsOneWidget);
  });
}
