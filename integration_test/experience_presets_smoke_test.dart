// 実ブリッジ smoke test (#55)。
//
// widget test (test/experience_presets_test.dart) は experiencesProvider を
// fixture に差し替えて検証しているため、Rust ブリッジの初期化漏れ・同梱漏れを
// 検知できない（#52 の実害: 本番でプリセット欄が例外表示になった）。
// integration_test は実ネイティブライブラリをロードし、main() と同じ経路
// （services/native_bridge_service.dart の initNativeBridge()）で本物の
// experiences() / visionShaderGlsl() / visionUniformLayout() を呼ぶ。
//
// 実行: `flutter test integration_test/experience_presets_smoke_test.dart -d macos`
// app_bootstrap_test.dart と一緒に 1 回の `flutter test integration_test` へ
// まとめて渡すと、デスクトップでは 2 番目に起動する側のアプリ起動待ちが失敗する
// 既知の制約があるため、別コマンドとして実行する。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:universal_experience/l10n/app_localizations.dart';
import 'package:universal_experience/l10n/l10n_extensions.dart';
import 'package:universal_experience/models/disability_type.dart';
import 'package:universal_experience/models/vision_filter_catalog.dart';
import 'package:universal_experience/services/filter_service.dart';
import 'package:universal_experience/services/native_bridge_service.dart';
import 'package:universal_experience/services/preview_selection.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/src/rust/frb_generated.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';
import 'package:universal_experience/ui/widgets/experience_presets.dart';

Widget _presetsApp() {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => VisionFilterState()),
      ChangeNotifierProvider(create: (_) => FilterService()),
    ],
    child: const MaterialApp(
      // システムロケールに追従させると、実行環境（このリポの開発機は ja）次第で
      // 表示文言が変わり `en` 前提の find.text がすれ違う。テストは明示的に固定する。
      locale: Locale('en'),
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(child: ExperiencePresets()),
      ),
    ),
  );
}

/// home_screen.dart のプレビュー結線（#60）を最小構成で再現したアプリ。
/// [ExperiencePresets] のタップが実際に [BeforeAfterView] の描画へつながる
/// ことを、実ブリッジ（CPU `apply()`）込みで確かめる。
Widget _previewWithPresetsApp() {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => VisionFilterState()),
      ChangeNotifierProvider(create: (_) => FilterService()),
    ],
    child: const MaterialApp(
      locale: Locale('en'),
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              _PreviewFromState(),
              ExperiencePresets(),
            ],
          ),
        ),
      ),
    ),
  );
}

/// [_previewWithPresetsApp] 専用の配線ウィジェット。home_screen.dart の
/// `_buildPreviewSection` と同じ判定（`previewStrength`）で
/// [VisionFilterState] の選択を [BeforeAfterView] に渡す。
class _PreviewFromState extends StatelessWidget {
  const _PreviewFromState();

  @override
  Widget build(BuildContext context) {
    return Consumer2<VisionFilterState, FilterService>(
      builder: (context, visionState, filterService, _) {
        return BeforeAfterView(
          filter: visionState.build(),
          filterId: visionState.selectedId,
          strength: previewStrength(visionState, filterService),
          // integration_test では実ブリッジの CPU apply() を正準サイズ
          // （1024px）で 4 回走らせると重いため、実測に十分な小さめサイズで
          // 描画確認する（描画そのものは cpu_preview_all_filters_test.dart が
          // 正準サイズで別途カバー済み）。
          sampleSize: 64,
        );
      },
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final ok = await initNativeBridge();
    if (!ok) {
      fail('initNativeBridge() failed; check RustLib bundling (#55)');
    }
  });

  group('experiences()', () {
    testWidgets('実ブリッジで 4 件返る', (tester) async {
      expect(experiences(), hasLength(4));
    });

    testWidgets('id・分類が sensus 正本（cargo test の固定順）と一致する', (tester) async {
      final byId = {for (final e in experiences()) e.id: e};
      expect(byId.keys,
          {'meniere', 'bppv', 'vestibular_neuritis', 'labyrinthitis'});

      final meniere = byId['meniere']!;
      expect(meniere.vision, const VisionFilter.vertigo());
      expect(meniere.hearing, const HearingFilter.meniere());
      expect(meniere.urgency, Urgency.earlyConsultation);

      final bppv = byId['bppv']!;
      expect(bppv.vision, const VisionFilter.bppvRotation());
      expect(bppv.hearing, isNull);
      expect(bppv.urgency, Urgency.none);

      final vestibularNeuritis = byId['vestibular_neuritis']!;
      expect(
          vestibularNeuritis.vision, const VisionFilter.vestibularNeuritis());
      expect(vestibularNeuritis.hearing, isNull);
      expect(vestibularNeuritis.urgency, Urgency.emergency);

      final labyrinthitis = byId['labyrinthitis']!;
      expect(labyrinthitis.vision, const VisionFilter.vertigo());
      expect(labyrinthitis.hearing, const HearingFilter.labyrinthitis());
      expect(labyrinthitis.urgency, Urgency.earlyConsultation);
    });
  });

  group('プリセット欄（ExperiencePresets）', () {
    testWidgets('実ブリッジで例外なく描画される（Card 4枚）', (tester) async {
      await tester.pumpWidget(_presetsApp());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(Card), findsNWidgets(4));
    });

    testWidgets('カードをタップすると選択状態が変わる（色覚 FilterService は変更しない、#60）',
        (tester) async {
      await tester.pumpWidget(_presetsApp());
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(ExperiencePresets));
      final visionState = context.read<VisionFilterState>();
      final filterService = context.read<FilterService>();

      // タップ前に色覚フィルタを有効化しておき、体験プリセット適用で
      // 変更されないことも合わせて確認する（widget test と同じ契約、#60）。
      filterService.applyFilter(ColorVisionType.protanopia);
      expect(visionState.selectedId, isNull);

      final en = lookupAppLocalizations(const Locale('en'));
      await tester.tap(find.text(en.experienceMeniere));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(visionState.selectedId, 'vertigo');
      expect(visionState.selectedPresetId, 'meniere');
      expect(filterService.currentFilter, ColorVisionType.protanopia,
          reason: 'プリセット適用は色覚クイック選択の状態に干渉しない（#60）');
    });
  });

  group('プリセット → プレビュー結線（#60）', () {
    /// [finder] が見つかるまで実時間でポンプし続ける。integration_test は実
    /// デバイス上で動く（`flutter test` の FakeAsync とは違い実際の非同期）ため、
    /// `tester.pump(duration)` を繰り返すだけで実ブリッジの CPU apply() 完了を
    /// 待てる。
    Future<void> pumpUntilFound(
      WidgetTester tester,
      Finder finder, {
      int maxTries = 100,
    }) async {
      for (var i = 0; i < maxTries; i++) {
        if (finder.evaluate().isNotEmpty) return;
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('プリセット 4 種すべてが、タップで実ブリッジ CPU apply() まで例外なく描画される',
        (tester) async {
      await tester.pumpWidget(_previewWithPresetsApp());
      await tester.pumpAndSettle();

      final en = lookupAppLocalizations(const Locale('en'));
      // (プリセットのラベル, 選択後の after ペインに出るはずのフィルタ名) の組。
      // meniere と labyrinthitis はどちらも vertigo に写るため after ラベルは
      // 同じになる — それでも構わない（ここでの主張は「例外なく描画される」）。
      final cases = <(String presetLabel, String afterLabel)>[
        (en.experienceMeniere, visionFilterName(en, 'vertigo')),
        (en.experienceBppv, visionFilterName(en, 'bppv_rotation')),
        (
          en.experienceVestibularNeuritis,
          visionFilterName(en, 'vestibular_neuritis'),
        ),
        (en.experienceLabyrinthitis, visionFilterName(en, 'vertigo')),
      ];

      for (final (presetLabel, afterLabel) in cases) {
        await tester.tap(find.text(presetLabel));
        await tester.pump();
        await pumpUntilFound(tester, find.text(afterLabel));

        expect(tester.takeException(), isNull,
            reason: '$presetLabel 選択後の描画で例外が発生した');
        expect(find.text(afterLabel), findsOneWidget,
            reason: '$presetLabel 選択後、after ペインに "$afterLabel" が出ていない');
        expect(find.text(en.previewFailed), findsNothing,
            reason: '$presetLabel 選択後にプレビューが失敗表示になっている');
      }
    });
  });

  group('全 30 フィルタの shader/uniform ブリッジ呼び出し', () {
    for (final entry in kVisionFilterCatalog) {
      testWidgets('${entry.id}: visionShaderGlsl / visionUniformLayout が例外なく返る',
          (tester) async {
        // VisionFilterState.select() がカタログの defaultValue で payload を
        // 埋めるので、payload 付きフィルタも UI と同じ経路で実インスタンス化する
        // （手書きの座標値をここで重複定義しない）。
        final state = VisionFilterState()..select(entry.id);
        final filter = state.build();
        expect(filter, isNotNull, reason: '${entry.id} が build() できなかった');

        final glsl = visionShaderGlsl(filter: filter!);
        expect(glsl, isNotEmpty, reason: '${entry.id} の GLSL が空');

        final layout = visionUniformLayout(filter: filter);
        final uniforms = visionUniforms(
          filter: filter,
          strength: 1.0,
          time: 0.0,
          width: 64,
          height: 64,
        );
        expect(layout.length, uniforms.length,
            reason: '${entry.id} は layout と uniforms の長さが一致しない');
      });
    }
  });

  group('initNativeBridge() の二重初期化', () {
    testWidgets('RustLib.init() を直接 2 回呼ぶと StateError になる（ライブラリの既定挙動）',
        (tester) async {
      // RustLib.init() は async 関数なので同期的には投げない。StateError は
      // 返された Future の rejection として届くため、Future を直接 matcher に渡す。
      await expectLater(RustLib.init(), throwsA(isA<StateError>()));
    });

    testWidgets('initNativeBridge() は既に初期化済みなら例外を投げず true を返す（bootstrap の仕様）',
        (tester) async {
      expect(RustLib.instance.initialized, isTrue);
      final result = await initNativeBridge();
      expect(result, isTrue);

      // 二重呼び出し後もブリッジは正常に動作し続ける。
      expect(experiences(), hasLength(4));
    });
  });
}
