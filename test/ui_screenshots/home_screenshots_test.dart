// HomeScreen のスクリーンショット出力（#72）。
//
// 実ディスプレイのない環境でも UI を目視レビューできるよう、HomeScreen を
// 実際の Provider 構成で描画して PNG に書き出す。回帰テストではない（比較は
// しない）。DESIGN.md「検証方法」の手順:
//
//   UE_SCREENSHOTS=1 UE_SCREENSHOT_DIR=/path/to/out \
//     flutter test test/ui_screenshots/home_screenshots_test.dart
//
// `UE_SCREENSHOTS=1` でないとき（通常の `flutter test`・CI）は全ケースが
// skip される。出力ファイル名:
//   {wide|narrow}-{light|dark}-{ja|en}.png        — ウィンドウ 1 枚ぶん
//                                                    （wide=1280x800、narrow=800x700）
//   wide-{light|dark}-ja-hc.png                    — ハイコントラストテーマ
//   {wide|wide-low|default-window}-light-ja-clickthrough.png
//                                                  — クリックスルー ON の復帰バナー
//                                                    （wide-low=1280x480、default-window=800x600）
//   wide-light-ja-dialog.png                       — 起動モードのダイアログ（ON にする前）
//   wide-{light|dark}-{ja|en}-languagedialog.png   — 言語ダイアログ（#82）
//   narrow-{light|dark}-{ja|en}-full.png          — 縦に十分長い画面で全体を撮ったもの
//                                                    （狭幅の縦積みのスクロール量の確認用）
//   {wide|narrow}-{light|dark}-{ja|en}-compare-{off|on}.png
//                                                  — 色覚 4 型の 2×2 比較（#84）の切替前/後
//   wide-{light|dark}-{ja|en}-compare-export.png   — 2×2 の書き出し PNG（保存されたバイトそのもの）
//
// 注意: after ペインは実ブリッジ（sensus の CPU `apply()`）を呼べないため、
// レイアウト確認用の簡易フェイク（輝度への単純なブレンド）に差し替えている。
// 色覚シミュレーションの正しさを示す画像ではない。2×2 比較（#84）の撮影では、
// 4 セルが見分けられるよう型ごとに色味を変える別のフェイクに差し替える。

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/main.dart' show WindowModeUiContext;
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/models/sample_catalog.dart';
import 'package:universal_experience/rendering/cpu_vision_renderer.dart';
import 'package:universal_experience/services/color_vision_selection.dart';
import 'package:universal_experience/services/export_service.dart';
import 'package:universal_experience/services/filter_service.dart';
import 'package:universal_experience/services/hotkey_service.dart';
import 'package:universal_experience/services/image_source_state.dart';
import 'package:universal_experience/services/loupe_window_controller.dart';
import 'package:universal_experience/services/settings_service.dart';
import 'package:universal_experience/services/vision_filter_metadata.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/ui/screens/home_screen.dart';
import 'package:universal_experience/ui/theme/app_theme.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';
import 'package:universal_experience/ui/widgets/experience_presets.dart';

import '../support/screenshot_harness.dart';
import '../support/vision_filter_metadata_fixture.dart';

/// sensus の experiences() と同じ id / vision / hearing / urgency の 4 体験
/// （実ブリッジは native lib が要るため fixture で代替。experience_presets_test と同じ）。
List<Experience> _fixtureExperiences() => const [
      Experience(
        id: 'meniere',
        vision: VisionFilter.vertigo(),
        hearing: HearingFilter.meniere(),
        urgency: Urgency.earlyConsultation,
      ),
      Experience(
        id: 'bppv',
        vision: VisionFilter.bppvRotation(),
        urgency: Urgency.none,
      ),
      Experience(
        id: 'vestibular_neuritis',
        vision: VisionFilter.vestibularNeuritis(),
        urgency: Urgency.emergency,
      ),
      Experience(
        id: 'labyrinthitis',
        vision: VisionFilter.vertigo(),
        hearing: HearingFilter.labyrinthitis(),
        urgency: Urgency.earlyConsultation,
      ),
    ];

/// レイアウト確認専用の after フェイク。BT.709 輝度と元画像を strength で混ぜる
/// だけ（色覚のアルゴリズムではない）。
Future<ui.Image> _layoutOnlyApplier(
  ui.Image source,
  VisionFilter filter,
  double strength,
) async {
  final data = await source.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();
  final out = Uint8List.fromList(bytes);
  final s = strength.clamp(0.0, 1.0);
  for (var i = 0; i + 3 < out.length; i += 4) {
    final y = 0.2126 * out[i] + 0.7152 * out[i + 1] + 0.0722 * out[i + 2];
    for (var c = 0; c < 3; c++) {
      out[i + c] = (out[i + c] * (1 - s) + y * s).round().clamp(0, 255);
    }
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    out,
    source.width,
    source.height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// 2×2 比較（#84）のレイアウト確認専用フェイク。4 型が見分けられるよう、型ごとに
/// 異なる色味（チャンネルの混ぜ方）にして strength で元画像と混ぜる。色覚の
/// アルゴリズムではない。
Future<ui.Image> _tintedApplier(
  ui.Image source,
  VisionFilter filter,
  double strength,
) async {
  // (R', G', B') = 行列 × (R, G, B)。型ごとに大きく違う値にしてある。
  final List<double> m;
  if (filter == const VisionFilter.protanopia()) {
    m = [0.1, 0.9, 0.0, 0.1, 0.9, 0.0, 0.0, 0.3, 0.7];
  } else if (filter == const VisionFilter.deuteranopia()) {
    m = [0.6, 0.4, 0.0, 0.6, 0.4, 0.0, 0.0, 0.2, 0.8];
  } else if (filter == const VisionFilter.tritanopia()) {
    m = [1.0, 0.0, 0.0, 0.0, 0.4, 0.6, 0.0, 0.4, 0.6];
  } else {
    m = [0.33, 0.33, 0.34, 0.33, 0.33, 0.34, 0.33, 0.33, 0.34];
  }
  final data = await source.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();
  final out = Uint8List.fromList(bytes);
  final s = strength.clamp(0.0, 1.0);
  for (var i = 0; i + 3 < out.length; i += 4) {
    final r = bytes[i], g = bytes[i + 1], b = bytes[i + 2];
    for (var c = 0; c < 3; c++) {
      final t = m[c * 3] * r + m[c * 3 + 1] * g + m[c * 3 + 2] * b;
      out[i + c] = (bytes[i + c] * (1 - s) + t * s).round().clamp(0, 255);
    }
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    out,
    source.width,
    source.height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // (幅ラベル, 幅px, 高さpx) — 高さは「ウィンドウ 1 枚ぶん」。
  const sizes = <(String, double, double)>[
    ('wide', 1280, 800),
    ('narrow', 800, 700),
  ];
  // 組み合わせ: 広幅 × {light,dark} × {ja,en} + 狭幅 × light×ja / dark×en。
  final combos = <(String, bool, String)>[
    ('wide', false, 'ja'),
    ('wide', false, 'en'),
    ('wide', true, 'ja'),
    ('wide', true, 'en'),
    ('narrow', false, 'ja'),
    ('narrow', true, 'en'),
  ];

  setUpAll(() async {
    if (!screenshotsEnabled) return;
    await loadScreenshotFonts();
  });

  setUp(() {
    experiencesProvider = _fixtureExperiences;
    installVisionFilterMetadataFixture();
    CpuVisionRenderer.applier = _layoutOnlyApplier;
  });
  tearDown(() {
    experiencesProvider = experiences;
    resetVisionFilterMetadataProviders();
    CpuVisionRenderer.applier = CpuVisionRenderer.apply;
    pngSaver = savePng;
  });

  ThemeData themed(ThemeData base) => base.copyWith(
        textTheme: base.textTheme.apply(
          fontFamilyFallback: screenshotFontFallback,
        ),
      );

  Future<void> shoot(
    WidgetTester tester, {
    required String widthLabel,
    required double width,
    required double height,
    required bool dark,
    required String locale,
    required String suffix,
    bool highContrast = false,
    bool clickThrough = false,
    bool viaDialog = false,
    bool languageDialog = false,
    // 指定すると、初回起動の色覚ではなくこの advanced フィルタを選び、強度を
    // [strength] にする（契約注記の警告表示の確認用、#66）。
    String? advancedFilterId,
    double? strength,
    // true なら「モデルと出典」「表現できないこと」を両方開いて撮る（#80）。
    bool expandProvenance = false,
    // 指定すると体験プリセット（[id, 対応するカタログ id]）を選ぶ（#80）。
    (String, String)? preset,
    // true なら色覚 4 型の 2×2 比較（#84）に切り替えて撮る（4 型が見分けられる
    // フェイクに差し替える）。[compareExport] が true なら、さらに書き出しを
    // 実行し、保存された PNG を書き出して 4 セルの色が互いに異なることを確かめる。
    bool compare = false,
    bool compareExport = false,
  }) async {
    if (compare) CpuVisionRenderer.applier = _tintedApplier;
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = SettingsService();
    await settings.load();
    final visionState = VisionFilterState();
    final filterService = FilterService(visionState: visionState);
    final imageSourceState = ImageSourceState();
    // 初回起動と同じ状態: 2型3色覚（deuteranomaly）を推奨サンプルで選択。
    selectColorVision(
      filterService,
      visionState,
      ColorVisionType.deuteranomaly,
    );
    if (advancedFilterId != null) {
      visionState.select(advancedFilterId);
      if (strength != null) visionState.setStrength(strength);
    }
    if (preset != null) visionState.selectPreset(preset.$1, preset.$2);
    imageSourceState.followRecommendedSample(
      recommendedSampleIdForFilter(visionState.selectedId),
    );

    final loupe = LoupeWindowController();
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsService>.value(value: settings),
            ChangeNotifierProvider<FilterService>.value(value: filterService),
            ChangeNotifierProvider<VisionFilterState>.value(value: visionState),
            ChangeNotifierProvider<ImageSourceState>.value(
              value: imageSourceState,
            ),
            ChangeNotifierProvider<LoupeWindowController>.value(value: loupe),
            Provider<WindowModeUiContext>.value(
              value: WindowModeUiContext(
                trayAvailable: clickThrough,
                hotkeyStatus: const HotkeyStatus(),
              ),
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: Locale(locale),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            theme: themed(
              highContrast ? AppTheme.highContrastTheme : AppTheme.lightTheme,
            ),
            darkTheme: themed(
              highContrast
                  ? AppTheme.highContrastDarkTheme
                  : AppTheme.darkTheme,
            ),
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            home: const HomeScreen(),
          ),
        ),
      ),
    );

    // サンプル画像のデコード・after 描画は実時間の非同期。落ち着くまで待つ。
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }

    final base = '$widthLabel-${dark ? 'dark' : 'light'}-$locale';
    if (compare) {
      final l10n = lookupAppLocalizations(Locale(locale));
      final chip = find.widgetWithText(FilterChip, l10n.compareToggleLabel);
      await tester.tap(chip);
      await tester.pump();
      // 4 型ぶんの描画（実時間の非同期）が終わるまで待つ。
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
    }
    if (expandProvenance) {
      for (final key in ['provenance-model', 'provenance-limitations']) {
        final header = find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(ListTile),
        );
        await tester.ensureVisible(header);
        await tester.tap(header);
        await tester.pumpAndSettle();
      }
    }
    if (languageDialog) {
      // AppBar の言語ボタンから開く言語ダイアログ（#82）。
      await tester.tap(find.byIcon(Icons.language));
      await tester.pumpAndSettle();
    }
    if (clickThrough) {
      // クリックスルー ON（復帰方法の案内バナー）の状態。viaDialog は、起動モードの
      // ダイアログを開いてそのスイッチで ON にする（ON でダイアログが自動で閉じる）。
      await tester.runAsync(() => loupe.setAppMode(AppMode.loupe));
      if (viaDialog) {
        await tester.tap(find.byIcon(Icons.window_outlined));
        await tester.pumpAndSettle();
        final dialogPath =
            await writeScreenshot(tester, boundaryKey, '$base-dialog');
        // ignore: avoid_print
        print('[ui_screenshots] wrote $dialogPath');
        await tester.runAsync(() async {
          await tester.tap(find.byType(SwitchListTile).last);
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pumpAndSettle();
      } else {
        await tester.runAsync(() => loupe.setClickThrough(true));
        await tester.pump();
      }
    }

    final path = await writeScreenshot(tester, boundaryKey, '$base$suffix');
    // ignore: avoid_print
    print('[ui_screenshots] wrote $path');
    if (compareExport) {
      final l10n = lookupAppLocalizations(Locale(locale));
      Uint8List? saved;
      pngSaver = (bytes, filename) async {
        saved = bytes;
        return '/fake/Downloads/$filename';
      };
      await tester.tap(find.byTooltip(l10n.exportButtonTooltip));
      await tester.runAsync(() async {
        for (var i = 0; i < 100 && saved == null; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await tester.pump(const Duration(milliseconds: 500));
      expect(saved, isNotNull, reason: '書き出しが保存まで進む');
      final exportPath =
          '${screenshotOutputDir().path}/$base-compare-export.png';
      await tester.runAsync(() => File(exportPath).writeAsBytes(saved!));
      // ignore: avoid_print
      print('[ui_screenshots] wrote $exportPath');

      // 保存された PNG を実際にデコードし、4 セルの画像部分の平均色が互いに
      // 異なる（= 4 型が別々に描かれて 1 枚に並んでいる）ことを確かめる。
      final means = await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(saved!);
        final frame = await codec.getNextFrame();
        final image = frame.image;
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final rgba = data!.buffer.asUint8List();
        // セルの位置は本番と同じ compareGridLayout で求める。4 セルは同じ大きさ
        // （幅 = 画像の幅から割り出し、高さ = 行の高さ）なので、組んだレイアウトの
        // 全体サイズが保存された PNG と一致することで、この割り出しの正しさを確かめる。
        const g = kCompareGridGap;
        final cellW = (image.width - 3 * g) ~/ 2;
        final rowH = (image.height - 3 * g) ~/ 2;
        final layout = compareGridLayout([
          for (var i = 0; i < 4; i++)
            ui.Size(cellW.toDouble(), rowH.toDouble()),
        ]);
        expect(layout.size,
            ui.Size(image.width.toDouble(), image.height.toDouble()),
            reason: 'compareGridLayout の全体サイズが書き出した PNG と一致する');
        final result = <List<double>>[];
        for (var i = 0; i < 4; i++) {
          // セルの上部は正方形の画像。
          final ox = layout.origins[i].dx.toInt();
          final oy = layout.origins[i].dy.toInt();
          var r = 0.0, gr = 0.0, b = 0.0;
          for (var y = oy; y < oy + cellW; y++) {
            for (var x = ox; x < ox + cellW; x++) {
              final o = (y * image.width + x) * 4;
              r += rgba[o];
              gr += rgba[o + 1];
              b += rgba[o + 2];
            }
          }
          final n = cellW * cellW;
          result.add([r / n, gr / n, b / n]);
        }
        image.dispose();
        codec.dispose();
        return result;
      });
      // ignore: avoid_print
      print('[ui_screenshots] compare-export cell mean RGB: $means');
      for (var i = 0; i < 4; i++) {
        for (var j = i + 1; j < 4; j++) {
          final d = (means![i][0] - means[j][0]).abs() +
              (means[i][1] - means[j][1]).abs() +
              (means[i][2] - means[j][2]).abs();
          expect(d, greaterThan(6.0), reason: 'セル $i と $j の平均色が近すぎる');
        }
      }
    }
    if (clickThrough) {
      await tester.runAsync(() => loupe.setClickThrough(false));
      await tester.runAsync(() => loupe.setAppMode(AppMode.settings));
    }
  }

  // ハイコントラスト（OS 設定が有効なときに切り替わるテーマ）。ファイル名は
  // wide-{light|dark}-ja-hc.png。
  for (final dark in [false, true]) {
    testWidgets(
      'screenshot wide/${dark ? 'dark' : 'light'}/ja high-contrast',
      (tester) => shoot(
        tester,
        widthLabel: 'wide',
        width: 1280,
        height: 800,
        dark: dark,
        locale: 'ja',
        suffix: '-hc',
        highContrast: true,
      ),
      skip: !screenshotsEnabled,
    );
  }

  // 強度スライダの上限付近の注意（#66、#51 注記1）。tunnel_vision を選び、
  // 中程度（印の説明）と上限（警告）を撮る。ファイル名は
  // wide-{light|dark}-{ja|en}-tunnel-{mid|max}.png（ハイコントラストは末尾 -hc）。
  for (final (label, width, height, dark, locale, hc, s, tag)
      in const <(String, double, double, bool, String, bool, double, String)>[
    ('wide', 1280, 800, false, 'ja', false, 0.5, 'mid'),
    ('wide', 1280, 800, false, 'ja', false, 1.0, 'max'),
    ('wide', 1280, 800, true, 'ja', false, 1.0, 'max'),
    ('wide', 1280, 800, false, 'en', false, 1.0, 'max'),
    ('wide', 1280, 800, false, 'ja', true, 1.0, 'max'),
  ]) {
    testWidgets(
      'screenshot $label/${dark ? 'dark' : 'light'}/$locale tunnel-vision $tag${hc ? ' hc' : ''}',
      (tester) => shoot(
        tester,
        widthLabel: label,
        width: width,
        height: height,
        dark: dark,
        locale: locale,
        suffix: '-tunnel-$tag${hc ? '-hc' : ''}',
        highContrast: hc,
        advancedFilterId: 'tunnel_vision',
        strength: s,
      ),
      skip: !screenshotsEnabled,
    );
  }

  // フィルタごとの説明（#80）。「モデルと出典」「表現できないこと」を開いた状態。
  // ファイル名は {wide|narrow}-{light|dark}-{ja|en}-explain-{deutan|cataract|
  // tetrachromacy|floaters}.png。sensus の実文言は native lib が要るため、
  // 実際の長さに近い**レイアウト確認用**の文を差し込む（内容は実データではない）。
  for (final (label, width, height, dark, locale, filterId, tag)
      in const <(String, double, double, bool, String, String?, String)>[
    ('wide', 1280, 1100, false, 'ja', null, 'deutan'),
    ('wide', 1280, 1100, true, 'en', null, 'deutan'),
    ('wide', 1280, 1100, false, 'ja', 'cataract', 'cataract'),
    ('wide', 1280, 1100, true, 'en', 'floaters', 'floaters'),
    ('wide', 1280, 1100, false, 'ja', 'tetrachromacy', 'tetrachromacy'),
    ('wide', 1280, 1100, true, 'en', 'tetrachromacy', 'tetrachromacy'),
    ('narrow', 800, 4200, false, 'ja', 'floaters', 'floaters'),
    ('narrow', 800, 4200, true, 'en', 'tetrachromacy', 'tetrachromacy'),
    ('narrow', 800, 4200, false, 'ja', null, 'deutan'),
  ]) {
    testWidgets(
      'screenshot $label/${dark ? 'dark' : 'light'}/$locale explanation $tag',
      (tester) {
        visionFilterCitationProvider = (_) => filterId == 'tetrachromacy'
            ? null
            : 'Machado, Oliveira & Fernandes (2009). A Physiologically-based '
                'Model for Simulation of Color Vision Deficiency. IEEE '
                'Transactions on Visualization and Computer Graphics, 15(6), '
                '1291-1298. doi:10.1109/TVCG.2009.113';
        visionFilterLimitationsProvider = (_) =>
            'A single global colour transform applied to every pixel. It does '
            'not model individual variation between people, the effect of '
            'lighting, or how the brain adapts to a deficiency over time. The '
            'preview is not what a person with this condition actually sees.';
        return shoot(
          tester,
          widthLabel: label,
          width: width,
          height: height,
          dark: dark,
          locale: locale,
          suffix: '-explain-$tag',
          advancedFilterId: filterId,
          expandProvenance: true,
        );
      },
      skip: !screenshotsEnabled,
    );
  }

  // 体験プリセット（見出しは体験名）。どの視覚フィルタの情報かを添える行の確認（#80）。
  for (final (locale, dark) in const [('ja', false), ('en', true)]) {
    testWidgets(
      'screenshot wide/${dark ? 'dark' : 'light'}/$locale explanation meniere',
      (tester) {
        visionFilterCitationProvider = (_) => null;
        visionFilterLimitationsProvider = (_) =>
            'Layout-only sample text about what the simulation cannot show.';
        return shoot(
          tester,
          widthLabel: 'wide',
          width: 1280,
          height: 1100,
          dark: dark,
          locale: locale,
          suffix: '-explain-meniere',
          preset: ('meniere', 'vertigo'),
          expandProvenance: true,
        );
      },
      skip: !screenshotsEnabled,
    );
  }

  // クリックスルー ON の復帰バナー（#63, #72）。ダイアログのスイッチで ON にすると
  // ダイアログが自動で閉じ、主画面の案内が見える。低い広幅（1280x480）と既定
  // ウィンドウ（800x600）でも、一覧とプレビューが破綻しないことを確認する。
  for (final (label, width, height, viaDialog)
      in const <(String, double, double, bool)>[
    ('wide', 1280, 800, true),
    ('wide-low', 1280, 480, false),
    ('default-window', 800, 600, false),
  ]) {
    testWidgets(
      'screenshot $label click-through banner',
      (tester) => shoot(
        tester,
        widthLabel: label,
        width: width,
        height: height,
        dark: false,
        locale: 'ja',
        suffix: '-clickthrough',
        clickThrough: true,
        viaDialog: viaDialog,
      ),
      skip: !screenshotsEnabled,
    );
  }

  // 言語ダイアログ（#82）。ファイル名は wide-{light|dark}-{ja|en}-languagedialog.png。
  for (final (dark, locale) in const <(bool, String)>[
    (false, 'ja'),
    (true, 'en'),
  ]) {
    testWidgets(
      'screenshot wide/${dark ? 'dark' : 'light'}/$locale language dialog',
      (tester) => shoot(
        tester,
        widthLabel: 'wide',
        width: 1280,
        height: 800,
        dark: dark,
        locale: locale,
        suffix: '-languagedialog',
        languageDialog: true,
      ),
      skip: !screenshotsEnabled,
    );
  }

  // 色覚 4 型の 2×2 比較（#84）。切替の前（compare-off）と後（compare-on）。
  // 広幅は light×ja / dark×en / light×en / dark×ja、狭幅（縦積み）は light×ja と
  // dark×en。wide の compare-on では書き出しも実行し、保存された PNG も書き出す。
  for (final (widthLabel, dark, locale) in const <(String, bool, String)>[
    ('wide', false, 'ja'),
    ('wide', false, 'en'),
    ('wide', true, 'ja'),
    ('wide', true, 'en'),
    ('narrow', false, 'ja'),
    ('narrow', true, 'en'),
  ]) {
    final size = sizes.firstWhere((s) => s.$1 == widthLabel);
    final height = widthLabel == 'narrow' ? 2600.0 : 1000.0;
    final tag = '$widthLabel/${dark ? 'dark' : 'light'}/$locale';

    testWidgets(
      'screenshot $tag compare-off',
      (tester) => shoot(
        tester,
        widthLabel: widthLabel,
        width: size.$2,
        height: height,
        dark: dark,
        locale: locale,
        suffix: '-compare-off',
      ),
      skip: !screenshotsEnabled,
    );

    testWidgets(
      'screenshot $tag compare-on',
      (tester) => shoot(
        tester,
        widthLabel: widthLabel,
        width: size.$2,
        height: height,
        dark: dark,
        locale: locale,
        suffix: '-compare-on',
        compare: true,
        compareExport: widthLabel == 'wide',
      ),
      skip: !screenshotsEnabled,
    );
  }

  for (final (widthLabel, dark, locale) in combos) {
    final size = sizes.firstWhere((s) => s.$1 == widthLabel);
    final tag = '$widthLabel/${dark ? 'dark' : 'light'}/$locale';

    testWidgets(
      'screenshot $tag',
      (tester) => shoot(
        tester,
        widthLabel: widthLabel,
        width: size.$2,
        height: size.$3,
        dark: dark,
        locale: locale,
        suffix: '',
      ),
      skip: !screenshotsEnabled,
    );

    // 縦長の全体撮りは狭幅（縦積み）だけ。広幅は 3 カラムが 1 枚に収まる。
    if (widthLabel == 'narrow') {
      testWidgets(
        'screenshot $tag (full length)',
        (tester) => shoot(
          tester,
          widthLabel: widthLabel,
          width: size.$2,
          height: 4200,
          dark: dark,
          locale: locale,
          suffix: '-full',
        ),
        skip: !screenshotsEnabled,
      );
    }
  }
}
