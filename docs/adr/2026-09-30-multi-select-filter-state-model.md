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
- `before_after_view.dart`: after 側の見出し（`visionFilterDisplayName(l10n, widget.colorVisionType,
  widget.filterId)`、725 行付近）と、書き出しファイル名の `symptomId`（`colorVisionType?.id ??
  filterId ?? 'none'`、648 行付近）が 1 フィルタ前提。見出しは #120（複数層なら HUD と同じ
  「名前 + 名前 …（+N）」）、`symptomId` は書き出しの一部として #121（適用順の id を連結し、
  長さの上限を設ける）が担当する。
- `color_vision_compare_view.dart`: 4 セルが強度 1 つ（`strength`）と元画像だけを受け取る
  1 フィルタ前提の構造で、土台（色覚以外の層の合成結果）を受け取れない。表示条件の
  `isColorVisionFilterId(selectedId)`（`services/color_vision_compare.dart`）も 1 選択前提。#122 が担当する。
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
VisionLayer { id, params, variantId?, origin }             // variantId = -omaly の別名（protanomaly 等）。強度は持たない（決定 2）
VisionFilterState.layers : List<VisionLayer>               // 適用順（下記 4）で並ぶ。id は重複しない
VisionFilterState.focusedId : String?                      // 調整パネルが開く層・#78 の推奨サンプルの追従先
```

- **単一選択 = 1 要素の多選択**。別の状態モデルは作らない。従来の `select` は「全部外して 1 つ足す」
  `replaceWith` に相当し、既存の単一選択 API（`selectedId` / `strength` / `params` / `build()`）は
  移行期間中「フォーカス中の層」を見る薄い互換層として残す。
- **定義と状態の分離を保つ**: min/max/default/options・段・排他グループ・-omaly の別名表はカタログ
  （定義）、どの層が選ばれているか・強度・payload は `VisionFilterState`（状態）。状態は id で定義を参照するだけ。
  強度は層ではなく per-key 記憶（決定 2）が持ち、層の強度はそこから導く。
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
- **層は強度を持たず、強度は per-key 記憶の 1 か所だけが持つ**（二重化の再発防止）。層の強度は
  `strengthByKey[variantId ?? id]`、無ければ既定（色覚 7 型は推奨強度 opia=1.0 / -omaly=0.6、
  それ以外はカタログの既定）から**読むときに導く**。推奨強度へのフォールバックは記憶に**書き込まない**
  （書き込むのは利用者が強度を変えたときだけ。スライダーを動かしていない型が推奨値のまま
  「固定」されることを避ける）。永続 JSON の `layers[]` にも `strength` は持たせない。
- **`FilterService` の強度記憶（#57）は `VisionFilterState` の per-key 記憶に統合する**。これを最終段
  でなく**第 1 段（#117）に前倒しする**。`FilterService.intensity` / `setIntensity` は
  per-key 記憶への薄い委譲になり、強度を永続化する書き手は `settings.visionFilter` の 1 つだけに
  なる。`settings.intensityByType` は移行して消す（下記）。これで `selectedStrength` /
  `adjustPreviewStrength` / `showsAdvancedStrengthSlider` の「どちらから読むか」の分岐は強度について
  不要になり（常に per-key 記憶から導いた層の強度）、見た目の挙動は変わらない。
- **通知経路**: `IntensitySlider` は `Consumer2<FilterService, VisionFilterState>`（`intensity_slider.dart`
  25 行付近）なので、per-key 記憶の更新を `VisionFilterState` の通知として出せばスライダーは再描画される。
  一方 `FilterService` の listener にはトレイ（`tray_service.dart` の `_onSelectionChanged`）と
  `home_screen.dart` の `_persistFilterState` がある。これらを壊さないため、`FilterService.setIntensity`
  は記憶への書き込み（`VisionFilterState` が通知）に加えて、**従来どおり自身も `notifyListeners()`
  する**（中継ではなく、委譲先と自身の両方が通知する）。`Consumer` の差し替えは #124（`FilterService`
  削除）まで行わない。
- **`isColorQuickSelection`（全体に 1 つのフラグ）は、層ごとの属性 `origin`（クイック / advanced）に
  置き換える**。#117 で層の属性にし、`isColorQuickSelection` は「フォーカス中の層の origin」を返す
  互換 getter として残す（単一選択では従来と同じ値）。これで #117 までは挙動不変。UI 側の消費者
  （調整パネルの二重スライダー・一覧のハイライト）は #120、トレイの消費者は #121 で層単位の判定に
  移し、互換 getter と `origin` 自体は #124 で消す。#119（多選択 API）は層ごとの `origin` をそのまま使う。
- **旧状態 → v2 の移行規則**（`origin` と強度の出どころの食い違いを引き継がない）。入力は
  「v1 の保存 JSON（あってもなくてもよい）」と「`settings.intensityByType`（あってもなくてもよい）」
  の 2 つで、**移行のきっかけは `settings.intensityByType` の存在**（v1 JSON の有無とは独立）:
  - **背景**: 保存 JSON が無いと `VisionFilterStore.load()` は null を返す（`vision_filter_store.dart`
    50 行付近）。また `main.dart` の色覚シード（229 行付近）は store の bind より前に走り、その後に
    色覚クイックのスライダーだけを動かすと `settings.visionFilter` は作られず `intensityByType` だけが
    書かれる。この状態は実在するので、「v1 JSON の初回読み込み」に結びつけると強度記憶が推奨値に戻り、
    「挙動不変」が崩れる。
  - **きっかけと順序**: 起動時、色覚シードより**前**に、次の条件で 1 回だけ折り畳む。以下、v2 が「ある」
    とは**読める**（`VisionFilterStore.load()` が null でない。壊れた JSON・未知の版は null）ことを指し、
    読めない v2 は「無い」として扱う。
    (a) `settings.intensityByType` がある **かつ** 読める v2 が無い → 移行する。未知の版の v2 と
    `intensityByType` が両方あるときも、v2 は読めないので (a) と同じ扱い。
    (b) `settings.intensityByType` がある **かつ** 読める v2 がある → v2 が新しい（移行後の編集は v2 にだけ
    書かれる）ので、`intensityByType` のうち **v2 の `strengthByKey` に無い鍵だけ**を取り込んでから消す
    （移行の書き込みが失敗したまま状態が変わって v2 が書かれた場合の取りこぼしを防ぐ）。
    (c) どちらも無い → 何もしない。
  - **折り畳みの内容**（(a)）: per-key 記憶を、読める v1 JSON があればその `strengthById`（ただし下の
    規則 3 で除く鍵を除く）で初期化し、そのうえに `intensityByType` の各エントリを**上書き**で入れる。
    v1 JSON が無い・読めない・`isEmpty` なら `intensityByType` だけで初期化する。**色覚シードはこの記憶が
    できた後に走る**ので、シードされた層（初回起動の deuteranomaly や `settings.filterType`）の強度も
    `intensityByType` の値になる（層に強度を持たせないので、シード層も記憶を読むだけで済む）。
  - **置き場所**: 折り畳みは、現在 `main.dart` が `filterService.load()`（211 行付近）を呼んでいる
    位置（設定の読み込みの後、色覚シード（229 行付近）の前）に、`load()` の代わりとして置く。`load()` は
    `intensityByType` を読んで `FilterService` の内部 map に入れているが、#117 以降の `FilterService` は
    記憶を持たない薄い委譲なので、`load()` も `_persist` / `flush`（`filter_service.dart` の 163〜266 行付近）
    も `intensityByType` を**読み書きしない**ようにする（書き続けると、起動のたびに (b) の分岐になる）。
    折り畳みだけが生の `SharedPreferences` から `intensityByType` を読む。
  - **v2 の `layers`（v1 の選択を写せないとき）**: 起動順は `filterService.load()` → 色覚シード →
    `restoreAndBind`（`main.dart` の 211 → 229 → 240 行付近）で、`VisionFilterSnapshot.isEmpty` は
    `selectedId == null && strengthById.isEmpty && paramsById.isEmpty`（`vision_filter_snapshot.dart` 136 行付近）
    と強度も見るため、`strengthByKey` だけが入った v2 は「空でない」と判定されて `restore` が走る。
    `restore` は `selectedId == null` だと選択を全部外す（`vision_filter_state.dart` 353〜362 行付近）ので、
    `layers` が空の v2 を書くと、**シードした色覚層が起動のたびに消える**。現行（v1 まで）は、保存が無い・
    壊れている・未知の版（`load()` が null）・中身が空（`isEmpty`）のとき `restoreAndBind`（`vision_filter_store.dart`
    71 行付近）が復元を飛ばしてシード層が残る。これを保つため、**v1 JSON が無い・読めない・または
    `isEmpty` のとき**の v2 は、色覚シードと同じ選択を `layers` に書く: シードと同じ型（`settings.isFirstRun`
    なら deuteranomaly、そうでなければ `settings.filterType`）が none でなければ、その型に対応する
    `{id: catalogId(t), variantId: -omaly なら t、そうでなければ null, origin: クイック}` の 1 層（強度は
    `strengthByKey` に `intensityByType` から入れた値）。none なら `layers` は空で、`strengthByKey` だけを
    持つ v2 になる（復元は走るが、選択は元々無いので何も変わらない）。読めて空でない v1 JSON があるときは
    従来どおり v1 の選択（`selectedId` / `colorVisionType`）を v2 の層に写す。
  - **書き込みと冪等性**: **折り畳みの結果（per-key 記憶とシード層）は、書き込みの成否に関係なく
    メモリ上の `VisionFilterState` に入れる**。v2 への書き込み（`settings.visionFilter`）はそのメモリ状態から
    行い、書けたことを確認してから `settings.intensityByType` を消す。書けなかった場合は旧キーを消さず、
    メモリ状態が正として起動を続けるので、次に状態が変わったときの `_persist` が v2 を正しく書く（その時点
    から次回は (b) になり、(b) は v2 に無い鍵だけを取り込むので取りこぼさない）。状態が一度も変わらなければ
    次回も (a) になるだけで、結果は同じ。つまり「書けなければ次回再び (a)」は**保証せず**、どちらの経路でも
    強度記憶が失われないことを保証する。2 回目の起動は (c)（または上記の (b)）になり、`restoreAndBind` が
    v2 の層（deuteranomaly / `filterType`）を復元して、1 回目と同じ選択で起動する。v1 JSON は v2 で
    上書きされる。
  - **旧バージョンへ戻す場合**: 戻すことは非対応（本機能は未リリース）。戻した場合、旧版は v2 を捨てて
    推奨強度で起動し、旧版で動かした `intensityByType` は新版の再起動時に (b) の分岐で（v2 に無い鍵は
    取り込まれたうえで）消える。
  1. v1 に `colorVisionType = t`（≠ none）があれば、それは色覚クイック選択だった。層は
     `{id: catalogId(t), variantId: t が -omaly なら t、そうでなければ null, origin: クイック}`。
     強度は per-key 記憶の `t`（= `intensityByType[t]`、無ければ記憶に書かず推奨強度で導く）。
  2. `colorVisionType` が無ければ advanced / プリセット由来で、強度は従来どおり `strengthById[id]`
     （per-key 記憶の `id`）。
  3. **色覚クイックを経ずに書かれた色覚 id（`ColorVisionType` の 7 型の鍵）の advanced 側の強度は捨てる**
     （`strengthById` のうち protanopia / deuteranopia / tritanopia / achromatopsia の鍵は移行しない。
     色覚行は一覧でもトレイでも必ずクイック選択を通る — `selectColorVision` が唯一の橋 — ので、
     利用者が実際に見てきた強度は `intensityByType` 側にあり、advanced 側の値は #72 以前の保存値など
     実害の小さい残骸だから）。`tetrachromacy` は `ColorVisionType` に無く advanced 側だけなので
     `strengthById` を移行する。

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
- **2×2 比較（#84）**: スイッチは**色覚層があるときだけ**出す（現行の `canCompare =
  isColorVisionFilterId(selectedId)` と同じ条件を「層集合に色覚層がある」に広げるだけ。色覚層が 0 の
  ときはスイッチを出さず、2×2 は表示されない）。4 枚は「色覚より前の全層を 1 回だけ適用した結果」を
  共通の土台にして、その上に色覚 4 型を 1 枚ずつ適用する。色覚層だけのときは現行と同じ（土台 = 原画、
  #122）。4 枚に共通の強度は色覚層の強度。
- **書き出し（#80）**: `ExportCaption` を層ごとの行に拡張する（1 層は現行と同じ見た目）。受診喚起は
  「urgency は最大、escalation は段ごとにマージして重複を除く」を合成するヘルパで作る。実験的フィルタを
  含めば実験の注記を添え、「シミュレーション（近似）」は常に焼き込む（#121）。

### 7. 永続化は v2 に上げ、v1 は移行して読む

```text
{ version: 2,
  layers: [{ id, params, variantId?, origin }],             // 適用順。強度は持たない
  focusedId, presetId,
  strengthByKey: { <variantId ?? id>: number },              // 強度の唯一の置き場（決定 2）
  paramsById:    { <id>: {...} } }
```

- **層の強度は `strengthByKey[variantId ?? id]` から導く**（無ければ既定。決定 2）。`layers[]` に強度を
  持たせないので「食い違い」は起きない。v1 → v2 に限らず、記憶に無い鍵を推奨強度のままにしておく
  ことが、書き込み先を持たない規則 1 のフォールバックの扱い。
- 旧状態（v1 JSON と `settings.intensityByType`）の移行規則は「2. 強度の出どころを 1 つにする」の
  とおり。**きっかけは `settings.intensityByType` の存在で、v1 JSON が無くても起きる**（`load()` が null
  を返す経路）。`VisionFilterSnapshot.fromJson` は、現状「版が違えば丸ごと捨てて null」だが、
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
| 1 | #117 | `VisionFilterState` をレイヤー列に（挙動不変）+ 段の表（sensus 宣言順）+ 記憶鍵 `variantId ?? id` + `FilterService` 強度記憶の統合（`intensityByType` の移行。きっかけはそのキーの存在で、v1 JSON が無くても行う）+ `origin` の層属性化 + 永続化 v2（v1 移行）+ 通知経路の維持 | なし |
| 2 | #118 | bridge に Pipeline の複数ステップ CPU 適用 | なし（1 と並行可） |
| 3 | #119 | 多選択 API（排他・上限・プリセット置換）+ 合成プレビュー + 合成順 golden + 推奨サンプルの `focusedId` 追従 | 1, 2 |
| 4 | #120 | 統合一覧・調整パネル・HUD・キー操作の多選択 UI（`origin` の UI 消費者を層単位に） | 3 |
| 5 | #121 | トレイ・ホットキー・PNG 書き出し | 3（4 の後が望ましい） |
| 6 | #122 | 色覚 2×2 比較を層の土台つきに | 3, 4 |
| 7 | #123 | 全 30 フィルタの実測 + 層境界キャッシュ（計測ゲート。不要なら close） | 3, 4 |
| 8 | #124 | `ColorVisionType` / `FilterService` / `origin` / `isColorQuickSelection` の削除・`filterType` 統合 | 4, 5, 6 |
| 付帯 | #125 | 暫定の段表を sensus の標準順序 API に置き換え | sensus#191, #119 |

**実装状況**

- **第 1 段（#117）実装済み**: 層列化・段の表（`lib/models/vision_filter_stage.dart`、metamorphopsia は retina）・記憶鍵
  `variantId ?? id`・`FilterService` の強度記憶の統合（`VisionFilterStore.migrateLegacyStrengths`）・`origin` の層属性化・
  永続化 v2（v1 は読んで変換）を 1 PR で入れた。選択は常に 1 層のまま（複数層の API は #119）。決定どおりの実装で、
  実装時に確定した点は次のとおり。
  - 単一選択のままでは、色覚の quick 選択と advanced 選択が同じ色覚 id の強度の記憶を共有する（旧実装は別々だった）。
    また推奨強度は初回選択で記憶へ書かず、読むときに導出する。体験プリセットと「推奨値に戻す」は当該キーの記憶を消す。
  - `FilterService` は永続化（保存・デバウンス・flush・load）を持たず、`VisionFilterState` を必須引数に取る薄い窓になった。
  - 旧 v1 の -opia 4 種の強度は移行時に持ち越さず、旧 per-type 強度（`intensityByType`）を正とした。
  - 読める空の v2 は「未選択で終了」として復元し、設定側の色覚シードより優先する（空の v1 は従来どおり復元しない。
    -opia の強度だけを持つ v1 は変換後に見かけが空でも、旧実装どおり非空として復元する）。

- **第 2 段（#118）実装済み**: bridge に `apply_vision_pipeline_cpu_rgba8(steps, rgba8, w, h)` と
  `VisionStep{filter, strength}` を追加し、`CpuVisionRenderer.applyPipeline`（seam は `pipelineApplier`）が
  包む。呼び出し側の配線は #119。実装時に確定した点は次のとおり。
  - 並びの順にそのまま適用し、bridge は並べ替え・重複除去をしない（順序の決定は ue 側の段順）。
  - **空のステップ列は入力をそのまま返す**（エラーにしない）。バッファ長の検証は空でも行う。
  - 1 ステップの結果は単体適用とバイト一致し、2〜5 ステップは 1 つずつ単体適用した結果とバイト一致する
    （Rust テストで固定）。順序を入れ替えると結果が変わる組（ピクセル化とぼかし）で順序が結果に反映されることも固定した。

- **第 3 段（#119）実装済み**: `VisionFilterState` に `toggle` / `remove` / `setLayerStrength` / `setLayerParams` /
  `replaceWith` / `clear` と結果型 `VisionLayerResult` を追加し、`_previewCard` が層を段順で `BeforeAfterView.steps`
  経由の 1 回の合成（#118）へ渡すようにした。実装時に確定した点・当初の記述との差は次のとおり。
  - **層が 0〜1 のときは従来の単一フィルタの経路**（`afterImageRenderer`）のまま、2 層以上のときだけ
    `pipelineApplier` を使う（単一層の挙動を変えないため。1 層でも合成経路へ寄せるかは #120 以降の判断）。
  - 層の同一性は (id, variantId)。-opia と -omaly は同じカタログ id なので、片方を選んでいる状態で他方を
    `toggle` すると色覚グループの置き換えになる（同じ別名を再度 `toggle` すれば外れる）。
  - 上限での追加は no-op で `VisionLayerResult.blocked(layerLimit)` を返す。色覚の置き換え（既存の色覚層がある
    とき）と体験プリセットは上限に当たらない。強度 0 の層は合成から除くが上限には数える。
  - 体験プリセットは層集合がそのプリセット単体でなくなった時点で破棄し、集合が戻っても復元しない。
  - `select` / `selectColorVisionType` / `selectPreset` は `replaceWith` ベースの薄い窓として残した
    （`selectedId` はフォーカス層の id の別名。削除は #124）。推奨サンプル（#78）の 3 箇所は `focusedId` に変えた。
  - 相談喚起の統合 `mergeConsultInputs`（urgency は最大、escalation は段ごとに重複除去）と
    `consultInputForFilters` を追加した。UI・書き出しへの適用は #121。
  - 見出し・書き出し・2×2 比較の出し分け・トレイは #120〜#122 まで単一（フォーカス層）の意味のまま。
  - **既知の制約**: `toggle(..., origin: quick)` で色覚を足しても `FilterService` の色覚型・
    `settings.filterType`・色覚の強度スライダーは更新されない（同期は `selectColorVision` 経由のみ）。
    production から `toggle` を呼ぶのは #120 からなので、同期の持たせ方は #120 で決める。
  - `consultInputForFilters` は渡された層をすべて数える（強度 0 の層を含めるかは呼び出し側が
    渡す列で決まり、最終決定は #121）。
  - 合成のバイト一致は #118 の Rust テストが担う。#119 のテストは `pipelineApplier` をフェイクにして、
    渡る列（段順・強度・payload・強度 0 の除外）と状態遷移を固定した。

- **第 4 段（#120）実装済み**: 統合一覧・調整パネル・HUD・プレビュー周りを多選択 UI にした。実装時に確定した点は次のとおり。
  - **統合一覧**は行頭にチェック（色覚行はラジオ式の見た目）を持ち、チェック済みの行に適用順の番号バッジ
    （`LayerOrderBadge`）を出す。番号は段順で、クリック順には依存しない。色覚の見出しは「いずれか 1 つ」。
    色覚行は `toggleColorVision`（`color_vision_selection.dart`）で足す・外す・別の色覚へ置き換える。
    他の層は残る。
  - **上限（5）に達すると**、未選択の行はチェックを無効にし、理由を行内の文言で出す（色だけに頼らない）。
    既存の色覚層があるときの色覚行と体験プリセットの行は、置き換えになるので有効のまま。
  - **チップ帯**（`LayerChipStrip`）を Before / After の上に出す（**2 層以上のときだけ**。1 層のときは帯に情報が無く、従来の画面を変えないため出さない）。
    チップ = 番号 + 名前 + ✕。チップを押すとその層が調整中（`focusedId`）になる。調整中は塗り + 太い枠で
    形でも区別する。末尾の「すべて解除」は全層を外す。
  - **調整パネル**は 2 層以上で層ごとの節になる。調整中の層だけ展開し、ほかは「番号・名前・強度」の 1 行に畳む。
    強度スライダーは 1 本（旧 `IntensitySlider` と `showsAdvancedStrengthSlider` は廃止。強度の出どころが
    1 つになったため）で、`setLayerStrength` がその層を調整中にする。受診喚起・注意書き・出典は層の節ごと。
  - **プリセット**は層全体を置き換える。プリセットの行が強調されるのは、層集合がそのプリセット単体に
    ちょうど一致するときだけ。
  - **キー操作**: ↑↓ は行フォーカスの移動だけ（選択は変えない）。Space / Enter が足し引き。←→ は
    `focusedId` の層の強度。行からの ←→ が受け口へ出る挙動（#84）は変えていない。
    `CycleFilterIntent` は行にフォーカスがあるときか、操作部品にフォーカスが無いときだけ動く
    （`_RowAwareCycleAction`）。
  - **見出し・HUD**: 複数層の Before / After の見出しと HUD は「名前 + 名前 …（+N）」（強度は出さない。
    先頭 2 件を名前で出す）。HUD の相談喚起ダイアログは層ごとに名前の見出しを付けて並べる。
    Before / After の見出しは切らずに折り返し、横並びでは見出しの行を左右で高い方に揃える（画像の上端を
    ずらさない）。
  - 「静止フレーム」の注記（時間依存のフィルタは CPU プレビューでは固定フレームにしかならない）は、
    複数層のとき**どれか 1 層でも時間依存なら**出す（調整中の層だけでは判らないため、`BeforeAfterView.layerIds`
    で全層のカタログ id を渡して判定する）。
  - **暫定の 2 点を入れた**: 複数層のとき PNG 書き出しを無効にして理由を表示する（#121 で解除）。
    「2×2 で比較」は層集合がちょうど色覚 1 層のときだけ出す（#122 で解除）。
  - **`FilterService` との同期**（第 3 段の「既知の制約」）は `syncFilterServiceWithLayers` に決めた。
    UI の足し引き・プリセット選択（`selectExperiencePreset`）の後に、色覚クイック選択（origin が quick）の
    層があればその型、無ければ none へ `FilterService.currentFilter` を合わせる。トレイ・
    `settings.filterType` はこれを読む。プリセットは層の集合を置き換えるので、直前の色覚クイック選択は
    同期で none になり、`settings.filterType` に「いま無い色覚」は残らない。起動時の復元も、復元した層の
    集合全体から同じ関数で導く（フォーカス層だけは見ない）。
  - トレイのチェック式への拡張は #121 のまま。
  - **廃止した部品**: `IntensitySlider` と `showsAdvancedStrengthSlider`（強度の出どころが 1 つになったため、調整パネルの
    強度スライダー 1 本へ統合）。上の第 1〜3 段や `2025-11-17-state-management-provider.md` にある
    これらの記述は、当時の設計の記録としてそのまま残す。

- **第 5 段（#121）実装済み**: トレイ・ホットキー・PNG 書き出しを多層に対応させた。下の「#120〜#122 の間の暫定挙動」のうち、
  複数層の書き出し無効とトレイの単一選択の意味は本段で廃止した（2×2 比較の出し分けは #122 で解除する）。

  - **トレイ**: 「高度なフィルタ」をチェック式にした。クリックはメイン画面の一覧と同じ入口
    （`toggleColorVision` / `toggleFilterListEntry`）を通る。チェックは層の集合から導く（`origin` は見ない。
    トレイに `isColorQuickSelection` の消費者は残らず、層単位の判定に移った）。色覚 4 項目は排他（別の型で置き換え）、
    上限 5 層で未選択の項目は灰色（色覚の置き換え・プリセットは有効）。メニュー構造が変わらなければ送り直さない
    最適化は維持（チェック・灰色も構造に含む）。トレイ↔メイン画面の双方向同期と言語追従は従来どおり。
    暫定の「トレイは 1 フィルタだけのときチェック・クリックは全体置き換え」は廃止した。
  - **ホットキー**: 「フィルタ解除」は従来から全層を外す配線（`deactivateColorVision`）で、挙動は変えていない。main.dart の配線を
    関数（`hotkeyDeactivateFilters`）に切り出し、テストが同じ関数で全層解除と `FilterService` の none 復帰を固定する。
    ホットキーは足していない。
  - **PNG 書き出し**: 複数層の無効化を外した。画像に効いている層ごとの「症状名 + 強度」の行を適用順に並べ、
    受診喚起は `consultInputForFilters` の併合（最大の緊急度・escalation は段ごとに重複除去）を 1 つだけ焼き込み、
    どれか 1 層でも実験的なら注記を足し、「シミュレーション（近似）」は常に焼き込む。1 層のときは従来と同じ画素。
    ファイル名は 1 層なら従来どおり、複数層は症状 id を適用順に `-` 連結（強度の % は入れない）し、48 文字を超える分は
    `-plusN` で省く（ファイル名に使えない文字は `-` に正規化）。書き出しに使う層・強度・フィルタは、画像を描画した
    時点の控え（`ExportLayer`）から作る。
  - **併合した喚起の適用範囲**: 共有される 1 枚の画像である PNG 書き出しだけが併合結果を使う。調整パネルの層ごとの節と
    HUD のダイアログは、層ごとに読むもの（どの層の注意かを示す）なので、上の UI の決定どおり層ごとのままにした。
  - **強度 0 の層は、書き出しの症状行・受診喚起・実験的の注記・ファイル名に数えない**（決定）。強度 0 の層は層として残り
    上限にも数えるが、画素には何も足さない（プレビューの `pipelineSteps` も除く）。画像に写らない症状の行や喚起を焼き込むと、
    画像だけが共有されたとき実際の見え方と食い違うため。判定は、キャプションに出す整数パーセント（四捨五入）が 0 になるかで行う
    （0.004 のような値が「0%」の行として出ないように）。プレビューの `pipelineSteps` は厳密に 0 の層だけを除くので、0.5% 未満の層は
    ごくわずかに画素へ効くが、目に見える差ではない。UI 側（調整パネル・HUD）は層ごとのまま、強度 0 の層の注意も出す。
  - **例外（決定）**: 表示強度（整数パーセント）が 0 の層しかないとき（全層が強度 0・0.004 の層だけ・原画比較中）は、従来どおり
    フォーカス中の層の名前・強度・喚起でキャプションを作る（#121 以前の単一層と同じ出力を保つ。テストで固定）。
  - **廃止した暫定**: 書き出しの「複数層で無効 + 理由」（ARB `exportDisabledMultiLayer`）を削除した。
    「2×2 で比較」の出し分けは #122 で解除する。

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
