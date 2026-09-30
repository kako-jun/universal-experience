// sensus API 契約注記（#51）の UI 反映（#66）。
//
// - 注記1: tunnel_vision の強度スライダ上限付近に、目盛り（印）と注記・警告を出す。
//   閾値をまたいだとき注記が警告に切り替わること、印が閾値の位置に描かれること、
//   受診喚起ブロックの位置が動かないことを検証する。
// - 注記3: starbursts の推奨サンプルに広いベタ白を使わない（実画素で検証）。
//
// 受診喚起は sensus ブリッジが正本で flutter test では呼べないため、フィクスチャに
// 差し替える（test/support/vision_filter_metadata_fixture.dart）。

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/models/sample_catalog.dart';
import 'package:universal_experience/models/vision_filter_catalog.dart';
import 'package:universal_experience/models/vision_filter_contract_notes.dart';
import 'package:universal_experience/rendering/image_fit.dart';
import 'package:universal_experience/services/vision_filter_metadata.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/widgets/consult_notice_block.dart';
import 'package:universal_experience/ui/widgets/filter_param_panel.dart';
import 'package:universal_experience/ui/widgets/strength_caution.dart';

import 'support/vision_filter_metadata_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('kStrengthCautionByFilterId（定義）', () {
    test('キーはすべてカタログに存在する id、閾値は 0 と 1 の間', () {
      final ids = kVisionFilterCatalog.map((e) => e.id).toSet();
      for (final e in kStrengthCautionByFilterId.entries) {
        expect(ids, contains(e.key));
        expect(e.value.threshold, inInclusiveRange(0.05, 0.95), reason: e.key);
      }
    });

    test('tunnel_vision は定義されている（#51 注記1）', () {
      expect(kStrengthCautionByFilterId['tunnel_vision']!.threshold, 0.8);
    });
  });

  group('強度スライダの上限付近の注意（#66）', () {
    late VisionFilterState state;

    setUp(() {
      installVisionFilterMetadataFixture();
      state = VisionFilterState();
    });
    tearDown(resetVisionFilterMetadataProviders);

    Future<void> pumpPanel(WidgetTester tester, {Locale? locale}) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<VisionFilterState>.value(
          value: state,
          child: MaterialApp(
            locale: locale,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: SingleChildScrollView(child: FilterParamPanel()),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    AppLocalizations en() => lookupAppLocalizations(const Locale('en'));
    AppLocalizations ja() => lookupAppLocalizations(const Locale('ja'));

    testWidgets('tunnel_vision の中程度の強さでは、印の説明だけが出て警告は出ない', (tester) async {
      state.select('tunnel_vision');
      state.setStrength(0.5);
      await pumpPanel(tester);

      expect(find.text(en().strengthCautionMarkerNote(80)), findsOneWidget);
      expect(find.text(en().strengthCautionNearLimit), findsNothing);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });

    testWidgets('閾値の直前（75%）は警告にならず、閾値ちょうど（80%）から警告になる', (tester) async {
      state.select('tunnel_vision');
      state.setStrength(0.75);
      await pumpPanel(tester);
      expect(find.text(en().strengthCautionNearLimit), findsNothing);

      state.setStrength(0.8);
      await tester.pump();
      expect(find.text(en().strengthCautionNearLimit), findsOneWidget);
      expect(find.text(en().strengthCautionMarkerNote(80)), findsNothing);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsNothing);
    });

    testWidgets('100% では警告。スライダを動かして閾値をまたぐと表示が切り替わる', (tester) async {
      state.select('tunnel_vision');
      state.setStrength(1.0);
      await pumpPanel(tester);
      expect(find.text(en().strengthCautionNearLimit), findsOneWidget);

      state.setStrength(0.3);
      await tester.pump();
      expect(find.text(en().strengthCautionNearLimit), findsNothing);
      expect(find.text(en().strengthCautionMarkerNote(80)), findsOneWidget);
    });

    testWidgets('警告は太字（w600）・onSurface で、印の説明の補足表現と区別できる', (tester) async {
      state.select('tunnel_vision');
      state.setStrength(0.5);
      await pumpPanel(tester);
      final theme = Theme.of(tester.element(find.byType(FilterParamPanel)));
      final note = tester.widget<Text>(
        find.text(en().strengthCautionMarkerNote(80)),
      );
      expect(note.style!.color, theme.colorScheme.onSurfaceVariant);
      expect(note.style!.fontWeight, isNot(FontWeight.w600));

      state.setStrength(1.0);
      await tester.pump();
      final warn =
          tester.widget<Text>(find.text(en().strengthCautionNearLimit));
      expect(warn.style!.color, theme.colorScheme.onSurface);
      expect(warn.style!.fontWeight, FontWeight.w600);
      // 注記は bodySmall のサイズ（下限 12 を割らない、DESIGN §3）。
      expect(warn.style!.fontSize, theme.textTheme.bodySmall!.fontSize);
    });

    testWidgets('日本語ロケールでは日本語の文言が出る', (tester) async {
      state.select('tunnel_vision');
      state.setStrength(1.0);
      await pumpPanel(tester, locale: const Locale('ja'));
      expect(find.text(ja().strengthCautionNearLimit), findsOneWidget);
      expect(ja().strengthCautionNearLimit, contains('故障ではありません'));
      expect(en().strengthCautionNearLimit, contains('not a malfunction'));
    });

    testWidgets('注意の定義が無いフィルタでは注記も印も出ない', (tester) async {
      for (final id in ['protanopia', 'glaucoma', 'hemianopia']) {
        expect(kStrengthCautionByFilterId.containsKey(id), isFalse);
        state.select(id);
        state.setStrength(1.0);
        await pumpPanel(tester);
        expect(find.byType(StrengthCautionNote), findsNothing, reason: id);
        final slider = tester.widget<Slider>(find.byType(Slider));
        expect(slider.divisions, 20);
        final theme = SliderTheme.of(tester.element(find.byType(Slider)));
        expect(theme.trackShape, isNot(isA<StrengthCautionTrackShape>()),
            reason: id);
      }
    });

    testWidgets('印は閾値（80%）のつまみ・目盛りと同じ x に描かれる', (tester) async {
      // 強度 0.8（= 閾値）のとき、つまみの中心が印の x と一致する。実装と同じ式を
      // 使わず、Slider が実際に描いたつまみ・目盛りの位置と直接比べる。
      state.select('tunnel_vision');
      state.setStrength(0.8);
      await pumpPanel(tester);

      final sliderFinder = find.byType(Slider);
      final theme = SliderTheme.of(tester.element(sliderFinder));
      final shape = theme.trackShape as StrengthCautionTrackShape;
      expect(shape.threshold, 0.8);

      double? markX;
      double? thumbX;
      double? tickX;
      final box = tester.renderObject<RenderBox>(sliderFinder);
      expect(
        box,
        paints
          ..something((Symbol method, List<dynamic> args) {
            if (method != #drawRRect) return false;
            final rrect = args[0] as RRect;
            if ((rrect.width - StrengthCautionTrackShape.markWidth).abs() >
                    1e-6 ||
                rrect.height <= 4) {
              return false;
            }
            markX = rrect.center.dx;
            return true;
          })
          ..something((Symbol method, List<dynamic> args) {
            // つまみ（半径の大きい円）。目盛りは半径 2 未満の小さな円。
            // 半径 5 での見分けは year2023: true（現行 M3）のスライダ前提。
            if (method != #drawCircle) return false;
            final center = args[0] as Offset;
            final radius = args[1] as double;
            if (radius < 5) return false;
            thumbX = center.dx;
            return true;
          }),
      );
      expect(markX, isNotNull);
      expect(thumbX, isNotNull);
      expect(markX!, closeTo(thumbX!, 0.01));

      // 目盛り（20 分割の 16 番目）も同じ x。
      expect(
        box,
        paints
          ..something((Symbol method, List<dynamic> args) {
            if (method != #drawCircle) return false;
            final center = args[0] as Offset;
            final radius = args[1] as double;
            if (radius >= 5 || (center.dx - markX!).abs() > 0.01) return false;
            tickX = center.dx;
            return true;
          }),
      );
      expect(tickX, isNotNull);
    });

    testWidgets('無効なスライダでは印も無効表現（不透明度 38%）になる', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                trackShape: StrengthCautionTrackShape(
                  threshold: 0.8,
                  markColor: Color(0xFF102030),
                ),
              ),
              child: Slider(value: 0.5, divisions: 20, onChanged: null),
            ),
          ),
        ),
      );
      Color? markColor;
      expect(
        tester.renderObject<RenderBox>(find.byType(Slider)),
        paints
          ..something((Symbol method, List<dynamic> args) {
            if (method != #drawRRect) return false;
            final rrect = args[0] as RRect;
            if ((rrect.width - StrengthCautionTrackShape.markWidth).abs() >
                1e-6) {
              return false;
            }
            markColor = (args[1] as Paint).color;
            return true;
          }),
      );
      expect(markColor, isNotNull);
      expect(markColor!.a, closeTo(0.38, 0.01));
    });

    testWidgets('浮動小数の誤差（0.7999…）でも 80% の位置は警告になる', (tester) async {
      // 0.1 + 0.7 は 0.7999999999999999。整数パーセントに丸めて比べるので警告側。
      const almost = 0.1 + 0.7;
      expect(almost, lessThan(0.8));
      const caution = StrengthCaution(threshold: 0.8);
      expect(
          const StrengthCautionNote(caution: caution, strength: almost)
              .isNearLimit,
          isTrue);
      expect(
          const StrengthCautionNote(caution: caution, strength: 0.79)
              .isNearLimit,
          isFalse);
      expect(
          const StrengthCautionNote(caution: caution, strength: 0.8)
              .isNearLimit,
          isTrue);
    });

    testWidgets('強さの % 表示と警告判定が同じ丸めで一致する（0.7999… / 0.795 / 0.79）',
        (tester) async {
      state.select('tunnel_vision');
      // 表示された % が閾値（80%）以上のときだけ警告が出る。
      for (final (value, shown, warns) in [
        (0.1 + 0.7, 80, true),
        (0.795, 80, true),
        (0.79, 79, false),
        (0.7949, 79, false),
      ]) {
        state.setStrength(value);
        await pumpPanel(tester);
        expect(strengthPercent(value), shown, reason: '$value');
        expect(find.text(en().strengthLabel(shown)), findsOneWidget,
            reason: '$value の表示');
        expect(find.text(en().strengthCautionNearLimit),
            warns ? findsOneWidget : findsNothing,
            reason: '$value の警告');
        expect(find.byType(Slider), findsOneWidget);
        final slider = tester.widget<Slider>(find.byType(Slider));
        expect(slider.label, '$shown%', reason: '$value のスライダのラベル');
      }
    });

    testWidgets('受診喚起ブロックは強度（スライダと注記）のすぐ下に出続ける（位置・内容を動かさない）', (tester) async {
      visionFilterUrgencyProvider = (_) => Urgency.earlyConsultation;
      state.select('tunnel_vision');
      state.setStrength(1.0);
      await pumpPanel(tester);

      final noteBottom =
          tester.getBottomLeft(find.byType(StrengthCautionNote)).dy;
      final noticeTop = tester.getTopLeft(find.byType(ConsultNoticeBlock)).dy;
      expect(noticeTop, greaterThan(noteBottom));
      // 注記と喚起の間は余白スケール 16 のまま。
      expect(noticeTop - noteBottom, closeTo(16, 0.01));
      expect(find.text(en().consultEarly), findsOneWidget);
      expect(find.text(en().consultDisclaimer), findsOneWidget);
    });
  });

  group('starbursts の推奨サンプルに広いベタ白を使わない（#51 注記3）', () {
    // 「白」= R・G・B のすべてが 240 以上の画素。
    Future<double> whiteRatio(String assetPath) async {
      final data = await rootBundle.load(assetPath);
      final image = await decodeImageBytes(data.buffer.asUint8List());
      addTearDown(image.dispose);
      final bytes =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      var white = 0;
      final n = image.width * image.height;
      for (var i = 0; i < n; i++) {
        final o = i * 4;
        if (bytes.getUint8(o) >= 240 &&
            bytes.getUint8(o + 1) >= 240 &&
            bytes.getUint8(o + 2) >= 240) {
          white++;
        }
      }
      return white / n;
    }

    test('計測が効いている: 白地のサンプル（chart）は白が過半を占める', () async {
      expect(await whiteRatio(kSampleCatalogById['chart']!.assetPath),
          greaterThan(0.5));
    });

    test('starbursts の推奨サンプルは白が 1% 未満', () async {
      final id = recommendedSampleIdForFilter('starbursts');
      final ratio = await whiteRatio(kSampleCatalogById[id]!.assetPath);
      expect(ratio, lessThan(0.01), reason: '$id の白画素率 $ratio');
    });
  });
}
