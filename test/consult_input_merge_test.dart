// 複数層の受診喚起の入力の合成（#119）。
//
// `mergeConsultInputs` は resolveConsultNotice に渡す (urgency, escalation) を作る純粋関数。
// 書き出しへの適用（`buildLayeredExportCaption`）は export_multi_layer_test.dart が確認する。
// ここは「緊急度は最大」「escalation は段ごとに併合して重複行を除く」という規則と、最終的な
// resolveConsultNotice の表示（見出し・行）までを確認する。

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/l10n/l10n_extensions.dart';
import 'package:universal_experience/services/vision_filter_metadata.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';

import 'support/vision_filter_metadata_fixture.dart';

UrgencyEscalation _esc(Urgency u, String c) =>
    UrgencyEscalation(urgency: u, condition: c);

void main() {
  setUp(installVisionFilterMetadataFixture);
  tearDown(resetVisionFilterMetadataProviders);

  group('mergeConsultInputs', () {
    test('空なら none・escalation なし', () {
      final merged = mergeConsultInputs(const []);
      expect(merged.urgency, Urgency.none);
      expect(merged.escalation, isEmpty);
    });

    test('1 件ならそのまま', () {
      final e = _esc(Urgency.emergency, 'sudden onset');
      final merged = mergeConsultInputs([
        (urgency: Urgency.earlyConsultation, escalation: [e]),
      ]);
      expect(merged.urgency, Urgency.earlyConsultation);
      expect(merged.escalation, [e]);
    });

    test('緊急度は最大（順序に依らない）', () {
      for (final order in [
        [Urgency.none, Urgency.emergency, Urgency.earlyConsultation],
        [Urgency.emergency, Urgency.earlyConsultation, Urgency.none],
        [Urgency.earlyConsultation, Urgency.none, Urgency.emergency],
      ]) {
        final merged = mergeConsultInputs([
          for (final u in order) (urgency: u, escalation: const []),
        ]);
        expect(merged.urgency, Urgency.emergency, reason: '$order');
      }
      expect(
        mergeConsultInputs([
          (urgency: Urgency.none, escalation: const <UrgencyEscalation>[]),
          (
            urgency: Urgency.earlyConsultation,
            escalation: const <UrgencyEscalation>[],
          ),
        ]).urgency,
        Urgency.earlyConsultation,
      );
    });

    test('escalation は併合し、同じ段・同じ条件文の重複を除く（最初に現れた順）', () {
      final a = _esc(Urgency.emergency, 'sudden onset');
      final b = _esc(Urgency.earlyConsultation, 'persists over days');
      final c = _esc(Urgency.emergency, 'with speech trouble');
      final merged = mergeConsultInputs([
        (urgency: Urgency.earlyConsultation, escalation: [a, b]),
        (urgency: Urgency.none, escalation: [b, c, a]),
      ]);
      expect(merged.escalation, [a, b, c]);
    });

    test('同じ条件文でも段が違えば別の行として残す', () {
      final early = _esc(Urgency.earlyConsultation, 'same words');
      final emergency = _esc(Urgency.emergency, 'same words');
      final merged = mergeConsultInputs([
        (urgency: Urgency.none, escalation: [early]),
        (urgency: Urgency.none, escalation: [emergency]),
      ]);
      expect(merged.escalation, [early, emergency]);
    });

    test('結果の escalation は変更できない', () {
      final merged = mergeConsultInputs([
        (urgency: Urgency.none, escalation: [_esc(Urgency.emergency, 'x')]),
      ]);
      expect(() => merged.escalation.add(_esc(Urgency.emergency, 'y')),
          throwsUnsupportedError);
    });
  });

  group('consultInputForFilters（provider から読む）', () {
    test('層ごとの urgency / escalation を読んで併合する', () {
      final shared = _esc(Urgency.emergency, 'sudden onset');
      visionFilterUrgencyProvider = (f) => switch (f) {
            VisionFilter_Vertigo() => Urgency.earlyConsultation,
            VisionFilter_Myopia() => Urgency.emergency,
            _ => Urgency.none,
          };
      visionFilterUrgencyEscalationProvider = (f) => switch (f) {
            VisionFilter_Vertigo() => [
                shared,
                _esc(Urgency.earlyConsultation, 'persists'),
              ],
            VisionFilter_Myopia() => [shared],
            _ => const [],
          };

      final state = VisionFilterState()
        ..toggle('myopia')
        ..toggle('vertigo');
      final merged = consultInputForFilters(state.buildAll());

      expect(merged.urgency, Urgency.emergency);
      expect(
          merged.escalation,
          [
            shared,
            _esc(Urgency.earlyConsultation, 'persists'),
          ],
          reason: '適用順（vertigo → myopia）で最初に現れた順、shared は 1 行');
    });

    test('resolveConsultNotice に渡すと、緊急度の段ごとの見出しと重複なしの行になる', () {
      final shared = _esc(Urgency.emergency, 'sudden onset');
      final merged = mergeConsultInputs([
        (urgency: Urgency.earlyConsultation, escalation: [shared]),
        (
          urgency: Urgency.emergency,
          escalation: [shared, _esc(Urgency.earlyConsultation, 'persists')],
        ),
      ]);
      final l10n = lookupAppLocalizations(const Locale('ja'));
      final notice =
          resolveConsultNotice(l10n, merged.urgency, merged.escalation)!;

      expect(notice.urgency, Urgency.emergency);
      expect(notice.escalationGroups, hasLength(2));
      expect(
          notice.escalationGroups.first.header, l10n.escalationHeaderEmergency);
      expect(notice.escalationGroups.first.lines, hasLength(1));
      expect(notice.escalationGroups.last.header, l10n.escalationHeaderEarly);
    });
  });
}
