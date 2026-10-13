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

## 代替案

- **ブランチ保護や `workflow_run` で CI を必須にする**: 採らなかった。タグ push は
  ブランチ保護の対象外で、`workflow_run` は別 workflow の完了を待つだけなので、
  「赤いコミットのタグ」で release.yml 自体は走ってしまう。release.yml の中で
  `needs` により依存させるのが、公開を確実に止められる唯一の形。
- **`rust/Cargo.toml` の版をアプリ版と独立に持つ**: 採らなかった。出所が 2 つになり、
  どちらが正かが曖昧なまま片方だけ古くなる（実際に 0.1.0 のまま残っていた）。
- **`--dart-define` でビルド時に版を注入する**: 採らなかった。実行時に pubspec から読む
  `package_info_plus` なら、ビルド手順に注入の取りこぼしが生じず、ローカル実行でも同じ版が出る。

## 根拠

「タグを打てば公開される」手順は、検証を人の注意に頼っていた。ゲートを workflow に置けば、
忘れても赤いものは出ない。版は 1 か所（pubspec.yaml）を正とし、他は検査で縛るのが、
手動同期より壊れにくい。

## 結果・トレードオフ

- 赤い CI・版不一致のタグでは build 系 job が走らず、Release は公開されない。
- **`v0.1.1` は既にタグ済み**（このゲート導入前）。ゲート付きの最初のリリースは `v0.1.2` 以降。
- リリース手順は `CLAUDE.md`「リリース手順」を参照。

## 関連 Issue・PR・docs

- Issue #158（本件）、#160（リリース配布の整備）
- PR #165
- `CLAUDE.md`「リリース手順」、`.github/workflows/release.yml`、`.github/workflows/ci.yml`
