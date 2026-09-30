# 言語の追加手順と医学用語の訳の確認方針

アプリ内の言語ピッカー（AppBar の地球儀ボタン、#82）は「システムに合わせる」と、
対応している各言語をその言語自身の表記で並べる。新しい言語を足すときの手順と、
医学用語を含む訳をどう確かめるかをここに固める。

## 言語が決まる仕組み

- 文言の正本は `lib/l10n/*.arb`。`app_en.arb` がテンプレート（キー・プレースホルダ型・
  `@meta` の正本）、`app_ja.arb` のような `app_<言語コード>.arb` が各言語の訳だけを持つ。
- 言語の選択は `SettingsService.locale`（`null` = システムに合わせる）に言語コードで永続化する。
- 実際に使う言語は `lib/l10n/locale_resolution.dart` の `resolveSupportedLocale` が一箇所で決める。
  「選んだ言語 → OS の言語 → 英語」の順で、対応していない言語コードは次の候補へ落ちる。
  `MaterialApp.locale`・トレイ・起動時のエラー画面が同じ関数を使うので、言語の解決がずれない。
- トレイは `BuildContext` を持たないため、`lib/services/tray_locale_sync.dart` が
  設定の変更と OS のロケール変更（「システムに合わせる」のとき）を見て、解決した言語の文言を
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
4. `flutter test --no-pub` を通す。足し忘れは次のテストが落ちて教える。
   - `test/i18n_test.dart` — ARB のキー集合が en と一致すること、全メッセージが非空であること、
     全フィルタ id・サンプル id・有病率が翻訳の抜けなく解決できること（en/ja を回している
     ケースには新言語を足す）。
   - `test/language_dialog_test.dart` — `supportedLocales` の全言語に自称名があること。
5. 画面の崩れを見る。`UE_SCREENSHOTS=1 flutter test test/ui_screenshots/home_screenshots_test.dart`
   の出力（DESIGN.md §8）で、長い訳（ドイツ語など）でも AppBar・ダイアログ・3 カラムが
   崩れないかを確認する。ケースの言語は `home_screenshots_test.dart` に足す。
6. README の「多言語（i18n）」と `CLAUDE.md` の l10n の説明の言語一覧を更新する。

言語ピッカー本体（`LanguageDialog`）は `supportedLocales` と `kLanguageEndonyms` から
選択肢を組むので、上の 3 までで新しい選択肢が出る。

## 医学用語を含む訳の確認方針

このアプリは色覚異常・屈折異常・前庭障害などの当事者が読む。誤訳は当事者への誤情報になるので、
機械翻訳の出力をそのまま入れない。

- **訳語は、その言語の医学会・公的機関が使う表記に揃える。** 日本語なら日本眼科学会・耳鼻咽喉科
  関連学会などの用語に合わせる。一般向けの通称や俗称、縁起で付いた別名を代表にしない。
- **病名・症状名は、根拠にした出典を PR 本文に書く**（学会の用語集、公的機関の患者向けページなど）。
  出典を示せない訳は入れない。分からない用語は英語のまま残し、その旨を PR に書いて確認を求める。
- **有病率・数値・受診の目安は、sensus が持つ値を訳すだけ**で、UI 側で言い換えたり丸めたりしない。
  数値の単位・小数の表記だけをその言語の慣習に合わせる。
- **受診喚起の文言は特に慎重に。** 診断を断定する・不安を煽る・受診を妨げる言い回しにならないよう、
  原文（en）の強さを保ったまま訳す。
- **母語話者または該当分野に詳しい人が読んで確認してから出す。** 確認が取れていない言語は
  マージ前に PR で「未確認」と明記し、確認できるまでリリース対象に含めない。
- 訳を足したら、`test/i18n_test.dart` の「全 catalog id がフォールバックなしで名前解決できる」
  系のテストで、名前・説明の訳漏れ（英語のまま残る）がないことを機械的に確かめる。
