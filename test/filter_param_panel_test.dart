// FilterParamPanel の widget test（#60 の strength スライダー表示/非表示 +
// #76/#77 の受診喚起ブロック・推奨値リセット）。
//
// 色覚クイック選択由来の選択（`VisionFilterState.isColorQuickSelection`）
// では、実際の強度は #57 のタイプ別記憶（FilterService）が決めるため、
// FilterParamPanel の strength スライダーを動かしても反映されない。
// advanced カタログ・体験プリセット由来の選択では、`VisionFilterState.
// strength` がそのまま使われるのでスライダーを表示する（`preview_selection.
// dart` の `showsAdvancedStrengthSlider`）。
//
// #76: 受診喚起は sensus ブリッジ（`visionFilterUrgencyProvider` /
// `visionFilterUrgencyEscalationProvider`）を唯一の正本にする。実ブリッジは
// native lib を要求し flutter test では呼べないため、フィクスチャで差し替える
// （`test/support/vision_filter_metadata_fixture.dart`）。UI には段階名（旧
// 「緊急度：高」）を一切出さないことも検証する。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/services/vision_filter_metadata.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/widgets/filter_param_panel.dart';

import 'support/vision_filter_metadata_fixture.dart';

void main() {
  late VisionFilterState visionState;

  setUp(() {
    installVisionFilterMetadataFixture();
    visionState = VisionFilterState();
  });
  tearDown(resetVisionFilterMetadataProviders);

  Future<void> pumpPanel(WidgetTester tester, {Locale? locale}) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<VisionFilterState>.value(
        value: visionState,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: FilterParamPanel()),
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

  testWidgets('色覚クイック選択由来の選択でも strength スライダーは 1 本だけ表示する（#120）',
      (tester) async {
    visionState.selectColorVisionType(ColorVisionType.protanopia, 'protanopia');
    expect(visionState.isColorQuickSelection, isTrue);

    await pumpPanel(tester);

    expect(find.byType(Slider), findsOneWidget);
    expect(find.byType(FilterParamPanel), findsOneWidget);
  });

  testWidgets('strength スライダーは調整中の層の強度の記憶を動かし、原画比較を解除する', (tester) async {
    visionState.selectColorVisionType(ColorVisionType.protanopia, 'protanopia');
    visionState.toggle('myopia');
    visionState.focusLayer('protanopia');
    visionState.acquireBypass(Object());
    expect(visionState.bypassed, isTrue);
    await pumpPanel(tester);

    await tester.tap(find.byType(Slider)); // 中央 = 50%
    await tester.pump();

    final protan = visionState.layers.firstWhere((l) => l.id == 'protanopia');
    expect(visionState.strengthOf(protan), closeTo(0.5, 0.06));
    expect(visionState.bypassed, isFalse);
    expect(visionState.focusedId, 'protanopia');
  });

  group('受診喚起ブロック（#76）', () {
    testWidgets('urgency=none かつ escalation なしでは何も表示しない', (tester) async {
      visionFilterUrgencyProvider = (_) => Urgency.none;
      visionFilterUrgencyEscalationProvider = (_) => const [];
      visionState.select('protanopia');

      await pumpPanel(tester);
      final en = lookupAppLocalizations(const Locale('en'));

      expect(find.text(en.consultEarly), findsNothing);
      expect(find.text(en.consultEmergency), findsNothing);
      expect(find.text(en.consultDisclaimer), findsNothing);
    });

    testWidgets('urgency=emergency では喚起文と免責文を表示し、段階名は出さない',
        (tester) async {
      visionFilterUrgencyProvider = (_) => Urgency.emergency;
      visionFilterUrgencyEscalationProvider = (_) => const [];
      visionState.select('hemianopia');

      await pumpPanel(tester);
      final en = lookupAppLocalizations(const Locale('en'));

      expect(find.text(en.consultEmergency), findsOneWidget);
      expect(find.text(en.consultDisclaimer), findsOneWidget);
      // 旧「緊急度：高」のような段階名は一切出ない。
      expect(find.textContaining('Urgency'), findsNothing);
      expect(find.text('High'), findsNothing);
    });

    testWidgets('escalation は「次の場合は受診を」の形で併記し、訳があれば日本語になる',
        (tester) async {
      visionFilterUrgencyProvider = (_) => Urgency.none;
      visionFilterUrgencyEscalationProvider = (_) => const [
            UrgencyEscalation(
              urgency: Urgency.earlyConsultation,
              condition: 'recurrent or severe episodes',
            ),
          ];
      visionState.select('bppv_rotation');

      await pumpPanel(tester, locale: const Locale('ja'));
      final ja = lookupAppLocalizations(const Locale('ja'));

      // urgency=none なので喚起文そのものは出ないが、escalation ブロックは出る。
      expect(find.text(ja.consultEarly), findsNothing);
      expect(find.text(ja.escalationHeaderEarly), findsOneWidget);
      expect(
        find.textContaining(ja.escalationConditionBppvRecurrentSevere),
        findsOneWidget,
      );
    });

    testWidgets('訳の対応表に無い condition は英語のままフォールバック表示する',
        (tester) async {
      const unknownCondition = 'a brand-new sensus condition string';
      visionFilterUrgencyProvider = (_) => Urgency.earlyConsultation;
      visionFilterUrgencyEscalationProvider = (_) => const [
            UrgencyEscalation(
              urgency: Urgency.emergency,
              condition: unknownCondition,
            ),
          ];
      visionState.select('teichopsia');

      await pumpPanel(tester);

      expect(find.textContaining(unknownCondition), findsOneWidget);
    });

    testWidgets(
        'escalation は emergency と earlyConsultation で見出しを分けて表示する',
        (tester) async {
      // 現状 vision フィルタの escalation は全て earlyConsultation だが、
      // ConsultNoticeBlock 自体は聴覚側（#80、emergency 段を持つ）にも備えて
      // 両方の見出しを持つため、フィクスチャで両段を同時に発生させて検証する。
      visionFilterUrgencyProvider = (_) => Urgency.none;
      visionFilterUrgencyEscalationProvider = (_) => const [
            UrgencyEscalation(
              urgency: Urgency.emergency,
              condition: 'a sudden drop in hearing, especially in one ear '
                  '(possible sudden sensorineural hearing loss)',
            ),
            UrgencyEscalation(
              urgency: Urgency.earlyConsultation,
              condition: 'recurrent or severe episodes',
            ),
          ];
      visionState.select('bppv_rotation');

      await pumpPanel(tester);
      final en = lookupAppLocalizations(const Locale('en'));

      expect(find.text(en.escalationHeaderEmergency), findsOneWidget);
      expect(find.text(en.escalationHeaderEarly), findsOneWidget);
      expect(
        find.textContaining(en.escalationConditionHearingSuddenOneEar),
        findsOneWidget,
      );
      expect(
        find.textContaining(en.escalationConditionBppvRecurrentSevere),
        findsOneWidget,
      );
    });

    testWidgets('emergency の喚起文は本文（bodyMedium）より大きいスタイルで表示する',
        (tester) async {
      visionFilterUrgencyProvider = (_) => Urgency.emergency;
      visionFilterUrgencyEscalationProvider = (_) => const [];
      visionState.select('hemianopia');

      await pumpPanel(tester);
      final en = lookupAppLocalizations(const Locale('en'));

      final messageWidget =
          tester.widget<Text>(find.text(en.consultEmergency));
      final theme = Theme.of(tester.element(find.text(en.consultEmergency)));
      final bodySize = theme.textTheme.bodyMedium?.fontSize ?? 0;
      final messageSize = messageWidget.style?.fontSize ??
          theme.textTheme.titleSmall?.fontSize ??
          0;
      expect(messageSize, greaterThan(bodySize));
    });

    testWidgets('免責文の根拠 URL を選択可能なテキストで表示する',
        (tester) async {
      visionFilterUrgencyProvider = (_) => Urgency.earlyConsultation;
      visionFilterUrgencyEscalationProvider = (_) => const [];
      visionState.select('glaucoma');

      await pumpPanel(tester);

      expect(find.textContaining('sensus/blob/main/docs/overview.md'),
          findsOneWidget);
    });
  });

  group('推奨値に戻す（#77）', () {
    testWidgets('強度・パラメータを変更後、ボタンで推奨値・既定値に戻る', (tester) async {
      visionFilterRecommendedStrengthProvider = (_) => 0.5;
      visionState.select('astigmatism');
      expect(visionState.strength, 0.5);

      visionState.setStrength(0.9);
      visionState.setParam('axisDeg', 30.0);
      expect(visionState.strength, 0.9);
      expect(visionState.paramValue(visionState.selectedEntry!.parameters.first),
          30.0);

      await pumpPanel(tester);
      final en = lookupAppLocalizations(const Locale('en'));
      await tester.tap(find.text(en.resetToRecommendedStrength));
      await tester.pump();

      expect(visionState.strength, 0.5);
      expect(visionState.paramValue(visionState.selectedEntry!.parameters.first),
          90.0); // カタログ既定値（axisDeg の defaultValue）
    });
  });
}
