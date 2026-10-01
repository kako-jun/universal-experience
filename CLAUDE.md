# Universal Experience 開発者向けドキュメント

感覚障害シミュレーションアプリ。「決定版」を目指し、乱立するシミュレータを統一する。

## コンセプト

### 3つの「ユニバーサル」

1. **Universal Global**: 世界共通のアプリ
2. **Universal Standard**: 科学的に正確なアルゴリズム
3. **Universal Coverage**: 複数の障害タイプに対応

## プロジェクト構造

```
lib/
├── main.dart
├── l10n/                   # 多言語化（ARB: app_en.arb / app_ja.arb、ja/en。生成物は非コミット）。
│                           # locale_resolution.dart が「選んだ言語 → OS → 英語」の解決の唯一の入口（#82）
├── models/
│   ├── vision_filter_catalog.dart   # sensus カタログ（30種）の Dart 側定義と、色覚の別名表（-omaly = -opia と同 id・variantId・強度 0.6。
│   │                                 # kVisionAliases / resolveVisionKey / colorVisionDefaultStrength、#124）
│   ├── vision_filter_contract_notes.dart # sensus API 契約上の注意の定義（強度の上限付近の警告の対象・閾値、#66）
│   ├── sample_catalog.dart          # サンプル画像集（8種）+ フィルタ id ごとの推奨サンプル（#78）
│   └── preview_image_source.dart    # プレビュー原画の値型（サンプル/ユーザー画像、#78）
├── rendering/
│   ├── cpu_vision_renderer.dart     # sensus CPU apply() 経由、プレビュー描画の正本（#85）。
│   │                                 # 複数ステップ版 applyPipeline（sensus Pipeline、#118）も持つ
│   ├── color_matrices.g.dart        # sensus 由来 Machado 11段テーブルの生成物（GPU 経路専用）
│   ├── shader_filter.dart           # sensus 由来 GLSL → Impeller FragmentProgram 適用
│   │                                 # （ライブ画面キャプチャ向けに残置、現状 production 未使用）
│   └── image_fit.dart               # 任意画像を正準サイズの正方形へレターボックス（#78）
├── services/
│   ├── app_shortcuts.dart           # アプリ内キー操作（/, ↑↓, ←→, Esc, Cmd/Ctrl+V）の Intent 定義（#63/#72/#97/#120）
│   ├── clipboard_image_reader.dart  # クリップボード画像取得の seam（実体は pasteboard、#97）
│   ├── color_vision_compare.dart    # 色覚 4 型の 2×2 比較で並べる型（カタログ順・実験的を除く）と
│   │                                 # 切替を出す条件（色覚層があるとき。colorVisionLayerOf）・セルのフィルタ（#84）・
│   │                                 # 他の層の土台と色覚の強度（colorVisionCompareInputOf、#122）
│   ├── export_service.dart          # PNG エクスポート（メタ焼き込み・「シミュレーション（近似）」と実験的フィルタの注記の焼き込み #80・Downloads へ非上書き保存・フォルダで表示、#43/#64）。2×2 比較の書き出し用に composeCompareGrid（#84）。複数層はキャプションを層ごとの行にし（ExportCaption.layered）、ファイル名の症状 id は exportSymptomId（適用順・48 文字上限・`-plusN`、#121）
│   ├── experience_source.dart       # 体験プリセットの供給源 seam・availableExperiences・
│   │                                 # isValidExperiencePreset（永続化した選択の検証、#65）
│   ├── filter_list_selection.dart   # 統合フィルタ一覧（色覚 7 型 + advanced 30 = 33 行。行はカタログ id + 別名 id）の
│   │                                 # 検索・選択入口 toggleFilterListEntry・↑↓ の順送りの純粋ロジック（#72）
│   ├── export_layers.dart           # 書き出しが数える層 effectiveExportLayers（強度 > 0 のみ。表示の整数パーセントが 0 になる強度も除く）・描画時点の控え ExportLayer / exportLayersOf（#121）
│   ├── hotkey_actions.dart          # グローバルホットキー4アクションの実処理（#63。フィルタ解除は全層を外す、#121 でテスト固定）
│   ├── hotkey_service.dart          # hotkey_manager 登録の副作用層（#63）
│   ├── image_source_state.dart      # プレビュー原画（サンプル/ユーザー画像）の選択の唯一の正本（#78）
│   ├── loupe_rect_source.dart       # ルーペ矩形決定元のインターフェース（#44 向け seam、#63）
│   ├── loupe_window_controller.dart # ルーペ窓のモード/透過/最前面/クリックスルー（#63）
│   ├── native_bridge_service.dart   # flutter_rust_bridge（sensus-core）の bootstrap 初期化
│   ├── preview_selection.dart       # プレビュー強度の出どころを一本化する判定（#60/#63）・
│   │                                 # 複数層のプレビューに渡すステップ列 previewPipelineSteps（#119）
│   ├── settings_service.dart        # テーマ・言語・welcomeBannerDismissed（#78）。選択状態は持たない（VisionFilterStore が正本、#124）
│   ├── tray_menu_labels.dart        # トレイの i18n 解決済み文言 TrayMenuLabels・クイック色覚一覧 quickColorVisionFilters（#65）
│   ├── tray_service.dart            # タスクトレイ（updateLocalization で文言を差し替える #82・
│   │                                 # カテゴリ別「高度なフィルタ」サブメニューで UI と双方向同期 #65。チェック式の多選択 #121）
│   ├── tray_locale_sync.dart        # 言語の選択/OS ロケール変更をトレイの文言へ橋渡し（#82）
│   ├── vision_filter_snapshot.dart  # 層・強度の記憶・payload の永続 JSON（v2。v1 も読む）と、
│   │                                 # カタログ定義に照らした補正 sanitizeVisionParams（#65/#117）
│   ├── vision_filter_store.dart     # VisionFilterState の SharedPreferences 永続化・起動時復元・
│   │                                 # 300ms デバウンス・flush（#65）・旧 settings.filterType /
│   │                                 # intensityByType / 版 1 の取り込み（一度だけ・旧キー削除）
│   │                                 # migrateLegacySettings（#117/#124）
│   ├── vision_layer.dart            # VisionLayer（id・payload・別名 variantId）・強度の記憶キー・
│   │                                 # 層の列の不変条件 normalizeVisionLayers（#117）・
│   │                                 # 多選択の結果 VisionLayerResult（added/removed/replaced/blocked、#119）
│   ├── vision_filter_metadata.dart  # urgency/urgency_escalation/recommended_strength の
│   │                                 # provider seam（sensus ブリッジが唯一の正本、#76/#77）。
│   │                                 # citation/limitations も同じ seam（#80）。複数層の相談喚起の
│   │                                 # 入力の統合 mergeConsultInputs / consultInputForFilters（#119。PNG 書き出しが使う、#121）
│   └── vision_filter_state.dart     # 層の列・フォーカス・強度の記憶（キー variantId ?? id）・
│                                     # パラメータの記憶（#77/#117）・多選択 API
│                                     # toggle/remove/setLayerStrength/setLayerParams/replaceWith（#119）・
│                                     # 初回起動の層 seedInitialLayers（#124）
├── src/rust/                        # flutter_rust_bridge 生成コード（sensus-core 連携）
└── ui/
    ├── screens/home_screen.dart
    ├── widgets/                     # filter_browser（左カラム「選ぶ」: 検索・カテゴリ・統合一覧、#72）,
    │                                 # filter_list_tile（一覧の 1 行: チェック・適用順の番号バッジ、#120）,
    │                                 # layer_chip_strip（プレビュー上の適用順チップ帯・✕・すべて解除、#120）,
    │                                 # adjust_panel（右カラム「調整」: 2 層以上は層ごとの節、#72/#120）,
    │                                 # before_after_view（複数層は名前の要約見出し・書き出しは層ごとの行と併合した受診喚起、#120/#121）, loupe_hud,
    │                                 # color_vision_compare_view（色覚 4 型の 2×2 比較と書き出し、#84。他の層の土台つき、#122）,
    │                                 # experience_presets（体験プリセットの行 ExperiencePresetTile）, filter_param_panel,
    │                                 # consult_notice_block（受診喚起の共有表示ウィジェット、#76）,
    │                                 # strength_caution（強度スライダの上限付近の印・注記、#66）,
    │                                 # filter_provenance（モデルと出典・表現できないこと、#80）,
    │                                 # experimental_badge（「実験的」バッジ、#80）,
    │                                 # window_mode_panel（起動モード・最前面・クリックスルー・
    │                                 # ホットキー一覧を持つ。AppBar のダイアログで開く、#63/#72）,
    │                                 # loupe_hud（ルーペ窓モード限定の HUD。症状名・強度・
    │                                 # 受診喚起・原画比較・設定を開く、#79）,
    │                                 # language_dialog（AppBar の言語ピッカー。自動/日本語/English、#82）,
    │                                 # click_through_dialog_scope（ダイアログ共通のクリックスルー安全策、#63/#82）,
    │                                 # image_source_picker（サンプルチップ・ファイル選択・
    │                                 # drag&drop・クリップボード貼り付け、#78/#97）, welcome_banner（初回案内、#78）
    └── theme/app_theme.dart         # light/dark に加え highContrastTheme / highContrastDarkTheme
                                      # （contrastLevel 1.0。OS のハイコントラスト設定で MaterialApp が自動選択、#72）

rust/                        # sensus-core を FRB で公開する Rust crate
├── Cargo.toml
└── src/
    ├── api/sensus_bridge.rs
    ├── frb_generated.rs
    └── golden_gen.rs        # GPU golden 参照生成（#[cfg(test)] のみ）
rust_builder/                 # cargokit 統合（#55）。flutter build/run 時に rust/ をビルドし
                               # macOS/Linux アプリへ同梱する FFI plugin（生成物、直接編集しない）

tools/                       # シェーダ codegen（sensus の .frag → Impeller サブセットへ機械変換）
                              # + generate_samples.dart（サンプル画像集の生成、#78）
                              # + generate_font_atlases.py（サンプル用フォントの生成、#99）
                              #   samples-sync / font-atlas-sync ワークフローが生成物との一致を検証（#115）
                              # + fonts/（Noto Sans / Noto Sans JP 由来のビットマップフォント。OFL の
                              #   全文・著作権表示・出典は fonts/README.md、#99）
                              # + check_frb_drift.sh（FRB 生成物のドリフト検証。CI の check job が実行、#88）
shaders/                     # 変換済み .frag（ビルド時 impellerc がコンパイル）
assets/samples/              # サンプル画像集（図形は自作・手続き生成、#78。文字は OFL フォント、#99）。出典は README.md

macos/                       # macOS ランナー（現行対応）
linux/                       # Linux ランナー（現行対応）
# Android / Windows ランナーは計画中（未作成）

DESIGN.md                    # UI 設計原則（カラートークン・タイポ・余白・コンポーネント・画面構成・検証方法、#72）

test/
├── no_hardcoded_colors_test.dart   # lib/ の色ハードコードを検出（例外は DESIGN.md の例外表と一致させる、#72）
├── app_theme_test.dart             # ハイコントラストテーマの生成と MaterialApp での切替（#72）
├── home_screen_layout_test.dart    # 3 カラム/縦積み・プレビューの初回ビューポート（準備中・読み込み済みの両方で測定）と画像の高さ配分（#130）・空状態・キー操作（#72）
├── accessibility_guidelines_test.dart # Flutter 標準ガイドライン（タップ領域・ラベル・コントラスト）を主画面・選択別パネル・ダイアログ・HUD に 4 テーマ × ja/en で当てる（#45）
├── accessibility_semantics_test.dart  # スライダー/ドロップダウンの名前と値・見出し・選択状態・画像の代替テキスト・liveRegion・視差効果・Esc で閉じてフォーカスが戻る（#45）
├── tap_target_size_test.dart       # macOS 指定で操作領域が 48dp 以上（padded + standard・言語ダイアログの選択肢、#72/#82）
├── filter_browser_test.dart        # 統合一覧の検索・カテゴリ切替・行の選択（#72）
├── filter_browser_multi_select_test.dart # 統合一覧のチェック式・番号バッジが段順・色覚の排他置き換え・上限で未選択の行が無効（色覚置き換え行とプリセットは有効）・プリセット置換と一致時だけ強調・行フォーカス移動（#120）
├── layer_chip_strip_test.dart      # チップ帯: 2 層以上で出る・チップで調整中が移る・✕ で 1 層除去・すべて解除・状態が形で分かる（#120）
├── adjust_panel_layers_test.dart   # 調整パネルの層ごとの節・調整中の層だけ展開・強度スライダー 1 本・1 層は従来の見た目（#120）
├── home_screen_multi_layer_heading_test.dart # 複数層の見出し（名前の要約）・書き出しボタンが複数層でも有効・2×2 スイッチが色覚層のあるときだけ（#120/#121/#122）
├── export_multi_layer_test.dart    # 複数層の書き出し: 層ごとの行・最大の緊急度と併合した escalation・実験的の注記・強度 0 の層を数えない・ファイル名・描画時点の控え・単一層の従来どおり（#121）
├── home_screen_multi_select_keys_test.dart # ↑↓ は選択を変えず Space/Enter で足し引き・←→ は調整中の層の強度（#120）
├── home_screen_slash_key_test.dart # `/` のガードはテキスト入力中だけ: チップ・ボタン・スライダー・一覧の行にフォーカスがあっても検索欄へ移り全選択・検索欄の中では奪わない・↑↓←→ のガードは不変（#141）
├── home_screen_search_down_key_test.dart # 検索欄の ↓ で先頭のフォーカス可能な行へ（選択は不変・空/絞り込み/上限無効/可視 0 件/プリセットのみは奪わず入力欄がキャレットを末尾へ/狭幅）・先頭行（上限で無効なら最初の有効行）の ↑ で検索欄へ戻る（折り返さない・キャレット維持）・IME 変換中は奪わない・検索欄の ↑←→Home/End`/`Ctrl+V・チップ/スライダー上の ↓ は不変（#141）
├── filter_list_selection_test.dart # 統合一覧の純粋ロジック（#72）
├── color_vision_compare_test.dart  # 2×2 比較で並べる型の順・色覚層の検出・土台と強度（colorVisionCompareInputOf）・フィルタの対応表（#84/#122）
├── color_vision_compare_view_test.dart # 2×2 の描画・Semantics（失敗文言・描画済みの強さ）・直列最新優先・失敗（控えがある間は出さない）・書き出し PNG の実画素・土台（1 回だけ合成・色覚の強度だけ動かしても再合成しない・4 セルが土台 + 各型とバイト一致・層の名前つきキャプション／ファイル名）（#84/#122）
├── home_screen_color_vision_compare_test.dart # 「2×2 で比較」の切替が色覚層のあるときだけ出て（他の層と重ねていても出る・色覚が無ければ出ない）Before / After・見出しと入れ替わる／Tab で操作できる／行からの → は高さによらず受け口／bypass（#84）
├── clipboard_paste_test.dart       # クリップボード画像の貼り付け経路・失敗 5 種・Cmd/Ctrl+V・ボタン（#97）
├── language_dialog_test.dart       # 言語ピッカー: 切替で追従・永続化・自称名の網羅と読み上げ言語・画面とトレイの言語一致（#82）
├── tray_locale_sync_test.dart      # 言語の選択/OS ロケール変更でトレイの文言が更新される（#82）
├── tray_advanced_filters_test.dart # トレイの「高度なフィルタ」サブメニュー: 構造・チェック式（層の集合から導く）・クリック→状態・上限での灰色・UI との双方向同期・言語追従・click-through 不干渉（#65/#121）
├── vision_filter_snapshot_test.dart # 永続 JSON v2 の往復・層の不変条件・v1 → v2 変換・壊れた値/未知 id/範囲外のフォールバック（#65/#117）
├── vision_filter_store_test.dart   # 永続化ストア・VisionFilterState.snapshot/restore・旧キーの取り込み（migrateLegacySettings: filterType のみ・版 1 のみ・origin 入り v2 の読み込み・書き込み失敗でも結果はメモリへ入る・壊れた保存は filterType の層と旧強度で作り直す・intensityByType）（#65/#117/#124）
├── color_vision_alias_test.dart    # 色覚 7 種のキー（カタログ id + 別名 id）の解決・-omaly の既定強度 0.6・強度記憶の独立・同じ色覚の再選択・色覚グループの排他（#124）
├── vision_filter_persistence_app_test.dart # 実アプリ（buildRootApp）を作り直して選択が復元される・旧強度の取り込み（#65/#117）
├── vision_filter_stage_test.dart   # 段の表（30 フィルタがちょうど 1 段・段内は sensus 宣言順）と適用順・色覚の排他グループ（#117）
├── vision_layer_test.dart          # 強度の記憶キー・別名の検証・層の列の正規化（上限・排他・重複・適用順）（#117）
├── vision_filter_multi_select_test.dart # 多選択 API: toggle/remove・色覚の排他と置き換え・上限 5 と例外・プリセット置換と破棄・強度/パラメータ・単一選択の互換・pipelineSteps・上限ちょうど 5 層・同段 3 層の pipelineSteps 列のリテラル固定・永続化 v2 の往復（#119）
├── home_screen_multi_layer_preview_test.dart # 複数層のプレビュー: pipelineApplier をフェイクにして段順・強度・payload・強度 0 除外・単一層の従来経路・bypass・steps だけ変わる更新での再合成・合成失敗の表示と旧結果の dispose を確認、推奨サンプルの focusedId 追従（#119）
├── consult_input_merge_test.dart   # 複数層の相談喚起入力の統合: urgency は最大・escalation は段ごとに重複除去（#119）
├── home_screen_harness_test.dart   # ハーネス（installHomeScreenFixtures）の契約: 差し替えと復元（読み込み・適用・複数層の合成）・アプリ本体経路で単一層/2 層のフィルタ選択・強度変更・画像読み込みを実時間（runAsync）で進めても RustLib 未初期化の例外が漏れない（#127/#131）
├── support/home_screen_harness.dart # HomeScreen を Provider 一式で組む widget test 用の共通部品。HomeScreen / UniversalExperienceApp を pump するテストは setUp で installHomeScreenFixtures（体験・メタデータ・プレビューの読み込み/適用・複数層の合成 pipelineApplier を Rust 非依存のフェイクに固定）、tearDown で resetHomeScreenFixtures を呼ぶ（独自 pump で実ローダ/実レンダラを残さない、#131）
├── support/color_vision_select.dart # 色覚 7 種のキーで単一選択するテスト用ヘルパ（別名を解いて replaceWith へ渡す）
├── support/screenshot_harness.dart # スクリーンショット用フォント読込・PNG 書出し（フォントはコミットしない）
└── ui_screenshots/                 # HomeScreen の PNG 書出し。`UE_SCREENSHOTS=1` のときだけ実行（DESIGN.md §8）

docs/
├── adr/                     # 設計判断の正本（Architecture Decision Records）
├── accessibility.md         # ue 自身の UI のアクセシビリティ: 画面別チェックリスト・既知の制約・実機確認の項目（#45）
├── ADDING_A_LANGUAGE.md     # 言語の追加手順と医学用語の訳の確認方針（#82）
├── ARCHITECTURE.md
├── COLOR_ALGORITHM.md
├── GETTING_STARTED.md
├── PLATFORM_APIS.md
├── sensus-integration.md
└── competitive-analysis.md
```

`core/`（旧 LMS 実装）と `plugins/color_vision_filter/`（旧 system-wide ネイティブプラグイン）は
#13 で撤去済みで現存しない。経緯は `docs/adr/2026-05-31-sensus-core-consolidation.md` を参照。

## アーキテクチャ

```
Flutter UI (Presentation)
    ↓
Services / State (Provider)
    ↓
flutter_rust_bridge (FRB)
    ↓
sensus-core (Rust, アルゴリズム正本) + FragmentProgram シェーダ (GPU 描画)
```

## 色覚アルゴリズム

### 色空間変換

```
linear sRGB → Machado 2009 per-severity 行列 → simulated linear sRGB
```

正本は sensus-core の `vision/color.rs`。色覚 3 型（protanopia/deuteranopia/
tritanopia）は LMS 色空間を経由しない（旧 LMS 実装は #13 で撤去済み、
`docs/COLOR_ALGORITHM.md` 参照）。Machado, Oliveira, Fernandes (2009) が
プリ計算した severity=0.0〜1.0 の 11 段テーブルを linear sRGB 空間へ直接適用し、
中間 strength はテーブルを区分線形補間する。例外: achromatopsia は BT.709
輝度への変換、tetrachromacy は HPE（Hunt-Pointer-Estévez）行列を linear RGB に
流用した疑似 LMS ヒューリスティックを使う（どちらも Machado 行列とは別経路）。

- 事前計算された変換行列で高速処理
- 強度補間による柔軟な調整

### 対応色覚異常（7 型）

| タイプ | 有病率（男性） |
|--------|--------------|
| Protanopia | 約1% |
| Deuteranopia | 約1% |
| Tritanopia | 0.001% |
| Achromatopsia | 0.003% |
| Protanomaly | 約1% |
| Deuteranomaly | 約5% |
| Tritanomaly | 0.01% |

## プラットフォーム実装

かつては OS 全体（他アプリ含む全画面）へ色覚フィルタを適用する独自ネイティブ機構
（Android: AccessibilityService + Overlay、Windows: Magnification API、macOS:
CGSetDisplayTransferByTable、Linux: Wayland/X11 compositor 連携）を目指していたが、
sensus-core への一元化に伴い撤去した。判断の経緯・代替案・根拠は
`docs/adr/2026-05-31-sensus-core-consolidation.md` を参照。各 API の調査自体は
歴史的記録として `docs/PLATFORM_APIS.md` に残す。

現在の before/after プレビューは sensus の CPU `apply()`（`CpuVisionRenderer`、#85）が
描画する。GPU シェーダ（`ShaderFilter`）はライブ画面キャプチャ（他アプリ含む全画面。
未実装、`docs/adr/2026-09-26-loupe-as-single-render-unit.md`）向けに残置してあるが、
現状 production コードからは呼ばれない。

## 設計判断

> formal な ADR（判断・代替案・根拠・結果）は `docs/adr/` を正本とする。本節は概要。

### Flutter採用

- クロスプラットフォーム効率
- ネイティブ並みの性能
- 活発なエコシステム

### Provider選定

- Flutterチーム推奨
- シンプルで学習コスト低
- 将来的にRiverpod移行可能

### 主画面の構成（統合一覧 + 3 カラム）

色覚 7 型・advanced 30 フィルタ・体験プリセットを 1 つの検索できる一覧に統合し、広幅は
選ぶ / 見る / 調整の 3 カラム、狭幅は縦積み。起動モード等は AppBar のダイアログへ移した。
カテゴリ切替を `NavigationRail` でなく `ChoiceChip` の `Wrap` にした理由と代替案（`NavigationRail`・
ボトムシート）、ハイコントラスト対応は `docs/adr/2026-09-30-home-screen-unified-list-and-three-columns.md`。

### 色覚 4 型の 2×2 比較

層の集合に色覚の層があるときだけ「2×2 で比較」を出し、ON の間は中央カラムの Before / After の代わりに
色覚 4 型（カタログの非実験的な色覚）を同じ画像・同じ強さで並べる。描画・書き出しは既存の経路を
再利用する（専用レンダラを持たない）。他の層（強度 > 0、色覚より前）を重ねているときは、それらを 1 回だけ適用した画像を
土台にして 4 型を 1 枚ずつ重ねる（土台は色覚の強度だけが動いても作り直さない。書き出しのキャプションに症状名行、ファイル名は
層の id の適用順連結）。色覚の強度 0 は単独選択と同じく切替は出たまま 4 セルとも恒等で「0%」（#122）。Before / After との関係と理由は
`docs/adr/2026-09-30-color-vision-2x2-compare.md`。

### 状態モデルの統一と多症状の同時適用（#124 で完了）

選択状態は `VisionFilterState` の 1 系統（カタログ 30 フィルタ + 色覚の別名 3。`ColorVisionType` / `FilterService` は #124 で削除）。
選択の単位は「カタログ id ごとに 1 つのレイヤー」の順序つき列（最大 5、色覚は排他、
適用順は段で固定）で、sensus の `Pipeline` で合成する。色覚 7 種はカタログ id（protanopia 等）と別名 id
（protanomaly 等 = 対応する -opia と同じカタログ id + `variantId` + 既定強度 0.6。別名表は
`lib/models/vision_filter_catalog.dart`）で選ぶ。判断・代替案は
`docs/adr/2026-09-30-multi-select-filter-state-model.md`。強度の記憶は層でなくキー（`variantId ?? id`）ごとに
持ち、永続化は v2 JSON（#117）。旧保存（`settings.filterType` / `intensityByType` / 版 1 の `settings.visionFilter`）は
起動時に `VisionFilterStore.migrateLegacySettings` が一度だけ取り込み、旧キーを削除する。初回起動の層は
`VisionFilterState.seedInitialLayers`（deuteranomaly・強度 0.6）。bridge の `apply_vision_pipeline_cpu_rgba8`
（`VisionStep` 列を並びの順に適用。空列は入力を返す）と `CpuVisionRenderer.applyPipeline`（#118）があり、
`VisionFilterState` の多選択 API（`toggle` / `remove` / `setLayerStrength` / `setLayerParams` / `replaceWith` /
`clear`、#119）で層を操作し、`HomeScreen._previewCard` が層を段順で `BeforeAfterView.steps` 経由の 1 回の合成へ渡す:

- 色覚は排他（新しい色覚が既存の色覚を置き換える。層数は増えない）。層は最大 5 で、上限での未選択の
  追加は何もせず `VisionLayerResult.blocked(layerLimit)` を返す（色覚の置き換えと体験プリセットは例外）。
  体験プリセットは層全体を置き換え、層集合がそのプリセット単体でなくなったら破棄し、戻っても復元しない。
- 強度 0 の層は合成から除く（ただし上限には数える）。層が 0〜1 のときは従来の単一フィルタの経路
  （`afterImageRenderer`）のままで、2 層以上のときだけ `pipelineApplier`（#118）を使う。
- 推奨サンプル（#78）は `focusedId` の層に追従する。フォーカスが外れたら適用順で最後の層へ移る。
- 複数層の相談喚起の入力は `mergeConsultInputs`（urgency は最大・escalation は段ごとに重複除去）で作る
  （PNG 書き出しが使う、#121。調整パネル・HUD の注意書きは ADR どおり層ごと）。

UI は多選択（#120）:

- 統合一覧はチェック式（色覚行はラジオ式の見た目・見出し「いずれか 1 つ」）で、チェック済みの行に適用順の
  番号バッジが付く。上限 5 に達すると未選択の行は無効になり理由を行内に出す（色覚の置き換えと体験プリセットは有効）。
- プレビュー上のチップ帯（2 層以上のみ）で層の切替（調整中）・✕・「すべて解除」。調整パネルは 2 層以上で層ごとの
  節（調整中の層だけ展開）、強度スライダーは 1 本。1 層のときの見た目・挙動は従来どおり。
- キー: ↑↓ は行フォーカスの移動だけ、Space / Enter が足し引き、←→ は調整中の層（`focusedId`）の強度。
- 複数層の見出し・HUD は「名前 + 名前 …（+N）」（強度は出さない）。PNG 書き出しは複数層でも使え（#121）、画像に効いている層
  （強度 > 0）ごとの行・最大の緊急度と併合した escalation・実験的の注記を焼き込む。強度 0 の層は症状行・受診喚起・注記・
  ファイル名に数えない（画像だけが共有されたとき実際の見え方と食い違わないため）。「2×2 で比較」は色覚層があるとき
  だけ出し、他の層は土台として重ねる（#122）。
- トレイ（#121）: 「高度なフィルタ」はチェック式。クリックはメイン画面の一覧と同じ入口（`toggleFilterListEntry`）を通り、チェックは層の集合から導く。
  色覚 4 項目は排他（別の型で置き換え）、上限 5 で未選択の項目は灰色（色覚の置き換えは有効）。フィルタ解除（トレイ・ホットキー）は全層を外す。

### iOS非対応

目標とする方式（ルーペ窓のライブキャプチャ。`docs/adr/2026-09-26-loupe-as-single-render-unit.md`、
Issue #1）は、他アプリの画面をキャプチャしてフィルタをかけ、その結果を他アプリの上に
重ねて表示する。iOS はサードパーティアプリに他アプリの上へオーバーレイ表示する API を
与えておらず、画面キャプチャも ReplayKit 拡張経由に限られる（加工結果を他アプリの上に
出す手段がない）ため、この方式は成立しない。現状は合成したデモ画像へのプレビューのみ
だが、プロダクトの目標がライブのルーペである以上、iOS は対象外のまま。詳細は
`docs/adr/2025-11-17-no-ios-support.md` を参照。

## ビルド

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

UI を変える場合は先に `DESIGN.md` を読む（色は `colorScheme` のロールのみ、余白は 4 の倍数、
画面構成の目標状態など）。スクリーンショットで確認する手順は DESIGN.md §8。

## CI

`.github/workflows/ci.yml` は2ジョブ構成。`check`（runs-on: macos-latest。
Flutter golden を生成プラットフォームと揃えるため）が push/PR（main）で
flutter analyze / flutter test / `rust/` の cargo fmt --check /
clippy --all-targets -D warnings / cargo test / flutter build macos --debug /
実ブリッジ integration test（`flutter test integration_test/experience_presets_smoke_test.dart -d macos`
と `flutter test integration_test/app_bootstrap_test.dart -d macos` の2コマンド、#55。
2ファイルを1回の `flutter test integration_test` 呼び出しにまとめるとデスクトップでは
2番目のアプリ起動が失敗するため個別に実行する）を回す。cargokit 統合（#55）により
`flutter build macos` が rust/ crate のビルドも兼ねるため、Setup Rust は Flutter
build より前に置く。rust 依存は crates.io のみ（sensus-core）なので、private
依存を git 経由で引く場合に要る deploy key / ssh-agent 設定は不要。

`linux-build`（runs-on: ubuntu-latest、#55）は Linux 側の cargokit 同梱経路
（`flutter build linux --debug`、`.so` がバンドルされることを ls/test -f で
確認）と、xvfb 上での実ブリッジ integration test を検証する。`Swatinem/rust-cache`
によるキャッシュ対象は両ジョブで異なり、`linux-build` は cargokit のビルド出力も
含めるが、`check`（macOS）は `rust/`（cargo target）+ crates.io 依存のみキャッシュする。

`samples-sync`（`.github/workflows/samples-sync.yml`、ubuntu-latest、#115）は
`assets/samples/*.png` が `tools/generate_samples.dart` の生成結果と一致することを検証する
（既存 PNG を消して再生成し、`git status` に差分が出たら失敗）。`font-atlas-sync`
（`.github/workflows/font-atlas-sync.yml`）は `tools/fonts/` について
`tools/generate_font_atlases.py`（Python + ネットワーク）で同じ検証をする。どちらも
`paths` フィルタで対象ファイルを変えた push/PR（と手動実行）のときだけ起動し、通常の
PR の CI 時間は増えない（必須チェックにはしない前提）。落ちたら
`dart run tools/generate_samples.dart`（アトラスなら
`uv run --with pillow==12.3.0 python3 tools/generate_font_atlases.py` も）を実行して
差分をコミットする。

## ロードマップ

- **Phase 1**: 色覚障害シミュレーション（色覚 7 型: protanopia/deuteranopia/
  tritanopia/achromatopsia + 各 -omaly）— before/after プレビューの実描画まで
  配線済み（#34/#59 で GPU、#85 で sensus の CPU `apply()` 経路に置き換え）
- **Phase 2**: 聴覚障害シミュレーション — 複合体験の型定義（FRB, `HearingFilter`）は
  公開済みだが、音声の加工・再生は未実装
- **Phase 3**: 視野欠損・視覚ぼやけなど色覚以外の見え方 — sensus のカタログには
  既に含まれ、advanced カタログから選択・プレビュー反映まで動作する（ARB の
  `aboutPhases` 参照）。専用 UI・ライブ GPU 描画は個別 Issue で拡張中。sensus に
  運動障害（motor。前庭・めまい系の motion カテゴリとは別物）のカテゴリは存在
  しないため、Phase 3 の対象に含めない

> **共通**: sensus 全 30 種（色覚 7 型・advanced カタログ・体験プリセットは、この
> 同じ 30 種への 3 つの選び方に過ぎない）は #60 で advanced カタログ・体験
> プリセットの UI 結線が完了し、いずれの選び方でも before/after プレビューが
> 実描画される。プレビューの描画対象は `VisionFilterState` の現在の選択を
> 唯一の正本にする。GPU は将来のライブ画面キャプチャ向けに残置してあるが
> 現状未使用。

## やらないこと

非目標は `README.md`「やらないこと（非目標）」を正本とする。個別 docs 側での
重複記載はしない。
