// 右カラム「調整」の層ごとの節（#120）の widget test。
//
// 1 層なら従来どおりの 1 つの節・複数層なら調整中（focusedId）の層だけが展開され、ほかは 1 行に
// たたまれる。受診喚起と強度上限付近の注意は、各層の節ごとにその層単体の入力で出る。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/services/filter_service.dart';
import 'package:universal_experience/services/vision_filter_metadata.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/widgets/adjust_panel.dart';
import 'package:universal_experience/ui/widgets/consult_notice_block.dart';
import 'package:universal_experience/ui/widgets/filter_list_tile.dart';
import 'package:universal_experience/ui/widgets/strength_caution.dart';

import 'support/vision_filter_metadata_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VisionFilterState state;
  late FilterService filterService;

  setUp(() {
    installVisionFilterMetadataFixture();
    state = VisionFilterState();
    filterService = FilterService(visionState: state);
  });
  tearDown(resetVisionFilterMetadataProviders);

  Future<void> pumpPanel(WidgetTester tester, {double height = 2400}) async {
    tester.view.physicalSize = Size(400, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<FilterService>.value(value: filterService),
          ChangeNotifierProvider<VisionFilterState>.value(value: state),
        ],
        child: const MaterialApp(
          locale: Locale('ja'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(child: AdjustPanel()),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder section(String id) => find.byKey(ValueKey('layer_section_$id'));

  group('1 層（従来どおり）', () {
    testWidgets('番号の丸も折りたたみ行も出さず、スライダーは 1 本', (tester) async {
      state.toggle('myopia');
      await pumpPanel(tester);
      expect(find.byType(LayerOrderBadge), findsNothing);
      expect(section('myopia'), findsNothing);
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('何も選んでいないと空状態', (tester) async {
      await pumpPanel(tester);
      expect(find.text('何も選択されていません'), findsOneWidget);
      expect(find.byType(Slider), findsNothing);
    });
  });

  group('複数層の節', () {
    testWidgets('調整中の層だけ展開し、ほかは 1 行にたたむ（適用順の番号つき）', (tester) async {
      state.toggle('glaucoma');
      state.toggle('myopia');
      state.toggle('cataract'); // 最後に足した層が調整中
      await pumpPanel(tester);

      expect(state.focusedId, 'cataract');
      expect(find.byType(Slider), findsOneWidget,
          reason: '強度スライダーは展開中の層の 1 本だけ');
      expect(section('cataract'), findsNothing);
      expect(section('myopia'), findsOneWidget);
      expect(section('glaucoma'), findsOneWidget);
      // 番号は適用順（段の順）で 1..3 がすべて出る。
      expect(find.byType(LayerOrderBadge), findsNWidgets(3));
      for (final n in ['1', '2', '3']) {
        expect(
          find.descendant(
              of: find.byType(LayerOrderBadge), matching: find.text(n)),
          findsOneWidget,
        );
      }
    });

    testWidgets('たたんだ行を押すとその層が調整中になり、展開が入れ替わる', (tester) async {
      state.toggle('myopia');
      state.toggle('glaucoma');
      await pumpPanel(tester);
      expect(state.focusedId, 'glaucoma');
      expect(section('myopia'), findsOneWidget);

      await tester.tap(section('myopia'));
      await tester.pump();

      expect(state.focusedId, 'myopia');
      expect(section('myopia'), findsNothing);
      expect(section('glaucoma'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(state.layers.length, 2, reason: '層は変わらない');
    });

    testWidgets('たたんだ行に強さを出し、スライダーは調整中の層の強さだけを動かす', (tester) async {
      state.toggle('myopia');
      state.toggle('glaucoma');
      state.setLayerStrength('myopia', 0.4);
      state.focusLayer('glaucoma');
      await pumpPanel(tester);

      expect(
        find.descendant(of: section('myopia'), matching: find.text('40%')),
        findsOneWidget,
      );
      final glaucomaBefore =
          state.strengthOf(state.layers.firstWhere((l) => l.id == 'glaucoma'));

      await tester.tap(find.byType(Slider)); // 中央 = 50%
      await tester.pump();

      final myopia = state.layers.firstWhere((l) => l.id == 'myopia');
      final glaucoma = state.layers.firstWhere((l) => l.id == 'glaucoma');
      expect(state.strengthOf(myopia), 0.4, reason: 'たたんだ層は動かない');
      expect(state.strengthOf(glaucoma), isNot(glaucomaBefore));
      expect(state.strengthOf(glaucoma), closeTo(0.5, 0.06));
      expect(state.focusedId, 'glaucoma');
    });
  });

  group('受診喚起（各層の節ごと・その層単体）', () {
    setUp(() {
      visionFilterUrgencyProvider = (f) => switch (f) {
            VisionFilter_Vertigo() => Urgency.earlyConsultation,
            VisionFilter_Myopia() => Urgency.emergency,
            _ => Urgency.none,
          };
    });

    testWidgets('喚起のある層の節にだけ出る（展開中もたたまれていても）', (tester) async {
      state.toggle('vertigo');
      state.toggle('myopia');
      state.toggle('glaucoma'); // 喚起なし・調整中
      await pumpPanel(tester);

      // vertigo・myopia はたたまれているが、それぞれの喚起は出る。
      expect(find.byType(ConsultNoticeBlock), findsNWidgets(2));
    });

    testWidgets('喚起は層ごとの単体入力で、合成しない（最も強い方 1 つに畳まない）', (tester) async {
      state.toggle('vertigo');
      state.toggle('myopia');
      await pumpPanel(tester);

      final blocks = tester
          .widgetList<ConsultNoticeBlock>(find.byType(ConsultNoticeBlock))
          .toList();
      expect(blocks.map((b) => b.notice.urgency).toSet(), {
        Urgency.earlyConsultation,
        Urgency.emergency,
      });
    });

    testWidgets('喚起の無い層だけなら出ない', (tester) async {
      state.toggle('glaucoma');
      state.toggle('cataract');
      await pumpPanel(tester);
      expect(find.byType(ConsultNoticeBlock), findsNothing);
    });
  });

  group('強度上限付近の注意（#66）も層の節ごと', () {
    testWidgets('たたまれた層が上限付近のときだけ、その節に注意が出る', (tester) async {
      state.toggle('tunnel_vision');
      state.setLayerStrength('tunnel_vision', 0.9);
      state.toggle('glaucoma');
      await pumpPanel(tester);
      expect(state.focusedId, 'glaucoma');
      expect(section('tunnel_vision'), findsOneWidget);
      expect(find.byType(StrengthCautionNote), findsOneWidget);

      state.setLayerStrength('tunnel_vision', 0.5);
      state.focusLayer('glaucoma');
      await tester.pump();
      expect(find.byType(StrengthCautionNote), findsNothing,
          reason: 'たたまれた層は、上限付近でなければ印の説明を出さない');
    });

    testWidgets('調整中の層が tunnel_vision ならスライダーの下に注意が出る', (tester) async {
      state.toggle('glaucoma');
      state.toggle('tunnel_vision');
      await pumpPanel(tester);
      expect(state.focusedId, 'tunnel_vision');
      expect(find.byType(StrengthCautionNote), findsOneWidget);
    });
  });

  group('アクセシビリティ', () {
    testWidgets('たたんだ行は 48dp 以上で、順番・名前・強さを読み上げる', (tester) async {
      final handle = tester.ensureSemantics();
      state.toggle('myopia');
      state.toggle('glaucoma');
      await pumpPanel(tester);

      expect(
          tester.getSize(section('myopia')).height, greaterThanOrEqualTo(48));
      expect(
        find.bySemanticsLabel(RegExp(r'^適用順 \d 番目、.+、強さ \d+%$')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });
}
