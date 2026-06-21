# ADR: sensus-core への色変換一元化（plugin/simulator 撤去）

- **決定日**: 2026-05-31（撤去を実装した #13 / PR #25 の commit 日）
- **記録日**: 2026-06-21（ADR 化）
- **ステータス**: Accepted

## 文脈（問題）

ue は色覚シミュレーションのアルゴリズムを**二重に**持っていた。

- `lib/core/color_vision_simulator.dart` — ue 内に持つ LMS 色空間変換実装。
- `plugins/color_vision_filter/` — ColorMatrix ベースの独自ネイティブプラグイン
  （Android Kotlin / Windows C++、macOS/Linux は計画段階）で、OS 全体に
  system-wide フィルタを適用する経路。
- `lib/services/filter_service.dart` が上記 `ColorVisionSimulator` と plugin の
  両方を直接参照していた。
- README / CLAUDE.md にも「LMS色空間変換」「plugins/color_vision_filter」が
  正本のように書かれていた。

一方で、感覚障害シミュレーションのアルゴリズム正本は別 crate
[`sensus-core`](https://crates.io/crates/sensus-core)（Rust, crates.io 公開）に
一元化する方針が立っていた。ue 側に LMS 行列や plugin の ColorMatrix を残すと、
「sensus（正本）側の出力」と「ue 内実装の出力」がズレる事故源になる。アルゴリズムの
正しさ（KAT・行列値・linear sRGB での適用）を 2 箇所で同期し続けるのは現実的でない。

## 決定

色変換アルゴリズムを **sensus-core crate 一本に委譲**し、ue 内の重複実装を撤去する。

- **削除**: `lib/core/color_vision_simulator.dart`（ue 内 LMS 実装）。
- **削除**: `plugins/color_vision_filter/`（system-wide フィルタ用の独自ネイティブ
  プラグイン）と `pubspec.yaml` の `color_vision_filter` path 依存、
  `filter_service.dart` の import。
- **`FilterService` の一本化**: plugin 呼び出し（apply/setIntensity/remove/getState）・
  permission 概念・`colorMatrix` getter（simulator 依存）を撤去。現在は純粋な選択状態
  モデル（`currentFilter` / `intensity` / `isActive`）で、選択・強度変更時に
  `notifyListeners` するだけ。`ColorVisionType` → sensus `VisionFilter` のマッピング
  （`VisionFilter? get sensusFilter`）を追加。
- フィルタ適用は sensus 由来の GPU シェーダ（`lib/rendering/shader_filter.dart`）が担う。
  ue は GLSL や行列・半径式を**再実装しない**。

## 代替案

1. **ue 内の自前 LMS simulator を維持する** — sensus を導入せず、`ColorVisionSimulator`
   を正本にし続ける。却下: アルゴリズムの正本を ue が抱えると、他プロジェクト
   （sensus を使う別アプリ）との整合が取れず、正しさの検証コストも ue が負う。
2. **plugin（system-wide ColorMatrix）を残す** — OS 全体への適用を維持したまま、
   アルゴリズムだけ sensus に寄せる。却下: plugin は ColorMatrix（線形 RGB 上の
   素朴な行列）であり、sensus の linear sRGB 空間での厳密な変換とは別物。両立すると
   結局二重の見え方が残る。system-wide 適用はライブ画面キャプチャ経路（#1/#3/#4）で
   別途取り直す。
3. **アルゴリズム正本を sensus 側でなく ue↔plugin 共有ライブラリに切る** — 却下:
   正本リポ（sensus-core）が KAT/ADR を持って正しさを固定している。ue がそれを
   消費する側に回るのが、二重化を根本から無くす唯一の形。

## 根拠

- **正本の二重化を排除する**。「CPU 版（sensus）と ue 内実装がズレる」事故源を断つ
  ことが #13 の主目的（Issue #13「これらが残ると…事故源になる」）。
- **正しさを正本に固定する**。アルゴリズムの妥当性（行列値・linear sRGB での適用・
  検査プレートでの見え方）は sensus 側の KAT/ADR が保証する。ue は変換規則を
  保守しない。
- 既に sensus 連携の土台（FRB ブリッジ #7/#8、impellerc 変換 #12）が入っており、
  色覚フィルタが sensus 経路で描画できる状態になっていたため、撤去を一度の
  リグレッション確認で済ませられる段階だった。

## 結果・トレードオフ

- ue から LMS 行列・plugin・permission の関心事が消え、`FilterService` は選択状態の
  保持に純化した。`test/filter_service_test.dart`（選択状態遷移・clamp・sensusFilter
  マッピング）を追加。
- **トレードオフ**: 「他アプリ含む全画面への system-wide 適用」は plugin 撤去で
  いったん失われた。現状の ue は sensus シェーダで**画像（ルーペ窓内）**にフィルタを
  適用する。ライブ全画面適用は画面キャプチャ経路（#1/#3/#4）の実装後に取り直す。
- `ColorVisionType` の全面 sensus `VisionFilter` 化、category/param パネル（#16）は
  本決定のスコープ外として残課題。
- `-anomaly` 系は sensus が severity を `strength` で表すため、base の `-opia` へ
  マップ（anomaly = 強度 < 1 相当）する暫定対応。

### 既存 docs の現状（重要）

- `docs/COLOR_ALGORITHM.md` / `docs/PLATFORM_APIS.md` / `docs/ARCHITECTURE.md` の
  Platform Channel / Native 実装・LMS 行列の記述は **#13 以前の歴史的記録**で、
  各冒頭にその旨の注記がある。
- `CLAUDE.md` の「プロジェクト構造」には `plugins/color_vision_filter/` や
  `lib/core/color_vision_simulator.dart` が残っているが、これらは **#13 で撤去済み**で
  現存しない。本 ADR が現状（sensus-core 一元化）の正本である。

## 関連 Issue・PR・docs

- Issue #13（重複ロジック撤去 3/3）/ PR #25（commit `a1c2925`, 2026-05-31）
- 前提: Issue #7/#8（sensus 連携 1/3, Rust ブリッジ）、#12（impellerc 変換）、#11（描画配線）
- `docs/sensus-integration.md` §4-5（撤去予約と完了記録）
- 撤去された記述: `CLAUDE.md`「プロジェクト構造」「色覚アルゴリズム」、`docs/COLOR_ALGORITHM.md`、`docs/PLATFORM_APIS.md`
