# サンプル画像集（#78）

このディレクトリの PNG はすべて**自作・手続き的生成**です。外部素材のダウン
ロード・スクリーンショット・写真は一切使っていません。**人物の顔は含みません**。

## 生成方法

[`tools/generate_samples.dart`](../../tools/generate_samples.dart)
（`dart run tools/generate_samples.dart`）が
[`package:image`](https://pub.dev/packages/image)（純 Dart のラスタライザ。
`pubspec.yaml` の `dev_dependencies` にのみ入っており、アプリ本体には
含まれない）で矩形・円・多角形・線を組み合わせて手続き的に描画し、このディレ
クトリへ書き出します。テキストは `package:image` に同梱されたビットマップ
フォント（Arial 14/24/48）を使っており、外部フォントファイルは一切読み込みま
せん。夜景の点光源の配置は固定シードの疑似乱数なので、再生成しても常に同じ
バイト列になります。

正準サイズは 1024×1024px
（`BeforeAfterView.canonicalSampleSize`、Issue #85）に揃えています。

## 一覧

| ファイル | 場面 | 相性の良いフィルタの例 |
|---|---|---|
| `route_map.png` | 路線図（色で区別する複数路線、駅・番号のラベル） | 色覚（achromatopsia）・複視・歪視 |
| `chart.png` | 凡例付きのグラフ（赤・緑・青・橙の 4 系列） | 色覚（tetrachromacy）・きらめき視 |
| `traffic_signs.png` | 信号（赤が点灯・黄/緑は消灯）・標識（警告三角・太いリングの禁止円・案内四角） | 色覚（protanopia）・視野 |
| `info_board.png` | 文字の多い案内板（見出し arial48、本文は最小でも arial24） | 屈折異常（astigmatism 含む）・眼精疲労・白内障・飛蚊症・detail_loss |
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
