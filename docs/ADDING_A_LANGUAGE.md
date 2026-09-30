# 言語の追加手順と医学用語の訳の確認方針

アプリ内の言語ピッカー（AppBar の地球儀ボタン、#82）は「自動」と、
対応している各言語をその言語自身の表記で並べる。新しい言語を足すときの手順と、
医学用語を含む訳をどう確かめるかをここに固める。

## 言語が決まる仕組み

- 文言の正本は `lib/l10n/*.arb`。`app_en.arb` がテンプレート（キー・プレースホルダ型・
  `@meta` の正本）、`app_ja.arb` のような `app_<言語コード>.arb` が各言語の訳だけを持つ。
- 言語の選択は `SettingsService.locale`（`null` =「自動」）に言語コードで永続化する。
- 実際に使う言語は `lib/l10n/locale_resolution.dart` の `resolveSupportedLocale` が一箇所で決める。
  「選んだ言語 → OS の言語の一覧 → 英語」の順で、対応していない言語コードは次の候補へ落ちる。
  OS の言語の一覧は Flutter 標準の `basicLocaleListResolution` で選ぶ（`[fr, ja]` で fr 未対応なら ja）。
- `main.dart` の `MaterialApp` は、言語を選んでいれば `locale` に、「自動」なら
  `localeListResolutionCallback` からこの関数を呼ぶ。起動時のエラー画面とトレイも同じ関数なので、
  画面とトレイの言語がずれない（`test/language_dialog_test.dart` が一致を確かめる）。
  保存された言語コードが `supportedLocales` に無ければ `SettingsService.load` が捨てて「自動」に戻す。
- トレイは `BuildContext` を持たないため、`lib/services/tray_locale_sync.dart` が
  設定の変更と OS のロケール変更（「自動」のとき）を見て、解決した言語の文言を
  `TrayService.updateLocalization` に渡す。
- フィルタ名・説明・有病率・体験プリセット名は、sensus の id を ARB のキーへ引き当てて出している
  （`lib/l10n/l10n_extensions.dart` の `visionFilterName` / `colorVisionTypeDescription` /
  `experienceName` など）。UI の言語と同じ ARB から引くので、言語を切り替えれば一緒に変わる。

## 追加手順

例として `fr`（フランス語）を足す。

1. `lib/l10n/app_fr.arb` を作る。`"@@locale": "fr"` を入れ、`app_en.arb` の**全キー**を訳す
   （プレースホルダ `{name}` などはそのまま残す）。`@meta` は書かない（テンプレート側だけが持つ）。
2. `flutter pub get`（または `flutter gen-l10n`）で `AppLocalizations` を再生成する。
   生成物 `lib/l10n/app_localizations*.dart` は gitignore 済みなのでコミットしない。
3. `lib/ui/widgets/language_dialog.dart` の `kLanguageEndonyms` に
   `'fr': 'Français'` を足す。**言語名はその言語自身の表記**で、翻訳せず ARB にも入れない
   （読めない言語の画面から抜け出せるようにするため）。
4. `flutter test --no-pub` を通す。次のテストが機械的に検出できるのは、構造の抜けだけ。
   - `test/i18n_test.dart` — `lib/l10n/app_*.arb` を全部拾い、`supportedLocales` と一致すること
     （ARB を足して gen-l10n を回し忘れた・逆に消し忘れた）、`@@locale` がファイル名と合うこと、
     キー集合とプレースホルダが en と一致すること、全メッセージが非空であること、全フィルタ id・
     サンプル id・有病率が全言語で解決できること。
   - `test/language_dialog_test.dart` — `supportedLocales` の全言語に自称名があること。
   - **検出できないもの**: 英語のまま残した訳、誤訳、不自然な医学用語。これらはテストでは
     分からないので、下の「医学用語を含む訳の確認方針」で人が確かめる。
5. 画面の崩れを見る。`UE_SCREENSHOTS=1 flutter test test/ui_screenshots/home_screenshots_test.dart`
   の出力（DESIGN.md §8）で、長い訳（ドイツ語など）でも AppBar・ダイアログ・3 カラムが
   崩れないかを確認する。ケースの言語は `home_screenshots_test.dart` に足す。
6. README の「多言語（i18n）」と `CLAUDE.md` の l10n の説明の言語一覧を更新する。

言語ピッカー本体（`LanguageDialog`）は `supportedLocales` と `kLanguageEndonyms` から
選択肢を組むので、上の 3 までで新しい選択肢が出る。

### 言語コード単位という制約

解決・保存・自称名はすべて**言語コード（`fr`、`ja` のような languageCode）単位**で持つ。
`zh_Hant` と `zh_Hans`、`pt_BR` と `pt_PT` のような地域・文字体系の違いは区別できない
（`resolveSupportedLocale` は languageCode に正規化し、`SettingsService` は languageCode だけを
保存し、`kLanguageEndonyms` のキーも languageCode）。これらを分けるときは、解決・保存・
自称名のキーの 3 か所を地域・文字体系まで扱うよう拡張してから ARB を足す。

## 医学用語を含む訳の確認方針

このアプリは色覚異常・屈折異常・前庭障害などの当事者が読む。誤訳は当事者への誤情報になるので、
機械翻訳の出力をそのまま入れない。

- **訳語は、その言語の医学会・公的機関が使う表記に揃える。** 日本語なら日本眼科学会・耳鼻咽喉科
  関連学会などの用語に合わせる。一般向けの通称や俗称、縁起で付いた別名を代表にしない。
- **病名・症状名は、根拠にした出典を PR 本文に書く**（学会の用語集、公的機関の患者向けページなど）。
  出典を示せない訳は入れない。分からない用語を英語のまま残す場合も、その旨と該当キーを PR に
  書いて確認を求める（英語のまま残っても機械では検出できないので、PR の記述が唯一の手掛かり）。
- **有病率・数値・受診の目安は、sensus が持つ値を訳すだけ**で、UI 側で言い換えたり丸めたりしない。
  数値の単位・小数の表記だけをその言語の慣習に合わせる。
- **受診喚起の文言は特に慎重に。** 診断を断定する・不安を煽る・受診を妨げる言い回しにならないよう、
  原文（en）の強さを保ったまま訳す。対象のキーは `consult*`（`consultDisclaimer` /
  `consultEarly` / `consultEmergency` など）と `escalation*`。これらは**母語話者で、かつ医療分野の
  知識がある人**が読んで確認する（母語話者だけ・医療者だけでは足りない）。
- **確認が取れていない言語は公開しない。** `gen-l10n` は `lib/l10n/` の `app_*.arb` をすべて
  `supportedLocales` に出すため、置いた時点で言語ピッカーに現れる。未確認の間は次のどちらかにする。
  - ARB を `lib/l10n/` の外（例: `docs/l10n-drafts/app_fr.arb`）に置き、PR は draft のままにする。
    `lib/l10n/` に無いので `supportedLocales` にも言語ピッカーにも出ない。
  - その PR をマージしない。

  確認が取れたら ARB を `lib/l10n/` へ移し、上の追加手順 2 以降を行う。
