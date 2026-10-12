# ADR: リリースを CI 成功と版一致で関門にし、版の正本を pubspec.yaml に置く

- **決定日**: 2026-10-13（Issue #158）
- **記録日**: 2026-10-13
- **ステータス**: Accepted

## 文脈（問題）

`vX.Y.Z` タグの push だけで release.yml が全 OS の bundle を公開していた。CI が赤い
コミットや、アプリ内の版・Cargo.toml の版とずれたタグでも公開でき、「このアプリについて」は
版をハードコード（0.1.0）していたため、実際の版（0.1.1）と食い違っていた。

## 決定

1. **公開は CI 成功が前提**。release.yml に `ci` job（`ci.yml` を `workflow_call` で呼ぶ）を置き、
   全 build job を `needs` で依存させる。CI は全 OS の実ブリッジ integration test
   （Windows を含む）まで回すので、ロードできない bundle は公開されない。`ci` job は
   `contents: read` で足りる。
2. **版の正本は `pubspec.yaml` の `version`（`X.Y.Z+build`）**。タグ `vX.Y.Z` は X.Y.Z と
   一致しなければならない（+build は無視）。アプリ内の表示は `package_info_plus` で実行時に
   読む（build 番号は出さない）。
3. **`rust/Cargo.toml` の `version` も同じ X.Y.Z に揃える**。版の出所を 1 つにし、
   ずれを放置しないため。release.yml の `version-check` job が、タグ・pubspec・Cargo.toml・
   `rust/Cargo.lock` の当該 crate の 4 つの一致を検査する。cargokit は build 時に
   Cargo.lock を書き換えうるので、Cargo.toml の版を上げたら Cargo.lock も同じ commit で
   更新しておく（古いままだと検査が落ちる）。
4. 配布物の download は名前指定にし、`ci` job が保存する Windows debug bundle を Release の
   作業領域へ混ぜない（公開するファイルは従来どおり明示列挙）。

## 結果

- 赤い CI・版不一致のタグでは build 系 job が走らず、Release は公開されない。
- **`v0.1.1` は既にタグ済み**（このゲート導入前）。ゲート付きの最初のリリースは `v0.1.2` 以降。
- リリース手順は `CLAUDE.md`「リリース手順」を参照。
