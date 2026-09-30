// #80: フィルタごとの「モデルと出典」「表現できないこと」、seed パラメータの
// 「パターンを変える」ボタン、平易なパラメータ名、「実験的」バッジ。
//
// 文言の正本は sensus のメタデータ（`visionFilterCitationProvider` /
// `visionFilterLimitationsProvider`）。実ブリッジは flutter test で呼べないので
// フィクスチャで差し替え、UI が**その値をそのまま**出すことを確かめる。
// 書き出し PNG の焼き込みは `export_service_test.dart` が実画素で検証する。

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show LocaleStringAttribute;
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

    testWidgets('展開すると sensus の出典と限界が原文のまま出る（ja では両方に原文の注記付き）', (tester) async {
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
      // 英語の原文であることを日本語 UI では明示する（出典・限界の両方）。
      expect(
        find.text('sensus が英語で提供している原文を、そのまま表示しています。'),
        findsNWidgets(2),
      );
      expect(find.textContaining('医療監修を受けたものではありません'), findsOneWidget);
    });

    testWidgets('「医療監修を受けたものではありません」は折りたたみの外・最下段に常時 1 行だけ出る', (tester) async {
      await pumpHomeScreen(
        tester,
        size: _wide,
        select: (f, s) => selectColorVision(f, s, ColorVisionType.protanopia),
      );
      final note = find.byKey(const Key('provenance-source-note'));

      // 閉じたままでも読める。
      expect(note, findsOneWidget);
      expect(find.textContaining('医療監修を受けたものではありません'), findsOneWidget);
      // 折りたたみの中ではなく、最下段（限界の行より下）にある。
      expect(
        find.ancestor(of: note, matching: find.byType(ExpansionTile)),
        findsNothing,
      );
      final closedTop = tester.getTopLeft(note).dy;
      expect(
        closedTop,
        greaterThan(tester.getBottomLeft(tile('provenance-limitations')).dy),
      );

      // どちらを開いても 1 行のまま（増えない・消えない）。
      await expand(tester, 'provenance-model');
      await expand(tester, 'provenance-limitations');
      expect(note, findsOneWidget);
      expect(find.textContaining('医療監修を受けたものではありません'), findsOneWidget);
      expect(tester.getTopLeft(note).dy, greaterThan(closedTop));
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
      // 英語 UI の注記文（実際の en 文言）は、どちらの行にも出ない。
      final en = lookupAppLocalizations(const Locale('en'));
      expect(en.provenanceEnglishOriginalNote, isNotEmpty);
      expect(find.text(en.provenanceEnglishOriginalNote), findsNothing);
      // ja 側の文言が en に紛れていない（en の医療監修の注記は出る）。
      expect(find.text(en.provenanceSourceNote), findsOneWidget);
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

    testWidgets('出典が空文字でも「示していません」と書く。限界が空なら折りたたみ自体を出さない', (tester) async {
      visionFilterCitationProvider = (_) => '';
      visionFilterLimitationsProvider = (_) => '  ';
      await pumpHomeScreen(
        tester,
        size: _wide,
        select: (f, s) => s.select('tetrachromacy'),
      );

      await expand(tester, 'provenance-model');
      expect(find.text('このフィルタについて、sensus は出典を示していません。'), findsOneWidget);
      expect(tile('provenance-limitations'), findsNothing);
      // 注記は残る。
      expect(find.byKey(const Key('provenance-source-note')), findsOneWidget);
    });

    testWidgets('体験プリセットの見出しでは、情報がどのフィルタのものかを示す。フィルタ直選択では出さない', (tester) async {
      final ja = lookupAppLocalizations(const Locale('ja'));
      final h = await pumpHomeScreen(
        tester,
        size: _wide,
        select: (f, s) => s.selectPreset('meniere', 'vertigo'),
      );
      expect(
        find.text(ja.provenanceAboutFilter(visionFilterName(ja, 'vertigo'))),
        findsOneWidget,
      );

      h.visionState.select('vertigo');
      await tester.pumpAndSettle();
      expect(find.textContaining('についての情報です'), findsNothing);
    });

    testWidgets(
        '原文は ja UI で英語として読み上げられる（LocaleStringAttribute=en）。en UI では付けない',
        (tester) async {
      final handle = tester.ensureSemantics();
      try {
        visionFilterCitationProvider = (_) => _citation;
        await pumpHomeScreen(
          tester,
          size: _wide,
          select: (f, s) => selectColorVision(f, s, ColorVisionType.protanopia),
        );
        await expand(tester, 'provenance-model');

        final data = tester.getSemantics(find.bySemanticsLabel(_citation));
        final locales = [
          for (final a in data.attributedLabel.attributes)
            if (a is LocaleStringAttribute) a.locale,
        ];
        expect(locales, [const Locale('en')]);
        // 属性の範囲は本文全体。
        final attr = data.attributedLabel.attributes
            .whereType<LocaleStringAttribute>()
            .single;
        expect(attr.range, const TextRange(start: 0, end: _citation.length));
      } finally {
        handle.dispose();
      }
    });

    testWidgets('en UI の原文には言語属性を付けない（もともと英語）', (tester) async {
      final handle = tester.ensureSemantics();
      try {
        visionFilterCitationProvider = (_) => _citation;
        await pumpHomeScreen(
          tester,
          size: _wide,
          locale: const Locale('en'),
          select: (f, s) => selectColorVision(f, s, ColorVisionType.protanopia),
        );
        await expand(tester, 'provenance-model');

        // 選択可能な本文そのもの（en UI では言語のラッパーを挟まない）。
        final data = tester.getSemantics(find.descendant(
          of: tile('provenance-model'),
          matching: find.byType(SelectableText),
        ));
        expect('${data.label} ${data.value}', contains(_citation));
        expect(
          [
            ...data.attributedLabel.attributes,
            ...data.attributedValue.attributes,
          ].whereType<LocaleStringAttribute>(),
          isEmpty,
        );
      } finally {
        handle.dispose();
      }
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

    testWidgets('読み上げにはパラメータ名を含む（どのパターンかが分かる）。画面の文言は短いまま', (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await pumpHomeScreen(
          tester,
          size: _wide,
          select: (f, s) => s.select('cataract'),
        );

        final data = tester.getSemantics(
          find.bySemanticsLabel('パターンを変える（まぶしさの散り方）'),
        );
        expect(data.label, 'パターンを変える（まぶしさの散り方）');
        expect(data.flagsCollection.isButton, isTrue);
        // 見えている文言は短いまま。
        expect(find.text('パターンを変える'), findsOneWidget);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('アイコンは 16px（8 の倍数系のサイズ）', (tester) async {
      await pumpHomeScreen(
        tester,
        size: _wide,
        select: (f, s) => s.select('floaters'),
      );
      final icon = tester.widget<Icon>(find.descendant(
        of: find.widgetWithText(OutlinedButton, 'パターンを変える'),
        matching: find.byIcon(Icons.shuffle),
      ));
      expect(icon.size, 16);
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

  group('パラメータ名の意味が sensus の定義と対応している', () {
    // 言い換えが sensus の定義とずれていないことを固定する（「専門語が無い」
    // だけでは、意味が逆の言い換えを通してしまう）。定義の所在は sensus-core
    // 0.6.1 のソース:
    // - 乱視 axis_deg: シャープ方向。ぼかし方向は axis_deg + 90°
    //   （src/vision/refraction.rs の astigmatism() の doc、
    //   src/shaders.rs の astigmatism の axis_deg の doc。ue 側の
    //   lib/src/rust/api/sensus_bridge.dart の「シャープ方向の経線角」も同じ）。
    // - 歪視 freq: 格子の細かさ（1 マス = 短辺 / freq、src/vision/phenomena.rs）。
    // - 光芒 threshold: 光芒を発生させる輝度の閾値、dispersion: 波長分散による
    //   虹色の度合い（0 = 白、1 = 完全な虹色。src/vision/motion.rs の starbursts）。
    // - 眼振 direction_deg: 揺れの方向。amplitude: 揺れの大きさ。
    // - 複視 ghost_strength: 二重像（ゴースト）の濃さ。
    // - 詳細喪失 cell_size: ブロック（セル）の大きさ（px）。
    const expectations = <String, ({List<String> ja, List<String> en})>{
      'param.astigmatism.axis_deg': (ja: ['くっきり'], en: ['Sharp']),
      'param.metamorphopsia.freq': (ja: ['細か'], en: ['fineness']),
      'param.starbursts.threshold': (ja: ['明るさ'], en: ['Brightness']),
      'param.starbursts.dispersion': (ja: ['虹色'], en: ['Rainbow']),
      'param.nystagmus.direction_deg': (ja: ['向き'], en: ['direction']),
      'param.nystagmus.amplitude': (ja: ['大きさ'], en: ['size']),
      'param.diplopia.ghost_strength': (ja: ['濃さ'], en: ['opacity']),
      'param.detail_loss.cell_size': (ja: ['ブロック'], en: ['Block']),
    };

    test('乱視の軸は「ぼやける向き」ではなく「くっきり見える向き」（90° 逆になる誤訳の再発防止）', () {
      final ja = lookupAppLocalizations(const Locale('ja'));
      final en = lookupAppLocalizations(const Locale('en'));
      expect(ja.paramAstigmatismAxisDeg, contains('くっきり'));
      expect(ja.paramAstigmatismAxisDeg, isNot(contains('ぼやけ')));
      expect(en.paramAstigmatismAxisDeg, contains('Sharp'));
      expect(en.paramAstigmatismAxisDeg, isNot(contains('Blur')));
    });

    test('sensus の定義に対応する語を含む（ja・en）', () {
      final ja = lookupAppLocalizations(const Locale('ja'));
      final en = lookupAppLocalizations(const Locale('en'));
      for (final e in expectations.entries) {
        for (final word in e.value.ja) {
          expect(visionParamLabel(ja, e.key), contains(word), reason: e.key);
        }
        for (final word in e.value.en) {
          expect(visionParamLabel(en, e.key), contains(word), reason: e.key);
        }
      }
    });

    test('カタログの英語フォールバック名は ARB の en と一致する（食い違うと別の意味に読める）', () {
      final en = lookupAppLocalizations(const Locale('en'));
      for (final entry in kVisionFilterCatalog) {
        for (final param in entry.parameters) {
          expect(param.displayName, visionParamLabel(en, param.labelKey),
              reason: '${entry.id}/${param.name}');
          for (final o in param.options) {
            expect(o.displayName, visionParamLabel(en, o.labelKey),
                reason: '${entry.id}/${param.name}/${o.value}');
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
