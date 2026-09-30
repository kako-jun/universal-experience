# サンプル画像用ビットマップフォント（#99）

`assets/samples/*.png` に描き込む文字のためのフォントです。アプリ本体には
含まれません（`pubspec.yaml` の assets に入っておらず、`tools/generate_samples.dart`
だけが読みます）。

## 出典とライセンス

ここにある `*.fnt` / `*.png`（BMFont 形式のビットマップフォントとアトラス）は、
次の **SIL Open Font License 1.1（OFL）** のフォントから、サンプル画像に使う
文字だけを固定サイズでラスタライズした派生物です。派生物も OFL の下にあります。

| 出力 | 元のフォント | 著作権表示 | ライセンス全文 |
|---|---|---|---|
| `noto_sans_*` | Noto Sans Regular / Bold（notofonts/latin-greek-cyrillic、`notofonts.github.io` の版 `025970232f4f8ff349310d9785431e87d20ed27c` の `fonts/NotoSans/full/ttf/`） | Copyright 2022 The Noto Project Authors (https://github.com/notofonts/latin-greek-cyrillic) | [`OFL-NotoSans.txt`](OFL-NotoSans.txt) |
| `noto_sans_jp_*` | Noto Sans CJK JP（配布名 Noto Sans JP）Regular / Bold（`notofonts/noto-cjk` の版 `f8d157532fbfaeda587e826d4cd5b21a49186f7c` の `Sans/SubsetOTF/JP/`） | Copyright 2014-2021 Adobe (http://www.adobe.com/), with Reserved Font Name 'Source' | [`OFL-NotoSansJP.txt`](OFL-NotoSansJP.txt) |

- 配布元: <https://github.com/notofonts/notofonts.github.io>・<https://github.com/notofonts/noto-cjk>
  （ライセンス全文は <https://github.com/google/fonts> の `ofl/notosans/OFL.txt`・`ofl/notosansjp/OFL.txt`、
  版 `24ecb0bbdc3a52d6fddef160b769c61463f455d9` と同一）。
- Noto Sans JP の予約フォント名（Reserved Font Name）は `Source` です。この派生物の名前は
  `noto_sans_jp_*` で、`Source` を含みません。各 `.fnt` の `info face` も元のフォント名
  ではなく派生名（`NotoSansJP-Bold-BitmapSubset` のように `-BitmapSubset` を付けたもの）に
  しています。
- フォントのソフトウェア本体（TTF/OTF）はこのリポに入れていません。入っているのは、
  サンプルに使う文字だけを含むビットマップのアトラスです。
- サンプル画像（PNG）に描かれた文字は、フォントのグリフを画素として描いた出力であり、
  OFL の制約は画像には及びません（出典は `assets/samples/README.md` に明記）。

## 収録文字とサイズ

| ファイル | サイズ | 収録 |
|---|---|---|
| `noto_sans_regular_18` | 18px | 夜景の看板「OPEN」の文字 |
| `noto_sans_regular_24` | 24px | 英大文字・数字・`:`・空白・`-`（駅ラベル、案内板の時刻・地名・補足行） |
| `noto_sans_bold_48` | 48px | 「INFORMATION」「!」「P」の文字 |
| `noto_sans_jp_regular_24` | 24px | 数字・`:`、日本語の案内板の表（「1番線」〜「6番線」・行き先・補足行）に出る文字 |
| `noto_sans_jp_bold_48` | 48px | 「のりば案内」 |
| `noto_sans_jp_bold_96` | 96px | 「出口」「駅」「営業中」 |

収録文字は、サンプル画像で実際に描く文字列だけから導いています
（`tools/generate_font_atlases.py` の文字集合。`tools/generate_samples.dart` の
文字列と対応させます）。

`tools/generate_samples.dart` は、収録外の文字を描こうとすると例外で止まります
（黙って欠落させません）。文字を増やすときは `tools/generate_font_atlases.py` の
文字集合に足して再生成します。

## 再生成

```sh
uv run --with pillow==12.3.0 python3 tools/generate_font_atlases.py
dart run tools/generate_samples.dart
```

前者は固定した版のフォントを公式配布元から取得し（SHA-256 を検証、作業ディレクトリは
実行後に削除）、ここへアトラスを書き出します。Pillow の版を固定し、グリフ順・パッキングも決定的です。
同一環境（同じ Pillow / FreeType）で 2 回実行して全 `*.fnt` / `*.png` のバイト列が
一致することを確認しています（別の版・別の環境での一致までは保証しません）。

この再生成結果とコミット済みの `*.fnt` / `*.png` が一致することは CI
（`font-atlas-sync` ワークフロー、`.github/workflows/font-atlas-sync.yml`）が
検証します。`tools/generate_font_atlases.py` や `tools/fonts/` を変えた push/PR と手動実行（`workflow_dispatch`）だけで
起動します。落ちたら上のコマンドで再生成して差分をコミットし、アトラスが変わったときは
`dart run tools/generate_samples.dart` で `assets/samples/*.png` も更新します
（こちらは `samples-sync` ワークフローが検証します）。スクリプトが作らなくなった古い
アトラスが差分（削除）に出た場合は、手元でも `git rm` します。
