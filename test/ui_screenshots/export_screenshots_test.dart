// PNG 書き出し（焼き込みキャプション）のスクリーンショット出力（#121）。
//
// 実ディスプレイのない環境でも、書き出される PNG を目視レビューできるよう、
// [composeExportImage] の結果（保存されるバイトそのもの）をファイルに書き出す。
// 回帰テストではない（比較はしない）。手順:
//
//   UE_SCREENSHOTS=1 UE_SCREENSHOT_DIR=/path/to/out \
//     flutter test test/ui_screenshots/export_screenshots_test.dart
//
// `UE_SCREENSHOTS=1` でないとき（通常の `flutter test`・CI）は全ケースが skip される。
// 出力ファイル名: `export-{1|3|5}-layers-{ja|en}-{1024|480}.png`
//   - 1 層: 従来の書き出し（症状名 + 強度の 2 行）。
//   - 3 層: 層ごとの行 + 喚起（最大の緊急度・併合した escalation）。
//   - 5 層: 上限。全部入り（喚起・escalation・実験的の注記）で、切れ・重なりが無いかの確認用。
// 幅 480 は、帯の文章が折り返す狭い画像（長い言語の最悪ケース）。
//
// 注意: 土台の画像は実ブリッジを通らない色相グラデーションのダミー。色覚の正しさを示す
// 画像ではない。受診喚起の緊急度・escalation は、文章の量が最大になるようフィクスチャで
// 与えている（実際の sensus の値ではない）。

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/services/export_layers.dart';
import 'package:universal_experience/services/export_service.dart';
import 'package:universal_experience/services/vision_filter_metadata.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';

import '../support/sample_image_generator.dart';
import '../support/screenshot_harness.dart';
import '../support/vision_filter_metadata_fixture.dart';

bool _defaultFamilyLoaded = false;

/// 焼き込みテキストは font family を指定しない（テストの既定は Ahem＝四角）ので、
/// 読めるように既定のファミリ名（Ahem）へ、日本語・英数字の両方を持つシステムフォントを
/// 読み込む。スクリーンショット出力のときだけの細工で、production コードは変えない。
Future<void> _loadDefaultFamilyForExport() async {
  if (_defaultFamilyLoaded) return;
  _defaultFamilyLoaded = true;
  for (final p in const [
    '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
    '/Library/Fonts/Arial Unicode.ttf',
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
  ]) {
    final f = File(p);
    if (!f.existsSync()) continue;
    final bytes = Uint8List.fromList(await f.readAsBytes());
    final loader = FontLoader('Ahem')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    return;
  }
  stderr.writeln(
      '[ui_screenshots] no readable default font; text renders as boxes');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    installVisionFilterMetadataFixture();
    if (!screenshotsEnabled) return;
    await loadScreenshotFonts();
    await _loadDefaultFamilyForExport();
  });
  tearDown(resetVisionFilterMetadataProviders);

  /// 喚起の文章が多くなる入力（最大の緊急度・2 段の escalation）。
  void installWordyConsultNotice() {
    visionFilterUrgencyProvider = (f) => switch (f) {
          VisionFilter_Vertigo() => Urgency.earlyConsultation,
          VisionFilter_Hemianopia() => Urgency.emergency,
          _ => Urgency.none,
        };
    visionFilterUrgencyEscalationProvider = (f) => switch (f) {
          VisionFilter_Vertigo() => const [
              UrgencyEscalation(
                urgency: Urgency.emergency,
                condition: 'a sudden drop in hearing, especially in one ear '
                    '(possible sudden sensorineural hearing loss)',
              ),
              UrgencyEscalation(
                urgency: Urgency.earlyConsultation,
                condition: 'recurrent or severe episodes',
              ),
            ],
          VisionFilter_Hemianopia() => const [
              UrgencyEscalation(
                urgency: Urgency.emergency,
                condition: 'sudden double vision',
              ),
            ],
          _ => const [],
        };
  }

  Future<void> shoot(
    WidgetTester tester, {
    required List<String> ids,
    required String name,
    required Locale locale,
    required int width,
  }) async {
    final state = VisionFilterState();
    for (final id in ids) {
      state.toggle(id);
    }
    final l10n = lookupAppLocalizations(locale);
    final layers = exportLayersOf(state);
    final plan = planExport(
      l10n,
      layers: layers.length > 1 ? layers : null,
      filterId: ids.last,
      variantId: state.layers.last.variantId,
      filter: state.buildLayer(state.layers.last),
      strength: 1.0,
      isoDate: '2026-10-01',
    );
    final path = '${screenshotOutputDir().path}/$name.png';
    await tester.runAsync(() async {
      final base = await generateSampleImage(width);
      final composed = await composeExportImage(base, plan.caption);
      final png = await encodePngAndDispose(composed);
      base.dispose();
      await File(path).writeAsBytes(png);
    });
  }

  const one = ['protanopia'];
  const three = ['protanopia', 'myopia', 'vertigo'];
  const five = ['tetrachromacy', 'hemianopia', 'myopia', 'vertigo', 'glaucoma'];

  for (final locale in const [Locale('ja'), Locale('en')]) {
    for (final width in const [1024, 480]) {
      final tag = '${locale.languageCode}-$width';
      testWidgets('1 層 $tag', (tester) async {
        await shoot(tester,
            ids: one,
            name: 'export-1-layers-$tag',
            locale: locale,
            width: width);
      }, skip: !screenshotsEnabled);
      testWidgets('3 層 $tag', (tester) async {
        installWordyConsultNotice();
        await shoot(tester,
            ids: three,
            name: 'export-3-layers-$tag',
            locale: locale,
            width: width);
      }, skip: !screenshotsEnabled);
      testWidgets('5 層 $tag', (tester) async {
        installWordyConsultNotice();
        await shoot(tester,
            ids: five,
            name: 'export-5-layers-$tag',
            locale: locale,
            width: width);
      }, skip: !screenshotsEnabled);
    }
  }
}
