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
import 'package:universal_experience/models/preview_image_source.dart';
import 'package:universal_experience/models/sample_catalog.dart';
import 'package:universal_experience/models/vision_filter_catalog.dart';
import 'package:universal_experience/services/native_bridge_service.dart';
import 'package:universal_experience/services/preview_selection.dart';
import 'package:universal_experience/services/vision_filter_state.dart';
import 'package:universal_experience/src/rust/api/sensus_bridge.dart';
import 'package:universal_experience/src/rust/frb_generated.dart';
import 'package:universal_experience/ui/widgets/before_after_view.dart';
import 'package:universal_experience/ui/widgets/experience_presets.dart';
import 'package:universal_experience/ui/widgets/filter_browser.dart';
import '../test/support/color_vision_select.dart';

/// 統合フィルタ一覧（#72）を固定高さで置くヘルパ。体験プリセットは一覧の最上段に
/// 並ぶので、4 行とも初期表示で見える高さにしてある。
class _BrowserBox extends StatefulWidget {
  const _BrowserBox();

  @override
  State<_BrowserBox> createState() => _BrowserBoxState();
}

class _BrowserBoxState extends State<_BrowserBox> {
  final FilterBrowserController _controller = FilterBrowserController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 560,
        child: FilterBrowser(controller: _controller),
      );
}

Widget _presetsApp() {
  final visionState = VisionFilterState();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: visionState),
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
        body: _BrowserBox(),
      ),
    ),
  );
}

/// home_screen.dart のプレビュー結線（#60）を最小構成で再現したアプリ。
/// 体験プリセットの行（[ExperiencePresetTile]）のタップが実際に [BeforeAfterView] の描画へつながる
/// ことを、実ブリッジ（CPU `apply()`）込みで確かめる。
Widget _previewWithPresetsApp(ScrollController scrollController) {
  final visionState = VisionFilterState();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: visionState),
    ],
    // ConstrainedBox に const コンストラクタが無いため MaterialApp 以下は
    // const にできない。
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          // 外側のスクロールはテストが直接動かす（プリセットの行を確実にヒットテストできる
          // 位置へ出すため）。
          controller: scrollController,
          // home_screen.dart の ConstrainedBox(maxWidth: 800) を再現する
          // （#60）。これが無いと、幅無制限のウィンドウ上で
          // BeforeAfterView の左右ペインが横幅いっぱい（1000px超）の正方形に
          // なり、プリセットカードがウィンドウの縦サイズを大きく超えて
          // 押し出されてしまう。
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: const Column(
                children: [
                  _PreviewFromState(),
                  _BrowserBox(),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// [_previewWithPresetsApp] 専用の配線ウィジェット。home_screen.dart の
/// `_previewCard` と同じ判定（`previewStrength`）で
/// [VisionFilterState] の選択を [BeforeAfterView] に渡す。
class _PreviewFromState extends StatelessWidget {
  const _PreviewFromState();

  @override
  Widget build(BuildContext context) {
    return Consumer<VisionFilterState>(
      builder: (context, visionState, _) {
        return BeforeAfterView(
          filter: visionState.build(),
          filterId: visionState.selectedId,
          strength: previewStrength(visionState),
          // #78: imageSource は必須。実アセットからデコードできる既知の
          // サンプル id を使う（kDefaultSampleId、rootBundle 経由）。
          imageSource: const SamplePreviewImageSource(kDefaultSampleId),
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

  group('プリセット行（統合フィルタ一覧の最上段、#72）', () {
    testWidgets('実ブリッジで例外なく描画される（プリセットの行 4 つ）', (tester) async {
      await tester.pumpWidget(_presetsApp());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(ExperiencePresetTile), findsNWidgets(4));
    });

    testWidgets('行をタップすると層がそのプリセット 1 つに置き換わり、色覚クイック選択の層は無くなる（#120）',
        (tester) async {
      await tester.pumpWidget(_presetsApp());
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(FilterBrowser));
      final visionState = context.read<VisionFilterState>();

      // タップ前に色覚クイック選択（protanopia の層）を入れておく。体験プリセットは層を
      // そのプリセット 1 つに置き換えるので、色覚の層は無くなる（#120。かつては
      // プリセット適用が色覚の状態に干渉しない契約だった、#60）。
      selectColorVisionKey(visionState, 'protanopia');
      expect(visionState.layers.map((l) => l.id), ['protanopia']);

      final en = lookupAppLocalizations(const Locale('en'));
      await tester.tap(find.text(en.experienceMeniere));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(visionState.layers.map((l) => l.id), ['vertigo'],
          reason: 'プリセット選択は層を全部そのプリセット 1 つに置き換える');
      expect(visionState.selectedId, 'vertigo');
      expect(visionState.selectedPresetId, 'meniere');
      expect(visionState.focusedVariantId, isNull);
    });
  });

  group('プリセット → プレビュー結線（#60）', () {
    /// [finder]（プリセットの行）が実際にヒットテストできる位置へ、一覧自身のスクロールと
    /// 外側のスクロール（[scrollController]）を動かして出す。
    ///
    /// 実ジェスチャの `drag` や `ensureVisible` には頼らない。外側のスクロールの中に一覧
    /// 自身のスクロールが入れ子になっており、`drag` は画面中央の位置で始まるため、中央が
    /// 一覧の上に来ると外側ではなく一覧側がスクロールする。また #120 では、プリセットを
    /// タップすると層がそのプリセットの 1 つに置き換わり、置き換わった層に対応するフィルタの
    /// 行（一覧の下の方）が選択中になって、[FilterListTile] が一覧の内側のスクロールを
    /// その行まで動かす。すると一覧の最上段にあるほかのプリセットの行は、矩形が画面の中に
    /// あっても一覧の表示領域の上へ出てしまい、ヒットテストが当たらない（2 枚目以降が
    /// 外れる）。そのため、一覧を先頭へ戻し、外側を末尾まで動かして一覧の箱を画面の下端へ
    /// 揃える。最後に実際のヒットテストで確かめ、外れるならタップの前に明示的に fail() する。
    Future<void> revealPresetCard(
      WidgetTester tester,
      Finder finder,
      ScrollController scrollController,
    ) async {
      // 一覧自身のスクロール（行から見て最も近い Scrollable）を先頭へ戻す。
      final listScrollable = tester.state<ScrollableState>(
        find.ancestor(of: finder, matching: find.byType(Scrollable)).first,
      );
      listScrollable.position.jumpTo(listScrollable.position.minScrollExtent);
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
      await tester.pump();
      if (finder.hitTestable().evaluate().isEmpty) {
        fail(
          '$finder が外側を末尾までスクロールしてもヒットテストできない '
          '(rect=${tester.getRect(finder)}, '
          'window=${tester.view.physicalSize / tester.view.devicePixelRatio})',
        );
      }
    }

    testWidgets('プリセット 4 種すべてが、タップで実ブリッジ CPU apply() まで例外なく描画される',
        (tester) async {
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      await tester.pumpWidget(_previewWithPresetsApp(scrollController));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(FilterBrowser));
      final visionState = context.read<VisionFilterState>();

      // afterImageRenderer（BeforeAfterView が公開する production 供給源、
      // 実ブリッジの CpuVisionRenderer.applier を最終的に呼ぶ）をラップし、
      // 実ブリッジの CPU apply() が完了するたびに renderCount を増やし、
      // 完了した filter を lastCompletedFilter に記録する（#60）。テキストが
      // 出るまで単純にポーリングするより、実際に何を待っているか（このタップ
      // が引き起こした描画そのもの）が明確になる。
      //
      // Completer ではなく単調カウンタ + 直近の完了 filter にしてあるのは、
      // 1 回のタップに対して BeforeAfterView 側の再構築が複数回の render
      // 呼び出しを引き起こすことがあり（CI で実測: "Bad state: Future
      // already completed"）、Completer だと 2 回目の complete() で例外に
      // なるため。renderCount が増えただけでは「このタップより前に投げられて
      // いた古い render がここで完了した」可能性を排除できないので、完了した
      // filter が現在の BeforeAfterView.filter と一致することまで確認する。
      var renderCount = 0;
      VisionFilter? lastCompletedFilter;
      final productionRenderer = afterImageRenderer;
      addTearDown(() => afterImageRenderer = productionRenderer);
      afterImageRenderer = (source, filter, strength) async {
        final result = await productionRenderer(source, filter, strength);
        renderCount++;
        lastCompletedFilter = filter;
        return result;
      };

      final en = lookupAppLocalizations(const Locale('en'));
      // (experience id, 選択後の after ペインに出るはずのフィルタ名) の組。
      // meniere と labyrinthitis はどちらも vertigo に写るため after ラベルは
      // 同じになる — それでも構わない（ここでの主張は「例外なく描画される」）。
      //
      // カードは experience id ベースの Key（experienceCardKey）で見つける。
      // 表示名の文字列は「上に積まれたプレビューペインのせいでカードが
      // ビューポート外に出て tap のヒットテストが外れる」問題には無関係
      // （原因は off-screen であることそのもの）だが、id ベースの Key の方が
      // ロケール・レイアウトに依存せず安定して見つけられる。
      final cases = <(String experienceId, String afterLabel)>[
        ('meniere', visionFilterName(en, 'vertigo')),
        ('bppv', visionFilterName(en, 'bppv_rotation')),
        ('vestibular_neuritis', visionFilterName(en, 'vestibular_neuritis')),
        ('labyrinthitis', visionFilterName(en, 'vertigo')),
      ];

      for (final (experienceId, afterLabel) in cases) {
        final cardFinder = find.byKey(experienceCardKey(experienceId));
        // プレビューペインの下にあるため、タップ前に確実にヒットテストできる位置へ出す。
        await revealPresetCard(tester, cardFinder, scrollController);

        final renderCountBeforeTap = renderCount;
        await tester.tap(cardFinder);
        await tester.pump();

        // タップ直後に選択状態そのものも確認する（実描画の結果だけを見て、
        // 選択が正しく反映されたことを間接的に推測しない、#60）。
        expect(visionState.selectedPresetId, experienceId,
            reason: '$experienceId タップ直後に selectedPresetId が反映されていない');

        // 実ブリッジの CPU apply() が「このタップの選択」で完了するまで待つ
        // （renderCount が増えただけでなく、完了した filter が現在の
        // BeforeAfterView.filter と一致することまで確認する、#60）。
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        VisionFilter? currentWidgetFilter() =>
            tester.widget<BeforeAfterView>(find.byType(BeforeAfterView)).filter;
        while ((renderCount <= renderCountBeforeTap ||
                lastCompletedFilter != currentWidgetFilter()) &&
            DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        final rendered = renderCount > renderCountBeforeTap &&
            lastCompletedFilter == currentWidgetFilter();
        await tester.pump();
        await tester.pump();
        // tester.takeException() は呼ぶと例外キューを消費してしまうため、
        // ここで一度だけ読み取り、タイムアウト時のメッセージと後段の
        // 例外なしチェックの両方でこの値を使い回す（#60）。
        final caughtException = tester.takeException();
        expect(
          rendered,
          isTrue,
          reason: '$experienceId タップ後、実ブリッジの描画が完了しなかった '
              '(renderCount=$renderCount, lastCompletedFilter='
              '$lastCompletedFilter, 例外の有無=${caughtException != null})',
        );

        // vestibular_neuritis はプリセットカードの見出し
        // （experienceName、"Vestibular neuritis"）とプレビューの after
        // ラベル（visionFilterName、こちらも "Vestibular neuritis"）が同じ
        // 文字列になるため、ページ全体ではなく BeforeAfterView の中だけで
        // 探す（#60）。
        final afterLabelFinder = find.descendant(
          of: find.byType(BeforeAfterView),
          matching: find.text(afterLabel),
        );

        expect(caughtException, isNull, reason: '$experienceId 選択後の描画で例外が発生した');
        expect(afterLabelFinder, findsOneWidget,
            reason: '$experienceId 選択後、after ペインに "$afterLabel" が出ていない');
        expect(
          find.descendant(
            of: find.byType(BeforeAfterView),
            matching: find.text(en.previewFailed),
          ),
          findsNothing,
          reason: '$experienceId 選択後にプレビューが失敗表示になっている',
        );
      }
    });
  });

  group('全 30 フィルタの shader/uniform ブリッジ呼び出し', () {
    for (final entry in kVisionFilterCatalog) {
      testWidgets('${entry.id}: visionShaderGlsl / visionUniformLayout が例外なく返る',
          (tester) async {
        // VisionFilterState.replaceWith() がカタログの defaultValue で payload を
        // 埋めるので、payload 付きフィルタも UI と同じ経路で実インスタンス化する
        // （手書きの座標値をここで重複定義しない）。
        final state = VisionFilterState()..replaceWith(entry.id);
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
