# ADR: Windows を対応 OS に加え、GitHub Releases で配布する

- **決定日**: 2026-10-13（Releases・zip / dmg / tar.gz の配布は PR #153・#155 で 2026-10-09 に導入済み。2026-10-13 は、CI で関門された対応 OS としての判断を記録する。Issue #149 / #150 / #158 / #160 の積み重ね）
- **記録日**: 2026-10-13
- **ステータス**: Accepted

## 文脈（問題）

ue は macOS と Linux のランナーだけを持ち、配布物は Actions の artifact だった。artifact は
期限つきで、利用者（特に Windows の利用者）が入手する正規の場所がなかった。Windows ランナーは
作られたが、「対応 OS と呼べる根拠」「何をどの形式で配るか」は文書化されていなかった。

## 決定

1. **Windows（x64）を対応 OS に加える**。`windows/` ランナーは Flutter 標準のテンプレートで、
   `rust_builder`（cargokit）が Rust DLL（`universal_experience_rust.dll`）を exe と同じ場所へ同梱する（#149）。
   トレイは Windows が ICO を要するため `assets/tray/tray_icon.ico` を選ぶ（#150、#163）。
   「対応」の根拠は CI で、`ci.yml` の `windows-build` が debug bundle の exe/DLL 同梱確認と、
   macOS / Linux と同じ 4 本の実ブリッジ integration test を `-d windows` で実行する（#158、#165）。
2. **配布は GitHub Releases に一本化する**。`vX.Y.Z` タグで `release.yml` が全 OS の release bundle を
   同じ Release に公開する（公開の関門は `docs/adr/2026-10-13-release-gate-and-version-source.md`）。
3. **形式は OS ごとの最小のアーカイブで、インストーラは作らない**:
   - Windows: `universal-experience-windows-x64.zip`（`build/windows/x64/runner/Release` の中身を
     `Compress-Archive`）。
   - macOS: `universal-experience-macos.dmg`（`.app` と `/Applications` へのリンクを `hdiutil` で UDZO 化）。
     ビルドは `macos-latest` で `flutter build macos --release`。ユニバーサルバイナリ（arm64 + x86_64）。
     ARCHS は明示指定せず Flutter の Release 既定に従う（v0.1.1 の dmg で本体・Rust framework とも両スライスを確認）。
   - Linux: `universal-experience-linux-x64.tar.gz`（`build/linux/x64/release/bundle`）。`ubuntu-latest`
     （現在は Ubuntu 24.04）でビルドし、それより古い glibc での動作は未検証。
4. **デスクトップ3 OSは未署名**。Windows は Authenticode 署名なし（SmartScreen の警告が出うる）、macOS は Developer ID 署名・
   公証なし（ad-hoc 署名のみ。Gatekeeper で「このまま開く」操作が要る）。Android は v0.2.0 から
   release JKS で署名した APK を配布する。必要な4つの Repository Secrets と、未設定時に公開を止める
   仕組みは `docs/GETTING_STARTED.md` と `CLAUDE.md` に記録する。初回起動の手順は `README.md` に書く。
5. **Android（API 29+）を対応 OS に加える**。`android/` ランナーと `rust_builder` の
   cargokit plugin が Rust `.so` を arm64-v8a / armeabi-v7a / x86_64 を含む universal APK へ同梱する。
   `ci.yml` は debug APK の3 ABIすべてで native library の同梱を確認し、`release.yml` は署名済み
   `universal-experience-android.apk` を同じ Release に公開する。

## 代替案

- **インストーラ（MSI / NSIS / MSIX、pkg）を作る**: 採らなかった。署名しない限り警告は消えず、
  インストーラ固有の保守（アンインストール・更新・署名鍵の管理）だけが増える。zip / dmg / tar.gz なら
  展開または移動で済み、同梱物は exe + DLL + `data/` のフォルダ一式のまま壊れない。
- **署名・公証を行う**: 今回は採らなかった。証明書と Apple Developer 契約（secrets の管理を含む）が要る。
  必要になった時点で別の判断として足す（本 ADR は未署名を現状として記録する）。
- **Actions の artifact のまま配る**: 採らなかった。期限があり、版・タグと対応する正規の入手先にならない。
- **Windows を対応に含めない**: 採らなかった。ランナーとビルドは既に通り、CI で実ブリッジのロードまで
  検証できる状態にあった。

## 根拠

デスクトップ 3 OS の差は、同じ Flutter + cargokit の経路で吸収できる。対応の可否は「DLL が同梱される」
だけでは決まらず、「ロードして初期化できる」ことまで CI で見る必要がある（#158）。配布は、1 か所
（Releases）に版つきで置けば入手先が曖昧にならない。署名のない状態で配るなら、インストーラの形をとるより
最小のアーカイブにして警告への対処を README に書く方が、約束していないことを約束しない。

## 結果・トレードオフ

- 利用者は初回に OS の警告（SmartScreen / Gatekeeper）を越える必要がある。手順は `README.md`「初回起動の手順」。
- Windows 実機での画面表示・フィルタ選択・トレイ・ホットキー・クリップボード・PNG 書き出しの確認は
  残っている（#150）。CI はロードと CPU プレビューまでで、これらは保証しない。
- Linux はトレイ・ホットキー用の共有ライブラリを利用者が入れる必要がある（`README.md`）。
- 版・ゲートの規則は release-gate ADR に従う。Android は CI で APK と native library の同梱を検証するが、
  実機 golden path はリリース前に別途確認する。iOS は非対応のまま。

## 関連 Issue・PR・docs

- Issue #149（Windows ランナー）、#150（トレイ ICO・実機確認）、#158（実ブリッジ integration test・Release 公開）、#160（本件）
- PR #153・#155（Releases 配布の導入）、#163（トレイ ICO）、#165（リリースの CI 関門）
- `docs/adr/2026-10-13-release-gate-and-version-source.md`
- `.github/workflows/release.yml`、`.github/workflows/ci.yml`、`CLAUDE.md`「CI」「リリース手順」、`README.md`
- `docs/ARCHITECTURE.md`「プラットフォーム差」「システムアーキテクチャ（現行）」
