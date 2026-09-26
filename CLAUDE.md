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

### LMS色空間変換

```
RGB → LMS → CVD Simulation → LMS → RGB
```

- 人間の視覚システムに基づく科学的手法
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

現在は sensus 由来の GPU シェーダでルーペ窓内の画像にフィルタを適用する方式を採る
（`docs/adr/2026-09-26-loupe-as-single-render-unit.md`）。

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

Appleのサンドボックス制約により、システム全体へのフィルタ適用が技術的に困難。

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
実ブリッジ integration test（`flutter test integration_test -d macos`、#55）
を回す。cargokit 統合（#55）により `flutter build macos` が rust/ crate の
ビルドも兼ねるため、Setup Rust は Flutter build より前に置く。rust 依存は
crates.io のみ（sensus-core）なので、private 依存を git 経由で引く場合に要る
deploy key / ssh-agent 設定は不要。

`linux-build`（runs-on: ubuntu-latest、#55）は Linux 側の cargokit 同梱経路
（`flutter build linux --debug`、`.so` がバンドルされることを ls/test -f で
確認）と、xvfb 上での実ブリッジ integration test を検証する。両ジョブとも
`Swatinem/rust-cache` で crates.io 依存 + cargokit のビルド出力をキャッシュする。

## ロードマップ

- **Phase 1**: 色覚障害シミュレーション — 進行中。ライブ GPU 描画は protanopia /
  protanomaly のみ配線済みで、他の色覚型はクイック選択できるが描画は
  「描画は近日対応」（en: "Rendering coming soon"）表示。advanced カタログ・
  体験プリセットの選択は `VisionFilterState` に入るだけでプレビューには反映されない
  （詳細は GitHub Issues、特に #34 / #59 / #60）
- **Phase 2**: 聴覚障害シミュレーション — 複合体験の型定義（FRB, `HearingFilter`）は
  公開済みだが、音声の加工・再生は未実装
- **Phase 3**: 視野欠損、視覚ぼやけ、運動障害 — 未着手
