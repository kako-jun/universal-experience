# Architecture Decision Records (ADR)

Universal Experience（ue）の主要な設計判断を記録する正本ディレクトリ。

これまで設計判断は Issue / commit / 各 docs に散在していた。本ディレクトリは
それらを ADR として一元化し、「なぜそう決めたか・何を捨てたか」を後から辿れる
ようにする（Issue #33）。

## 命名規約

- ファイル名: `YYYY-MM-DD-<topic>.md`
  - 日付は **その決定が成された時期**（Issue / commit / docs から特定できる場合）。
    特定できない場合は ADR 正式化日 `2026-06-21` を使う。
    （現行 ADR は全件で決定日を commit/Issue から特定できたため、このフォールバックは未使用。）
  - `<topic>` は短い英小文字スラッグ（ハイフン区切り）。
- 各 ADR は冒頭に「**決定日**（判断が成された時期）」と「**記録日**（ADR 化した日）」を
  両方明記する。日付特定の根拠が薄い場合はその旨を本文に書く。

## ADR の構成

各 ADR は次の節を持つ:

1. **タイトル**
2. **ステータス**（Accepted / Superseded / Deprecated 等）
3. **文脈（問題）** — 何を解決しようとしたか
4. **決定** — 何を選んだか
5. **代替案** — 検討して採らなかった選択肢
6. **根拠** — なぜその決定にしたか
7. **結果・トレードオフ** — 決定がもたらした影響・残課題
8. **関連 Issue・PR・docs** — 出典

> 注: 本リポジトリのドクトリン guideline はリポジトリ外で管理しているため、ue には
> `docs/guidelines/` を置かない。ADR はそれとは別物として `docs/adr/` に置く。

## 一覧

| ファイル | タイトル | 決定日 | ステータス |
|---|---|---|---|
| [2026-09-30-export-png-to-downloads.md](2026-09-30-export-png-to-downloads.md) | PNG エクスポートは保存ダイアログを使わず Downloads へ直接保存する | 2026-09-30 | Accepted |
| [2026-09-30-home-screen-unified-list-and-three-columns.md](2026-09-30-home-screen-unified-list-and-three-columns.md) | 主画面を「統合一覧 + 3 カラム（広幅）/ 縦積み（狭幅）」にする | 2026-09-30 | Accepted |
| [2026-09-26-loupe-as-single-render-unit.md](2026-09-26-loupe-as-single-render-unit.md) | ルーペ窓を唯一の描画単位にする（対象アプリ指定は自動配置モード） | 2026-09-26 | Accepted |
| [2026-05-31-sensus-core-consolidation.md](2026-05-31-sensus-core-consolidation.md) | sensus-core への色変換一元化（plugin/simulator 撤去） | 2026-05-31 | Accepted |
| [2026-05-31-flutter-rust-split.md](2026-05-31-flutter-rust-split.md) | Flutter + Rust の分割 | 2026-05-31 | Accepted |
| [2026-05-31-buildtime-impellerc-conversion.md](2026-05-31-buildtime-impellerc-conversion.md) | ビルド時 impellerc 変換（FragmentProgram） | 2026-05-31 | Accepted |
| [2025-11-17-state-management-provider.md](2025-11-17-state-management-provider.md) | 状態管理に Provider を採用 | 2025-11-17 | Accepted |
| [2025-11-17-no-ios-support.md](2025-11-17-no-ios-support.md) | iOS 非対応 | 2025-11-17 | Accepted |

## 関連ドキュメント

- `docs/sensus-integration.md` — sensus 連携・シェーダ方言・impellerc 変換の詳細
  （impellerc / sensus 一元化 ADR の主素材）
- `docs/ARCHITECTURE.md` — レイヤー構造（#13 で撤去された system-wide 機構の
  歴史的記述を含む）
- `docs/COLOR_ALGORITHM.md` — 色アルゴリズム（#13 以前の ue 内 LMS 実装の歴史的記録）
- `docs/PLATFORM_APIS.md` — プラットフォーム別 API 調査（system-wide 適用の歴史的記録）
- `CLAUDE.md`「設計判断」節 — Flutter 採用 / Provider 選定 / iOS 非対応の元記述
