# ADR: Linux の Wayland セッションでは XWayland (X11 バックエンド) を優先する

- **決定日**: 2026-11-14（Issue #178）
- **記録日**: 2026-11-14
- **ステータス**: Accepted

## 文脈（問題）

COSMIC の Wayland ネイティブセッションで起動すると、Flutter (GTK) の描画サーフェスが
`Timed out waiting for subsurface frame ... (have 0x0)` のまま一度も描画されず、ウィンドウは
出るが操作できなかった。`GDK_BACKEND=x11` を付けると正常に動く。グローバルホットキーの
`Binding '...' failed!` は X11 バックエンドでも同じく出るため、原因ではない（登録失敗は
アクションごとに握りつぶして続行する設計。`docs/ARCHITECTURE.md` 参照）。

## 決定

1. Wayland セッション（`XDG_SESSION_TYPE=wayland` または `WAYLAND_DISPLAY` あり）では、
   `linux/main.cc` が GTK 初期化前に `GDK_BACKEND=x11,wayland` を `setenv` する。
   XWayland が無い環境では Wayland にフォールバックする。
2. 上書きするのは `GDK_BACKEND` が未設定、または値に `wayland` / `*` を含む場合だけ。
   先頭が `x11` の場合や `broadway` など wayland を含まない明示指定は尊重して何もしない。
3. 逃げ道として `UE_ALLOW_WAYLAND=1`（`0` と空は未設定扱い）を付けると何もせず、従来の
   ネイティブ Wayland 起動になる。
4. 判定は GTK 非依存の純関数 `decide_gdk_backend`（`linux/backend_policy.{h,cc}`）に切り出し、
   `linux/test/` で単体テストする。

### GTK3 の挙動（一次確認）

GTK 3.24 の `gdk/gdkdisplaymanager.c` `gdk_display_manager_open_display` は、環境変数
`GDK_BACKEND` が設定されていればそれを「試す順番」として使い、無ければ
`gdk_set_allowed_backends()` の文字列を順番に使う。各候補は `allowed_backends` で絞られる
（`gdk_set_allowed_backends()` のドキュメントも「`GDK_BACKEND` が順序を決め、許可リストは
尊重される」と記す）。したがって `GDK_BACKEND` 未設定なら `gdk_set_allowed_backends("x11,wayland")`
だけでも x11 が優先される。それでも `setenv` を使うのは、セッションが `GDK_BACKEND=wayland`
などを渡してくる場合にも順番を上書きするため。

## 代替案

- **`gdk_set_allowed_backends("x11,wayland")` のみ**: 採らなかった。`GDK_BACKEND` が
  セッションから渡されている場合、その順番が優先され効かない。
- **ネイティブ Wayland の修正を待つ**: 採らなかった。原因が Flutter / GTK / コンポジタの
  どこにあるか切り分けられておらず、待つ間は COSMIC で操作不能のまま。
- **何もしない（利用者に `GDK_BACKEND=x11` を付けてもらう）**: 採らなかった。起動して
  何も描画されない症状で、利用者が原因に辿り着けない。

## 根拠

XWayland は主要な Wayland コンポジタで標準的に提供され、`x11,wayland` の優先リストなら
無い環境でも壊れない。ネイティブ Wayland を使いたい人・将来修正された環境のために
`UE_ALLOW_WAYLAND=1` を逃げ道として残し、ポリシー変更を再ビルド不要にしている。

## 結果・トレードオフ（副作用）

- `setenv` した `GDK_BACKEND` は子プロセスにも引き継がれる（本アプリが起動する子プロセスが
  GTK アプリだと X11 優先で動く）。
- `linux/my_application.cc:31-38` により、Wayland では常にヘッダーバー、X11 では WM が
  GNOME Shell 以外なら通常のタイトルバー（WM 装飾）になる。XWayland 上の COSMIC 等では
  見た目が変わりうる。
- ルーペの最前面（always on top）・クリックスルー・フレームレス・透過は window_manager
  経由で X11 の仕組みに変わるため、効き方が変わりうる。**XWayland 上での実機確認は未実施**
  （`docs/ARCHITECTURE.md` の実機確認手順に項目を追加済み）。
- XWayland 上でも、グローバルホットキーはネイティブ Wayland アプリへのキー入力を拾えない。
  そのため `isLikelyWaylandNativeSession` による UI ヒントの除外は維持する。
- X11 / Windows / macOS の挙動は変わらない。

## 関連 Issue・PR・docs

- Issue #178、PR #179
- `docs/ARCHITECTURE.md`「Linux Wayland セッションの GDK バックエンド (#178)」
- `linux/main.cc`、`linux/backend_policy.{h,cc}`、`linux/test/`
