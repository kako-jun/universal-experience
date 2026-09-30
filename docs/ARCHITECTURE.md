# Architecture Design

> **現状**: 当初設計にあった system-wide フィルタ機構（`color_vision_filter`
> プラグイン／`ColorVisionFilter.apply` 等、「Platform Channel Layer」「Native
> Implementation Layer」「OS-Specific Filter Application」と呼んでいたもの）の
> 撤去経緯・判断根拠は、当該節を ADR に畳んだ
> `docs/adr/2026-05-31-sensus-core-consolidation.md` を参照。色覚アルゴリズムの
> 正本は sensus-core crate（Rust）に一元化し、ue は flutter_rust_bridge 経由で
> 消費する（`lib/src/rust/`、詳細は `docs/sensus-integration.md`）。プレビュー
> （静止画）は sensus の CPU `apply()`（`lib/rendering/cpu_vision_renderer.dart`
> の `CpuVisionRenderer`、#85）が担う。GPU シェーダ（`lib/rendering/
> shader_filter.dart`）は将来のライブ画面キャプチャ（#1/#3/#4）向けに残置して
> あるが、現状 production コードから呼ばれることはなく、GPU golden テスト
> （`test/vision_filter_golden_test.dart` 等）だけが検証のために使う。
> `FilterService` は色覚クイック選択の型だけを保持し、強度は `VisionFilterState` の
> 記憶を読み書きする（#117）。他アプリ含む全画面への適用は画面キャプチャ経路
> （#1/#3/#4）の実装後。
>
> **追補（現状）**: 以下も実装済み。多言語化（#18・`flutter_localizations` +
> ARB、ja/en、`lib/l10n/`）、sensus の複合体験 API の FRB 公開（#10・
> `experiences()` / `Experience` / `Urgency` / `HearingFilter`、ただし音声再生は
> 未実装）、体験プリセット集 UI（#19・`lib/ui/widgets/experience_presets.dart`）、
> フィルタ済み画像のメタ焼き込み PNG エクスポート（#43・
> `lib/services/export_service.dart`）、sensus 全 30 種の CPU 実描画（#85）と
> そのプレビューへの UI 結線（#60）。プレビューの描画対象は `VisionFilterState`
> の現在の選択を唯一の正本にする（色覚のクイック選択・advanced カタログ・体験
> プリセットのいずれで選んでも、最終的に `VisionFilterState` に書き込まれる）。
> プリセットのタップは `FilterService`（色覚のクイック選択の状態）を変更しない
> — `deactivate()` は呼ばない。選択中のプリセットは体験 id で保持するため、
> 同じ `vertigo` フィルタに写る 2 つのプリセット（メニエール病・迷路炎）が
> 同時に選択中と表示されることはない（#60）。色覚のクイック選択
> （`FilterBrowser` の色覚の行・トレイ）は `lib/services/color_vision_selection.dart` の
> `selectColorVision`/`deactivateColorVision` を唯一の入口とし、呼ばれた
> その場で `FilterService` と `VisionFilterState` の両方を更新する（listener
> によるミラーはしない）。これに伴い `VisionFilterState` も `filterService`
> と同じくトップレベル singleton（`main.dart` の `visionFilterState`）に昇格
> した。色覚チップの点灯・`IntensitySlider` の有効/無効・解除ボタンの有効/
> 無効は、すべて `VisionFilterState.isColorQuickSelection` から導く（advanced/
> プリセットを見ている間はいずれも無効）。ただし「Normal vision」
> （`ColorVisionType.none`）チップだけは `VisionFilterState.selectedId == null`
> （＝何も選択されていない）で点灯を判定する — `isColorQuickSelection` は
> none を「選択中」扱いにしないため。**advanced/プリセットを選択中に
> 「Normal vision」を押すと、それらの選択もすべて消える**（`selectColorVisionType`
> は既存の選択を常に上書きするため）。これは意図した挙動で、「Normal vision」
> は色覚セクション内の一操作ではなく、プレビュー全体を原画に戻す操作として
> 扱う。advanced カタログの strength スライダー（`FilterParamPanel`）も、
> 色覚クイック選択が起点のときは出さない（動かしても実際の強度は #57 の
> タイプ別記憶が決めるため）。-omaly（protanomaly 等）は
> `VisionFilterState.colorVisionType` に実際の型を保持し、見出し・export の
> caption・ファイル名で正しい -omaly の名前を出す（#60。カタログは色覚を
> 5 種しか持たず、-omaly は base の -opia と同じカタログ id に写るため、id
> だけでは区別できない）。トレイのメニューも `filterService`/
> `visionFilterState` の変化を listener で受けて `refresh()` する（#60。
> ウィンドウ内 UI での選択もトレイのチェックマークに反映されるようにする
> ため。listener は `TrayService.dispose()` で外す）。
>
> **追補（#76 / #77）**: 受診喚起の緊急度（`Urgency`）・条件付きの上振れ
> （`urgency_escalation()`）・推奨強度（`recommended_strength()`）は
> sensus-core 0.6.1 が `Filter`/`HearingFilter` に追加した API を唯一の正本
> にする。ue 独自の段階分類（旧 `vision_filter_catalog.dart` の
> `VisionFilterUrgency`）は撤去した。喚起の解決（urgency + escalation →
> 喚起文・escalation の訳・免責文）は `lib/l10n/l10n_extensions.dart` の
> `resolveConsultNotice` に一本化し、表示は `lib/ui/widgets/
> consult_notice_block.dart` の `ConsultNoticeBlock` が担う。`FilterParamPanel`・
> `AdjustPanel` の体験プリセット選択時・PNG export（`ExportCaption`）の 3 か所が
> これを共有する（3 か所がそれぞれ解決すると
> 食い違いうるため）。段階名は出さず、喚起文だけを
> `ColorScheme` ロール（`tertiaryContainer`/`errorContainer`/
> `surfaceContainerHighest`）で塗った専用ブロックに表示し、emergency は
> earlyConsultation より大きい文字サイズにする。escalation は emergency/
> earlyConsultation で見出しを分ける（vision フィルタは全て earlyConsultation
> だが、`HearingFilter` の聴力低下系は emergency も持つため、聴覚側 UI（#20 で聴覚モードを足すか判断、FRB 公開は #10）に
> 備える）。末尾には「医学的な診断ではない・医療監修を受けたものではない」旨と
> sensus の Medical notes への参照を必ず添える。喚起文からは
> 診療科名を外した（めまい系フィルタは眼科の話ではないため）。
> `VisionFilterState` はフィルタ id ごとに強度・パラメータを記憶し
> （`_strengthById`/`_paramsById`）、初めて選ぶフィルタは推奨強度から始まる。
> 体験プリセットの強度・パラメータも #60 の「強制的に 1.0」から「常に推奨値・
> 常に既定パラメータ」へ置き換えた。既定パラメータの組み立て
> （`_defaultParamsFor`）と推奨強度の解決（`_recommendedStrength`）は
> `_selectInternal`/`resetToRecommended`/`selectPreset` が共有する。
> `#[frb(sync)]` 関数は native lib を要求しプレーンな
> `flutter test` から呼べないため、`lib/services/vision_filter_metadata.dart`
> の provider seam（`experiencesProvider` 等の既存 seam と異なり、複数
> ファイルから正規に production 利用されるため `@visibleForTesting` は
> 付けない）を経由し、widget/unit test は `test/support/
> vision_filter_metadata_fixture.dart` のフィクスチャに差し替える。実ブリッジ
> との一致・escalation 条件文の訳漏れ検知は
> `integration_test/vision_filter_urgency_parity_test.dart` が検証する。
>
> escalation は UI（`ConsultNoticeBlock`）だけでなく PNG
> （`ExportCaption.escalationGroups`）でも emergency/earlyConsultation の
> 見出しで段を分ける。PNG 用の短い免責文は「診断ではない旨」と「根拠」
> の両方を 1 行に含める。体験プリセットの各カードは喚起文・escalation
> は出すが免責文・根拠 URL は出さず、「体験プリセット」セクション末尾に
> `ConsultDisclaimerFooter` を 1 回だけ表示する。emergency の喚起文は
> `titleMedium` ではなく `bodyLarge`（プリセットカードのタイトルと衝突しない
> よう）。根拠 URL には Medical notes 節そのものを指すアンカーを付けた。
> 詳細は `docs/sensus-integration.md` §10。
>
> **追補（#66）**: sensus の API 契約上ユーザーに知らせるべき挙動（#51 の契約注記）のうち、
> UI に出すものは `lib/models/vision_filter_contract_notes.dart`（定義: フィルタ id →
> 強度の上限付近の注意の閾値）と `lib/ui/widgets/strength_caution.dart`（閾値位置の印
> `StrengthCautionTrackShape` と注記 `StrengthCautionNote`）が担い、`FilterParamPanel` の
> 強度スライダが使う。sensus-core 0.6.1 のメタデータ API には該当項目が無いので、
> 対象・閾値は ue が持ち、文言は ARB（ja/en 対称）。受診喚起（`ConsultNoticeBlock`）の
> 位置・表現は変えない。処理状況は `docs/sensus-integration.md` §11。

## ルーペ窓挙動 (#14)

ルーペ窓のウィンドウ設定の責務。実装は `lib/services/loupe_window_controller.dart`
(window_manager ラッパ + 純粋ロジック `LoupeWindowPolicy`) と `lib/main.dart` の配線。
画面キャプチャ (#3/#4/#5)・ライブ適用・描画 (#1)・フィルタ UI (#16)・トレイ (#15) は本節のスコープ外。

対象アプリ指定モード（ルーペ窓の自動配置モード）の設計判断・要検証事項・OS ごとの
提供可否は `docs/adr/2026-09-26-loupe-as-single-render-unit.md` 参照。

### 最小サイズ

- **320x240 (QVGA, 4:3)**。従来の 600x400 から引き下げた。
- 根拠: ルーペは「画面の一部に小さくかざす」使い方が主眼。320px あれば
  色覚/視野/コントラストのフィルタ差は判別できる下限。これ以下だと枠操作
  領域が窮屈で実用性を失う。4:3 は覗き窓の直感的比率 (アスペクト強制ではなく、
  リサイズで自由に変えられる)。
- **単位は論理ピクセル**。HiDPI (DPR 2x) のモニタでは実効の物理ピクセルは
  640x480 相当の見え方になる。物理解像度に応じた見え方の調整 (DPR 換算) は
  #5 DPR スコープで扱う。

### 状態遷移と枠ポリシー

状態は enum `LoupeWindowMode { normal, maximized, fullscreen }`。

| モード | 縁(フレーム/タイトルバー) | 用途 |
|---|---|---|
| normal | あり | 通常。掴んで移動・リサイズ |
| maximized | **あり** | 画面いっぱいでも縁を残す |
| fullscreen | なし | 没入。画面全域をフィルタ |

- 最大化で **縁を残す**のが要点。ルーペは「枠の向こうにフィルタ済みデスクトップ」
  が見える体験なので、最大化で縁が消えると「どこが覗き窓か」が破綻する。
  全画面だけは没入用に縁を消す。
- 遷移は `LoupeWindowPolicy.resolveMode` (純粋関数) で解決。toggle 系は
  同じモード再要求で normal に戻る。実 I/O は window_manager の
  `maximize`/`unmaximize`/`setFullScreen` + `setTitleBarStyle` で反映。
- **順序依存の注意 (実機確認)**: 実装は `setFullScreen` を当てた後に
  `setTitleBarStyle` を呼ぶ順序。プラットフォームによっては全画面遷移と
  タイトルバースタイル変更の順序差で「全画面なのにタイトルバーが残る/枠が
  二重に出る」等が起きうる。この順序 (fullscreen → titleBar) が破綻しないかは
  **実機目視で確認が必要（ライブキャプチャ #1 の実装後）**。

### リサイズ追従

`WindowListener.onWindowResize` でサイズを取得し state 更新 -> `notifyListeners()`
（`LoupeWindowController` は `ChangeNotifier`、#63）で UI に伝える (中身が
ウィンドウに貼り付く責務)。

### 透過・最前面・クリックスルー (既定方針、#63 で更新)

- **透明背景**: 起動モード (#63、後述の「アプリモード切替」参照) に連動する。
  設定モードは常に不透明 (フィルタ選択 UI を見やすくするため)、ルーペモードは
  透明 (枠の外は完全透過、枠の中だけ描画。VIP-Sim / Sim Daltonism 型, #6)。
  `LoupeWindowPolicy.transparentForMode(mode)` が単一の判定。起動時の
  `WindowOptions.backgroundColor` はこれで決め、以降は
  `LoupeWindowController.setAppMode()` が `windowManager.setBackgroundColor()`
  で反映する。
- **最前面**: **既定 OFF**、切替式 (#63 で ON→OFF に変更)。起動は設定モードから
  始まるため、まずフィルタ選択 UI を操作したい。常に最前面だと設定 UI が
  他アプリの上に居座って操作しづらいため、実際にかざして見たいときにユーザーが
  `LoupeWindowController.setAlwaysOnTop()` で ON にする運用にした。
- **クリックスルー**: 既定 **OFF**、切替式。起動直後は窓を掴んで移動・リサイズ
  したいのでイベントを受け取り、下のアプリを操作したいときユーザーが ON する。
  実装は `setIgnoreMouseEvents(true, forward: true)`。**ON にする操作は常に許可
  する (#63)**: クリックスルーはいつでも ON にしてよい（2 つの復帰経路が常に
  あるため）。トレイ・ホットキーというネイティブプラグイン依存の手段は「登録・
  作成成功」が実際にユーザーが復帰操作できることを保証しないため、アプリ自身が
  保証できる 2 つの復帰経路を常に用意している: (a) クリックスルー ON のまま
  ウィンドウがフォーカスを得たら「解除の予約」をし、実際に最初のキー入力が
  あった時点で解除する（`LoupeWindowController.onWindowFocus` /
  `releaseClickThroughOnFirstKeyPress`）、(b) アプリ内で Esc を押したら即座に
  解除する（`ReleaseClickThroughIntent`、`app_shortcuts.dart`）。トレイ・
  ホットキーはこの上に乗る追加の便利な手段という位置づけで、`WindowModePanel`
  はクリックスルーのスイッチ横に利用可能な復帰手段をすべて併記する。詳細は
  下記「クリックスルーの復帰経路」節。
- **起動モード・最前面・クリックスルーは独立して永続化する (#63)**:
  `LoupeWindowController` 自身が `SharedPreferences`
  (`loupeWindow.appMode` / `loupeWindow.alwaysOnTop` / `loupeWindow.clickThrough`)
  に即時書き込みする (`VisionFilterStore` のようなデバウンスは不要な、頻度の低い
  トグルのため)。`main()` は `windowManager.ensureInitialized()`
  の直後、`WindowOptions` を組み立てる前に `loupeWindow.load()` を呼んで復元し、
  `loupeWindow.initialize()` が実際の window_manager へ反映する。
- **クリックスルーの `forward` はプラットフォーム差あり**: `forward` 引数は
  **macOS 専用**で、Linux/Windows では window_manager 側で無視される。Linux では
  「自ウィンドウがイベントを無視する」までは効くが、「下のアプリへ転送する」挙動は
  forward では保証されない (コンポジタ/OS 依存)。クリックスルー時に下のアプリを
  実際に操作できるかは **Linux 実機での確認が必要（ライブキャプチャ #1 の実装後）**。
- フレームレス/クリックスルー forward 引数はプラットフォーム差・未対応があるため、
  全 window_manager I/O は try/catch + ログで握り、未対応でも落とさない。

### タスクトレイ (#15)

デスクトップ版はタスクトレイ (通知領域 / メニューバー) に常駐する。実装は
`lib/services/tray_service.dart` (tray_manager 0.2.4 ラッパ) と `lib/main.dart`
の配線から成る。

### 構成 (純粋ロジックと副作用の分離)

`tray_service.dart` は 2 層に分かれている。

- **純粋ロジック層** (`TrayMenuKind` / `TrayMenuEntry` /
  `quickColorVisionFilters()` / `buildTrayMenuSpec()` /
  `buildAdvancedFiltersSubmenu()` / `trayToggleLabel()` /
  `resolveCloseAction()`) — 「トレイメニューに何を出すか」をデータとして表現する。
  tray_manager に一切依存しないため、ウィンドウシステム無しで単体テストできる
  (`test/tray_service_test.dart`、`test/tray_advanced_filters_test.dart`)。
  文言の値オブジェクト `TrayMenuLabels` と `quickColorVisionFilters()` は
  `lib/services/tray_menu_labels.dart` にあり（`tray_service.dart` が再 export）、
  `l10n_extensions.dart` ⇄ `filter_list_selection.dart` ⇄ `tray_service.dart` の
  import 循環を避けている。
- **`TrayService`** — tray_manager を叩く副作用層。上記スペックを実際の
  `Menu` / `MenuItem` に変換し、クリックを `FilterService` (#14) と、main.dart
  から注入されるウィンドウ表示/非表示コールバックに橋渡しする。

### 言語の切替とトレイの文言 (#82)

AppBar の言語ダイアログ (`lib/ui/widgets/language_dialog.dart`) が
`SettingsService.setLocale` を呼ぶ。使う言語は `lib/l10n/locale_resolution.dart` の
`resolveSupportedLocale`（選んだ言語 → OS の言語の一覧 → 英語）が唯一の入口。
OS の言語は Flutter 標準の `basicLocaleListResolution` に一覧ごと渡して選ぶ
（`[fr, ja]` で fr 未対応なら ja になる）。`main.dart` の `MaterialApp` は、
言語を選んでいれば `locale` にこの関数の結果を、「自動」なら
`localeListResolutionCallback` からこの関数を呼ぶ。起動時のエラー画面とトレイも
同じ関数なので、画面とトレイの言語がずれない。保存された言語コードが
`supportedLocales` に無いときは `SettingsService.load` が捨てて「自動」に戻す。

トレイは `BuildContext` を持たないため、`TrayService` はコンストラクタで文言
(`TrayMenuLabels` とツールチップ) を受け取り、`updateLocalization()` で差し替える
(初期化済みならツールチップとメニューを作り直す)。`lib/services/tray_locale_sync.dart` の
`TrayLocaleSync` が `SettingsService` の変更と `WidgetsBindingObserver.didChangeLocales`
（「自動」のときの OS 言語変更）を見て、**解決後の言語が変わったときだけ**
`main()` から渡された `apply` を呼ぶ。`test/tray_locale_sync_test.dart` と
`test/tray_service_test.dart` の `updateLocalization` がこれを検証する。言語の追加手順は
`docs/ADDING_A_LANGUAGE.md`。

メインウィンドウ自体がルーペ窓 (#14)。`LoupeWindowController` は枠/モード/透過の
責務を持つが show/hide は持たないため、トレイの「ルーペ窓を表示/隠す」は
main.dart が `windowManager.show()` / `hide()` を `onShowLoupe` / `onHideLoupe`
として `TrayService` に注入して実現する。

### メニュー構成

上から順に:

1. **ルーペ窓を表示 / 隠す** — トグル (注入された `windowManager.show()` /
   `hide()` を呼ぶ。ラベルは現在の表示状態で切替)
2. (区切り線)
3. **起動モード切替** — `LoupeWindowController.setAppMode()`（settings/loupe をトグル、#63）
4. **最前面固定** — `LoupeWindowController.setAlwaysOnTop()`（#63）
5. **クリックスルー** — `LoupeWindowController.setClickThrough()`（#63。settings
   モード中の ON 拒否は `setClickThrough` 自身のガードに任せる。クリックスルーは
   いつでも ON にしてよい（2 つの復帰経路が常にあるため）ので可否チェックは不要）
6. (区切り線)
7. **即切替フィルタ** (`quickColorVisionFilters()`) — よく使う色覚シミュレーションを
   直接適用: Protanopia / Deuteranopia / Tritanopia / Achromatopsia。
   `selectColorVision`（`FilterService.applyFilter()` と `VisionFilterState` を
   同時に更新する色覚クイック選択の入口）を通り、選択中のものにチェックが付く。
   チェックは項番 8 と同じ選択行から決めるため、色覚の base 型（Protanopia 等）を
   「高度なフィルタ」側から選んでも同名のトップレベル項目に点灯する（統合一覧と同じ）。
   トップレベルは短く保つため代表のみで、全フィルタは次項の「高度なフィルタ」
   サブメニューから選べる (#65)。
8. **高度なフィルタ** (#65) — カテゴリ別の入れ子サブメニュー（7 カテゴリ）。統合
   フィルタ一覧 `kFilterListEntries`（色覚 7 型 + advanced 30 = 33 行、#72）の行を
   すべて並べ、選ぶとウィンドウ内一覧と同じ入口 `applyFilterListEntry`
   （色覚の行は `selectColorVision`、それ以外は `VisionFilterState.select`）を通る。
   チェックは `selectedFilterListEntry(visionFilterState)` で決めるため、
   ウィンドウ内 UI で選んだものもトレイに反映される（体験プリセット選択中は
   トレイに何もチェックを付けない。トレイにプリセットは出さず、ウィンドウ内一覧も
   一覧の行を点灯させないため）。ラベルは `TrayMenuLabels` の
   `advancedFilters` / `categoryLabels` / `catalogNames` / `filterLabels` で、
   ARB（ja/en）から解決し `updateLocalization` で言語変更に追従する
9. **フィルタを解除** — `deactivateColorVision`（色覚・advanced・プリセットを
   まとめて未選択へ戻す）。何も選ばれていないときにチェックが付く
10. (区切り線)
11. **設定を開く…** — フィルタ選択 UI はメインウィンドウ内にあるため
   `windowManager.show()` + `focus()` でウィンドウを表示する
12. (区切り線)
13. **終了** — 先頭で `VisionFilterStore.flush()`（#65・#117、フィルタ選択と
   強度の保留書き込みを取りこぼさない）した上で、トレイを破棄し
   `setPreventClose(false)` の上で `windowManager.destroy()`

`TrayService._rebuildMenu` は、組み立てたメニュー構造が直前にネイティブへ送った
ものと等しければ送り直さない（スライダーのドラッグ中に `VisionFilterState` が
連続通知されても、33 行 + カテゴリのメニューを作り直し続けないため）。ただし
メニュー項目のクリック後は、ネイティブ側が先にチェック表示を反転させる環境でも
見た目が食い違わないよう、必ず送り直す。フィルタ切替のクリックは
`LoupeWindowController`（クリックスルー・最前面・モード、#63）に一切触れない。

### ウィンドウクローズ・ポリシー

**トレイが使える環境では、ウィンドウを閉じても終了せず、トレイに最小化される
(close = トレイ常駐)。** 明示的な終了はトレイの "終了" のみ。

`windowManager.setPreventClose(true)` はトレイの有無に関わらず常に掛ける
(`main.dart` `_setUpTray`)。`onWindowClose` の中で `resolveCloseAction()`
(純粋関数、テスト済み) の結果を見て分岐する:

- **トレイが使える環境 (`hideToTray`)** — `windowManager.hide()` するだけ。
- **トレイ初期化が失敗した環境 (`exitApp`)** — トレイから復帰できずアプリが
  行方不明になるため close = 終了にフォールバックする。ただしフィルタ選択・強度の
  デバウンス永続化 (#65・#117) を取りこぼさないよう、`VisionFilterStore.flush()` →
  `setPreventClose(false)` → `windowManager.destroy()` の順で終了する
  (`flush()` は `try`、残り 2 つは `finally` で必ず実行)。

トレイの "終了" (`onQuit`) も同じ理由で先頭に `flush()` を置く。さらに
macOS の Cmd+Q やログアウトなど、window_manager のクローズイベントを経由しない
終了経路もあるため、`main()` で `AppLifecycleListener.onExitRequested` にも
同じ `flush()` を仕込んでいる（トレイ・ウィンドウクローズ経由の flush はそのまま
残る、二重の安全網）。

### プラットフォーム差

- **Windows / macOS**: トレイは常に利用可能。PNG アイコンが動作する
  (Windows は内部で 16px へリサイズ)。
- **Linux**: 単一のトレイ標準が無い。KDE/XFCE は StatusNotifierItem を標準提供
  するが、**GNOME は AppIndicator/KStatusNotifierItem シェル拡張が必要**で、無いと
  アイコンが黙って出ない。検出が困難なため tray_manager 呼び出しは全て try/catch
  で包み、失敗してもアプリは落ちずウィンドウのみで使える。
- **Android/iOS**: トレイ概念が無いためトレイ設定はスキップ
  (`TrayService.isTraySupportedPlatform` が false)。Android の常駐は Foreground
  Service (#4) でありスコープ外。

### アイコン

トレイアイコンは `assets/tray/tray_icon.png` (64x64 RGBA、青地に同心円の
"eye/loupe" マーク。ImageMagick も Pillow も無い環境のため Python stdlib の
`zlib` だけで生成したプレースホルダ) を `pubspec.yaml` の `flutter > assets` に
登録した。ビルド時 `data/flutter_assets/assets/tray/tray_icon.png` にバンドル
され、`trayManager.setIcon('assets/tray/tray_icon.png')` がこのバンドル相対パスを
解決する。**より洗練したアイコン (特に Windows 用 `.ico`) は要追加。**

### 実機目視について (正直な明記)

この開発環境 (Wayland + grim 制約、GNOME はトレイ拡張要) では
**トレイ常駐・メニュー操作の目視確認ができない**。検証は静的解析・単体テスト・
Linux debug ビルド成功で代替している:

- `flutter analyze`: No issues found! (0 issue)
- `flutter test`: 全 117 件緑 (うちトレイ純粋ロジック 15 件)。
- `flutter build linux --debug`: 成功。アイコンがバンドルに含まれることも確認。

トレイアイコンが実際に表示されるか・メニュークリックの挙動は、トレイ対応環境
(KDE 等、または GNOME + AppIndicator 拡張) での実機確認が別途必要。

## アプリモード切替 (#63、実装済み)

起動直後は「設定モード (settings)」から始まる。通常ウィンドウ・不透明で、
まずフィルタ選択 UI を操作しやすくする。実際にかざして見たいときはユーザーが
「ルーペモード (loupe)」へ切り替える。

| モード | 透明 | ウィンドウ | 用途 |
|---|---|---|---|
| 設定モード (settings) | OFF (不透明) | 通常 | フィルタ選択など UI 操作。**起動既定** |
| ルーペモード (loupe) | ON | 透明 | 実際に画面へかざして見る |

最前面固定・クリックスルーはモードとは**独立したトグル**として別に持つ
（モード切り替えはこれらを自動で変更しない。ただしルーペ→設定モードへの
切り替え時だけは、クリックスルーが ON のままだと設定 UI が操作不能になるため
`LoupeWindowController.setAppMode()` が強制的に OFF へ戻す）。

実装は `LoupeWindowController.appMode` / `AppMode` enum / `setAppMode()`
（`lib/services/loupe_window_controller.dart`）と、設定画面の
`WindowModePanel`（`lib/ui/widgets/window_mode_panel.dart`、`SegmentedButton<AppMode>`）、
およびタスクトレイ（`lib/services/tray_service.dart`、下記「メニュー構成」節）の
3 経路。起動モード・最前面・クリックスルーはいずれも `LoupeWindowController` 自身が
`SharedPreferences` へ即時永続化し、次回起動時に復元する（詳細は上記
「透過・最前面・クリックスルー」節）。永続化されたクリックスルーの起動時復元は
`LoupeWindowController.restorePersistedClickThrough()` が担う。クリックスルーは
いつでも ON にしてよい（2 つの復帰経路が常にあるため）ので復帰手段の可用性を
待つ必要はもう無いが、`main()` は診断ログのタイミングを揃えるため、引き続き
トレイ/ホットキーの初期化が終わったあとにこれを呼ぶ構成のままにしている。

## フィルタ選択の永続化 (#65)

`VisionFilterState`（プレビューの選択の唯一の正本）を再起動をまたいで残す。

- **保存するもの**: 重ねている層の列（各層はカタログ id・payload・別名 `variantId`
  （-omaly。quick 層だけが持つ）・起源 `origin`（quick / advanced））・フォーカス中の層の id・体験プリセット
  id・強度の記憶（キー `variantId ?? id` ごと）・カタログ id ごとの payload の記憶
  （#117。層自身は強度を持たない）。原画比較（bypass）など一時的な状態は保存しない。
  JSON は `version`（現在 2）つきで、seed（u64）は double を経由して精度が落ちないよう
  10 進文字列で持つ。版 1（選択 1 つ + フィルタ id ごとの強度）は読めて、v2 へ変換して
  復元する（次に状態が変わったとき v2 で書かれる）。
- **定義と状態を分ける**: 保存するのは状態だけで、min/max/default/options は
  カタログ（`vision_filter_catalog.dart`）が正本のまま。**読み込み時に**
  `VisionFilterSnapshot.fromJson` / `sanitizeVisionParams` がカタログに照らして補正する
  — 未知のフィルタ id・定義に無いパラメータは捨て、範囲外は min/max に丸め、
  型違い・NaN・未知の選択肢・範囲外の seed は既定値に戻し、欠けたパラメータは既定値で
  埋める。版 1（旧形式）は v2 の形へ変換して復元する。未知の版（新しすぎる・古すぎる・
  版なし）・Map でない値・JSON が壊れているときだけ丸ごと捨てて既定で起動する。
  したがって sensus 側でフィルタ id やパラメータが変わっても起動は止まらない
  （`test/vision_filter_snapshot_test.dart` が固定）。
- **復元の順序（`buildRootApp`）**: `VisionFilterStore.migrateLegacyStrengths`（旧
  `settings.intensityByType` の取り込み、下記）→ 設定の `filterType` による色覚シード（初回
  起動は deuteranomaly）→ `VisionFilterStore.restoreAndBind`。復元できる保存値があれば
  それが勝つ（「解除して終了」した場合、設定側に前回の色覚が残っていても
  未選択で始まる。読める v2 は層が空でも復元する）。保存値が無い・壊れている・空の版 1
  （選択も強度も payload も持たない。-opia の強度だけを持つ版 1 は、変換で強度を落としても
  旧実装どおり空とみなさず復元する）のときは state に触れず、色覚シードのまま。色覚クイック選択が復元されたときは `FilterService.applyFilter` も呼び、
  トレイとウィンドウ内 UI が同じ `FilterService` を見るようにする。advanced 選択中の
  `FilterService` は従来どおり古いまま（消費側は `isColorQuickSelection` で判定する）。
- **体験プリセット**: 保存された体験 id が今の体験一覧にあり、かつそのフィルタが
  保存されたカタログ id と一致するときだけプリセット選択として戻す。一覧から消えて
  いれば advanced の選択として戻す（`isValidExperiencePreset`。widget を経由せず
  main から使えるよう `lib/services/experience_source.dart` に置く）。
- **書き込み**: 変更は 300ms デバウンスで書き、JSON が直前と同じ変化（原画比較の切替など）は書かない。
  終了経路（トレイの終了・`onExitRequested`・ウィンドウクローズ）で `flush()` する。
  書き込み失敗は握りつぶす（次回は既定値で起動するだけ）。`flush()` は、タイマー発火後
  にすでに走っている書き込みの完了も待つ。
- **復元の失敗**: 復元の途中（推奨強度の算出・体験一覧の取得など sensus 呼び出し）で
  例外が出ても起動は止めない。`VisionFilterState.restore` は失敗時に呼び出し前の
  状態へ巻き戻して rethrow し、`VisionFilterStore.restoreAndBind` が握って、色覚シード
  のまま以後の保存だけ始める。
- **旧 per-type 強度の取り込み（#117）**: かつて `FilterService` が
  `settings.intensityByType`（`ColorVisionType.name` → 0..1）に持っていた強度は、
  `migrateLegacyStrengths(seedType:)` が**そのキーの存在**を合図に一度だけ v2 の強度の記憶へ
  取り込む（v1 JSON が無くても行う）。(a) 読める v2 が無い（無い・版 1・壊れている・未知の版）:
  版 1 の強度（-opia 4 種を除く。旧 per-type 強度のほうが新しい正本のため）に、旧 per-type
  強度（有効な色覚型名だけ・0..1 に丸める）を重ねて記憶にし、層は版 1 のもの（選択が無く
  空なら `seedType` の quick 層、none なら層なし）にして v2 を書く。(b) 読める v2 がある:
  v2 に無いキーだけ旧強度で補う。(c) 旧キーが無い: 何もしない。旧キーは**書き込みに成功
  してから**消し、失敗したら残して次回起動でもう一度取り込む（取り込み結果は
  `restoreAndBind(snapshot:)` 経由で書き込み失敗時もメモリへ入る）。さらに古い単一キー
  `settings.intensity`（#57 で撤去）は値を見ずに消す。
- **テスト**: 往復・補正・フォールバック・層の不変条件・v1 → v2 変換の純粋テスト
  （`test/vision_filter_snapshot_test.dart`・`test/vision_filter_store_test.dart`）、取り込みの
  (a)(b)(c) と失敗系（JSON 欠落・破損・空・書き込み失敗）（同 store テスト）、`buildRootApp` を
  2 回起動して復元・取り込みを確かめる実アプリ経路のテスト
  （`test/vision_filter_persistence_app_test.dart`）。

## 状態モデルの統一と多症状の同時適用 (#32 / #41、第 1 段 #117 まで実装)

> **実装状況**: 第 1 段（#117）で、`VisionFilterState` がレイヤー列（`lib/services/vision_layer.dart`）と
> 段の表（`lib/models/vision_filter_stage.dart`）を持ち、強度の記憶が `variantId ?? id` キーの 1 つに
> 統一され、永続化が v2 になった。**選択はまだ常に 1 層**（`select` / `selectColorVisionType` /
> `selectPreset` は「全部外して 1 つ足す」）で、複数層を作る API・合成描画は第 3 段（#119）。
> `FilterService` は色覚クイック選択の型を持ち、強度は `VisionFilterState` の記憶へ委譲する薄い窓に
> なった（`ColorVisionType` / `FilterService` の削除は最終段 #124）。下の「現状は状態が 2 系統」
> 以降は設計時点の記述。

現状は状態が 2 系統ある（`VisionFilterState` = カタログ 30 フィルタ、`FilterService` =
`ColorVisionType` 8 値 = none + 7 型）うえ、選択は常に 1 つだけ。両方を解く方針として、**選択の単位を
「カタログ id ごとに 1 つのレイヤー」の順序つき列に統一**し、単一選択を 1 要素の多選択として扱う。
要点:

- 層は最大 5、色覚カテゴリは排他（同時に 1 つ）。体験プリセットは層全体を置き換える。
- 適用順は段（motion → optics → media → retina → visualField → perception → colorVision）で
  決め、選択した順には依存させない。結果は「層の集合」の関数になる。
- プレビューは CPU `apply()`（1024px）のまま、sensus の `Pipeline` を bridge 経由で 1 回のジョブとして
  適用する（ue に合成ロジックを持たない）。ライブ（GPU）経路は同じ順序の N パス多段にする。
- 強度の出どころは 1 つにする: 記憶の鍵を `variantId ?? id` にして `FilterService` の強度記憶
  （`settings.intensityByType`）を第 1 段で `VisionFilterState` に統合し、`isColorQuickSelection` は
  層ごとの属性に置き換える。層は強度を持たず、強度は per-key 記憶から読むときに導く。
- 永続 JSON は v2（`layers` 配列）に上げ、旧状態は色覚クイック選択の強度の出どころを含めて移行して読む。
  移行のきっかけは `settings.intensityByType` の存在で、v1 JSON が無くても行う（色覚シードより前）。
  `ColorVisionType` / `FilterService` の削除は最終段。

段階ごとの実装は Issue #117〜#125、判断・代替案・根拠は
`docs/adr/2026-09-30-multi-select-filter-state-model.md`。実装済みの範囲は上の実装状況と、
「フィルタ選択の永続化 (#65)」・下の各サービスの記述が現行の挙動。

## グローバルホットキー (#63)

デスクトップ全体で効くグローバルホットキーを 4 種類提供する。実装は
`hotkey_manager` パッケージ経由（`lib/services/hotkey_service.dart` /
`lib/services/hotkey_actions.dart`）。

| アクション | 既定キー | 効果 |
|---|---|---|
| `toggleClickThrough` | Ctrl+Alt+Shift+C | クリックスルーの ON/OFF |
| `holdOriginal` | Ctrl+Alt+Shift+O | 押している間だけ原画を表示 |
| `emergencyExit` | Ctrl+Alt+Shift+Esc | 非常口: 全フィルタ停止 + 原画表示解除 + クリックスルー解除 + 最前面解除 + ルーペ窓表示/前面化 |
| `toggleLoupeVisibility` | Ctrl+Alt+Shift+L | ルーペ窓の表示/非表示 |

既定キーはすべて Ctrl+Alt+Shift の 3 修飾（`defaultHotkeyBindings()`）。主要
アプリ・OS 標準ショートカットと衝突しにくくするため。

### 構成 (純粋ロジックと副作用の分離)

`tray_service.dart` と同じ 2 層構成に倣う。

- **`HotkeyActions`**（`lib/services/hotkey_actions.dart`）— 4 アクションの
  実処理。すべて注入されたコールバック（`setClickThrough` / `setAlwaysOnTop` /
  `acquireBypass` / `releaseBypass` / `clearBypass` / `isBypassHeldByHotkey` /
  `showAndFocusLoupe` / `toggleLoupeVisible` 等）経由で副作用を起こすため、
  実 OS のホットキー/window_manager 無しでフェイクにより単体テストできる
  （`test/hotkey_actions_test.dart`）。
- **`HotkeyService`**（`lib/services/hotkey_service.dart`）— `hotkey_manager`
  への実際の登録を担う副作用層。登録処理は `HotkeyGateway` インターフェース
  越しに行い、テストではフェイクゲートウェイに差し替える
  （`test/hotkey_service_test.dart`）。登録失敗（Wayland 等でグローバル
  ホットキーが使えない環境）はアクションごとに個別に catch し、他のアクション
  の登録は続行する。結果は `registeredActions` / `failedActions` に残り、
  `main()` が `HotkeyStatus` として `UniversalExperienceApp` へ渡し、
  `WindowModePanel` が失敗したアクションをエラー色で表示する。

### `holdOriginal` の keyUp フォールバック設計

「押している間だけ原画を表示」は理想的には keyDown で ON・keyUp で OFF にする
hold ジェスチャだが、一部 OS のグローバルホットキーでは keyUp イベントが
配送されないことがある。`HotkeyActions.holdOriginalKeyDown()` /
`holdOriginalKeyUp()` はタイマー等の環境判定なしに両方の環境に自然に
フォールバックする:

- **keyUp が届く環境（macOS）**: 押す→ON、離す→OFF という正しい hold 挙動になる。
- **keyUp が届かない環境（Windows・Linux）**: 毎回の押下が単純なトグルとして機能する。OS の
  キーリピートで keyDown が連続送出されても、直前の keyDown から 1100ms 未満の keyDown は
  リピートとみなして無視するため、1 回の押下（連打）につき 1 回のトグルになる
  （`HotkeyActions._repeatDebounce`、#63）。

原画表示自体は `VisionFilterState.bypassed`（`lib/services/vision_filter_state.dart`）
が担い、選択中のフィルタ・strength・params は一切変更しない。判定は
`preview_selection.dart` の `previewStrength()` に集約する（bypassed なら
`isColorQuickSelection` に関わらず常に 0.0 を返す）。

> **未配線の注意**: `VisionFilterState.bypassed` は before/after プレビュー（`previewStrength()`
> 経由）には配線済みだが、ルーペ窓のライブ画面キャプチャ描画（#1 以降、未実装）には
> まだ配線先が無い。ライブ描画が実装されたら、そちらでも bypassed を見て原画へフォール
> バックする必要がある。

> **実機未検証の注意**: Windows で `Ctrl+Alt+Shift+Esc`（`emergencyExit` の既定キー）が
> OS 標準や他アプリのショートカットと衝突しないかは、Windows ランナー未着手のため実機
> 確認できていない。Windows 対応時に確認が必要。

### クリックスルーの復帰経路

ネイティブプラグイン（hotkey_manager/tray_manager）の「登録・作成成功」は実際にユーザーが復帰操作できる
ことを保証しない。そのため、アプリ自身が制御できる 2 つの復帰経路を実装し、これを「常に使える」ベース
ラインとする:

- **(a) フォーカス復帰＋最初のキー入力**: クリックスルー ON のままウィンドウがフォーカスを得ると
  （`LoupeWindowController.onWindowFocus`）、即座には解除せず「解除の予約」だけする。予約中にアプリ内で
  最初のキー入力を受け取った時点で解除する（`releaseClickThroughOnFirstKeyPress()`、`HardwareKeyboard` の
  全イベントハンドラ経由）。フォーカスを失うと予約は取り消す（`onWindowBlur`）。フォーカスを得ただけで
  即解除しないのは、トレイメニューを開いた・OS がユーザー操作を伴わずフォーカスを移しただけ（Windows の
  `SetForegroundWindow` 等）のときに意図せず解除されるのを避けるため。
- **(b) アプリ内 Esc**: クリックスルーが ON のとき、Esc を押すと即座に解除する
  （`ReleaseClickThroughIntent`、`app_shortcuts.dart`）。

この 2 つが揃っているため、クリックスルーはいつでも ON にしてよい（可否のチェックは不要）。トレイ・
ホットキーは追加の便利な手段という位置づけで、`WindowModePanel` はクリックスルーのスイッチ横に、そのとき
実際に使える復帰手段をすべて併記する（フォーカス復帰＋最初のキー入力・Esc は常時、トレイ・ホットキーは
可用性に応じて）。

> **実機未検証の注意**: フォーカス復帰＋最初のキー入力と Esc の組み合わせが、実際にすべてのプラット
> フォーム（macOS/Linux/Windows）で意図どおり動くかは、この実装段階では実機確認していない。特に
> Windows はトレイアイコンのクリックが `SetForegroundWindow` でこのウィンドウを前面化することがあり、
> その挙動が「解除の予約」にどう影響するかは Windows 対応時に確認が必要（トレイ操作そのものではクリック
> スルーは解除されず、その後アプリ内で最初のキー入力があった時点で解除される設計だが、実機での動作は
> 未検証）。

> **起動時の復元とフォーカスの競合の注意**: `restorePersistedClickThrough()` は起動時にクリックスルーを
> `setClickThrough(true)` で直接復元するため、「解除の予約」は経由しない。起動直後、ウィンドウがまだ
> フォーカスを得ていない状態で復元が走った場合、その後の最初のフォーカス取得＋キー入力で意図せず解除
> されうる（初回起動直後のみに限られる特殊ケースで、通常のトグル操作には影響しない）。

## アプリ内キー操作 (#63)

ウィンドウにフォーカスがある間だけ効くショートカット 5 種（貼り付けは #97 で追加）。実装は
`lib/services/app_shortcuts.dart`（`Intent` 定義 + `isFocusOnInteractiveControl()` /
`InteractiveFocusAwareCallbackAction`）+ `lib/services/preview_selection.dart`
（実処理: `adjustPreviewStrength()`）+ `lib/services/filter_list_selection.dart`
（↑↓ の順送り `nextFilterListEntry()`）+
`lib/ui/screens/home_screen.dart`（標準 Flutter `Shortcuts`/`Actions`/`Focus` で配線。
`hotkey_manager` の `GlobalShortcuts` は使わない — こちらはウィンドウ内フォーカス時だけの
アプリ内ショートカットで、OS 全体に効くグローバルホットキーとは別物）。

| キー | 効果 |
|---|---|
| `/` | 左カラムの検索欄（`FilterBrowserController.searchFocus`）にフォーカスを移し、入力済みの文字を全選択する |
| `↑` / `↓` | 統合フィルタ一覧（色覚 7 型 + advanced 30 件）の、今見えている行を逆送り/順送り（wraparound） |
| `←` / `→` | 選択中フィルタの強度を `kKeyboardStrengthStep`（5%）刻みで増減 |
| `Esc` | クリックスルーが ON のとき解除する（クリックスルーの復帰経路。上記「クリックスルーの復帰経路」参照） |
| `Cmd+V`（macOS）/ `Ctrl+V` | クリップボードの画像をプレビューの原画として貼り付ける（#97。下記） |

- **`Cmd/Ctrl+V` のガードだけは狭い**（#97）: `/`・↑↓・←→ は `isFocusOnInteractiveControl()`
  （テキスト入力・ボタン・スライダー等）で奪わないが、貼り付けは
  `isFocusOnTextInput()`（`EditableText` のみ）でしか奪わない
  （`TextInputAwareCallbackAction`）。ボタンやスライダーは貼り付けに固有の意味を
  持たず、「貼り付け」ボタンを押した直後（フォーカスがボタンに残る）でもキーボードの
  貼り付けが効くべきため。テキスト入力中は `isEnabled` が false になってキーイベントを
  消費しないので、`MaterialApp` 直下の `DefaultTextEditingShortcuts` が入力欄自身の
  貼り付けとして処理する。割り当てはプラットフォームで変わる（macOS は Cmd、それ以外は
  Ctrl）ので `home_screen.dart` の `Shortcuts` マップには実行時に足す
  （`pasteShortcutActivator()`）。
- **`/` は検索欄へフォーカスする**（#72 で左カラムに検索欄が入った。それ以前は
  advanced カタログへフォーカスしていた）。検索欄は `TextField` なので、フォーカス
  中は `/` 自体を含むキー入力が本来の文字入力として通る（上記ガード）。
- **↑↓ の対象は統合一覧の「今見えている行」**（#72）。色覚 7 型 + advanced 30 件を
  1 つの一覧にまとめたので、順送りもその一覧を対象にする（`nextFilterListEntry()`。
  検索・カテゴリで絞っていれば絞った行だけ）。体験プリセットは一覧の最上段にあるが
  送りの対象外（選択は行のタップ/Enter）。検索欄は `TextField` なので ↑↓ を奪わない —
  行を**ポインタで**選ぶと `HomeScreen` がショートカットの受け口へフォーカスを戻し、そこから
  ↑↓・←→ が効く。**Enter/Space で選んだときはフォーカスを行に残す**（キーボード利用者の
  現在位置を奪わない）。
  スクロールの追従は経路が 2 つある。**行にフォーカスがある間の ↑↓** は、アプリのショートカットではなく
  標準の方向フォーカス移動（隣の行へ移り、フレームワークのフォーカス走査が `Scrollable.ensureVisible`
  で見える位置へスクロールする。`FilterListTile` は関与しない）。**フォーカスが行にないときの ↑↓**
  （アプリのショートカット）は選択そのものを変え、選択中になった行の `FilterListTile` が
  `didUpdateWidget` で反応して、一覧の内側のスクロールだけを最小限動かす（上方向・末尾から先頭への
  折り返しにも対応。外側のページスクロールは動かさない）。`FilterListTile` が動かすのはこの
  「選択が変わった」ときだけで、フォーカスの移動には反応しない。
  **行にフォーカスがある間の ←→ は、その 1 回では強度の 5% 刻み調整が効かず、フォーカスが必ず
  画面のショートカット受け口（`homeShortcuts`）へ出る**ので、次の ←→ から強度が動く。これは標準の
  方向フォーカス移動任せにしていない。標準の走査は幾何（隣のカラムのコントロールとの縦帯の重なり）で
  着地点が決まり、色覚選択時に中央カラムへ出る「2×2 で比較」の切替が見出し行を高くすると、`→` が中央
  カラムのサンプル切替チップへ着地して強度に届かなくなった。そこで「選ぶ」カードの `FocusTraversalGroup` に
  `_ListExitToShortcutsPolicy`（`ReadingOrderTraversalPolicy` を継承し、`FilterListTile` 上からの
  左右だけ受け口へ固定。体験プリセットの行も同じ `FilterListTile` なので含み、それ以外の方向・部品は
  標準）を、広幅の左カラム・狭幅の末尾で共通の `_browserCard()` に付け、着地点を幾何から切り離した
  （`home_screen_layout_test.dart` / `home_screen_color_vision_compare_test.dart` がウィンドウ高さを
  変えて確認）。他のカラムへは Tab で行く。ポインタで行を選び直しても、フォーカスはショートカット
  受け口へ戻る。
  キーボード起点かポインタ起点かは、タップ処理の中で `HardwareKeyboard` の Enter/Space の
  押下状態を見て判定する。
- **`/`・↑↓・←→ はテキスト入力・ボタン・スイッチ等にフォーカスがある間は無効化される**
  （`isFocusOnInteractiveControl()` による `isEnabled` ガード、#63）。`Esc` だけは
  このガードの対象外 — クリックスルーからの復帰は常に効く必要があるため。
- ←→ の強度調整は `adjustPreviewStrength(visionState, delta)` が、フォーカス中の層の
  強度の記憶（`VisionFilterState.strength`）を動かす。色覚クイック選択でも advanced でも
  同じ記憶で、`FilterService.intensity` は同じ値を読む（#117）。

## ルーペ窓 HUD (#79)

`lib/ui/widgets/loupe_hud.dart` の `LoupeHud`。`LoupeWindowController.appMode`
が `AppMode.loupe`（ルーペ窓モード）のときだけ、窓の縁（上端）に小さな
ツールバーを出す。`AppMode.settings`（設定窓モード）では何も描画しない。

`main.dart` の `UniversalExperienceApp` は `home` を `Stack(children: [HomeScreen(),
LoupeHud()])` として組み立て、`LoupeHud` を `HomeScreen` とは別の最上位レイヤに
する。

### 表示するもの

- **症状名・強度**: `VisionFilterState` の現在の選択。表示名の解決は
  `visionFilterDisplayName`（`lib/l10n/l10n_extensions.dart`）— #60 で
  `before_after_view.dart` の `_displayName` として実装されていたものを、HUD と
  共有できる形に抽出した（重複定義しない、色覚 -omaly の名前も正しく出る）。
  強度は `selectedStrength`（`lib/services/preview_selection.dart`）で、bypass
  に関わらない素の値を表示する — 原画比較中でも「今選んでいるフィルタは何%か」
  が見え続けるようにするため（`previewStrength` は bypass 中に 0.0 を返すので
  ここでは使わない）。原画比較中であること自体は原画比較ボタンのアイコンの色
  （後述）で示す。
- **受診喚起アイコン**: `resolveConsultNotice`（`lib/l10n/l10n_extensions.dart`、
  #76）が非 null を返すときだけ表示する。押すと `ConsultNoticeBlock`
  （`lib/ui/widgets/consult_notice_block.dart`）で全文（免責文込み）をダイアログ
  表示する。advanced カタログ（`FilterParamPanel`）・体験プリセット
  （`ExperiencePresetTile` の選択後は `AdjustPanel`）・PNG export と同じ解決経路・同じ表示ウィジェットを
  共有する。
- **原画比較ボタン**: 押している間だけ `VisionFilterState.bypassed` を true に
  し、離すと false に戻す（#63 のホットキー「押している間だけ原画」と同じ
  `bypassed` を共有）。アイコンの色は「このボタン自身が押されているか」では
  なく `VisionFilterState.bypassed`（グローバル）を見て決める — ホットキー等
  他の入力元が保持している場合も原画比較中であることを示すため。
  「押している間だけ」の詳しい挙動・入力元ごとの保持は次節「bypass の
  入力元ごとの保持」参照。
- **設定を開くボタン**: `LoupeWindowController.setAppMode(AppMode.settings)` で
  設定窓モードへ戻す。

### bypass の入力元ごとの保持（#79）

`VisionFilterState.bypassed` は当初（#63）単一の bool だったが、ホットキー
（`hotkey_actions.dart`）とルーペ HUD（`loupe_hud.dart`）の両方が同時に
「押している間だけ原画」を要求しうるため、入力元ごとの保持（holder、
`Set<Object>`）に変更した:

- `VisionFilterState.acquireBypass(Object source)` / `releaseBypass(Object
  source)` が入力元ごとの holder を追加/削除する。`bypassed` は holder が
  1 つでもあれば true。片方の入力元が離しても、もう片方がまだ保持していれば
  `bypassed` のままになる。
- `VisionFilterState.isHeldBy(Object source)` は、特定の入力元が今まさに
  保持しているかを返す。ホットキーの hold/toggle 判定やルーペ HUD のトグル
  代替（後述）は、ローカルにミラーした bool ではなくこれを都度クエリする —
  ローカルなミラーは `clearBypass()` 等の外部からの一括解除に追従できず、
  「解除済みなのに release し続けて何も起きない」「ON のつもりのまま次の
  操作が release を呼んでしまい実際には ON にならない」というズレを起こす
  ため。
- `VisionFilterState.clearBypass()` は誰が保持していても全 holder を強制的に
  解除する。フィルタ選択（`select`/`selectColorVisionType`/`selectPreset`/
  `clear`）・強度変更（`setStrength`/`setParam`/`randomizeSeed`/
  `resetToRecommended`）・アプリ内ショートカット（`adjustPreviewStrength`）・
  `IntensitySlider` の操作・非常口（`HotkeyActions.emergencyExit`）が使う —
  これらは「原画比較の状態に関わらず必ずフィルタ表示に戻す」操作なので、
  誰が原画比較していたかは問わない。
- `hotkey_actions.dart` は `VisionFilterState.bypassed` のようなグローバル値
  ではなく、注入された `isBypassHeldByHotkey`（`VisionFilterState.isHeldBy` に
  ホットキー専用の識別子を束縛したもの）で hold/toggle 判定する。
  `HotkeyActions` はサービス層を直接知らず、`acquireBypass`/`releaseBypass`/
  `clearBypass`/`isBypassHeldByHotkey` の 4 コールバックを注入される
  （`main.dart` がホットキー専用の holder トークン `_hotkeyBypassSource` を
  束縛して渡す）。
- `LoupeHud` の原画比較ボタン（`_CompareOriginalButton`）はボタンインスタンス
  専用の 2 つの holder を持つ: 押している間用（`_pressHolder`）と、
  押し続けられない場合の代替トグル用（`_toggleHolder`、後述）。互いに独立
  しているので、押している間にトグルの状態が乱れることはない。トグルの
  ON/OFF もローカルなミラーではなく `isHeldBy(_toggleHolder)` を都度クエリ
  する。

### 原画比較ボタンの解除経路（#79）

「押している間だけ」を確実に離すため、以下すべての経路で holder
（`_pressHolder`）を解放する:

- 通常のポインタ up（`Listener.onPointerUp`）・ジェスチャキャンセル
  （`Listener.onPointerCancel`）。
- 押したまま領域外に出た場合。**タッチ入力には hover の概念が無い**ため
  `MouseRegion.onExit` だけには頼れない。`Listener.onPointerMove` で生の
  座標を直接見て、ボタンの実際のレンダリングサイズ（`RenderBox`、ハード
  コードした定数ではなく実測）に収まっているかを毎回判定する方式を主経路に
  し、`MouseRegion.onExit`（通常のホバー解除）は保険として併用する。
- フォーカスを失ったとき（`Focus.onFocusChange`。マウスボタンを離さないまま
  ダイアログ等へフォーカスが移ったケースを含む）。
- キーボード操作: Tab でフォーカスした状態での Enter/Space 押下で hold/
  release する。OS のキーリピート（`KeyRepeatEvent`）は再確保せず
  `handled` を返すだけにする。
- ウィジェット自体が dispose されるとき（`State.dispose`）。`dispose()` は
  ウィジェットツリーの unmount 中（フレームワークがロックされている間）に
  呼ばれるため、ここで同期的に `notifyListeners` すると Provider の
  `InheritedWidget` が `setState() called when widget tree was locked` で
  落ちる。解放そのものは `scheduleMicrotask` で遅延し、現在の unmount
  パスを抜けてから通知する。マイクロタスク実行時点で `VisionFilterState`
  自体が既に dispose 済み（`VisionFilterState.isDisposed`）なら、
  `notifyListeners` が落ちるので何もしない。

押し続ける操作ができない場合の代替として、`Semantics.onTap`（スクリーン
リーダー等の「アクティブ化」操作、Semantics のタップ）は押し続けではなく
**トグル**にする（専用の `_toggleHolder` で acquire/release。`_pressHolder`
とは独立）。`Semantics` の `toggled` フラグはこのトグル状態
（`isHeldBy(_toggleHolder)`）を反映し、`hint`（例: 「ダブルタップで原画比較の
切り替え」、ARB `hudCompareOriginalHint`）でその操作方法を説明する。

フォーカスが当たると `scheme.primary` の 2px 枠を表示する（`Container` の
`BoxDecoration.border`。既定の `IconButton`/`Material` の focus インジケータを
持たない自前の Container なので、明示的に描画する）。

`Tooltip` は `excludeFromSemantics: true` にし、代わりに明示的な `Semantics`
で `label` を 1 つだけ載せる。両方を素朴に重ねると、アクセシビリティツリーに
`label` と `tooltip` の両方が同じ文言で載って二重に読み上げられる。HUD の丸い
アイコンボタン（`_HudIconButton`）も同じパターンを使う。

### 表示/非表示ロジック（#79）

窓の**上端全幅・高さ 12px の検知帯**（`Positioned` + `MouseRegion`）にポインタが
入ると表示し、バー本体（検知帯より下に張り出す）の上にいる間は表示を維持する。
検知帯・バーいずれからも離れると、`kLoupeHudHideDelay`（700ms）だけ遅らせて
隠す — 検知帯からバー本体へ移動する一瞬の途切れで隠れてしまわないための猶予。
`Timer` は `State.dispose` で必ず `cancel` する。

検知帯・バー本体いずれの `MouseRegion` も `opaque: false` にする（純粋な
ホバー検知専用）。既定の `opaque: true` のままだと、非表示中に中身を
`IgnorePointer` で操作不能にしていても `MouseRegion` 自身がヒットテストを
奪ってしまい、下の画面（将来のライブキャプチャ #1 が描く実デスクトップ等）
へのクリックが届かなくなる。

非表示中は `IgnorePointer`（操作不能）・`ExcludeSemantics`（アクセシビリティ
ツリーから除外）・`ExcludeFocus`（Tab フォーカスが届かないようにする）の
3 つでバーを外す。**表示/非表示でウィジェットツリーの形は変えず、これら
3 つの `excluding`/`ignoring` フラグだけを切り替える**（常に
`ExcludeSemantics(excluding:) > IgnorePointer(ignoring:) > ExcludeFocus
(excluding:) > _LoupeHudBar()` の形）。以前は非表示中だけ別の Widget 型で
ラップしており、表示状態が切り替わるたびに `_LoupeHudBar` 以下の Element が
作り直され、`_CompareOriginalButton` の State（トグルの保持・フォーカス）が
失われていた。非表示中も外側の `MouseRegion` 自体は常にレイアウトされたまま
（`AnimatedOpacity` は要素を消さず不透明度だけ 0 にする）なので、縁への接近を
検知できる。

全画面判定は `LoupeWindowController.mode == LoupeWindowMode.fullscreen` を見る
（`LoupeWindowController` は `onWindowEnterFullScreen`/`onWindowLeaveFullScreen`
で既に `_mode` をリアルタイムに追従させているため、`window_manager` の
`isFullScreen()` を別途ポーリングする必要は無い）。この判定自体は
`loupe_hud.dart` の `isLoupeFullScreenProvider`（既定は上記の一行）という
provider seam 越しに行う — `vision_filter_metadata.dart` の
`visionFilterUrgencyProvider` 等と同じパターンで、widget test から差し替え
可能にするため。

### 将来のライブキャプチャ（#1）に向けた前提

`LoupeHud` はキャプチャ対象・フィルタ対象から**除外する必要がある**（HUD 自体を
フィルタ加工したりキャプチャに写り込ませたりしてはいけない）。現状ライブ
キャプチャは実装されていないため実際の除外処理は無いが、`LoupeHud` を常に
独立した最上位レイヤ（`main.dart` の `Stack`）として置くことで、#1 実装時に
「キャプチャ対象の矩形から HUD の矩形を差し引く」または「キャプチャそのものを
HUD より下のレイヤだけに限定する」実装がしやすい構造にしてある。

## `LoupeRectSource` (#63、#44 向けの差し替え可能な seam)

`lib/services/loupe_rect_source.dart` は、ルーペ矩形の決定元をインターフェース
（`LoupeRectSource`）として切り出したもの。現状の唯一の実装
`ManualLoupeRectSource` はルーペ窓自身の矩形（ユーザーが手動で動かす）を返す。
将来 #44（対象アプリのウィンドウに自動追従するモード）が実装されたら、この
インターフェースの別実装に差し替える想定。#44 自体の実装（自動追従ロジック）は
この Issue のスコープ外で、seam を用意しただけ。`LoupeWindowController` は
コンストラクタ引数（既定 `ManualLoupeRectSource`）でこれを受け取り、
`currentLoupeRect()` 経由で公開する（#63。#44 実装時はここへ対象アプリ追従の
実装を注入できる）。

### マルチモニタ

- **第1弾はメインモニタのみ対象**。サブモニタへの移動追従や、モニタごとの
  DPR 換算 (#5) はスコープ外。window_manager のメインモニタ座標系で動作する前提。

### 実機目視について

透過・クリックスルー・最大化時の縁などの GUI 目視確認は、Wayland/grim 制約と
ライブキャプチャ（#1）の実装前のため本実装段階では未実施。`flutter analyze` /
`flutter test` / `flutter build linux --debug` で静的・ビルド確認のみ。実機目視は
#1 の実装後に行う。

## システムアーキテクチャ（現行）

Universal Experience は Flutter（UI）+ Rust（sensus-core、アルゴリズム正本）の
二言語構成。全体の層構造は本ファイル冒頭の要約と `docs/adr/2026-05-31-flutter-rust-split.md`
を参照。

```
Flutter UI (Screens/Widgets, Provider)
      ↓
FilterService / VisionFilterState (選択状態モデル)
      ↓
flutter_rust_bridge (lib/src/rust/)
      ↓
sensus-core (Rust, CPU apply() + GLSL/uniform 計算の正本)
      ↓
CpuVisionRenderer (lib/rendering/) — プレビュー（静止画）の正本経路（#85）
ShaderFilter    (lib/rendering/) — Impeller FragmentProgram。将来のライブ画面
                キャプチャ（#1/#3/#4）向けに残置。現状 production からの
                呼び出しはなく、GPU golden テストのみが使う
```

状態管理は Provider の `ChangeNotifier` ベース: `FilterService` /
`VisionFilterState` が状態変更時に `notifyListeners()` を呼び、それを購読する
`Consumer` を持つウィジェットだけが rebuild される。

`FilterService`（色覚クイック選択の型）と `VisionFilterState`（層・強度）の 2 つが残る現状を 1 系統に畳み、
複数症状の同時適用に拡張する方針（第 1 段 #117 で強度の正本は `VisionFilterState` に一本化済み）は「状態モデルの統一と多症状の同時適用 (#32 / #41)」節と
`docs/adr/2026-09-30-multi-select-filter-state-model.md`。

`rust/` crate は `rust_builder/`（cargokit 統合、#55）経由でビルドされ、
macOS / Linux アプリに同梱される。`lib/main.dart` の `buildRootApp()`（#55 で `main()` から
切り出したルート Widget 組み立て関数）が `runApp`
前に `services/native_bridge_service.dart` の `initNativeBridge()` を呼んで
同梱された native lib をロードする（呼ばないと `RustLib.instance` が未初期化の
まま `experiences()` 等が例外になる。#52 で実際に本番のプリセット欄が例外表示に
なっていた）。`initNativeBridge()` は `buildRootApp()`（`main()` から呼ぶ）と
`integration_test/experience_presets_smoke_test.dart` の両方が共有する唯一の
初期化経路で、二重初期化（`RustLib.instance.initialized` が true）は素通りに
し、`RustLib.init()` 自体の失敗は例外を外に投げず `false` を返す。
`buildRootApp()` はこれが `false` のとき `UniversalExperienceApp` の代わりに
`NativeBridgeErrorApp`（`AppLocalizations.nativeBridgeInitFailed`、ja/en）を
返し、`main()` はそれをそのまま `runApp` する。native lib が同梱されていない/
壊れている状態でもクラッシュせず文言表示に落ちる、という契約。
`NativeBridgeErrorApp` は任意の `locale` を注入できる（未指定ならシステム追従の
フォールバック）ため、widget test から ja/en それぞれの文言を固定して検証できる
（`test/native_bridge_error_app_test.dart`）。

`buildRootApp()` は `initBridge`（既定 `initNativeBridge`）と `settings`
（既定で新規 `SettingsService()`）、`store`（フィルタ選択の永続化 `VisionFilterStore`、#65）を
差し替え可能な引数に取る。windowManager /
trayService の初期化・配線は `buildRootApp()` の外、`main()` 内に閉じたまま
残している（デスクトップ専用の副作用をブリッジ初期化のテストに持ち込まない
ため）。`integration_test/app_bootstrap_test.dart`（#55）は
`main()` を直接は呼べない（windowManager 初期化を含むため）代わりに、新しい
別プロセスから `buildRootApp()` を直接呼んで実ブリッジの初期化〜
`UniversalExperienceApp` 描画までの実起動経路を再現し、`initBridge` を
差し替えて失敗系（`NativeBridgeErrorApp` への分岐）も検証する。既存の
`experience_presets_smoke_test.dart` は自身の `setUpAll` で先に
`initNativeBridge()` を呼んでしまうため、`main()`/`buildRootApp()` の呼び出し
漏れ自体は検知できない — それを埋めるのが `app_bootstrap_test.dart` を
あえて別ファイルにした理由。

> **注意（Linux の dev ロードパス優先）**: `RustLib.init()`（flutter_rust_bridge の
> `loadExternalLibrary`）は、まずカレントディレクトリ相対の `rust/target/release/`
> （生成済み `frb_generated.dart` の `ioDirectory` 設定）に `.so`/`.dylib` が
> 無いか探し、あればそれを優先してロードする。cargokit が同梱した native lib
> （フォールバック経路）を見るのはそれが無い場合だけ。`flutter run -d linux` は
> プロジェクトルートを CWD にして実行されるため、`cargo build`（`cd rust && cargo
> build` 等）を一度でも直接叩いたことがある開発環境では `rust/target/release/` に
> 古い `.so` が残り、それが cargokit の再ビルド分より優先されてロードされうる。
> 挙動が cargokit 側の変更と食い違って見えたら、まず `rust/target/release/` に
> 古い `.so`/`.dylib` が残っていないか確認する（`rm -rf rust/target` で消せる。
> `cargo test`/`clippy` 用の再ビルドは自動で走る）。

### 主要コンポーネント

- `HomeScreen`: メイン画面（#72）。幅 1000dp 以上は 3 カラム（左「選ぶ」=`FilterBrowser`、
  中央「見る」=`BeforeAfterView` + `ImageSourcePicker`、右「調整」=`AdjustPanel`）、
  それ未満は プレビュー → 調整 → 選択 の縦積み。`FilterBrowser` は検索・カテゴリ・
  統合フィルタ一覧（色覚 7 型 + advanced 30 = 33 行、ロジックは
  `filter_list_selection.dart`）と体験プリセットの最上段を持つ。`AdjustPanel` は選んだ
  症状の説明・強度（`IntensitySlider`）・受診喚起（`ConsultNoticeBlock` 常時展開）・
  `FilterParamPanel` を持ち、未選択時は空状態を出す。起動モード・最前面・クリックスルー・
  ホットキー一覧（`WindowModePanel`）は AppBar のダイアログに退避し、クリックスルー ON
  の間は復帰方法を `ClickThroughRecoveryBanner` が画面最上部に常時出す（#63）。
  PNG エクスポートはプレビュー側に置く。選択の状態は従来どおり `VisionFilterState` が
  唯一の正本
- `FilterService`: 色覚クイック選択（`ColorVisionType`）の選択状態。sensus `VisionFilter`
  へのマッピングを持つ。**強度は自前で持たず**、コンストラクタで受け取る `VisionFilterState` の
  強度の記憶（キー `ColorVisionType.name`）を読み書きする（#117。かつての per-type
  `Map` とその SharedPreferences 書き込みは撤去）。`intensity` は記憶があればそれ、無ければ
  推奨強度（-opia/achromatopsia=1.0、-omaly=0.6。記憶へは書かない、none は 0.0）。
  `setIntensity` / `applyFilter(intensity:)` は記憶へ書き、`VisionFilterState` と自身の
  listener の両方に通知する（スライダー・トレイは `FilterService`、プレビューは
  `VisionFilterState` を見るため）。`SettingsService` は `notifyListeners` を購読する
  `MaterialApp`（テーマ/ロケール用）を持つため、intensity のようにスライダー 1 目盛りごとに
  変わる値はそちらに混ぜず、`SettingsService` を経由しない。一方 filterType（どのタイプを
  選んでいるか）は `SettingsService.setFilterType` 経由で引き続き通知・永続化する
- `VisionFilterState`: 選択・パラメータ・強度の状態（sensus 全 30 種 + 色覚クイック選択）。
  重ねる層の列 `layers`（`VisionLayer`: id・payload・別名 `variantId`・起源 `origin`。層は強度を
  持たない）、フォーカス中の層 `focusedId`、強度の記憶 `strengthByKey`（キー `variantId ?? id`、
  読むときに導出: 記憶 → 色覚は `recommendedStrength` → それ以外は sensus の推奨値。
  導出した値は記憶へ書かない）、カタログ id ごとの payload の記憶を持つ。`selectedId` /
  `strength` / `params` / `isColorQuickSelection` などは、フォーカス中の層を指す互換の読み口。
  適用順は段（`lib/models/vision_filter_stage.dart`）で決まり、上限は `kMaxVisionLayers`（5）。
  層の列は `normalizeVisionLayers` が不変条件（有効な id・重複なし・色覚は排他・上限・
  適用順）に整える。これらは `snapshot()` / `restore()` で `VisionFilterSnapshot`
  （`lib/services/vision_filter_snapshot.dart`）と往復し、`VisionFilterStore`
  （`lib/services/vision_filter_store.dart`）が `SharedPreferences`
  （キー `settings.visionFilter`、版つき JSON）へ永続化する（#65。下記
  「フィルタ選択の永続化」）
- `CpuVisionRenderer`（`lib/rendering/cpu_vision_renderer.dart`）: sensus の CPU
  `apply()`（`applyVisionCpuRgba8`）で `ui.Image` にフィルタを適用する、
  **プレビュー（静止画）描画の正本**（#85）。`ui.Image` → straight RGBA8
  （`ImageByteFormat.rawStraightRgba`）→ 実ブリッジ呼び出し → premultiply →
  `ui.Image`（`ImmutableBuffer`/`ImageDescriptor.raw`/`instantiateCodec` の
  await 連鎖。`decodeImageFromPixels` は使わない — デコード失敗時にコール
  バックが呼ばれず呼び出し元がハングし得るため）の往復のみを行い、
  アルゴリズムは一切持たない。sensus は straight alpha、Flutter の `ui.Image`
  は premultiplied alpha を前提とするため、境界でこの変換を明示的に行う
  （#85）。任意の `VisionFilter`（payload 込み）を受け取れるため
  sensus 全 30 種を描画できる。`before_after_view.dart` はこの `VisionFilter`
  をそのまま（マッピングせず）中継するだけの presentational widget で、
  色覚のクイック選択・advanced カタログ・体験プリセットのどれで選んでも
  `VisionFilterState.build()` が組み立てた `VisionFilter` がここまで届く
  （#60、`home_screen.dart` の `_buildPreviewSection` がその配線点）。
  `applyVisionCpuRgba8` は `#[frb(sync)]` を外し非同期公開にしてあり
  （Rust 側スレッドプールで実行）、UI スレッドを塞がない。`before_after_view.dart`
  の `renderAfter` はこれを直接呼ぶ production コードなので、テストで差し替える
  ための `CpuVisionRenderer.applier`（`sampleImageGenerator`/
  `afterImageRenderer` と同じ seam パターン、#58）に `@visibleForTesting` は
  付けていない（同一ライブラリ外の production コードから正当に参照するため）
- `BeforeAfterView`（`lib/ui/widgets/before_after_view.dart`）: before/after
  プレビューペイン。#85 で、ペインの論理サイズ・
  `devicePixelRatio` に連動して都度サイズを変えていた旧 GPU 時代の auto-sizing
  （#58）を撤去し、常に固定の正準サイズ（`canonicalSampleSize` = 1024）で
  `CpuVisionRenderer` に描画させ、表示側は `FilterQuality.medium` でスケールする
  方式に変えた。理由は2つ: (1) `DetailLoss.cellSize` のように**絶対ピクセル数**
  でパラメータを取るフィルタは、画像サイズが変わるたびに見え方自体が変わって
  しまう、(2) disk blur 系（myopia/hyperopia/presbyopia/astigmatism）は半径を
  `strength × 比率 × min(width, height)` で決めており、比率が最小の
  astigmatism/presbyopia（1.1%）では画像サイズが小さいと半径が 1px 未満に
  退化してカーネルが中心 1 点だけになり完全な no-op になる（sensus-core の
  `build_ellipse_spans`、`integration_test/cpu_preview_all_filters_test.dart`
  参照）。CPU `apply()` は GPU シェーダより重いため、`_scheduleRebuild` が
  `_rebuild` の実行を直列化し（同時に走るジョブは常に1本、#85）、
  スライダーを連続操作しても実ブリッジ呼び出しが積み上がらないようにしている
  （#58 の世代管理・dispose・失敗表示の規約自体は変更していない）
- `ColorVisionCompareView`（`lib/ui/widgets/color_vision_compare_view.dart`、#84）: 色覚 4 型の
  2×2 比較。`HomeScreen` の「2×2 で比較」が ON（かつ色覚カテゴリ選択中）の間、`BeforeAfterView` の
  代わりに `ImageSourcePicker` の中へ出る。並べる型は `kColorVisionCompareEntries`
  （`lib/services/color_vision_compare.dart`。カタログの色覚カテゴリのうち `isExperimental` でないもの、
  宣言順）、各セルのフィルタは色覚クイック選択と同じ `visionFilterForColorVisionType` から引く
  （`colorVisionCompareFilter`）。専用のレンダラは持たず、`BeforeAfterView` と同じ経路
  （`previewSourceImageLoader` / `afterImageRenderer`。本番コードからは公開ラッパー
  `loadPreviewImage` / `renderPreviewAfter` 経由）で `CpuVisionRenderer` を 4 回、直列・最新優先で呼ぶ。
  強さは呼び出し側（`previewStrength`）が決めた値を 4 セル共通で受け取り、選択状態は読まない。
  セルの Semantics ラベルと「4 型とも同じ強さ」の注記は、表示中の画像を描いた強さ（`_afterStrength`、
  まだ無ければ `widget.strength`）から作り、再描画中に新しい強さが古い画像に被らない。失敗したセルは
  「描画に失敗しました」の文言に切り替わる。新しい描画が控えている間（`_rebuildPending`）の失敗は
  表示せず、最新の入力の描画が失敗したときだけ失敗を出す（スライダー操作中の点滅防止）。
  書き出しは各セルを `buildExportCaption` + `composeExportImage`（単独の書き出しと同じキャプション）で
  焼き込み、`composeCompareGrid`（`export_service.dart`。配置は pure な `compareGridLayout`）で
  1 枚に並べる。キャプションは描画時点の強さから作り、保存・通知・失敗の扱いは
  `savePngWithClipboard` / `showExportSuccess`（`BeforeAfterView` の書き出しと共通）を使う。
  `BeforeAfterView` との関係は `docs/adr/2026-09-30-color-vision-2x2-compare.md`
- `ShaderFilter`（`lib/rendering/shader_filter.dart`）: sensus 由来 GLSL を変換した
  Impeller `FragmentProgram` で `ui.Image` にフィルタを適用する。色覚 7 型
  （protanopia/deuteranopia/tritanopia/achromatopsia + 各 -omaly）に対応
  済み（#59）。protanopia/deuteranopia/tritanopia は sensus の Machado 11 段
  severity テーブルを `resolveSeverityMatrix()` で区分線形補間して解決する
  （グリッドは `lib/rendering/color_matrices.g.dart`、sensus-core からの生成物）。
  **プレビューの描画経路は #85 で `CpuVisionRenderer`（CPU `apply()`）に
  置き換え済み**。`ShaderFilter` は将来のライブ画面キャプチャ（#1/#3/#4、
  ルーペ窓 `loupe_window_controller.dart` での実描画を想定）向けに残置して
  あるが、その機能自体が未実装のため**現状 production コードから呼ばれることは
  ない**。GPU と CPU の等価性は `test/vision_filter_golden_test.dart` 等の
  GPU golden テストが（production の呼び出しとは独立に）担保する
- `ExportService`: フィルタ適用後（after）画像のメタ焼き込み PNG エクスポート。
  書き出し先は Downloads。macOS のサンドボックスでは `getDownloadsDirectory()` が
  コンテナ内 `Data/Downloads`（実 `~/Downloads` へのシンボリックリンク）を返し、
  `files.downloads.read-write` entitlement が無いとリンク先への書き込みが拒否される
  想定（#64。修正前の実機挙動は未検証）。`savePngInto` は保存先とファイルの最終パスを `resolveSymbolicLinks` で
  実パスにして返す（SnackBar・クリップボード・「フォルダで表示」用）。ファイル名は
  日付＋時刻（`exportFilename`）で、同名があっても `writeBytesWithoutOverwrite` が
  `File.create(exclusive: true)` で連番にし上書きしない（書き込み失敗時は作りかけの
  ファイルを消す）。成功 SnackBar の「フォルダで表示」は `revealInFolder`
  （コマンドと成功条件の決定は pure な `revealCommandFor`。macOS は終了コード 0、
  Windows は終了コード無視、Linux は `xdg-open` を切り離して起動）。判断の経緯は
  `docs/adr/2026-09-30-export-png-to-downloads.md`
- `ExperiencePresetTile`（`lib/ui/widgets/experience_presets.dart`）: sensus の
  `experiences()` をワンタップ適用の行として消費する（複合体験、#19）。統合一覧
  `FilterBrowser` の最上段に並ぶ（#72）
- `ImageSourceState`（`lib/services/image_source_state.dart`）: プレビューの
  **原画**（before ペインの元画像）の選択状態を持つ、唯一の正本（#78）。
  `VisionFilterState`（フィルタの選択）とは独立した軸で、内蔵サンプル 8 種
  （`lib/models/sample_catalog.dart`）か、ユーザーが読み込んだ画像
  （`ui.Image`、ファイル選択/ドラッグ＆ドロップ/クリップボード貼り付け）のどちらかを指す
  `PreviewImageSource`（`lib/models/preview_image_source.dart`。サンプルは
  `sampleId` の値型、ユーザー画像は単調増加する `generation` で世代を区別する
  値型 — `ui.Image` 自体に意味のある値等価性が無いため）を返す。フィルタが
  変わると `home_screen.dart` のリスナー（`_persistFilterState` と同じ
  subscribe-once パターン）が `followRecommendedSample` を呼び、そのフィルタの
  推奨サンプル（`kRecommendedSampleByFilterId`）に自動で切り替える — ただし
  ユーザー画像を表示中、または手動でサンプルを選んだ後（`selectSample`。同じ
  サンプルの選び直しは no-op、#78）は no-op になる
  （`resetToRecommended` で自動追従を再開）。
  ユーザー画像の `ui.Image` は本状態が所有し、差し替え・`clearUserImage`・
  `dispose()` のいずれでも確実に dispose する（#58/#85 と同じ規律）。ただし
  差し替え・`clearUserImage` 時の dispose は同期的には行わず
  `SchedulerBinding.addPostFrameCallback` で次フレームまで遅らせる（#78）—
  `BeforeAfterView._rebuild` が `fitImageToSquare` でその
  画像をまだ参照中（`Picture` に描画コマンドとして記録済みだが `toImage()`
  のラスタライズ待ち）の可能性があるため。`dispose()`（サービス全体の
  teardown）自体は同期的なまま
  （並行する `Picture` recording が起きようがないため）。
  `BeforeAfterView` は `imageSource`（必須パラメータ）を
  `loadPreviewSourceImage`/`previewSourceImageLoader`（サンプルは
  `rootBundle` からデコード、ユーザー画像はそのまま）→
  `lib/rendering/image_fit.dart` の `fitImageToSquare`（縦横比を保った
  レターボックス、中央クロップはしない — 余白の色はブリッジしにくい
  `photophobia`/`night_blindness` 等への影響を避けた中間グレー固定。視野欠損系
  フィルタ（glaucoma/tunnel_vision/hemianopia）を非正方形画像に適用すると、
  周辺を暗くする効果がこのレターボックス余白にも均等にかかる — 余白も
  「見えている画面の一部」として扱う設計）で正準サイズへ収めてから既存の
  世代管理・dispose（#58/#85）に載せる。`_rebuild` は `widget.imageSource` を
  冒頭で一度だけ `source` に固定し、読み込み・`_currentImageSource` の記録の
  どちらにもこの値だけを使う（#78）— 末尾で `widget.imageSource`
  を再度読むと、読み込み中に親が別の source へ進んでいた場合に「実際に
  読み込んだ画像」と「記録される source」が食い違い、以後の
  `reuseBefore` 判定が新しい source への切替を誤ってスキップしてしまう
  （`test/before_after_view_image_source_test.dart` の回帰テスト参照）
- `ImageSourcePicker`（`lib/ui/widgets/image_source_picker.dart`）:
  サンプルチップ・「画像を選ぶ」ボタン（`file_selector`）・drag & drop
  （`desktop_drop` の `DropTarget`）・「画像を閉じる」ボタン（`clearUserImage`、
  #78）をまとめた、`BeforeAfterView` を包むプレゼンテーション層。
  ファイル選択・ドロップのどちらも最終的に `loadUserImageFile`
  （サイズ確認 → デコード → `ImageSourceState.setUserImage`）という同じ 1 本の
  経路を通る（#78: 取得からデコードまでを単一の try/catch に
  収め、どこで失敗しても同じ `imageSourcePickFailed` SnackBar に落ちる）。
  `loadUserImageFile` は `XFile.length()` を読んでから
  `kMaxUserImageFileBytes`（50MB）を超える場合はファイル本体を読まずに
  拒否し（#78）、`decodeUserImageBytes`
  （`lib/rendering/image_fit.dart`。`ui.instantiateImageCodecWithSize` で
  `kUserImageMaxDimension`（2048px）を超える長辺をデコード時にダウンスケール
  する）でデコードする。画像はメモリ上の `ui.Image` に変換するだけで、
  ディスクへの保存や外部送信は一切しない（#78）。
  **クリップボード貼り付け（#97）**は同じ正本に流し込む別の入口:
  「貼り付け」ボタンと `Cmd/Ctrl+V`（後述）はどちらも
  `pasteUserImageFromClipboard`（`ClipboardImageReader.read()` →
  画像データなら 50MB 超は専用文言で拒否 → `decodeUserImageBytes` → `setUserImage`）を通る。
  実行中の再入は無視する（in-flight ガード。キーのリピートは `includeRepeats: false` でも弾く）。
  クリップボード取得は `lib/services/clipboard_image_reader.dart` の
  `ClipboardImageReader`（interface。`read()` が `ClipboardContent` =
  画像なし / 画像データ / 画像ファイルのパス / 非対応ファイルのみ を返す）に切り出してあり、本番実装は
  `pasteboard` パッケージ（macOS: NSPasteboard、Linux: GtkClipboard。画像は PNG
  バイト列）、テストは `clipboardImageReader` をフェイクへ差し替える。
  **ファイルを先に見る**（`resolveClipboardContent`）: ファイラでファイルをコピーすると
  OS がアイコン画像も載せるため、**ローカルに実在するパス**（`existsLocally` を注入して判定。ファイル・
  フォルダとも真。ブラウザの画像コピーで載る http(s) URL など実在しないパスは無視）のうち画像拡張子の
  ものがあれば先頭 1 枚を `loadUserImageFile`（選択・ドロップと同じ経路）に回す。実在するものはあるが
  画像が 1 枚も無い（HEIC 等・フォルダ・.app・拡張子なし）なら画像データ（アイコン）へ進まず
  「非対応ファイルのみ」、実在するものが無いときだけ画像データへ進む。読み取りには 30 秒のタイムアウトがあり、超えたら読み取り
  失敗として扱う（in-flight ガードも解除される）。失敗は 5 種
  （画像なし `imageSourcePasteNoImage` / 巨大 `imageSourcePasteTooLarge` /
  デコード不能 `imageSourcePasteUnsupported` / 非対応ファイルのみ
  `imageSourcePasteUnsupportedFile` / 読み取り失敗 `imageSourcePasteFailed`）を SnackBar で示し、
  `ImageSourceState` には触れない（ファイル経路の失敗は `loadUserImageFile` の文言）。
  依存に `pasteboard` を選んだ理由は `docs/adr/2026-09-30-clipboard-image-paste.md`
- `WelcomeBanner`（`lib/ui/widgets/welcome_banner.dart`）: 初回起動時だけ出す
  案内バナー（#78）。表示条件・恒久的な非表示は `SettingsService.
  welcomeBannerDismissed`/`dismissWelcomeBanner()` に永続化する。初期選択
  自体（deuteranomaly を推奨強度で）は `main.dart` の `buildRootApp()` が
  `SettingsService.isFirstRun`（`filterType` が一度も永続化されていないかで
  判定 — 明示的な「Normal vision」選択との区別のため専用の永続化キーは
  持たない）を見て一度だけシードする。「ほかの見え方を選ぶ」は
  `home_screen.dart` が `FilterBrowser` の検索欄（`FilterBrowserController.searchFocus`）へ
  `requestFocus()` してから dismiss する（#78）。「自分の画像で
  試す」は `pickAndLoadUserImage` の成否（`bool`）を見て、キャンセル/失敗では
  dismiss しない（#78。ピッカーをキャンセルしただけなのにバナーが
  消えると再度の呼び出し手段を失うため）

### 過去の設計: system-wide プラグイン（#13 で撤去）

当初は Android（AccessibilityService + Overlay）/ Windows（Magnification API）/
macOS（CGSetDisplayTransferByTable）/ Linux（Wayland compositor / X11 XRandR）それぞれの
ネイティブ機構で OS 全体に色覚フィルタを適用する Platform Channel + Native Plugin 構成を
計画・調査していた。この構成は撤去済みで、判断の経緯・代替案・根拠は
`docs/adr/2026-05-31-sensus-core-consolidation.md` に、各 API 調査そのものは歴史的記録として
`docs/PLATFORM_APIS.md` にまとめてある。

## テスト戦略（現行）

- **ユニット/ウィジェットテスト**（`test/*.dart`, `flutter test`）: ARB 整合性・
  トレイ純粋ロジック・ルーペ窓ポリシー・PNG エクスポート・シェーダ codegen ドリフト
  検証・体験プリセット等を含む。`before_after_view_test.dart` の `renderAfter`
  は実ブリッジを要する `CpuVisionRenderer.applier`（#85）をフェイクに差し替え、
  `ColorVisionType` → `VisionFilter` のマッピング契約（#57/#59 の不変条件）を
  検証する（実描画そのものは下記の実ブリッジ integration test が担う）。
  同ファイルは `_scheduleRebuild` が実行を直列化すること（同時に走るジョブは
  常に1本、#85）も検証する。`cpu_vision_renderer_test.dart` は
  実ブリッジなしで検証できる部分（straight⇄premultiplied 変換の正しさ・
  `ImageDescriptor.raw` 経路のデコード失敗が例外として伝わること、#85）を担う
- **GPU golden テスト**（`test/vision_filter_golden_test.dart` /
  `test/protanopia_golden_test.dart`）: sensus-core 正本由来の参照 PNG と GPU 描画結果を
  PSNR/maxDiff で比較（詳細は `docs/sensus-integration.md` §6）。プレビュー自体は
  #85 で CPU 経路に切り替わり、GPU（`ShaderFilter`）は現状どの production
  コードからも呼ばれないが、将来のライブ画面キャプチャ（#1/#3/#4）向けに GPU
  経路自体の正しさ（sensus 正本との等価性）を引き続きこれらのテストが担保する
- **Rust 側**: `cargo test`（`rust/`、`golden_gen.rs` の正本一致テストを含む）
- **実ブリッジ integration test**（`integration_test/`、ファイルごとに
  `flutter test integration_test/<file> -d macos`（CI では linux -d linux も）、
  #55。1回の `flutter test integration_test` 呼び出しに複数ファイルを渡すと
  デスクトップでは2番目以降のアプリ起動が失敗するため個別に実行する）:
  - `experience_presets_smoke_test.dart`: widget test は `experiencesProvider`
    を fixture に差し替えているため検知できない領域を、`initNativeBridge()`
    経由で実ネイティブライブラリをロードして確認する。`experiences()` の
    4 件・id/分類の内容一致、プリセット欄のタップによる選択状態遷移、全 30
    `VisionFilter` の `visionShaderGlsl()` / `visionUniformLayout()` が例外なく
    呼べること、`initNativeBridge()` の二重初期化が仕様どおり（例外を投げず
    true を返す）であることを検証する。`setUpAll` の `initNativeBridge()` が
    `false` を返した場合（native lib が同梱されていない・壊れている）は
    テスト自体を `fail()` させて検知する（`main()` 側はクラッシュせず
    `NativeBridgeErrorApp` に落ちるが、CI ではそれを「壊れている」として
    検知したいため）
  - `app_bootstrap_test.dart`（#55）: 上記が自前の `setUpAll` で
    先に `initNativeBridge()` を呼んでしまうのに対し、こちらは新しい別プロセス
    （`RustLib` 未初期化）から `main()` が実際に呼ぶ `buildRootApp()` を直接
    呼んで実起動経路そのものを検証する。`buildRootApp()` 内の `initNativeBridge()`
    呼び出しが削除/誤配置される退行（#52 と同種）を、他のテストを変更せずに
    検知するための専用ファイル
  - `cpu_preview_all_filters_test.dart`（#85）: `kVisionFilterCatalog` の全 30
    エントリについて、`VisionFilterState.select()/build()` でカタログ既定値の
    payload を埋めた `VisionFilter` を組み立て、`CpuVisionRenderer.apply()`
    （実ブリッジ）で production と同じ [canonicalSampleSize]（1024、#85）の
    サンプル画像に適用する。例外が出ないこと・出力が入力サイズと
    一致すること・出力ピクセルが入力と異なること（strength=1.0 で全フィルタが
    視覚的に効果を持つ設計であるため）を検証する。加えて protanopia について、
    strength=0.0 が原画とバイト一致すること・strength による出力の違い・
    変化したピクセル比率の下限を検証する（#85）。golden 参照
    （`protanopia_ref.png`）とのバイト一致比較も一度実装したが、
    デスクトップの integration_test はビルド済みアプリとして起動するため
    `File('test/golden/...')` のようなリポジトリルート相対パスが実行時
    カレントディレクトリと一致せず `PathNotFoundException` になり、CI で
    撤去した（ファイルの末尾コメント参照）。同じ数値的主張は rust 側
    `cargo test`（`golden_gen::tests::protanopia_ref_matches_sensus_core`）と
    `test/cpu_vision_renderer_test.dart`（plain `flutter test` は CWD がリポジトリ
    ルートと一致するため file I/O が安全）で引き続き検証している。widget test の
    フェイク注入では検知できない「実際に sensus-core の CPU apply が 30 種
    すべてで動く」ことを保証するのがこのファイルの役割
- **CI**（#38、完了）: `.github/workflows/ci.yml` は2ジョブ構成。`check`
  （macos-latest）が push/PR で上記に加え `flutter build macos --debug` を
  回す（#54）。cargokit 統合（#55）によりこの build が rust/ crate のビルドも
  兼ねるため、Rust toolchain セットアップを build より前に置く。`linux-build`
  （ubuntu-latest、#55）は Linux 側の cargokit 同梱経路（`.so` がバンドルに
  含まれることの確認）と、xvfb 上での実ブリッジ integration test を検証する。
  `Swatinem/rust-cache` によるキャッシュ対象は両ジョブで異なり、`linux-build`
  は cargokit のビルド出力も含めるが、`check`（macOS）は `rust/`（cargo target）
  + crates.io 依存のみキャッシュする
- **タスクトレイ常駐**（#15、完了）: 実機でのトレイ表示・メニュー操作は環境制約
  （Wayland + grim、GNOME のトレイ拡張要件）のため未検証。純粋ロジックの単体テストと
  ビルド成功で代替している（上記「実機目視について」）
- **サンプル画像の文字の出典（#99）**: サンプル生成は OFL の Noto Sans / Noto Sans JP 由来の
  ビットマップフォント（`tools/fonts/`、生成は `tools/generate_font_atlases.py`）で文字を描く。
  `sample_fonts_provenance_test.dart` が Arial 依存の再混入・OFL 全文と出典の同梱・
  フォント本体（TTF/OTF）を入れていないことを固定し、`sample_catalog_test.dart` が
  日本語案内板 `info_board_ja` の看板色と文字の描画を実画素で検証する。
- **プレビュー原画（#78）**: `sample_catalog_test.dart`（カタログ完全性・
  `assets/samples/*.png` が `rootBundle` 経由でデコードでき正準サイズと一致
  すること・`kRecommendedSampleByFilterId` が全 30 catalog id を過不足なく
  カバーすること・文字/グラフ素材の割り当て変更（#78））、`image_source_state_test.dart`
  （自動追従/手動選択の相互排他・同じサンプルの再選択が no-op であること
  ・ユーザー画像の世代管理と dispose・遅延 dispose を
  `SchedulerBinding.scheduleFrame()` を明示的に呼んで検証）、
  `image_fit_test.dart`（レターボックスの余白・source を dispose しない契約）、
  `before_after_view_image_source_test.dart`（`imageSource` 変更時の
  世代管理・再利用、#58/#85 と同じ規律を新しい軸で。source 切替の競合の回帰テストは
  `Completer` で読み込みを保留したまま source を切り替え、最終的に新しい
  source が読み込まれることを検証）、`image_source_picker_test.dart`
  （file_selector/desktop_drop は実 platform channel を要するため
  flutter test では踏めない — `pickImageFile` seam のフェイクと、
  `DropTarget.onDragDone` をウィジェットツリーから見つけて合成
  `DropDoneDetails` で直接呼ぶ手法で実ブリッジなしにデコード経路を検証する。
  50MB 超はファイル本体を読まずに拒否すること・取得からデコードまでが
  単一の try/catch であること（`length()` 自体の失敗も同じ経路で拾われる）の
  専用テストを含む）、`welcome_banner_test.dart`（フォーカス移動・
  キャンセル時に dismiss しない契約）、`home_screen_image_source_test.dart`
  （フィルタ切替で `selectedSampleId` が追従すること。
  `home_screen_preview_*.dart` とは別ファイルにしてコンフリクトを避けている）、
  `first_run_seed_test.dart`（`buildRootApp()` の初回シードのみを狙い撃ちで
  検証。共有トップレベル singleton を直接動かすため `tearDown` で明示的に
  ニュートラル状態へ戻す）が担う

## 今後の拡張

- **聴覚障害対応**: 複合体験の型定義（`HearingFilter` 14 種、`Experience`、`Urgency`。
  FRB 公開済み、#10 部分実装）はあるが、実際の音声加工・再生は未実装。スコープに
  入れるか／サンプル音源デモか／system audio リアルタイム加工かは #20 で検討中
  （旧計画にあった `AudioFilterService` + `audio_filter` プラグインという構成は
  この検討を経ていないため前提としない）
- **視野欠損・視覚ぼやけ等**: sensus-core のカタログには既に含まれ、
  advanced フィルタとして選択・パラメータ調整はできる。live GPU 描画・専用 UI の
  拡張は個別 Issue（#61 等）で順次対応する。運動障害・認知障害は非目標
  （`README.md`「やらないこと（非目標）」参照）
- **depth_aware_blur の配線**（#78 着手コメント参照）: `depth_landscape` の
  深度マップ（`assets/samples/depth_landscape_depth.png`）は素材として同梱
  済みだが、sensus の `depth_aware_blur`（近視/遠視/老視を距離依存のぼけで
  表現する）自体はまだブリッジ経由で公開されておらず、現状のプレビューは
  深度マップを消費しない。ユーザー画像がポートレート写真の場合の XMP 深度
  読み込みも同じ後続 Issue の対象
