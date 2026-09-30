# ADR: 言語ピッカーは自称名で並べ、言語の解決を 1 つの関数に一本化する

- **決定日**: 2026-09-30（Issue #82）
- **記録日**: 2026-09-30（ADR 化）
- **ステータス**: Accepted

## 文脈（問題）

ue の文言は OS の言語で自動選択されるだけで、アプリ内で言語を選べなかった（#82）。
言語ピッカーを足すにあたり、次の 2 つを決める必要があった。

- 選択肢の言語名を、UI の言語に合わせて翻訳するか、その言語自身の表記にするか。
- 使う言語を決める処理が、`MaterialApp`（Flutter 標準の解決）・起動時のエラー画面・
  システムトレイ（`BuildContext` を持たない）でバラバラになりうる。

## 決定

1. **言語名は自称名（endonym）で出し、翻訳しない。** `日本語` / `English` のように、
   ARB にも入れず `kLanguageEndonyms`（言語コード → 表記）に持つ。「自動」だけは
   UI の言語に従う ARB の文言にする。読み上げには `LocaleStringAttribute` で言語を付ける。
2. **使う言語は `resolveSupportedLocale` 1 つで決める。** 順序は「選んだ言語 → OS の
   言語の一覧（`basicLocaleListResolution`）→ 英語」。`MaterialApp` は `locale`（選択時）と
   `localeListResolutionCallback`（「自動」時）からこの関数を呼び、エラー画面も同じ関数を使う。
3. **トレイは `TrayLocaleSync` が同じ関数の結果を見て文言を差し替える。** 設定の変更と
   OS のロケール変更を監視し、解決後の言語が変わったときだけ `TrayService.updateLocalization`
   を呼ぶ。
4. **保存する言語コードが `supportedLocales` に無ければ、読み込み時に捨てて「自動」に戻す。**
5. **言語は言語コード（languageCode）単位で扱う。** 地域・文字体系の違いは区別しない。

## 代替案

- **自称名を ARB に入れて UI の言語で翻訳する。** 却下: 読めない言語の画面になったとき、
  自分の言語の選択肢を見つけられなくなる。
- **`MaterialApp` は Flutter 標準の解決に任せ、トレイだけ自前で解決する。** 却下: 標準の解決と
  自前の解決の規則（OS の言語一覧の見方）が食い違い、画面とトレイの言語がずれる
  （例: OS が `[fr, ja]` で fr 未対応のとき、標準は ja、先頭だけを見る自前解決は en になる）。
- **トレイ用の文言を別の仕組みで持つ。** 却下: ARB と二重管理になり、言語の追加のたびに
  2 か所を直すことになる。

## 根拠

- 言語の解決規則を 1 か所に置けば、画面・エラー画面・トレイの一致をテストで保証できる
  （`test/language_dialog_test.dart`）。sensus-core への一元化と同じ「正本を 1 つに保つ」判断。
- 自称名は言語の追加時に ARB の翻訳を要さず、`kLanguageEndonyms` に 1 行足すだけで済む。

## 結果・トレードオフ

- 言語の追加は ARB を足し、`kLanguageEndonyms` に自称名を足す作業になる
  （手順は `docs/ADDING_A_LANGUAGE.md`）。
- `zh_Hant` と `zh_Hans`、`pt_BR` と `pt_PT` のような地域・文字体系の区別はできない。
  必要になったら解決・保存・自称名のキーの 3 か所を拡張する。

## 関連 Issue・PR・docs

- Issue #82
- `docs/ARCHITECTURE.md`「言語の切替とトレイの文言 (#82)」
- `docs/ADDING_A_LANGUAGE.md`
