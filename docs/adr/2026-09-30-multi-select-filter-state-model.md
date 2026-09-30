# ADR: 状態モデルを「順序つきレイヤー列」の 1 系統に統一し、複数症状の同時適用を sensus の Pipeline で合成する

- **決定日**: 2026-09-30（Issue #32・#41 を一体で設計）
- **記録日**: 2026-09-30（ADR 化）
- **ステータス**: Accepted（設計のみ。実装は段階ごとの Issue #117〜#125 で行う。各段の完了時に「結果・トレードオフ」を更新する）

## 文脈（問題）

#32 は「状態モデルが 2 つ並行している」問題、#41 は「症状を 1 つしか選べない」問題で、
**どちらも「選択の単位を何にするか」という同じ決定に行き着く**。#32 を単一選択のまま畳むと、
#41 で同じ箇所（選択状態・一覧・トレイ・永続化）をもう一度作り直すことになるため、1 本の
ADR で設計する。

この ADR は、両 Issue の記述のうち次の 3 点を**上書きする**。

- **#32 の「GPU live 適用（#1/#2/#5）の着手と歩調を合わせるのが安全」**（先行で畳むと UI 退行する
  という懸念）: 上書きする。現状の消費者（トレイ・一覧・2×2・書き出し・永続化）を全数調べたところ、
  退行の原因は「ColorVisionType 経路が宙に浮く」ことであり、GPU 経路とは独立に、旧系統を**最後に
  消す**段階移行で避けられる（下記「段階移行」）。GPU 経路の着手を待つ必要はなく、待つと #41 と
  矛盾する（単一選択の形で畳んだものを作り直す）。GPU 経路には「同じ順序で多段にする」という
  制約だけを #1 に渡す。
- **#41 の「複数 `VisionFilter` を選択順に…多段適用」**: 「**段（stage）の順序で**適用する」に
  変更する。選択した順に適用すると、結果が操作の履歴に依存して、永続化・2×2 比較・テストで同じ
  結果を再現できない。
- **#41 のコメントにある「`AudioPipeline` もブリッジで公開」**は、この ADR の範囲外とする
  （視覚のプレビュー合成だけを扱う。聴覚は #10（`HearingFilter` の bridge）と #20（聴覚モードを
  ue に入れるかの設計）で扱う）。

### 現状の正確な把握（2026-09-30、main 621286e 時点）

状態は 2 系統ある。

| 系統 | 単位 | 役割 |
|---|---|---|
| `VisionFilterState`（`lib/services/vision_filter_state.dart`） | カタログ 30 フィルタの id + 強度 + payload | プレビューの**唯一の正本**（#60）。per-id の強度/payload 記憶、体験プリセット、原画比較の bypass holder を持つ |
| `FilterService`（`lib/services/filter_service.dart`） | `ColorVisionType` の **8 値（`none` + 7 型）** + 型ごとの強度記憶（#57、`settings.intensityByType`） | トレイの色覚クイック項目・2×2 比較・色覚のクイック選択用。`SettingsService.filterType` に最後の型を残す |

（Issue #32 の「7 種」は `none` を除いた数。7 型 = protanopia / deuteranopia / tritanopia /
achromatopsia / protanomaly / deuteranomaly / tritanomaly。）

`selectColorVision`（`color_vision_selection.dart`）が 2 系統をつなぐ**唯一の橋**で、色覚を
クイック選択すると `VisionFilterState._isColorQuickSelection = true` と `_colorVisionType` が立つ。
**強度の出どころが 2 つある**のが核心で、`preview_selection.dart` の `selectedStrength` /
`adjustPreviewStrength` / `showsAdvancedStrengthSlider` は `isColorQuickSelection` を見て
「色覚クイック選択なら `FilterService.intensity`（型別記憶）、それ以外は `VisionFilterState.strength`
（id 別記憶）」と分岐する。つまり同じカタログ id（例: protanopia）でも、クイック選択で見えている
強度は `settings.intensityByType` 側、永続 JSON v1 の `strengthById` に入っているのは advanced 側の値で、
**両者は別物**。-omaly（`protanomaly` / `deuteranomaly` / `tritanomaly`）は opia と同じカタログ id へ
写り、強度が弱い（0.6）だけなので、`colorVisionType` を通してしか識別できない。

**単一選択を前提にしている箇所**（`rg` で網羅）:

- 状態: `VisionFilterState` の `_selectedId` / `_strength` / `_params` / `_selectedPresetId` /
  `_isColorQuickSelection` / `_colorVisionType`、`select` / `selectColorVisionType` / `selectPreset` /
  `restore` / `snapshot` / `build()`（30 ケースの switch）。`_bypassHolders` だけは選択数に依存しない。
- 入口: `color_vision_selection.dart`・`preview_selection.dart`・`filter_list_selection.dart`
  （`applyFilterListEntry` / `selectedFilterListEntry`＝統合一覧 33 行 = 30 + -omaly 3 の「今の 1 行」）。
- 描画: `home_screen.dart` の `_previewCard` → `BeforeAfterView` が 1 つの `VisionFilter` +
  強度を `CpuVisionRenderer.apply`（`apply_vision_cpu_rgba8`、1024px 正準）へ渡す。
- 推奨サンプル（#78）: `recommendedSampleIdForFilter(visionState.selectedId)` が 3 か所
  （`home_screen.dart`・`main.dart`・`image_source_picker.dart`）で「選択中の 1 フィルタ」の
  推奨サンプルへ追従する。
- キー操作（#63、`app_shortcuts.dart`）: ↑↓ = `CycleFilterIntent`（見えている行を順送りして**選択**）、
  ←→ = `AdjustStrengthIntent`（選択中フィルタの強度）。
- 調整 UI: `adjust_panel.dart` / `intensity_slider.dart` / `filter_param_panel.dart`（1 フィルタの
  調整と、色覚クイック用スライダーと advanced 用スライダーの二重化）、`strength_caution.dart`
  （フィルタごとの強度注意のしきい値・目印）、`experience_presets.dart`（選択表示を
  `selectedPresetId` で決める）。
- 周辺: `loupe_hud.dart`（名前 + 強度 1 つ）、`tray_service.dart` / `tray_menu_labels.dart`
  （1 つにチェック）、`color_vision_compare.dart`（色覚カテゴリ選択中に 2×2）、
  `ExportCaption`（症状名・強度が 1 つずつ）、`resolveConsultNotice`（1 フィルタの urgency +
  escalation）、`vision_filter_snapshot.dart` / `vision_filter_store.dart`（永続 JSON v1 が 1 選択）。
- `main.dart`: 起動時に `settings.filterType` から色覚シード（**初回起動は deuteranomaly**）→
  `restoreAndBind` の順で復元。

**#67（dead code 撤去、PR #113）で消えたもの**は未使用コードだけで、2 系統の構造そのものは
両方に生きた消費者がいるため残った。`ColorVisionType` の参照は `lib/` の 15 ファイルに残る。
`ShaderFilter`（GPU）は本番では未使用で、将来のライブルーペ（#1）用に温存されている。

### sensus 側の合成の能力

- `sensus_core::pipeline::Pipeline` / `FilterStep{filter, strength}`（crate ルートで再エクスポート
  されているのは `AudioPipeline` だけ。視覚の `Pipeline` はモジュール経由）は**追加した順に**
  適用し、単体適用と挙動が一致する（`FilterStep::apply` は `apply` に委譲）。`docs/overview.md` は
  "order matters" とするだけで、**標準の順序規約は無い**。
- 各ステップで 8bit ↔ f32 を往復するため、段数に応じて量子化誤差が累積する（`pipeline.rs` 冒頭の注記）。
- bridge（`sensus_bridge.rs`）は `apply_vision_cpu_rgba8`（1 フィルタ）だけを公開しており、
  `Pipeline` は未公開。`Experience` は vision フィルタを高々 1 つ（+ hearing 1 つ）しか持たない。
- 実測（#85、1024²、opt-level 3）は **3 フィルタだけ**: 近視 約 300ms、starbursts 約 30ms、
  protanopia 約 25ms。残り 27 フィルタは未測定で、最悪値はこれより重い可能性がある。

## 決定

### 1. 選択の単位は「カタログ id ごとに 1 つのレイヤー」の順序つき列

```text
VisionLayer { id, strength, params, variantId?, origin }  // variantId = -omaly の別名（protanomaly 等）
VisionFilterState.layers : List<VisionLayer>               // 適用順（下記 4）で並ぶ。id は重複しない
VisionFilterState.focusedId : String?                      // 調整パネルが開く層・#78 の推奨サンプルの追従先
```

- **単一選択 = 1 要素の多選択**。別の状態モデルは作らない。従来の `select` は「全部外して 1 つ足す」
  `replaceWith` に相当し、既存の単一選択 API（`selectedId` / `strength` / `params` / `build()`）は
  移行期間中「フォーカス中の層」を見る薄い互換層として残す。
- **定義と状態の分離を保つ**: min/max/default/options・段・排他グループ・-omaly の別名表はカタログ
  （定義）、どの層が選ばれているか・強度・payload は `VisionFilterState`（状態）。状態は id で定義を参照するだけ。
- **排他グループ**: 色覚カテゴリ（protanopia / deuteranopia / tritanopia / achromatopsia /
  tetrachromacy と -omaly 3 種）は**同時に 1 つだけ**。色覚を選ぶと既存の色覚層を置き換える。
  ほかのカテゴリに排他はない（近視 + 遠視のような矛盾する組も、利用者が選べばそのまま重ねる。
  ue は判定しない。sensus の `Filter` の組み合わせ制約が将来増えたら sensus 側に寄せる）。
- **上限は 5 層**（定数 1 か所）。根拠は CPU 費用と、利用者が「いま何が掛かっているか」を把握できる数。
  排他グループは 1 層と数える。強度 0 の層は描画から除くが上限には数える。
  - 上限に達したときの無効化は**未選択の行**に掛けるが、次の 2 つは例外（有効のまま）: ①色覚行
    （すでに色覚層があれば「置換」になり層数が増えないため）、②体験プリセット（層全体を置き換える
    ため）。色覚層が無いまま上限に達しているときの色覚行は無効。
- **体験プリセット**は今のところ 1 フィルタなので、押すと**層全体をその 1 フィルタに置き換える**。
  層集合がそのプリセットのフィルタ 1 つ以外になったらプリセット選択は外れ、戻さない
  （`experience_presets.dart` の選択表示は `selectedPresetId` で決まるので、外れた時点で消える）。
  sensus の `Experience` が複数の vision フィルタを持つようになったら、「層全体をそのステップ列に
  置き換える」に拡張する。

### 2. 強度の出どころを 1 つにする（2 系統の核心）

- **記憶の鍵を `variantId ?? id` にする**。`protanopia` / `achromatopsia` などは id、-omaly は
  `protanomaly` などの別名。これは `ColorVisionType.name` と一致するので、`settings.intensityByType` の
  キーをそのまま持ち込める。payload（params）の記憶は従来どおり id 単位。
- **`FilterService` の強度記憶（#57）は `VisionFilterState` の per-key 記憶に統合する**。これを最終段
  でなく**第 1 段（#117）に前倒しする**。`FilterService.intensity` / `setIntensity` は
  `VisionFilterState` への薄い委譲になり、強度を永続化する書き手は `settings.visionFilter` の 1 つだけに
  なる。`settings.intensityByType` は起動時に 1 回だけ読み、移行して消す。これで `selectedStrength` /
  `adjustPreviewStrength` / `showsAdvancedStrengthSlider` の「どちらから読むか」の分岐は強度について
  不要になり（常に層の `strength`）、見た目の挙動は変わらない。
- **`isColorQuickSelection`（全体に 1 つのフラグ）は、層ごとの属性 `origin`（クイック / advanced）に
  置き換える**。#117 で層の属性にし、`isColorQuickSelection` は「フォーカス中の層の origin」を返す
  互換 getter として残す（単一選択では従来と同じ値）。これで #117 までは挙動不変。UI 側の消費者
  （調整パネルの二重スライダー・一覧のハイライト）は #120、トレイの消費者は #121 で層単位の判定に
  移し、互換 getter と `origin` 自体は #124 で消す。#119（多選択 API）は層ごとの `origin` をそのまま使う。
- **v1 → v2 の移行で色覚層の強度をどう決めるか**（`origin` と強度の出どころの食い違いを
  引き継がない）:
  1. v1 に `colorVisionType = t`（≠ none）があれば、それは色覚クイック選択だった。層は
     `{id: catalogId(t), variantId: t が -omaly なら t、そうでなければ null, origin: クイック}`、
     **強度は `settings.intensityByType[t]`、無ければ推奨強度（opia=1.0、-omaly=0.6）**にする。
     v1 の `strengthById[id]` は advanced 側の値なので使わない。
  2. `colorVisionType` が無ければ advanced / プリセット由来で、強度は従来どおり `strengthById[id]`。
  3. v2 の per-key 記憶は `strengthById`（advanced 側）をまず入れ、そのうえに
     `intensityByType[t]`（7 型）を**上書き**で入れる。色覚 id は一覧の色覚行がクイック選択経由のため、
     利用者が実際に見てきた値は `intensityByType` 側だから。`intensityByType` に無い型は `strengthById` を残す。
  4. 移行は `VisionFilterStore` の初回読み込み 1 回だけ（`settings.intensityByType` の読み出しが必要なので
     `main.dart` の復元で `FilterService` の永続値を渡す）。移行後は `settings.intensityByType` を消す。

### 3. -omaly は「別名」としてカタログ層に持つ

状態は id + 強度 + `variantId` だけで表し、-omaly の一覧行は「同じカタログ id の別名（強度 0.6）」を
示す別名テーブルとして定義側に置く。`ColorVisionType`（8 値）は、最終段（#124）で
「カタログ id + 別名」に置き換えて消す。

### 4. 適用順は段（stage）で決め、選択した順には依存させない

```text
motion → optics → media → retina → visualField → perception → colorVision
```

**これは「結果が選択の履歴に依存しない」ための規約であり、生理学的な厳密さを主張するものではない。**
段の並びは、光が目に入ってから脳で知覚されるまでの大まかな順に沿わせたが、個々のフィルタの割り当ては
見立てで、厳密に決まるものではない。**色覚を最後に置く実際の理由は実装上のもの**: 2×2 比較（#84）が
「色覚以外の層を 1 回だけ適用した結果」を 4 枚で共有でき（各枠の追加費用が色覚 1 回分になる）、
色覚は層の列の末尾で入れ替えるだけで済むため。色覚の変換は画素ごとの行列で、空間処理（ぼかし・
歪み・視野欠損）とは**近似的に可換なものが多い**（8bit 丸めと clamp があるので厳密ではない）ので、
末尾に置いても結果が大きく変わらない、という見込みに立つ。

**同じ段の中の順序は、sensus の `Filter` 列挙の宣言順に揃える**。ue のカタログの並び
（例: myopia, hyperopia, presbyopia, astigmatism）は表示順で、sensus の宣言順
（Myopia, Hyperopia, Astigmatism, Presbyopia）とは違う。段の表は ue のカタログとは別に、
sensus の宣言順で書いた順序つきのリストとして持つ。そうしておけば、sensus が標準順序を公開したとき
（#125）に置き換えても、結果は同じで差分が出ない。

| 段 | 入るフィルタ（sensus の宣言順・暫定。#117 で確定） |
|---|---|
| motion | vertigo, bppv_rotation, vestibular_neuritis, nystagmus |
| optics | myopia, hyperopia, astigmatism, presbyopia, cataract, photophobia, diplopia, starbursts, eye_strain, dry_eye |
| media | floaters |
| retina | macular_degeneration, night_blindness, metamorphopsia, contrast_sensitivity, detail_loss |
| visualField | glaucoma, hemianopia, tunnel_vision |
| perception | teichopsia, flickering_stars |
| colorVision | protanopia, deuteranopia, tritanopia, achromatopsia, tetrachromacy |

（30 フィルタすべてが 1 つの段に入る。テストで「段の無いフィルタがない」こと、および段内の順が上の
リストどおりであることを固定する。diplopia は像が二重になる現象なので、知覚（脳）でなく光学側の
optics に置く。）

**順序の正本の置き場所**: 暫定は ue に上の表を持つ（#117）。ただし順序は「計算の正本は sensus に
1 つ」という方針に属するので、sensus に標準順序の公開を要望する（kako-jun/sensus#191）。sensus が
公開したら ue の表を消して置き換える（#125）。ue に順序ロジックを長く持たない。

### 5. 描画経路: CPU `apply()` を正準のまま、sensus の Pipeline で合成する

- プレビューの正準は CPU `apply()`（1024px）のまま。`layers` を段順に並べ、**bridge に
  `apply_vision_pipeline_cpu_rgba8(steps, rgba8, w, h)` を足して** `sensus_core::pipeline::Pipeline` で
  1 回の非同期ジョブとして適用する（#118）。ue に合成ロジックは書かない（#41 の方針）。
- **最新要求だけを描く**: 現行の `BeforeAfterView` の `_generation` + 待避（実行中は新しい要求を
  1 つだけ待避させ、古い結果は捨てる）をそのまま使う。変わるのは「何を渡すか」だけ。
- **推奨サンプル（#78）**: 複数層のときは **`focusedId` の層**（最後に追加または触れた層）の推奨サンプルに
  追従する。理由は、サンプルは「いま調べているフィルタの効果が見える絵」を出すためのもので、利用者が
  今見ているのがフォーカス中の層だから。「色覚層を優先」は、色覚が無い組では決まらず、色覚を後から
  足した途端にサンプルが切り替わって驚くため採らない。フォーカスが外れた（層を消した）ときは、適用順で
  最後の層へ移す。手動で選んだサンプルや自分の写真は従来どおり追従しない。呼び出し 3 か所は引数が
  `selectedId` から `focusedId` に変わるだけ。
- **費用**: 1 回の合成 = 各層の費用の和。**「5 層で約 1.5 秒」は、測定済みの 3 フィルタ（最大 約 300ms）
  からの外挿（300ms × 5）**で、未測定の 27 フィルタを含む実測の最悪値ではない。#123 で全 30 フィルタを
  1024² で測って確かめる。まず全層を毎回再計算する素朴な実装で出し、**計測して体感で引っかかる
  （目安 500ms 超）場合だけ**、層境界ごとの出力を再利用するキャッシュを足す（#123、計測ゲートつき）。
- **キャッシュの限界**: 再利用できるのは「変更された層より前」だけなので、**後ろの層を調整するときだけ
  効く**。前段の重い層（例: optics の近視）を調整している間は、後続が全部再計算になる。その手当てとして、
  ドラッグ中は縮小したプレビュー（例: 512px）で描き、離したときに 1024px で描き直す案を #123 で検討する。
- **量子化誤差**は最大 5 段で実用上の差が出るかを sensus 側で測る（#191 の要望 3）。ue は測定結果に従う。
- **GPU 経路（#1/#2/#5）との整合**: ライブルーペは同じ `layers` の順序で **N パスの多段シェーダ**
  （各パスが 1 層、出力を次のパスの入力へ）にする。順序は同じ 1 つの関数から得る。CPU の
  `Pipeline` と GPU の多段の等価性テストを #1 の受け入れ条件に足す（#1 にコメント）。上限 5 がパス数の
  上限にもなる。`FieldLossMode.blur` のように CPU でしか表現できない層は現状どおり CPU のみ。
  **GPU で描けない層（vertigo / bppv など）が混ざったときのルーペの既定**: その層を飛ばして描き、
  HUD に「この症状は静止画プレビューのみ」と出す（#1 に一文）。

### 6. UI

- 統合一覧（33 行）は**チェック式**。色覚カテゴリの行だけは排他なのでラジオ式の表示にし、見出しに
  「いずれか 1 つ」と添える。チェック済みの行には**適用順の番号**を出す。クリックした順ではなく
  段順の番号にする（結果が選択の順に依存しないので、クリック順を見せると誤解を招く）。
- プレビュー上に選択中の層の帯（適用順のチップ・✕・「すべて解除」）を置く。上限で未選択の行を
  無効化する（例外は「1. 上限」のとおり色覚行と体験プリセット）。
- 調整パネルは層ごとの節。フォーカス中の層だけ開き、ほかは名前と強度の 1 行に畳む。各層の節に
  その層の受診喚起・注意書き（`ConsultNoticeBlock`・`strength_caution`）を出す。色覚のクイック用と
  advanced 用に分かれていた強度スライダーは、強度の出どころが 1 つになったので（決定 2）1 つにする。
- **キー操作（#63）**: ↑↓ は「行フォーカスの移動」だけにし、**選択のトグルは Space / Enter** に分ける
  （多選択で移動のたびに層が増減するのを避ける）。←→ は `focusedId` の層の強度（フォーカスが無ければ
  何もしない）。`/`（検索）・Esc・貼り付けは変えない。
- HUD（#79）は 1 層なら従来どおり、複数層なら「名前 + 名前 …（+N）」で強度は出さない。原画比較
  （bypass）は全層に対する 1 つのまま。
- トレイ（#65）の高度なフィルタのサブメニューはチェック式（色覚クイック項目は排他のまま）。
  ホットキー（フィルタ解除）は全層解除で、新しいホットキーは足さない。
- **2×2 比較（#84）**: 色覚を選んでいるとき従来どおり出す。4 枚は「色覚より前の全層を 1 回だけ適用した
  結果」を共通の土台にして、その上に色覚 4 型を 1 枚ずつ適用する。層なしのときは現行と同じ（#122）。
- **書き出し（#80）**: `ExportCaption` を層ごとの行に拡張する（1 層は現行と同じ見た目）。受診喚起は
  「urgency は最大、escalation は段ごとにマージして重複を除く」を合成するヘルパで作る。実験的フィルタを
  含めば実験の注記を添え、「シミュレーション（近似）」は常に焼き込む（#121）。

### 7. 永続化は v2 に上げ、v1 は移行して読む

```text
{ version: 2,
  layers: [{ id, strength, params, variantId?, origin }],   // 適用順
  focusedId, presetId,
  strengthByKey: { <variantId ?? id>: number },              // 記憶（決定 2）
  paramsById:    { <id>: {...} } }
```

- v1（単一選択）の移行規則は「2. 強度の出どころを 1 つにする」のとおり（-omaly・色覚クイック選択の
  強度の決め方を含む）。`VisionFilterSnapshot.fromJson` は、現状「版が違えば丸ごと捨てて null」だが、
  **v1 に限って移行して読む**ように変える（v2 より新しい版・壊れた JSON は従来どおり捨てる）。
- 読み込み時の補正（未知 id を捨てる・範囲外を丸める・欠けを既定で埋める）に加え、重複・色覚グループ違反・
  上限超過は「最初の 1 つを残す」で直す。
- **`focusedId` を保存する理由**は、再起動後に調整パネルで開いていた層（と #78 の推奨サンプルの追従先）を
  復元するため。
- #65 の ADR は「移行は書かない」としたが、v1 → v2 は自明で、利用者の強度記憶を失わないため今回は
  移行を書く（#65 の ADR の該当箇所にこの ADR への参照を足した）。`settings.filterType` は最終段（#124）で
  `settings.visionFilter` に統合する。`main.dart` の初回起動の deuteranomaly の既定は、#124 で
  「初期状態の層」として `VisionFilterState` が持つ。

### 8. 段階移行（実装 Issue）

各段は単独でマージでき、前段までの挙動を退行させない。`ColorVisionType` / `FilterService` の削除は
**最後**。

| 段 | Issue | 内容 | 依存 |
|---|---|---|---|
| 1 | #117 | `VisionFilterState` をレイヤー列に（挙動不変）+ 段の表（sensus 宣言順）+ 記憶鍵 `variantId ?? id` + `FilterService` 強度記憶の統合（`intensityByType` の移行）+ `origin` の層属性化 + 永続化 v2（v1 移行） | なし |
| 2 | #118 | bridge に Pipeline の複数ステップ CPU 適用 | なし（1 と並行可） |
| 3 | #119 | 多選択 API（排他・上限・プリセット置換）+ 合成プレビュー + 合成順 golden + 推奨サンプルの `focusedId` 追従 | 1, 2 |
| 4 | #120 | 統合一覧・調整パネル・HUD・キー操作の多選択 UI（`origin` の UI 消費者を層単位に） | 3 |
| 5 | #121 | トレイ・ホットキー・PNG 書き出し | 3（4 の後が望ましい） |
| 6 | #122 | 色覚 2×2 比較を層の土台つきに | 3, 4 |
| 7 | #123 | 全 30 フィルタの実測 + 層境界キャッシュ（計測ゲート。不要なら close） | 3, 4 |
| 8 | #124 | `ColorVisionType` / `FilterService` / `origin` / `isColorQuickSelection` の削除・`filterType` 統合 | 4, 5, 6 |
| 付帯 | #125 | 暫定の段表を sensus の標準順序 API に置き換え | sensus#191, #119 |

**#120〜#122 の間の暫定挙動**（この間の退行を防ぐための取り決め）:

- #120 がマージされた時点で多層を選べるようになるが、**複数層のとき PNG 書き出しは無効にして理由を
  表示する**（#121 で解除。層の情報が欠けた PNG を出さないため）。
- **2×2 比較**は、層集合が「色覚層 1 つだけ」のときだけ出す。ほかの層があるときはスイッチを隠す
  （他層を無視した比較を出さない。#122 で解除）。
- **トレイ**は #121 まで 1 行のチェック（単一選択の意味）のまま: 層集合がその 1 フィルタだけのときに
  チェックが付き、クリックは層全体をそのフィルタに置き換える。複数層のときはどの行にもチェックが付かない。

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
5. **同時に複数の色覚型を許す**: 採らない。色覚の各型（protanopia / deuteranopia / tritanopia は特定の
   錐体が働かない状態、achromatopsia は錐体機能全体の欠如）は、どの錐体がどれだけ働くかを 1 つの
   型で表したもので、重ねても実在の状態に対応しない（比較したい用途は 2×2 が担う）。
6. **上限なし**: 採らない。費用が層数に比例し、利用者が内容を把握できなくなる。
7. **層の強度記憶を色覚だけ別に残す（`FilterService` を温存）**: 採らない。2 系統の問題そのもの。
   強度の統合を最終段まで先送りすると、多選択 API が「どの層はどちらの強度を見るか」を層ごとに持つことに
   なるため、第 1 段に前倒しした。

## 根拠

- 選択の単位を 1 つ決めれば、#32（2 系統）と #41（複数選択）が同じ変更で解ける。単一選択は特殊ケースに
  なり、別モデルが要らない。
- 順序を段で固定して選択履歴から切り離すと、結果が集合の関数になり、テスト・永続化・比較・GPU で
  同じ結果を再現できる。
- 合成を sensus の `Pipeline` に任せれば、単体適用と合成の一致は sensus の保証に乗れる。ue は順序と
  状態だけを持つ。
- 重い描画の最適化（キャッシュ）は計測を先にして、不要なら作らない。

## 結果・トレードオフ

- 最悪の描画時間は層の和。3 フィルタの実測からの外挿では 5 層で約 1.5 秒だが、未測定フィルタを含む実測は
  #123 で取る。最新要求だけを描く仕組みで操作は詰まらないが、重い組はスライダー操作への追従が遅れる。
- 段の割り当ては暫定の見立てで、個々のフィルタがどの段かは議論の余地がある。近似的に可換なものが多い
  ので結果への影響は限定的だが、sensus #191 で正本化されるまで ue 側の表が正本になる。
- 8bit ↔ f32 の往復誤差は段数で累積する。sensus での測定結果待ち。
- 排他グループは色覚だけ。ほかの「意味として矛盾する組」（近視 + 遠視など）は利用者の自由にし、
  ue は止めない。
- 体験プリセットは当面 1 フィルタのまま。複数 vision フィルタを持つ体験は sensus の対応を待つ。
- 第 1 段（#117）が大きくなる（層列化・記憶鍵・強度統合・永続化 v2）。挙動不変のまま 1 PR にするか
  割るかは、実装時に PR の大きさで判断してよい（割る場合は「層列化と永続化 v2」→「強度統合」の順）。
- 実機（macOS / Windows）での操作感・性能・トレイの複数チェックの表示は、各実装 Issue の
  「kako-jun 実機」項目で確認する。この ADR 時点では未確認。

## 未解決の問い（推奨の既定で進める）

| 問い | 既定 |
|---|---|
| 上限は 5 でよいか | 5。#123 の計測や実機の使用感で見直す（定数 1 か所） |
| 層の段の割り当て（例: metamorphopsia を retina にするか perception にするか） | 上表。#117 で sensus のドキュメントと照合して確定 |
| 書き出しキャプションが 5 層で長すぎないか | 層ごとの行で折り返す。#121 で最長言語の PNG を目視 |
| 強度 0 の層を上限に数えるか | 数える（見た目上の選択が残っているため） |
| 複数症状の組み合わせ保存（「マイ体験」） | 今回の範囲外。必要になれば per-key 記憶とは別に Issue 化 |
| GPU で描けない層（vertigo / bppv など）が混ざったルーペ | その層を飛ばして描き、HUD に「この症状は静止画プレビューのみ」（#1 に一文） |
| `focusedId` を永続化するか | する。再起動後に調整パネルで開いていた層（と推奨サンプルの追従先）を復元するため |
| 複数層のときの推奨サンプル | `focusedId` の層に追従（決定 5 の理由どおり） |

## 関連 Issue・PR・docs

- Issue #32、#41、#57（強度記憶）、#60（唯一の正本）、#63（キー操作）、#65（永続化・トレイ）、
  #67/#113（dead code）、#72/#100（統合一覧・3 カラム）、#78（推奨サンプル）、#79（HUD・bypass）、
  #80（書き出し）、#84（2×2 比較）、#85（CPU 正準）、#1/#2/#5（GPU ライブ経路）、#10/#20（聴覚）
- 実装 Issue: #117〜#125。sensus 側の要望: kako-jun/sensus#191
- `docs/ARCHITECTURE.md`「状態モデルの統一と多症状の同時適用 (#32 / #41)」
- `docs/adr/2026-09-30-filter-selection-persistence-and-tray-submenu.md`、
  `docs/adr/2026-09-30-color-vision-2x2-compare.md`、`docs/adr/2026-09-30-home-screen-unified-list-and-three-columns.md`
