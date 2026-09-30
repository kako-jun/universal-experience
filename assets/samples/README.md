# サンプル画像集（#78）

このディレクトリの PNG は、図形を自作し手続き的に生成しています。外部の画像素材・
スクリーンショット・写真は一切使っていません。**人物の顔は含みません**。画像に
描かれた文字だけは SIL OFL 1.1 のフォント（Noto Sans / Noto Sans JP）で描いています
（下の「文字の出典」）。

## 生成方法

[`tools/generate_samples.dart`](../../tools/generate_samples.dart)
（`dart run tools/generate_samples.dart`）が
[`package:image`](https://pub.dev/packages/image)（純 Dart のラスタライザ。
`pubspec.yaml` の `dev_dependencies` にのみ入っており、アプリ本体には
含まれない）で矩形・円・多角形・線を組み合わせて手続き的に描画し、このディレ
クトリへ書き出します。テキストは [`tools/fonts/`](../../tools/fonts/) のビット
マップフォント（BMFont 形式）で描きます（`package:image` 同梱の Arial ビット
マップは使いません）。夜景の点光源の配置は固定シードの疑似乱数なので、再生成
しても常に同じバイト列になります。

## 文字の出典（#99）

| 用途 | フォント | 版 | ライセンス | 配布元 |
|---|---|---|---|---|
| 英数字（路線図・グラフ・標識・案内板・夜景の看板） | Noto Sans Regular / Bold | [`notofonts.github.io` の `025970232f4f8ff349310d9785431e87d20ed27c`](https://github.com/notofonts/notofonts.github.io/tree/025970232f4f8ff349310d9785431e87d20ed27c/fonts/NotoSans/full/ttf) | SIL OFL 1.1（Copyright 2022 The Noto Project Authors） | <https://github.com/notofonts/latin-greek-cyrillic> |
| 日本語（日本語の案内板） | Noto Sans JP（Noto Sans CJK JP）Regular / Bold | [`noto-cjk` の `f8d157532fbfaeda587e826d4cd5b21a49186f7c`](https://github.com/notofonts/noto-cjk/tree/f8d157532fbfaeda587e826d4cd5b21a49186f7c/Sans/SubsetOTF/JP) | SIL OFL 1.1（Copyright 2014-2021 Adobe (http://www.adobe.com/), with Reserved Font Name 'Source'） | <https://github.com/notofonts/noto-cjk> |

フォント本体（TTF/OTF）はリポに入れていません。サンプルに使う文字だけを固定
サイズでラスタライズしたアトラスを `tools/fonts/` に置いています（生成は
`tools/generate_font_atlases.py`）。ライセンス全文・著作権表示・再生成手順は
[`tools/fonts/README.md`](../../tools/fonts/README.md)。OFL は、フォントで描いた
出力（この PNG）には制約を課しません。

正準サイズは 1024×1024px
（`BeforeAfterView.canonicalSampleSize`、Issue #85）に揃えています。

## 一覧

| ファイル | 場面 | 相性の良いフィルタの例 |
|---|---|---|
| `route_map.png` | 路線図（色で区別する複数路線、駅・番号のラベル） | 色覚（achromatopsia）・複視・歪視 |
| `chart.png` | 凡例付きのグラフ（赤・緑・青・橙の 4 系列） | 色覚（tetrachromacy）・きらめき視 |
| `traffic_signs.png` | 信号（赤が点灯・黄/緑は消灯）・標識（警告三角・太いリングの禁止円・案内四角） | 色覚（protanopia）・視野 |
| `info_board.png` | 文字の多い案内板（見出し Noto Sans Bold 48px、本文は最小でも 24px） | 屈折異常（astigmatism 含む）・眼精疲労・白内障・飛蚊症・detail_loss |
| `info_board_ja.png` | 日本語の案内板（「出口」「駅」「営業中」の大きな看板 + 小さな文字の「のりば案内」表。一般的な語のみで、実在の固有名・商標は使わない） | 屈折異常・眼精疲労・白内障・飛蚊症・detail_loss（日本語の細かい字画での読みにくさ） |
| `fruit_stand.png` | 食べ物・果物（熟した赤 vs 未熟な緑、柑橘の橙・黄、ぶどう・プラムの紫・青） | 色覚（protanopia/deuteranopia/tritanopia） |
| `night_scene.png` | 夜景（暗いグラデーション + ビルのシルエット + 低輝度の窓の格子 + 街路灯 + 照明看板 + 小さな点光源多数。広いベタ白は置いていない） | 夜盲・starbursts・flickering_stars |
| `depth_landscape.png` | 奥行きのある風景（遠景の山並み・中景の地面と木立と家・近景のフェンスと茂み） | 視野欠損・畏光（photophobia、明るい空）・前庭系（時間依存フィルタの静止フレーム） |
| `depth_landscape_depth.png` | `depth_landscape.png` の深度マップ | （下記参照。プレビューでは未消費、Issue #98） |

フィルタごとの既定サンプルの対応表は
[`lib/models/sample_catalog.dart`](../../lib/models/sample_catalog.dart) の
`kRecommendedSampleByFilterId` が正本です。

## 深度マップ（`depth_landscape_depth.png`）

`depth_landscape.png` と同じレイアウトの 8bit グレースケール画像です。
**明るいほど近い・暗いほど遠い**という規約でエンコードしています
（遠景の山並みは暗いグレー、近景のフェンス・茂みは明るいグレー）。

sensus 側の `depth_aware_blur`（近視・遠視・老視を距離依存のぼけで再現する
処理）はまだ flutter_rust_bridge 経由で公開されていないため、この深度マップは
**素材として同梱するだけ**で、プレビューでは消費していません。配線は
**Issue #98** で対応予定です（`docs/ARCHITECTURE.md`「今後の拡張」参照）。
