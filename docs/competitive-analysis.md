# Competitive Analysis

調査日: 2026-04-30

universal-experience の競合・類似ツールとの比較分析。差別化ポイントを明確にし、宣伝・README の打ち出しに使う。

## カテゴリ別競合一覧

### 1. ルーペ窓型 / 透明常駐オーバーレイ型

| ツール | 開発者 | OS | 屈折異常 | 軸付き乱視 | 色覚モデル | 備考 |
|---|---|---|---|---|---|---|
| **Sim Daltonism** | Michel Fortin | macOS / iOS | ✗ | ✗ | LMS | OSS、クリック透過、8 種色覚 |
| **DaltonLens** | Nicolas Burrus | Win / Mac / Linux | ✗ | ✗ | LMS | GPU 処理、色名取得機能 |
| **VIP-Sim** ★ | Rädler / Colley / Rukzio (UIST 2025) | Win / Mac | △ Gaussian | ✗ | LMS | **最大の事前研究**。21 症状、Webcam アイトラッキング、Unity 製、OSS。著者所属: Universität Ulm（独）+ UCL（英）|
| **Chromatic Vision Sim** | 浅田一憲 | iOS / Android | ✗ | ✗ | LMS | カメラ入力（デスクトップ非対応） |

### 2. システム全体に色覚フィルタを掛ける常駐型（参考）

| ツール | OS | スコープ |
|---|---|---|
| Color Oracle | Win/Mac/Linux | スクショ→別窓表示（追従なし） |
| Visolve | Win/Mac/iPhone | 全画面・領域フィルタ |
| Windows 10/11 カラーフィルター | Windows 標準 | OS 全体 |
| macOS Color Filters | macOS 標準 | OS 全体 |

universal-experience はこの路線を取らない（OS 設定変更ではなく、アプリ層完結）。

### 3. ブラウザ拡張型アクセシビリティシミュレータ

| ツール | 屈折ぼかし | 色覚 | 視野 | 制約 |
|---|---|---|---|---|
| NoCoffee (Chrome/Firefox) | ○ Gaussian | ○ | ○ tunnel/中心暗点 | ブラウザタブ内のみ |
| Funkify | ○ | ○ | ○ | ブラウザタブ内のみ |
| Stark | ○ Blurred Vision | ○ | ✗ | Figma / ブラウザ |
| Microsoft Edge DevTools | ○ | ○ | ✗ | DevTools パネル内 |

ブラウザ内に閉じる。ネイティブアプリ・動画・ゲーム画面には適用不可。

### 4. 研究プロトタイプ

| 研究 | 年 | 形態 |
|---|---|---|
| **VIP-Sim** (arXiv:2507.10479) | 2025 / UIST | デスクトップオーバーレイ、21 症状、Unity |
| Smart Glasses-based Simulation | 2022 / UIST | スマートグラス装着型 |
| Immersive Simulation of Visual Impairments | 2015 / TEI | see-through HMD |

### 5. VR / AR / 物理デバイス

- **Cambridge Simulation Glasses** — 物理眼鏡（色覚・視野・グレア対象外）
- **Cambridge Impairment Simulator Software** — 静止画ベース、軸付き乱視は扱う
- **Low Vision Simulator (VisionAid)** — VR ヘッドセット 20 種

## universal-experience の差別化点

### 強み

1. **物理光学ベースの屈折異常 + 軸付き乱視を OS 任意アプリにリアルタイム適用**
   - Smith-Helmholtz `θ ≈ pupil × |D|` による度数→画素半径換算
   - linear sRGB 空間での disk blur（Gaussian ではなく pillbox = 真の defocus 点像）
   - 軸角度指定可能な 1D directional blur による真の乱視シミュレーション
   - **VIP-Sim ですら屈折は Gaussian 中心で、軸付き乱視まで含む常駐ルーペは確認できず**

2. **Rust crate (sensus) としてアルゴリズム正本を分離**
   - CPU 実装と GLSL シェーダソースの両方を提供、CI で等価性保証
   - crates.io 公開で OSS 視覚シミュレーション基盤として再利用可能
   - 競合は単体アプリ実装でロジック再利用できず

3. **4 OS ネイティブ対応（Win / Mac / Linux / Android）**
   - Sim Daltonism は macOS/iOS、DaltonLens は Win/Mac/Linux のみ
   - **Android 対応のデスクトップ型ルーペは皆無**（CVS はカメラ入力のみ）

4. **医学的注記の併載**
   - 各フィルタに「こうなったらすぐ病院へ」を併記
   - 体験ツール + 早期発見の予備知識ツールという二重価値
   - 競合では VIP-Sim ですら教育向けで医学的緊急度の併記はない

### 弱み（現時点）

- **新参**：Sim Daltonism は 2013〜、Color Oracle は 2007〜、VIP-Sim も 2025 UIST 採択済みで認知度が高い。後発として実装品質と差別化の打ち出しで勝負する必要あり
- **デモ動画・サンプル不足**：Sim Daltonism や VIP-Sim はデモ動画が豊富。比較動画 / カラーチャート比較を出して説得する必要
- **VIP-Sim は学術論文付き**：これは強い。universal-experience も技術記事を充実させて補う

### 「世界初」と言える範囲（限定句で正確に）

宣伝で使ってよい：

- ✅ **「乱視軸を含む物理光学ベースの屈折異常を扱う、OS 常駐ルーペ型シミュレータ」として世界初候補**
- ✅ **クロスプラットフォーム視覚シミュレーションの Rust crate として OSS 公開する初の試み**

宣伝で使ってはいけない（先行あり）：

- ❌ ルーペ窓型シミュレータそのもの（Sim Daltonism 2013〜）
- ❌ デスクトップ任意アプリへの透明オーバーレイ（VIP-Sim 2025）
- ❌ 色覚 + ぼかしの組み合わせ（NoCoffee / Funkify / VIP-Sim）

## 戦略的示唆

VIP-Sim 論文 (UIST 2025) が最大の事前研究。kako-jun の打ち出しは：

- (a) **物理光学ベースの屈折モデル**（VIP-Sim を上回る精度）
- (b) **クロスプラットフォーム + モバイル**（Android が空白地帯）
- (c) **Rust crate 化**（OSS 基盤としての再利用性）

この 3 点を README・宣伝記事の冒頭に置く。「世界初の○○シミュレータ」と単純に言うより、「**乱視軸を含む光学的屈折を扱う初の常駐ルーペ**」という限定句で打ち出すのが正確かつ強い。

## VIP-Sim 監査の更新（#6, 2026-06-22）

実装が進んだ段階で VIP-Sim を参照ベンチに再対照した（#6）。要点:

- **ライセンス**: VIP-Sim は **CC BY 4.0**（arXiv:2507.10479, UIST 2025, Unity, Win/Mac）。派生・比較利用時は出典表示で扱える。
- **ue が広い**: 対応症状は **30 種**（VIP-Sim は 21 種）、軸付き乱視・物理光学屈折、Android、OSS Rust crate（sensus）、受診喚起の併載、聴覚ロードマップ。
- **ue が決定的に遅れている点（正直に）**: VIP-Sim を「今日使える物」にしている **リアルタイム画面キャプチャが ue では未稼働**。ue は現状、合成したデモ画像に対してのみフィルタを適用し、**ライブ描画は protanopia / protanomaly のみ**。この差は既存の #1（親）/#3/#4/#5 で追跡中。
- **VIP-Sim の新規性の柱**: ① **視線追従（gaze-contingent）** webcam + マウス、② **複数症状の同時適用（compositing）**（"one or multiple symptoms"）。ue は前者を #42、後者を #41 として起票済み（いずれも現状は未実装）。
- **ue の差別化（VIP-Sim に無い）**: フィルタ済み画像のメタ焼き込み **PNG エクスポート**（#43 実装済み）。

打ち出しの注意: live キャプチャと compositing が稼働するまでは「常駐ルーペとして VIP-Sim を代替できる」とは言わない。**精度（linear sRGB / disk blur / 軸付き乱視）・症状網羅・Rust crate・Android・受診喚起**という、現に手元にある強みに限定して訴求する。

## 出典

| URL | 種別 | 確認日 |
|---|---|---|
| https://michelf.ca/projects/mac/sim-daltonism/ | Sim Daltonism 公式 | 2026-04-30 |
| https://github.com/michelf/sim-daltonism/ | Sim Daltonism GitHub | 2026-04-30 |
| https://colororacle.org/ | Color Oracle | 2026-04-30 |
| https://github.com/DaltonLens/DaltonLens | DaltonLens | 2026-04-30 |
| https://www.ryobi.co.jp/products/visolve/en/ | Visolve | 2026-04-30 |
| https://asada.website/cvsimulator/e/ | Chromatic Vision Sim | 2026-04-30 |
| https://addons.mozilla.org/en-US/firefox/addon/nocoffee/ | NoCoffee | 2026-04-30 |
| https://www.funkify.org/simulators/vision-simulator/ | Funkify Vision | 2026-04-30 |
| https://www.getstark.co/blog/blurred-vision/ | Stark Blurred Vision | 2026-04-30 |
| https://learn.microsoft.com/en-us/microsoft-edge/devtools/accessibility/emulate-vision-deficiencies | Edge DevTools | 2026-04-30 |
| **https://arxiv.org/abs/2507.10479** | **VIP-Sim (UIST 2025) ★最大の競合** | 2026-04-30 |
| https://github.com/Max-Raed/VIP-Sim | VIP-Sim GitHub | 2026-04-30 |
| https://dl.acm.org/doi/10.1145/3526113.3545687 | Smart Glasses Simulation | 2026-04-30 |
| https://dl.acm.org/doi/10.1145/2677199.2680551 | Immersive Simulation HMD | 2026-04-30 |
| https://www.inclusivedesigntoolkit.com/csg/csg.html | Cambridge Simulation Glasses | 2026-04-30 |
| https://www.inclusivedesigntoolkit.com/simsoftware/simsoftware.html | Cambridge Impairment Sim Software | 2026-04-30 |
| https://www.visionaid.co.uk/low-vision-simulator-lvs | Low Vision Simulator VR | 2026-04-30 |
| https://daltonlens.org/opensource-cvd-simulation/ | DaltonLens 比較レビュー | 2026-04-30 |
