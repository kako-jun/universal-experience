# Architecture Design

> **現状**: 当初設計にあった system-wide フィルタ機構（`color_vision_filter`
> プラグイン／`ColorVisionFilter.apply` 等、「Platform Channel Layer」「Native
> Implementation Layer」「OS-Specific Filter Application」と呼んでいたもの）の
> 撤去経緯・判断根拠は、当該節を ADR に畳んだ
> `docs/adr/2026-05-31-sensus-core-consolidation.md` を参照。色覚アルゴリズムの
> 正本は sensus-core crate（Rust）に一元化し、ue は flutter_rust_bridge 経由で
> 消費する（`lib/src/rust/`、詳細は `docs/sensus-integration.md`）。フィルタ適用は
> sensus 由来の GPU シェーダ（`lib/rendering/shader_filter.dart`）が担い、
> `FilterService` は選択状態のみを保持する。他アプリ含む全画面への適用は
> 画面キャプチャ経路（#1/#3/#4）の実装後。
>
> **追補（現状）**: 以下も実装済み。多言語化（#18・`flutter_localizations` +
> ARB、ja/en、`lib/l10n/`）、sensus の複合体験 API の FRB 公開（#10・
> `experiences()` / `Experience` / `Urgency` / `HearingFilter`、ただし音声再生は
> 未実装）、体験プリセット集 UI（#19・`lib/ui/widgets/experience_presets.dart`）、
> フィルタ済み画像のメタ焼き込み PNG エクスポート（#43・
> `lib/services/export_service.dart`）。色覚のクイック選択で描画できない型は
> 「描画は近日対応」のプレースホルダを出す。advanced カタログ・体験プリセットの
> 選択は `VisionFilterState` に入るだけでプレビューには反映されない（#60）。
> プリセットのタップでは `FilterService` が deactivate され、before/after
> 両ペインとも原画のままになる（#60）。

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
8. **終了** — トレイを破棄し `setPreventClose(false)` の上で
   `windowManager.destroy()`

### ウィンドウクローズ・ポリシー

**ウィンドウを閉じても終了せず、トレイに最小化される (close = トレイ常駐)。**
明示的な終了はトレイの "終了" のみ。`main.dart` で
`windowManager.setPreventClose(true)` + `onWindowClose` → `windowManager.hide()`
で実装している。

ただしトレイから復帰できなければアプリが行方不明になるため、トレイ初期化が
**失敗した環境では close = 終了** にフォールバックする (`resolveCloseAction()` が
この判断を純粋関数として表現し、テスト済み)。よって `setPreventClose` の適用は
トレイ初期化の成否で決める。

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
sensus-core (Rust, GLSL + uniform 計算の正本)
      ↓
ShaderFilter (lib/rendering/) — Impeller FragmentProgram で ui.Image に適用
```

状態管理は Provider の `ChangeNotifier` ベース: `FilterService` /
`VisionFilterState` が状態変更時に `notifyListeners()` を呼び、それを購読する
`Consumer` を持つウィジェットだけが rebuild される。

### 主要コンポーネント

- `HomeScreen`: メイン画面。色覚クイック選択・強度スライダ・before/after プレビュー・
  advanced カタログ・体験プリセット・PNG エクスポートをまとめる
- `FilterService`: 色覚フィルタ（`ColorVisionType`）の選択状態管理。
  sensus `VisionFilter` へのマッピングを持つ純粋な状態モデル
- `VisionFilterState`: advanced カタログ（sensus 全 30 種）の選択・パラメータ状態
- `ShaderFilter`（`lib/rendering/shader_filter.dart`）: sensus 由来 GLSL を変換した
  Impeller `FragmentProgram` で `ui.Image` にフィルタを適用する。ライブ描画は
  protanopia（と、その強度を下げて流用する protanomaly）のみ。deuteranopia /
  tritanopia / achromatopsia は GPU golden テストで検証済みだが UI には未配線
  （#59）
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
  検証・体験プリセット等を含む
- **GPU golden テスト**（`test/vision_filter_golden_test.dart` /
  `test/protanopia_golden_test.dart`）: sensus-core 正本由来の参照 PNG と GPU 描画結果を
  PSNR/maxDiff で比較（詳細は `docs/sensus-integration.md` §6）
- **Rust 側**: `cargo test`（`rust/`、`golden_gen.rs` の正本一致テストを含む）
- **CI**（#38、完了）: `.github/workflows/ci.yml` が push/PR で上記を回す
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
