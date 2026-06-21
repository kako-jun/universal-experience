# ADR: iOS 非対応

- **決定日**: 2025-11-17（初期実装時。プラットフォーム対象に iOS を含めない方針が
  この時点で立っている）
- **記録日**: 2026-06-21（ADR 化）
- **ステータス**: Accepted

## 文脈（問題）

ue は当初、感覚障害（色覚等）のフィルタを**システム全体（他アプリ含む全画面）**に
適用することを目標にしていた。この system-wide 適用は各 OS のネイティブ機構に依存する
（`docs/PLATFORM_APIS.md`）:

- Android: AccessibilityService + Overlay（`TYPE_ACCESSIBILITY_OVERLAY`）
- Windows: Magnification API（`MagSetFullscreenColorEffect`）
- macOS: 公開 API のガンマテーブル（`CGSetDisplayTransferByTable`）
- Linux: Wayland compositor / X11 XRandR

iOS をこの対象に含めるかどうかを決める必要があった。

## 決定

**iOS は対応しない。**

ue のプラットフォーム対象は Android / Windows / macOS / Linux とし、iOS を含めない
（`CLAUDE.md`「設計判断 / iOS非対応」）。リポジトリにも `ios/` プラットフォーム
ディレクトリは作られていない。

## 代替案

- **iOS に対応する** — 却下。下記「根拠」のとおり、当初目標である system-wide な
  フィルタ適用が iOS では技術的に成立しないため。

## 根拠

> 出典は `CLAUDE.md`「設計判断 / iOS非対応」に接地する。

- **Apple のサンドボックス制約により、システム全体へのフィルタ適用が技術的に困難**。
  iOS は他アプリの画面に重ねて描画したり、ディスプレイ全体の色変換を行う公開 API を
  サードパーティアプリに与えていない（OS 標準のアクセシビリティ「カラーフィルタ」は
  設定アプリ側の機能）。

## 結果・トレードオフ

- 対象 OS から iOS を外したことで、ue は当初 Android/Windows/macOS/Linux の
  ネイティブ機構（`docs/PLATFORM_APIS.md`）に集中できた。
- **その後の変化（#13）**: system-wide 適用を担っていた `color_vision_filter` プラグインは
  撤去され、現状の ue は sensus-core 由来の GPU シェーダで**画像（ルーペ窓内）**に
  フィルタを適用する形に変わった（→ ADR `2026-05-31-sensus-core-consolidation.md`）。
  「画像へのフィルタ」だけなら iOS でも技術的成立の余地はあるが、本 ADR の決定
  （iOS 非対応）は維持している。iOS 対応を再検討する場合は本 ADR を Superseded にして
  新たに起こす。
- **未記録**: iOS 対応を将来再開する条件・優先度は現時点で文書化されていない。

## 関連 Issue・PR・docs

- `CLAUDE.md`「設計判断 / iOS非対応」「プラットフォーム実装」（本 ADR の元記述）
- `docs/PLATFORM_APIS.md`（各 OS の system-wide 適用 API 調査）
- `docs/ARCHITECTURE.md`（Native Implementation Layer の歴史的記述）
- 関連 ADR: `2026-05-31-sensus-core-consolidation.md`（system-wide → 画像フィルタへの転換）
