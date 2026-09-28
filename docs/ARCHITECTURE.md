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
> `FilterService` は選択状態のみを保持する。他アプリ含む全画面への適用は
> 画面キャプチャ経路（#1/#3/#4）の実装後。
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
> （`FilterSelector`/トレイ）は `lib/services/color_vision_selection.dart` の
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

## ルーペ窓挙動 (#14)

ルーペ窓のウィンドウ設定の責務。実装は `lib/services/loupe_window_controller.dart`
(window_manager ラッパ + 純粋ロジック `LoupeWindowPolicy`) と `lib/main.dart` の配線。
画面キャプチャ (#3/#4/#5)・ライブ適用・描画 (#11)・フィルタ UI (#16)・トレイ (#15) は本節のスコープ外。

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
  **実機目視で確認が必要 (#11 後)**。

### リサイズ追従

`WindowListener.onWindowResize` でサイズを取得し state 更新 -> `onChanged`
コールバックで UI に伝える (中身がウィンドウに貼り付く責務)。

### 透過・最前面・クリックスルー (既定方針)

- **透明背景**: 既定 ON。枠の外は完全透過、枠の中だけ描画 (VIP-Sim / Sim Daltonism 型, #6)。
  `WindowOptions.backgroundColor = transparent`。
- **最前面**: 既定 ON (`setAlwaysOnTop(true)`)。下のアプリより手前にいないと
  「かざして見る」が成立しない。
- **クリックスルー**: 既定 **OFF**、切替式。起動直後は窓を掴んで移動・リサイズ
  したいのでイベントを受け取り、下のアプリを操作したいときユーザーが ON する。
  実装は `setIgnoreMouseEvents(true, forward: true)`。
- **クリックスルーの `forward` はプラットフォーム差あり**: `forward` 引数は
  **macOS 専用**で、Linux/Windows では window_manager 側で無視される。Linux では
  「自ウィンドウがイベントを無視する」までは効くが、「下のアプリへ転送する」挙動は
  forward では保証されない (コンポジタ/OS 依存)。クリックスルー時に下のアプリを
  実際に操作できるかは **Linux 実機での確認が必要 (#11 後)**。
- フレームレス/クリックスルー forward 引数はプラットフォーム差・未対応があるため、
  全 window_manager I/O は try/catch + ログで握り、未対応でも落とさない。

### タスクトレイ (#15)

デスクトップ版はタスクトレイ (通知領域 / メニューバー) に常駐する。実装は
`lib/services/tray_service.dart` (tray_manager 0.2.4 ラッパ) と `lib/main.dart`
の配線から成る。

### 構成 (純粋ロジックと副作用の分離)

`tray_service.dart` は 2 層に分かれている。

- **純粋ロジック層** (`TrayMenuKind` / `TrayMenuEntry` /
  `quickColorVisionFilters()` / `buildTrayMenuSpec()` / `trayToggleLabel()` /
  `resolveCloseAction()`) — 「トレイメニューに何を出すか」をデータとして表現する。
  tray_manager に一切依存しないため、ウィンドウシステム無しで単体テストできる
  (`test/tray_service_test.dart`、15 件)。
- **`TrayService`** — tray_manager を叩く副作用層。上記スペックを実際の
  `Menu` / `MenuItem` に変換し、クリックを `FilterService` (#14) と、main.dart
  から注入されるウィンドウ表示/非表示コールバックに橋渡しする。

メインウィンドウ自体がルーペ窓 (#14)。`LoupeWindowController` は枠/モード/透過の
責務を持つが show/hide は持たないため、トレイの「ルーペ窓を表示/隠す」は
main.dart が `windowManager.show()` / `hide()` を `onShowLoupe` / `onHideLoupe`
として `TrayService` に注入して実現する。

### メニュー構成

上から順に:

1. **ルーペ窓を表示 / 隠す** — トグル (注入された `windowManager.show()` /
   `hide()` を呼ぶ。ラベルは現在の表示状態で切替)
2. (区切り線)
3. **即切替フィルタ** (`quickColorVisionFilters()`) — よく使う色覚シミュレーションを
   直接適用: Protanopia / Deuteranopia / Tritanopia / Achromatopsia。
   `FilterService.applyFilter()` を呼び、アクティブなものにチェックが付く。全フィルタ
   catalogue は設定 UI (#16) にあり、トレイは短く保つため代表のみ出す。
4. **フィルタを解除** — `FilterService.deactivate()`
5. (区切り線)
6. **設定を開く…** — フィルタ選択 UI はメインウィンドウ内にあるため
   `windowManager.show()` + `focus()` でウィンドウを表示する
7. (区切り線)
8. **終了** — 先頭で `FilterService.flush()`（#57、保留中の intensity
   デバウンス書き込みを取りこぼさない）した上で、トレイを破棄し
   `setPreventClose(false)` の上で `windowManager.destroy()`

### ウィンドウクローズ・ポリシー

**トレイが使える環境では、ウィンドウを閉じても終了せず、トレイに最小化される
(close = トレイ常駐)。** 明示的な終了はトレイの "終了" のみ。

`windowManager.setPreventClose(true)` はトレイの有無に関わらず常に掛ける
(`main.dart` `_setUpTray`)。`onWindowClose` の中で `resolveCloseAction()`
(純粋関数、テスト済み) の結果を見て分岐する:

- **トレイが使える環境 (`hideToTray`)** — `windowManager.hide()` するだけ。
- **トレイ初期化が失敗した環境 (`exitApp`)** — トレイから復帰できずアプリが
  行方不明になるため close = 終了にフォールバックする。ただし intensity の
  デバウンス永続化 (#57) を取りこぼさないよう、`FilterService.flush()` →
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

## フォロー事項: アプリモード切替 (#14/#16)

現状は起動直後から「透明背景 ON・最前面 ON」を常時適用している。しかしフィルタ
選択 UI (#16) を操作するときは、最前面・透明だと UI が背後のアプリと重なって
操作しづらく、他ウィンドウへも移りにくい。

将来は次の2モードを切り替える想定:

| モード | 透明 | 最前面 | ウィンドウ | 用途 |
|---|---|---|---|---|
| 設定モード (settings) | OFF | OFF | 通常 | フィルタ選択など UI 操作。**起動既定にしたい** |
| ルーペモード (loupe) | ON | ON | 透明・最前面 | 実際に画面へかざして見る |

実装時は `LoupeWindowController` に `setSettingsMode(bool)` / `setLoupeMode(bool)`
の口を用意し、`main` の起動既定を「設定モード=通常ウィンドウ」にする。
**本 PR (#14) ではスコープ外**のため、起動既定 (透明・最前面 ON) は現状維持。
該当箇所には `lib/services/loupe_window_controller.dart` と `lib/main.dart` に
TODO コメントを残してある。

### マルチモニタ

- **第1弾はメインモニタのみ対象**。サブモニタへの移動追従や、モニタごとの
  DPR 換算 (#5) はスコープ外。window_manager のメインモニタ座標系で動作する前提。

### 実機目視について

透過・クリックスルー・最大化時の縁などの GUI 目視確認は、Wayland/grim 制約と
#11 描画統合前のため本実装段階では未実施。`flutter analyze` / `flutter test` /
`flutter build linux --debug` で静的・ビルド確認のみ。実機目視は #11 描画統合後に行う。

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

`rust/` crate は `rust_builder/`（cargokit 統合、#55）経由でビルドされ、
macOS / Linux アプリに同梱される。`lib/main.dart` の `buildRootApp()`（#55
レビュー M1 で `main()` から切り出したルート Widget 組み立て関数）が `runApp`
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
（既定で新規 `SettingsService()`）を差し替え可能な引数に取る。windowManager /
trayService の初期化・配線は `buildRootApp()` の外、`main()` 内に閉じたまま
残している（デスクトップ専用の副作用をブリッジ初期化のテストに持ち込まない
ため）。`integration_test/app_bootstrap_test.dart`（#55 レビュー M1）は
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

- `HomeScreen`: メイン画面。色覚クイック選択・強度スライダ・before/after プレビュー・
  advanced カタログ・体験プリセット・PNG エクスポートをまとめる
- `FilterService`: 色覚フィルタ（`ColorVisionType`）の選択状態管理。
  sensus `VisionFilter` へのマッピングを持つ純粋な状態モデル。強度
  （`intensity`）はタイプごとに `Map<ColorVisionType, double>` で個別記憶し、
  初めて選ぶタイプは推奨強度（-opia/achromatopsia=1.0、-omaly=0.6）が初期値
  になる（#57）。永続化・通知も本サービス自身が担う（300ms デバウンスした
  SharedPreferences 書き込み + 自前の `ChangeNotifier`）。`SettingsService`
  は `notifyListeners` を購読する `MaterialApp`（テーマ/ロケール用）を持つため、
  intensity のようにスライダー 1 目盛りごとに変わる値をそちらに混ぜると
  アプリ全体が毎回再構築されてしまう。それを避けるため intensity は
  `SettingsService` を経由しない。一方 filterType（どのタイプを選んでいるか）は
  `SettingsService.setFilterType` 経由で引き続き通知・永続化する。フィルタの
  選び直しはユーザー操作としてスライダー操作ほど高頻度ではないため、
  `MaterialApp` 再構築が起きること自体は許容している
- `VisionFilterState`: advanced カタログ（sensus 全 30 種）の選択・パラメータ状態
- `CpuVisionRenderer`（`lib/rendering/cpu_vision_renderer.dart`）: sensus の CPU
  `apply()`（`applyVisionCpuRgba8`）で `ui.Image` にフィルタを適用する、
  **プレビュー（静止画）描画の正本**（#85）。`ui.Image` → straight RGBA8
  （`ImageByteFormat.rawStraightRgba`）→ 実ブリッジ呼び出し → premultiply →
  `ui.Image`（`ImmutableBuffer`/`ImageDescriptor.raw`/`instantiateCodec` の
  await 連鎖。`decodeImageFromPixels` は使わない — デコード失敗時にコール
  バックが呼ばれず呼び出し元がハングし得るため）の往復のみを行い、
  アルゴリズムは一切持たない。sensus は straight alpha、Flutter の `ui.Image`
  は premultiplied alpha を前提とするため、境界でこの変換を明示的に行う
  （#85 レビュー S1）。任意の `VisionFilter`（payload 込み）を受け取れるため
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
  プレビューペイン。#85 レビュー S4 で、ペインの論理サイズ・
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
  `_rebuild` の実行を直列化し（同時に走るジョブは常に1本、#85 レビュー S3）、
  スライダーを連続操作しても実ブリッジ呼び出しが積み上がらないようにしている
  （#58 の世代管理・dispose・失敗表示の規約自体は変更していない）
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
- `ExportService`: フィルタ適用後（after）画像のメタ焼き込み PNG エクスポート
- `ExperiencePresets`（`lib/ui/widgets/experience_presets.dart`）: sensus の
  `experiences()` をワンタップ適用 UI として消費する（複合体験、#19）

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
  常に1本、#85 レビュー S3）も検証する。`cpu_vision_renderer_test.dart` は
  実ブリッジなしで検証できる部分（straight⇄premultiplied 変換の正しさ・
  `ImageDescriptor.raw` 経路のデコード失敗が例外として伝わること、#85 レビュー
  S1/S2）を担う
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
  - `app_bootstrap_test.dart`（#55 レビュー M1）: 上記が自前の `setUpAll` で
    先に `initNativeBridge()` を呼んでしまうのに対し、こちらは新しい別プロセス
    （`RustLib` 未初期化）から `main()` が実際に呼ぶ `buildRootApp()` を直接
    呼んで実起動経路そのものを検証する。`buildRootApp()` 内の `initNativeBridge()`
    呼び出しが削除/誤配置される退行（#52 と同種）を、他のテストを変更せずに
    検知するための専用ファイル
  - `cpu_preview_all_filters_test.dart`（#85）: `kVisionFilterCatalog` の全 30
    エントリについて、`VisionFilterState.select()/build()` でカタログ既定値の
    payload を埋めた `VisionFilter` を組み立て、`CpuVisionRenderer.apply()`
    （実ブリッジ）で production と同じ [canonicalSampleSize]（1024、#85 レビュー
    S4）のサンプル画像に適用する。例外が出ないこと・出力が入力サイズと
    一致すること・出力ピクセルが入力と異なること（strength=1.0 で全フィルタが
    視覚的に効果を持つ設計であるため）を検証する。加えて protanopia について、
    strength=0.0 が原画とバイト一致すること・strength による出力の違い・
    変化したピクセル比率の下限を検証する（#85 レビュー S7）。golden 参照
    （`protanopia_ref.png`）とのバイト一致比較も S7 で一度実装したが、
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

## 今後の拡張

- **聴覚障害対応**: 複合体験の型定義（`HearingFilter` 14 種、`Experience`、`Urgency`。
  FRB 公開済み、#10 部分実装）はあるが、実際の音声加工・再生は未実装。スコープに
  入れるか／サンプル音源デモか／system audio リアルタイム加工かは #20 で検討中
  （旧計画にあった `AudioFilterService` + `audio_filter` プラグインという構成は
  この検討を経ていないため前提としない）
- **視野欠損・視覚ぼやけ・運動障害等**: sensus-core のカタログには既に含まれ、
  advanced フィルタとして選択・パラメータ調整はできる。live GPU 描画・専用 UI の
  拡張は個別 Issue（#59 等）で順次対応する
