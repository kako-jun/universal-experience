# ADR: 状態モデルを「順序つきレイヤー列」の 1 系統に統一し、複数症状の同時適用を sensus の Pipeline で合成する

- **決定日**: 2026-09-30（Issue #32・#41 を一体で設計）
- **記録日**: 2026-09-30（ADR 化）
- **ステータス**: Accepted（設計のみ。実装は段階ごとの Issue #117〜#125 で行う。各段の完了時に「結果・トレードオフ」を更新する）

## 文脈（問題）

#32 は「状態モデルが 2 つ並行している」問題、#41 は「症状を 1 つしか選べない」問題で、
**どちらも「選択の単位を何にするか」という同じ決定に行き着く**。#32 を単一選択のまま畳むと、
#41 で同じ箇所（選択状態・一覧・トレイ・永続化）をもう一度作り直すことになるため、1 本の
ADR で設計する。

### 現状の正確な把握（2026-09-30、main 621286e 時点）

状態は 2 系統ある。

| 系統 | 単位 | 役割 |
|---|---|---|
| `VisionFilterState`（`lib/services/vision_filter_state.dart`） | カタログ 30 フィルタの id + 強度 + payload | プレビューの**唯一の正本**（#60）。per-id の強度/payload 記憶、体験プリセット、原画比較の bypass holder を持つ |
| `FilterService`（`lib/services/filter_service.dart`） | `ColorVisionType` 7 種（none + 6 型）+ 型ごとの強度記憶（#57、`settings.intensityByType`） | トレイの色覚クイック項目・2×2 比較・色覚のクイック選択用。`SettingsService.filterType` に最後の型を残す |

`selectColorVision`（`color_vision_selection.dart`）が 2 系統をつなぐ**唯一の橋**で、色覚を
クイック選択すると `VisionFilterState._isColorQuickSelection = true` と `_colorVisionType` が立ち、
消費側は `isColorQuickSelection` で「強度をどちらから読むか」を分岐する（**強度の正本が 2 つ**ある）。
-omaly（`protanomaly` / `deuteranomaly` / `tritanomaly`）は opia と同じカタログ id へ写り、
強度が弱い（0.6）だけなので、`colorVisionType` を通してしか識別できない。

**単一選択を前提にしている箇所**（`rg` で網羅）:

- 状態: `VisionFilterState` の `_selectedId` / `_strength` / `_params` / `_selectedPresetId` /
  `_isColorQuickSelection` / `_colorVisionType`、`select` / `selectColorVisionType` / `selectPreset` /
  `restore` / `snapshot` / `build()`（30 ケースの switch）。`_bypassHolders` だけは選択数に依存しない。
- 入口: `color_vision_selection.dart`・`preview_selection.dart`・`filter_list_selection.dart`
  （`applyFilterListEntry` / `selectedFilterListEntry`＝統合一覧 33 行 = 30 + -omaly 3 の「今の 1 行」）。
- 描画: `home_screen.dart` の `_previewCard` → `BeforeAfterView` が 1 つの `VisionFilter` +
  強度を `CpuVisionRenderer.apply`（`apply_vision_cpu_rgba8`、1024px 正準）へ渡す。
- 周辺: `loupe_hud.dart`（名前 + 強度 1 つ）、`adjust_panel.dart` / `intensity_slider.dart` /
  `filter_param_panel.dart`（1 フィルタの調整）、`tray_service.dart` / `tray_menu_labels.dart`
  （1 つにチェック）、`color_vision_compare.dart`（色覚カテゴリ選択中に 2×2）、
  `ExportCaption`（症状名・強度が 1 つずつ）、`resolveConsultNotice`（1 フィルタの urgency +
  escalation）、`vision_filter_snapshot.dart` / `vision_filter_store.dart`（永続 JSON v1 が 1 選択）。
- `main.dart`: 起動時に `settings.filterType` から色覚シード → `restoreAndBind` の順で復元。

**#67（dead code 撤去、PR #113）で消えたもの**は未使用コードだけで、2 系統の構造そのものは
両方に生きた消費者がいるため残った。`ColorVisionType` の参照は `lib/` の 15 ファイルに残る
（`FilterService`・`SettingsService`・トレイ・`color_vision_compare`・`color_vision_selection`・
l10n の型名・`isColorQuickSelection` の分岐など）。`ShaderFilter`（GPU）は本番では未使用で、
将来のライブルーペ（#1）用に温存されている。

### sensus 側の合成の能力

- `sensus_core::Pipeline` / `FilterStep{filter, strength}` は**追加した順に**適用し、単体適用と
  挙動が一致する（`FilterStep::apply` は `apply` に委譲）。`docs/overview.md` は "order matters"
  とするだけで、**標準の順序規約は無い**。
- 各ステップで 8bit ↔ f32 を往復するため、段数に応じて量子化誤差が累積する（`pipeline.rs` 冒頭の注記）。
- bridge（`sensus_bridge.rs`）は `apply_vision_cpu_rgba8`（1 フィルタ）だけを公開しており、
  `Pipeline` は未公開。`Experience` は vision フィルタを高々 1 つ（+ hearing 1 つ）しか持たない。
- 実測（#85、1024²、opt-level 3）: 近視 約 300ms、starbursts 約 30ms、protanopia 約 25ms。

## 決定

### 1. 選択の単位は「カタログ id ごとに 1 つのレイヤー」の順序つき列

```text
VisionLayer { id, strength, params, variantId? }   // variantId = -omaly の別名（protanomaly 等）
VisionFilterState.layers : List<VisionLayer>        // 適用順（下記 3）で並ぶ。id は重複しない
VisionFilterState.focusedId : String?               // 調整パネルが開く層（最後に触れた層）
```

- **単一選択 = 1 要素の多選択**。別の状態モデルは作らない。従来の `select` は「全部外して 1 つ足す」
  `replaceWith` に相当し、既存の単一選択 API（`selectedId` / `strength` / `params` / `build()`）は
  移行期間中「フォーカス中の層」を見る薄い互換層として残す。
- **定義と状態の分離を保つ**: min/max/default/options・段・排他グループはカタログ（定義）、
  どの層が選ばれているか・強度・payload は `VisionFilterState`（状態）。状態は id で定義を参照するだけ。
- **per-id の強度/payload 記憶は現行のまま**残す。層を外しても、次に足したときに前回の値で戻る。
- **排他グループ**: 色覚カテゴリ（protanopia / deuteranopia / tritanopia / achromatopsia /
  tetrachromacy と -omaly 3 種）は**同時に 1 つだけ**。色覚を選ぶと既存の色覚層を置き換える。
  ほかのカテゴリに排他はない（近視 + 遠視のような矛盾する組も、利用者が選べばそのまま重ねる。
  ue は判定しない。sensus の `Filter` の組み合わせ制約が将来増えたら sensus 側に寄せる）。
- **上限は 5 層**（定数 1 か所）。根拠は CPU 費用（重いフィルタを含む最悪で合計 約 1.5 秒）と、
  利用者が「いま何が掛かっているか」を把握できる数。排他グループは 1 層と数える。上限に達したら
  未選択の行を無効化して理由を示す。強度 0 の層は描画から除くが上限には数える。
- **体験プリセット**は今のところ 1 フィルタなので、押すと**層全体をその 1 フィルタに置き換える**。
  層集合がそのプリセットのフィルタ 1 つ以外になったらプリセット選択は外れ、戻さない。
  sensus の `Experience` が複数の vision フィルタを持つようになったら、「層全体をそのステップ列に置き換える」
  に拡張する。

### 2. -omaly は「別名」としてカタログ層に持つ

状態は id + 強度 + `variantId` だけで表し、-omaly の一覧行は「同じカタログ id の別名（強度 0.6）」を
示す別名テーブルとして定義側に置く。`ColorVisionType` の 7 種は、最終段（#124）で
「カタログ id + 別名」に置き換えて消す。

### 3. 適用順は段（stage）で決め、選択した順には依存させない

```text
motion → optics → media → retina → visualField → perception → colorVision
```

光が目に入ってから脳で知覚されるまでの順。**結果を選択の履歴に依存させない**ことが目的で、
生理学的な厳密さを主張するものではない（線形で可換な処理どうしは順序が結果に影響しない）。
同じ段の中はカタログの宣言順にして決定的にする。これにより、結果は「層の集合」だけで決まり、
永続化・2×2 比較・テスト・GPU 経路で同じ順序を再現できる。

| 段 | 入るフィルタ（暫定・#117 の実装で確定） |
|---|---|
| motion | vertigo, bppv_rotation, vestibular_neuritis, nystagmus |
| optics | myopia, hyperopia, presbyopia, astigmatism, cataract, starbursts, photophobia, dry_eye, eye_strain |
| media | floaters |
| retina | macular_degeneration, night_blindness, contrast_sensitivity, detail_loss, metamorphopsia |
| visualField | glaucoma, hemianopia, tunnel_vision |
| perception | diplopia, teichopsia, flickering_stars |
| colorVision | protanopia, deuteranopia, tritanopia, achromatopsia, tetrachromacy |

（30 フィルタすべてが 1 つの段に入る。テストで「段の無いフィルタがない」ことを固定する。）
色覚を最後に置くのは、光学・網膜・視野・知覚の結果として見えた像に錐体の欠損が掛かる、という
見立てと、#41 の例（光学 → 網膜 → 視野 → 色覚）に合わせるため。

**順序の正本の置き場所**: 暫定は ue のカタログに `stage` を持つ（#117）。ただし順序は「計算の正本は
sensus に 1 つ」という方針に属するので、sensus に標準順序の公開と中間結果の取得を要望する
（kako-jun/sensus#191）。sensus が公開したら ue の表を消して置き換える（#125）。ue に順序ロジックを
長く持たない。

### 4. 描画経路: CPU `apply()` を正準のまま、sensus の Pipeline で合成する

- プレビューの正準は CPU `apply()`（1024px）のまま。`layers` を段順に並べ、**bridge に
  `apply_vision_pipeline_cpu_rgba8(steps, rgba8, w, h)` を足して** `sensus_core::Pipeline` で 1 回の
  非同期ジョブとして適用する（#118）。ue に合成ロジックは書かない（#41 の方針）。
- **最新要求だけを描く**: 現行の `BeforeAfterView` の `_generation` + 待避（実行中は新しい要求を
  1 つだけ待避させ、古い結果は捨てる）をそのまま使う。変わるのは「何を渡すか」だけ。
- **費用**: 1 回の合成 = 各層の費用の和（最悪 5 層で約 1.5 秒）。まず全層を毎回再計算する素朴な実装で
  出し、**計測して体感で引っかかる（目安 500ms 超）場合だけ**、層境界ごとの出力を再利用する
  キャッシュ（変更された層より前は再計算しない）を足す（#123、計測ゲートつき）。中間結果の取得は
  sensus の `apply_with_trace`（#191）か、なければ 1 ステップずつの bridge 呼び出し。
- **量子化誤差**は最大 5 段で実用上の差が出るかを sensus 側で測る（#191 の要望 3）。ue は測定結果に従う。
- **GPU 経路（#1/#2/#5）との整合**: ライブルーペは同じ `layers` の順序で **N パスの多段シェーダ**
  （各パスが 1 層、出力を次のパスの入力へ）にする。順序は同じ 1 つの関数から得る。CPU の
  `Pipeline` と GPU の多段の等価性テストを #1 の受け入れ条件に足す（#1 にコメント）。上限 5 がパス数の
  上限にもなる。色覚のような隣り合う行列パスの融合は最適化として後回し。
  `FieldLossMode.blur` のように CPU でしか表現できないものは現状どおり CPU のみ。

### 5. UI

- 統合一覧（33 行）は**チェック式**。色覚カテゴリの行だけは排他なのでラジオ式の表示にし、見出しに
  「いずれか 1 つ」と添える。チェック済みの行には**適用順の番号**を出す。クリックした順ではなく
  段順の番号にする（結果が選択の順に依存しないので、クリック順を見せると誤解を招く）。
- プレビュー上に選択中の層の帯（適用順のチップ・✕・「すべて解除」）を置く。上限で未選択の行を無効化する。
- 調整パネルは層ごとの節。フォーカス中の層だけ開き、ほかは名前と強度の 1 行に畳む。各層の節に
  その層の受診喚起・注意書きを出す。
- HUD（#79）は 1 層なら従来どおり、複数層なら「名前 + 名前 …（+N）」で強度は出さない。原画比較
  （bypass）は全層に対する 1 つのまま。
- トレイ（#65）の高度なフィルタのサブメニューはチェック式（色覚クイック項目は排他のまま）。
  ホットキー（フィルタ解除）は全層解除で、新しいホットキーは足さない。
- **2×2 比較（#84）**: 色覚を選んでいるとき従来どおり出す。4 枚は「色覚より前の全層を 1 回だけ適用した
  結果」を共通の土台にして、その上に色覚 4 型を 1 枚ずつ適用する（色覚は最終段なので土台は 1 回で済み、
  各枠の追加費用は色覚 1 回分）。層なしのときは現行と同じ（#122）。
- **書き出し（#80）**: `ExportCaption` を層ごとの行に拡張する（1 層は現行と同じ見た目）。受診喚起は
  「urgency は最大、escalation は段ごとにマージして重複を除く」を合成するヘルパで作る。実験的フィルタを
  含めば実験の注記を添え、「シミュレーション（近似）」は常に焼き込む（#121）。

### 6. 永続化は v2 に上げ、v1 は移行して読む

`{version: 2, layers: [{id, strength, params, variant?}], focusedId, presetId, memory: {id: {strength, params}}}`。
v1（単一選択）は選択中の id を 1 層にし、-omaly のクイック選択は `variant` にして読む。読み込み時の
補正（未知 id を捨てる・範囲外を丸める・欠けを既定で埋める）に加え、重複・色覚グループ違反・上限超過は
「最初の 1 つを残す」で直す。#65 の ADR は「移行は書かない」としたが、v1 → v2 は自明で、利用者の
強度記憶を失わないため今回は移行を書く（#117）。`settings.filterType` / `settings.intensityByType` は
最終段（#124）で `settings.visionFilter` に統合し、旧キーは 1 回だけ移行して消す。

### 7. 段階移行（実装 Issue）

各段は単独でマージでき、前段までの挙動を退行させない。`ColorVisionType` / `FilterService` の削除は
**最後**。

| 段 | Issue | 内容 | 依存 |
|---|---|---|---|
| 1 | #117 | `VisionFilterState` をレイヤー列に（挙動不変）+ 段の表 + 永続化 v2（v1 移行） | なし |
| 2 | #118 | bridge に Pipeline の複数ステップ CPU 適用 | なし（1 と並行可） |
| 3 | #119 | 多選択 API（排他・上限・プリセット置換）+ 合成プレビュー + 合成順 golden | 1, 2 |
| 4 | #120 | 統合一覧・調整パネル・HUD の多選択 UI | 3 |
| 5 | #121 | トレイ・ホットキー・PNG 書き出し | 3（4 の後が望ましい） |
| 6 | #122 | 色覚 2×2 比較を層の土台つきに | 3, 4 |
| 7 | #123 | 層境界キャッシュ（計測ゲート。不要なら close） | 3, 4 |
| 8 | #124 | `ColorVisionType` / `FilterService` の削除・設定キー統合 | 4, 5, 6 |
| 付帯 | #125 | 暫定の段表を sensus の標準順序 API に置き換え | sensus#191, 1 |

受け入れの核は**合成順のヘッドレス golden テスト**（#119）: 各層を順に単体適用した結果とバイト一致、
選択順を入れ替えても同一、排他・上限・プリセット置換の状態遷移。#124 で旧参照が `lib/` から消えたことを
grep で確認する。

## 代替案

1. **#32 を単一選択のまま先に畳む（`ColorVisionType` を先に消す）**: 採らない。選択状態・一覧・トレイ・
   永続化を単一選択の形で作り直したあと、#41 で同じ箇所をもう一度作り直すことになる。-omaly の別名の
   持ち方も層の単位が決まらないと決められない。代わりに #117 でレイヤー列を先に入れ（挙動不変）、
   旧系統を消す作業だけを最後に回した。
2. **`ColorVisionType` / `FilterService` を残し、多選択は `VisionFilterState` だけに足す**: 採らない。
   強度の正本が 2 つ・選択の保存先が 2 か所という #32 の問題が残ったまま、層の数だけ同期のズレる箇所が増える。
3. **利用者が並べ替えられるレイヤースタック（Photoshop 式）**: 採らない。対象は「何が見えにくいか」を
   確かめたい人で、順序の自由度は結果の再現性・永続化・2×2 比較・GPU 経路の等価性を重くするのに対して
   価値が薄い。将来必要なら「段順の上書き」として足せる（段順が既定であり続ける）。
4. **ue 側で合成ロジックを持つ（画像を自前で重ねる）**: 採らない。#41 の方針と、計算の正本は sensus という
   原則に反する。
5. **同時に複数の色覚型を許す**: 採らない。色覚 4 型は同じ錐体の欠損を別の型で表したもので重ねる意味が
   ない（比較したい用途は 2×2 が担う）。
6. **上限なし**: 採らない。費用が層数に比例し、利用者が内容を把握できなくなる。

## 根拠

- 選択の単位を 1 つ決めれば、#32（2 系統）と #41（複数選択）が同じ変更で解ける。単一選択は特殊ケースに
  なり、別モデルが要らない。
- 順序を段で固定して選択履歴から切り離すと、結果が集合の関数になり、テスト・永続化・比較・GPU で
  同じ結果を再現できる。
- 合成を sensus の `Pipeline` に任せれば、単体適用と合成の一致は sensus の保証に乗れる。ue は順序と
  状態だけを持つ。
- 重い描画の最適化（キャッシュ）は計測を先にして、不要なら作らない。

## 結果・トレードオフ

- 最悪の描画時間は層の和（5 層で約 1.5 秒）。最新要求だけを描く仕組みで操作は詰まらないが、重い組は
  スライダー操作に追従が遅れる。#123 の計測で判断する。
- 段の割り当ては暫定の見立てで、個々のフィルタがどの段かは議論の余地がある。可換な処理が多いので
  結果への影響は限定的だが、sensus #191 で正本化されるまで ue 側の表が正本になる。
- 8bit ↔ f32 の往復誤差は段数で累積する。sensus での測定結果待ち。
- 排他グループは色覚だけ。ほかの「意味として矛盾する組」（近視 + 遠視など）は利用者の自由にし、
  ue は止めない。
- 体験プリセットは当面 1 フィルタのまま。複数 vision フィルタを持つ体験は sensus の対応を待つ。
- 実機（macOS / Windows）での操作感・性能・トレイの複数チェックの表示は、各実装 Issue の
  「kako-jun 実機」項目で確認する。この ADR 時点では未確認。

## 未解決の問い（推奨の既定で進める）

| 問い | 既定 |
|---|---|
| 上限は 5 でよいか | 5。#123 の計測や実機の使用感で見直す（定数 1 か所） |
| 層の段の割り当て（例: metamorphopsia を retina にするか perception にするか） | 上表。#117 で sensus のドキュメントと照合して確定 |
| 書き出しキャプションが 5 層で長すぎないか | 層ごとの行で折り返す。#121 で最長言語の PNG を目視 |
| 強度 0 の層を上限に数えるか | 数える（見た目上の選択が残っているため） |
| 複数症状の組み合わせ保存（「マイ体験」） | 今回の範囲外。必要になれば per-id 記憶とは別に Issue 化 |

## 関連 Issue・PR・docs

- Issue #32、#41、#57（強度記憶）、#60（唯一の正本）、#65（永続化・トレイ）、#67/#113（dead code）、
  #72/#100（統合一覧・3 カラム）、#79（HUD・bypass）、#80（書き出し）、#84（2×2 比較）、#85（CPU
  正準）、#1/#2/#5（GPU ライブ経路）
- 実装 Issue: #117〜#125。sensus 側の要望: kako-jun/sensus#191
- `docs/ARCHITECTURE.md`「状態モデルの統一と多症状の同時適用 (#32 / #41)」
- `docs/adr/2026-09-30-filter-selection-persistence-and-tray-submenu.md`、
  `docs/adr/2026-09-30-color-vision-2x2-compare.md`、`docs/adr/2026-09-30-home-screen-unified-list-and-three-columns.md`
