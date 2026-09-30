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
│   ├── disability_type.dart
│   ├── vision_filter_catalog.dart   # sensus カタログ（30種）の Dart 側定義
│   ├── vision_filter_contract_notes.dart # sensus API 契約上の注意の定義（強度の上限付近の警告の対象・閾値、#66）
│   ├── sample_catalog.dart          # サンプル画像集（7種）+ フィルタ id ごとの推奨サンプル（#78）
│   └── preview_image_source.dart    # プレビュー原画の値型（サンプル/ユーザー画像、#78）
├── rendering/
│   ├── cpu_vision_renderer.dart     # sensus CPU apply() 経由、プレビュー描画の正本（#85）
│   ├── color_matrices.g.dart        # sensus 由来 Machado 11段テーブルの生成物（GPU 経路専用）
│   ├── shader_filter.dart           # sensus 由来 GLSL → Impeller FragmentProgram 適用
│   │                                 # （ライブ画面キャプチャ向けに残置、現状 production 未使用）
│   └── image_fit.dart               # 任意画像を正準サイズの正方形へレターボックス（#78）
├── services/
│   ├── app_shortcuts.dart           # アプリ内キー操作（/, ↑↓, ←→, Esc, Cmd/Ctrl+V）の Intent 定義（#63/#72/#97）
│   ├── clipboard_image_reader.dart  # クリップボード画像取得の seam（実体は pasteboard、#97）
│   ├── color_vision_selection.dart  # 色覚クイック選択の唯一の入口（FilterService/
│   │                                 # VisionFilterState を同時更新、#60）
│   ├── export_service.dart          # PNG エクスポート（メタ焼き込み・Downloads へ非上書き保存・フォルダで表示、#43/#64）
│   ├── filter_list_selection.dart   # 統合フィルタ一覧（色覚 7 型 + advanced 30 = 33 行）の
│   │                                 # 検索・選択入口・↑↓ の順送りの純粋ロジック（#72）
│   ├── filter_service.dart          # 選択状態モデル（sensus VisionFilter へのマッピング）
│   ├── hotkey_actions.dart          # グローバルホットキー4アクションの実処理（#63）
│   ├── hotkey_service.dart          # hotkey_manager 登録の副作用層（#63）
│   ├── image_source_state.dart      # プレビュー原画（サンプル/ユーザー画像）の選択の唯一の正本（#78）
│   ├── loupe_rect_source.dart       # ルーペ矩形決定元のインターフェース（#44 向け seam、#63）
│   ├── loupe_window_controller.dart # ルーペ窓のモード/透過/最前面/クリックスルー（#63）
│   ├── native_bridge_service.dart   # flutter_rust_bridge（sensus-core）の bootstrap 初期化
│   ├── preview_selection.dart       # プレビュー強度の出どころを一本化する判定（#60/#63）
│   ├── settings_service.dart        # isFirstRun/welcomeBannerDismissed も持つ（#78）
│   ├── tray_service.dart            # タスクトレイ（updateLocalization で文言を差し替える、#82）
│   ├── tray_locale_sync.dart        # 言語の選択/OS ロケール変更をトレイの文言へ橋渡し（#82）
│   ├── vision_filter_metadata.dart  # urgency/urgency_escalation/recommended_strength の
│   │                                 # provider seam（sensus ブリッジが唯一の正本、#76/#77）
│   └── vision_filter_state.dart     # フィルタ id ごとの強度・パラメータの記憶（#77）
├── src/rust/                        # flutter_rust_bridge 生成コード（sensus-core 連携）
└── ui/
    ├── screens/home_screen.dart
    ├── widgets/                     # filter_browser（左カラム「選ぶ」: 検索・カテゴリ・統合一覧、#72）,
    │                                 # filter_list_tile（一覧の 1 行）, adjust_panel（右カラム「調整」、#72）,
    │                                 # intensity_slider, before_after_view,
    │                                 # experience_presets（体験プリセットの行 ExperiencePresetTile）, filter_param_panel,
    │                                 # consult_notice_block（受診喚起の共有表示ウィジェット、#76）,
    │                                 # strength_caution（強度スライダの上限付近の印・注記、#66）,
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
shaders/                     # 変換済み .frag（ビルド時 impellerc がコンパイル）
assets/samples/              # サンプル画像集（自作・手続き生成、#78）。出典は README.md

macos/                       # macOS ランナー（現行対応）
linux/                       # Linux ランナー（現行対応）
# Android / Windows ランナーは計画中（未作成）

DESIGN.md                    # UI 設計原則（カラートークン・タイポ・余白・コンポーネント・画面構成・検証方法、#72）

test/
├── no_hardcoded_colors_test.dart   # lib/ の色ハードコードを検出（例外は DESIGN.md の例外表と一致させる、#72）
├── app_theme_test.dart             # ハイコントラストテーマの生成と MaterialApp での切替（#72）
├── home_screen_layout_test.dart    # 3 カラム/縦積み・プレビューの初回ビューポート・空状態・キー操作（#72）
├── tap_target_size_test.dart       # macOS 指定で操作領域が 48dp 以上（padded + standard・言語ダイアログの選択肢、#72/#82）
├── filter_browser_test.dart        # 統合一覧の検索・カテゴリ切替・行の選択（#72）
├── filter_list_selection_test.dart # 統合一覧の純粋ロジック（#72）
├── clipboard_paste_test.dart       # クリップボード画像の貼り付け経路・失敗 5 種・Cmd/Ctrl+V・ボタン（#97）
├── language_dialog_test.dart       # 言語ピッカー: 切替で追従・永続化・自称名の網羅と読み上げ言語・画面とトレイの言語一致（#82）
├── tray_locale_sync_test.dart      # 言語の選択/OS ロケール変更でトレイの文言が更新される（#82）
├── support/home_screen_harness.dart # HomeScreen を Provider 一式で組む widget test 用の共通部品
├── support/screenshot_harness.dart # スクリーンショット用フォント読込・PNG 書出し（フォントはコミットしない）
└── ui_screenshots/                 # HomeScreen の PNG 書出し。`UE_SCREENSHOTS=1` のときだけ実行（DESIGN.md §8）

docs/
├── adr/                     # 設計判断の正本（Architecture Decision Records）
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
