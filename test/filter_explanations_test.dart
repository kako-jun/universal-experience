// #80: フィルタごとの「モデルと出典」「表現できないこと」、seed パラメータの
// 「パターンを変える」ボタン、平易なパラメータ名、「実験的」バッジ。
//
// 文言の正本は sensus のメタデータ（`visionFilterCitationProvider` /
// `visionFilterLimitationsProvider`）。実ブリッジは flutter test で呼べないので
// フィクスチャで差し替え、UI が**その値をそのまま**出すことを確かめる。
// 書き出し PNG の焼き込みは `export_service_test.dart` が実画素で検証する。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/l10n/l10n_extensions.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/models/vision_filter_catalog.dart';
import 'package:universal_experience/services/color_vision_selection.dart';
import 'package:universal_experience/services/vision_filter_metadata.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/theme/app_theme.dart';
import 'package:universal_experience/ui/widgets/adjust_panel.dart';
import 'package:universal_experience/ui/widgets/experimental_badge.dart';
import 'package:universal_experience/ui/widgets/filter_list_tile.dart';
import 'package:universal_experience/ui/widgets/filter_provenance.dart';

import 'support/home_screen_harness.dart';
import 'support/vision_filter_metadata_fixture.dart';

const _wide = Size(1280, 1000);
const _citation =
    'Machado, Oliveira & Fernandes (2009). doi:10.1109/TVCG.2009.113';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installHomeScreenFixtures);
  tearDown(resetHomeScreenFixtures);

  Finder tile(String key) => find.byKey(Key(key));

  Future<void> expand(WidgetTester tester, String key) async {
    final title = find.descendant(
      of: tile(key),
      matching: find.byType(ListTile),
    );
    await tester.ensureVisible(title);
    await tester.tap(title);
    await tester.pumpAndSettle();
  }

  group('モデルと出典・表現できないこと', () {
    testWidgets('閉じた状態では見出しだけ。本文は展開するまで出ない', (tester) async {
      visionFilterCitationProvider = (_) => _citation;
      await pumpHomeScreen(
        tester,
        size: _wide,
        select: (f, s) => selectColorVision(f, s, ColorVisionType.protanopia),
      );

      expect(find.text('モデルと出典'), findsOneWidget);
      expect(find.text('表現できないこと'), findsOneWidget);
      expect(find.text(_citation), findsNothing);
      expect(find.text(kFixtureLimitations), findsNothing);
    });

    testWidgets('展開すると sensus の出典と限界が原文のまま出る（ja では原文の注記付き）', (tester) async {
      visionFilterCitationProvider = (_) => _citation;
      await pumpHomeScreen(
        tester,
        size: _wide,
        select: (f, s) => selectColorVision(f, s, ColorVisionType.protanopia),
      );

      await expand(tester, 'provenance-model');
      await expand(tester, 'provenance-limitations');

      expect(find.text(_citation), findsOneWidget);
      expect(find.text(kFixtureLimitations), findsOneWidget);
      // 英語の原文であることを日本語 UI では明示する（限界の側）。
      expect(
        find.text('sensus が英語で提供している原文を、そのまま表示しています。'),
        findsOneWidget,
      );
      // 医療監修を受けていない旨は「モデルと出典」の側に 1 度だけ付く。
      expect(find.textContaining('医療監修を受けたものではありません'), findsOneWidget);
    });

    testWidgets('英語 UI では原文の注記を出さない', (tester) async {
      await pumpHomeScreen(
        tester,
        size: _wide,
        locale: const Locale('en'),
        select: (f, s) => selectColorVision(f, s, ColorVisionType.protanopia),
      );

      await expand(tester, 'provenance-limitations');

      expect(find.text(kFixtureLimitations), findsOneWidget);
      expect(find.textContaining('sensus が英語で'), findsNothing);
      expect(find.textContaining('original text'), findsNothing);
    });

    testWidgets('出典が無い（citation が null）フィルタは「無い」と書き、捏造しない', (tester) async {
      visionFilterCitationProvider = (_) => null;
      await pumpHomeScreen(
        tester,
        size: _wide,
        select: (f, s) => s.select('tetrachromacy'),
      );

      await expand(tester, 'provenance-model');

      expect(find.text('このフィルタについて、sensus は出典を示していません。'), findsOneWidget);
    });

    testWidgets('メタデータは選択中フィルタの実インスタンスで引く（別フィルタの値を出さない）', (tester) async {
      final asked = <VisionFilter>[];
      visionFilterLimitationsProvider = (filter) {
        asked.add(filter);
        return 'limits for ${filter.runtimeType}';
      };
      await pumpHomeScreen(
        tester,
        size: _wide,
        select: (f, s) => s.select('tetrachromacy'),
      );

      await expand(tester, 'provenance-limitations');

      expect(asked, isNotEmpty);
      expect(
          asked.every((f) => f == const VisionFilter.tetrachromacy()), isTrue);
      expect(find.textContaining('limits for'), findsOneWidget);
    });

    testWidgets('何も選んでいないときは出さない', (tester) async {
      await pumpHomeScreen(tester, size: _wide);

      expect(find.byType(FilterProvenanceSection), findsNothing);
    });

    testWidgets('折りたたみの行も 48dp 以上の操作領域を持つ（macOS）', (tester) async {
      await pumpHomeScreen(
        tester,
        size: _wide,
        theme: AppTheme.lightTheme,
        select: (f, s) => selectColorVision(f, s, ColorVisionType.protanopia),
      );

      for (final key in ['provenance-model', 'provenance-limitations']) {
        final size = tester.getSize(find.descendant(
          of: tile(key),
          matching: find.byType(ListTile),
        ));
        expect(size.height, greaterThanOrEqualTo(48), reason: key);
      }
    });

    testWidgets('出典セクションはパラメータより下（最下段）にあり、上の要素を押しのけない', (tester) async {
      visionFilterUrgencyProvider = (_) => Urgency.emergency;
      await pumpHomeScreen(
        tester,
        size: _wide,
        select: (f, s) => s.select('cataract'),
      );

      final provenanceTop =
          tester.getTopLeft(find.byType(FilterProvenanceSection)).dy;
      final patternButtonTop =
          tester.getTopLeft(find.widgetWithText(OutlinedButton, 'パターンを変える')).dy;
      expect(provenanceTop, greaterThan(patternButtonTop));
    });
  });

  group('seed パラメータ', () {
    testWidgets('数値を出さず「パターンを変える」だけ。押すと seed が変わる', (tester) async {
      final h = await pumpHomeScreen(
        tester,
        size: _wide,
        theme: AppTheme.lightTheme,
        select: (f, s) => s.select('floaters'),
      );
      final before = h.visionState.params['seed'];
      expect(before, BigInt.zero);

      final button = find.widgetWithText(OutlinedButton, 'パターンを変える');
      expect(button, findsOneWidget);
      // 数値（0・u64 の桁）が seed の行に描かれていない。
      expect(find.text('0'), findsNothing);
      expect(find.textContaining(RegExp(r'\d{6,}')), findsNothing);
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));

      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();

      final after = h.visionState.params['seed'];
      expect(after, isA<BigInt>());
      expect(after, isNot(before));
      // 押したあとも数値は出ない。
      expect(find.textContaining(RegExp(r'\d{6,}')), findsNothing);
    });

    testWidgets('en でも「Change pattern」で数値を出さない', (tester) async {
      await pumpHomeScreen(
        tester,
        size: _wide,
        locale: const Locale('en'),
        select: (f, s) => s.select('flickering_stars'),
      );
      expect(find.widgetWithText(OutlinedButton, 'Change pattern'),
          findsOneWidget);
    });
  });

  group('平易なパラメータ名', () {
    test('ja の全パラメータ名・選択肢名に専門語（シード・しきい値・振幅・周波数）が無い', () {
      final l10n = lookupAppLocalizations(const Locale('ja'));
      const jargon = ['シード', 'しきい値', '閾値', '振幅', '周波数'];
      for (final entry in kVisionFilterCatalog) {
        for (final param in entry.parameters) {
          final labels = [
            visionParamLabel(l10n, param.labelKey),
            for (final o in param.options) visionParamLabel(l10n, o.labelKey),
          ];
          for (final label in labels) {
            for (final word in jargon) {
              expect(label, isNot(contains(word)),
                  reason: '${entry.id}/${param.name}: $label');
            }
          }
        }
      }
    });
  });

  group('実験的バッジ', () {
    test('既定では四色覚だけが実験的（カタログ側の 1 か所で決まる）', () {
      expect(
        [
          for (final e in kVisionFilterCatalog)
            if (e.isExperimental) e.id
        ],
        ['tetrachromacy'],
      );
    });

    testWidgets('四色覚を選ぶと右カラムの名前にバッジが付く', (tester) async {
      await pumpHomeScreen(
        tester,
        size: _wide,
        select: (f, s) => s.select('tetrachromacy'),
      );

      expect(
        find.descendant(
          of: find.byType(AdjustPanel),
          matching: find.byType(ExperimentalBadge),
        ),
        findsOneWidget,
      );
    });

    testWidgets('四色覚以外を選ぶとバッジは出ない', (tester) async {
      await pumpHomeScreen(
        tester,
        size: _wide,
        select: (f, s) => selectColorVision(f, s, ColorVisionType.protanopia),
      );

      // 一覧の四色覚の行のバッジは残る。右カラム（調整）には出ない。
      expect(
        find.descendant(
          of: find.byType(AdjustPanel),
          matching: find.byType(ExperimentalBadge),
        ),
        findsNothing,
      );
    });

    testWidgets('一覧では四色覚の行にだけバッジがある', (tester) async {
      await pumpHomeScreen(tester, size: _wide);

      final badgedRows = find.descendant(
        of: find.byType(FilterListTile),
        matching: find.byType(ExperimentalBadge),
      );
      expect(badgedRows, findsOneWidget);
      final owner = find.ancestor(
        of: badgedRows,
        matching: find.byType(FilterListTile),
      );
      expect(
        tester.widget<FilterListTile>(owner).title,
        visionFilterName(
            lookupAppLocalizations(const Locale('ja')), 'tetrachromacy'),
      );
    });

    testWidgets('バッジは色だけでなく文言とアイコンで示す', (tester) async {
      await pumpHomeScreen(
        tester,
        size: _wide,
        select: (f, s) => s.select('tetrachromacy'),
      );
      final badge = find.descendant(
        of: find.byType(AdjustPanel),
        matching: find.byType(ExperimentalBadge),
      );
      expect(
        find.descendant(of: badge, matching: find.text('実験的')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: badge, matching: find.byIcon(Icons.science_outlined)),
        findsOneWidget,
      );
    });
  });
}
