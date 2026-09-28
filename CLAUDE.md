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
├── l10n/                   # 多言語化（ARB: app_en.arb / app_ja.arb、ja/en。生成物は非コミット）
├── models/
│   ├── disability_type.dart
│   └── vision_filter_catalog.dart   # sensus カタログ（30種）の Dart 側定義
├── rendering/
│   └── shader_filter.dart           # sensus 由来 GLSL → Impeller FragmentProgram 適用
├── services/
│   ├── export_service.dart          # PNG エクスポート（メタ焼き込み）
│   ├── filter_service.dart          # 選択状態モデル（sensus VisionFilter へのマッピング）
│   ├── loupe_window_controller.dart # ルーペ窓のモード/透過/最前面
│   ├── settings_service.dart
│   ├── tray_service.dart            # タスクトレイ
│   └── vision_filter_state.dart
├── src/rust/                        # flutter_rust_bridge 生成コード（sensus-core 連携）
└── ui/
    ├── screens/home_screen.dart
    ├── widgets/                     # filter_selector, intensity_slider, before_after_view,
    │                                 # experience_presets, filter_catalog_selector, filter_param_panel
    └── theme/app_theme.dart

rust/                        # sensus-core を FRB で公開する Rust crate
├── Cargo.toml
└── src/
    ├── api/sensus_bridge.rs
    ├── frb_generated.rs
    └── golden_gen.rs        # GPU golden 参照生成（#[cfg(test)] のみ）
rust_builder/                 # cargokit 統合（#55）。flutter build/run 時に rust/ をビルドし
                               # macOS/Linux アプリへ同梱する FFI plugin（生成物、直接編集しない）

tools/                       # シェーダ codegen（sensus の .frag → Impeller サブセットへ機械変換）
shaders/                     # 変換済み .frag（ビルド時 impellerc がコンパイル）

macos/                       # macOS ランナー（現行対応）
linux/                       # Linux ランナー（現行対応）
# Android / Windows ランナーは計画中（未作成）

docs/
├── adr/                     # 設計判断の正本（Architecture Decision Records）
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

正本は sensus-core の `vision/color.rs`。LMS 色空間は経由しない
（旧 LMS 実装は #13 で撤去済み、`docs/COLOR_ALGORITHM.md` 参照）。
Machado, Oliveira, Fernandes (2009) がプリ計算した severity=0.0〜1.0 の
11 段テーブルを linear sRGB 空間へ直接適用し、中間 strength はテーブルを
区分線形補間する。

- 事前計算された変換行列で高速処理
- 強度補間による柔軟な調整

### 対応色覚異常

| タイプ | 有病率（男性） |
|--------|--------------|
| Deuteranopia | 約1% |
| Protanopia | 約1% |
| Deuteranomaly | 約5% |
| Protanomaly | 約1% |
| Tritanopia | 0.001% |

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

### iOS非対応

他アプリの画面をキャプチャできない（Apple のサンドボックス制約）ため、ルーペ窓に
他アプリの映像を映してフィルタをかける現行方式が成立しない。詳細は
`docs/adr/2025-11-17-no-ios-support.md` を参照。

## ビルド

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

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

- **Phase 1**: 色覚障害シミュレーション — sensus 全 30 種（色覚 7 型・advanced
  カタログ・体験プリセット）が before/after プレビューの実描画まで配線済み
  （#34/#59 で GPU、#85 で sensus の CPU `apply()` 経路に置き換え、#60 で
  advanced カタログ・体験プリセットの UI 結線を完了。プレビューの描画対象は
  `VisionFilterState` の現在の選択を唯一の正本にする。GPU は将来のライブ画面
  キャプチャ向けに残置してあるが現状未使用）
- **Phase 2**: 聴覚障害シミュレーション — 複合体験の型定義（FRB, `HearingFilter`）は
  公開済みだが、音声の加工・再生は未実装
- **Phase 3**: 視野欠損・視覚ぼやけなど色覚以外の見え方 — sensus のカタログには
  既に含まれ、advanced カタログから選択・プレビュー反映まで動作する（ARB の
  `aboutPhases` 参照）。専用 UI・ライブ GPU 描画は個別 Issue で拡張中。sensus に
  運動障害のカテゴリは存在しないため、Phase 3 の対象に含めない
