# ADR: Linux のライブキャプチャは portal + PipeWire をランナーの C++ で受け、窓の下は「控え」で映す

- **決定日**: 2026-11-14（Issue #180）
- **記録日**: 2026-11-14
- **ステータス**: Accepted

## 文脈（問題）

ルーペ窓（`docs/adr/2026-09-26-loupe-as-single-render-unit.md`）は、窓の枠の向こうの画面に
フィルタを掛けて映す。ライブ画面キャプチャが無かったため `LoupeWindowPolicy.loupeModeAvailable`
は false に固定していた（#156）。Linux（この開発機は COSMIC / Wayland。アプリは #178 により
XWayland の X11 ウィンドウで動く）から実装する。

制約:

- Wayland の画面キャプチャは xdg-desktop-portal の ScreenCast（→ PipeWire のストリーム）が標準。
  利用者がダイアログで共有を許可する。**自分の窓を除外して撮る手段は標準に無い**。
  そのまま窓の矩形を切り出すと、自分が描いたフィルタ済みの絵を撮ってもう一度フィルタする
  帰還（フィードバック）になる。
- X11 の `_NET_WM_WINDOW_OPACITY` 等で窓を透かして撮る方法は、合成器が無視しうる上に、
  ストリームに写る絵そのものが変わらない限り役に立たない。

実機での事前調査（2026-11-14、COSMIC、4K・150%）:

- `org.freedesktop.portal.ScreenCast` は v5（モニタ/ウィンドウ、カーソル非表示、persist_mode）。
- 共有のダイアログは初回、利用者のクリックが要る。セッションを `Close` するとダイアログは閉じる。
- XWayland の X11 ルートは 3840x2160（物理ピクセル）で、モニタのストリームと同じ大きさ。

## 決定

1. **取得はランナー側の C++（`linux/screen_capture/`）**。ポータルとの対話は GDBus（GIO、
   `gio-unix-2.0` で fd を受け取る）、フレームは `libpipewire-0.3`。共有メモリ（MemFd / MemPtr）の
   BGRx / RGBx 系だけを受ける（DMA-BUF の修飾子を提示しない）。Dart とは MethodChannel
   `universal_experience/live_capture`（`lib/services/live_capture_service.dart` と対）。
2. **フィードバックは「下の画面の控え」で避ける**（`linux/screen_capture/backdrop.{h,cc}`）。
   - ネイティブ側に全画面ぶんの控えを持ち、フレームごとに **自分の窓の外形（WM の枠込み）を
     24px 広げた矩形・直近 300ms の位置の履歴・直近の移動量から 2 回分先へ外挿した位置** を
     除外して書き込む。窓の中には控えから窓の描画域を切り出して映す。
   - 窓を動かすと、窓が来る前に撮れていた画素がそのまま映る（追従する）。自分の描画は撮り込まない。
   - 窓の真下は窓がある間は更新できない。**ルーペ窓に入った直後と HUD の「窓の下を撮り直す」
     でだけ、窓を一瞬隠して（`windowManager.hide` → 2 フレーム待つ → `show`）真下を撮る**。
     隠す前に除外を止め、戻す前に除外を再開する。
3. **描画は既存の sensus シェーダ経路**（`ShaderFilter.applyColorFilterGpu` + `vision_uniforms`）。
   複数層は `previewPipelineSteps` の段順に 1 層 1 パスで通す（#1 の制約）。GPU シェーダの無い
   10 種（緑内障・白内障・飛蚊症・めまい・BPPV・光芒・ドライアイ・変視症・細部の欠落・閃輝星）は
   飛ばし、HUD に「この症状は静止画プレビューのみ」を出す（`lib/rendering/live_filter_plan.dart`）。
   視野欠損系の表現モード（Blur）は GPU では Darken 相当になる（既存の `vision_uniforms` の制約）。
4. **全画面のプリフィルタ（#1 の当初案）はしない**。毎表示、窓の描画域だけを切り出してから
   フィルタする。#1 の懸念（移動で新しく見えた所が未フィルタになる）は、切り出しとフィルタを
   同じ表示の中で行うので起きない。空間フィルタの縁は窓の端で打ち切られる（シェーダのクランプ）。
5. **`loupeModeAvailable` は起動時の調査（`probeLiveCapture`）の結果**。Linux で GDK が X11
   （XWayland を含む）バックエンド、かつポータルが ScreenCast のモニタ共有を提供するときだけ true。
   ネイティブ Wayland（`UE_ALLOW_WAYLAND=1`）は自分の窓の絶対位置が分からないので false。
   ほかの OS は false（未実装）。理由は設定窓に出す。
6. **拒否・失敗・途中停止は設定窓へ戻す**（`LiveLoupeSession`）。理由はスナックバーで出す。
   選んだ画面は `persist_mode=2` の restore token を `SharedPreferences` に残し、次回はダイアログを
   省けるようにする（合成器が対応していれば）。
7. 2560x1440 を超える窓（全画面の 4K など）は、ネイティブ側で整数間引きして Dart へ渡す。

## 代替案

- **Rust 側（ashpd + pipewire-rs、flutter_rust_bridge）で取る**: 採らなかった。依存の木が大きく
  （zbus・bindgen）、FRB の再生成と macOS / Windows / Android 向けの cfg 分岐・スタブが要る。
  sensus の公開に専念している `rust/` の責務（アルゴリズムの橋）にも OS の取得が混ざる。
- **毎フレーム窓を隠して撮る**: ちらつきで成立しない。
- **ポータルでウィンドウ単体を共有させる**: 窓の下にあるのが 1 つのアプリとは限らず、Wayland では
  そのウィンドウの位置も分からない（対象アプリ指定モードを Wayland で提供しない理由と同じ）。
- **フィードバックを許す（色覚の行列は射影に近いので 2 回掛けても大差ない）**: ぼかし系は掛けるたびに
  広がり、映る絵が収束しない。採らない。

## 結果・トレードオフ

- 窓の下で動く動画は、窓を動かすか「撮り直す」まで止まって見える（窓がある間は真下を撮れない）。
- 開始時と撮り直しのとき、窓が一瞬消える。
- 第 1 弾はモニタ 1 台（窓のいるモニタとストリームが同じ前提で、X11 のモニタの範囲をフレームの大きさへ
  写す）。別のモニタを共有に選ぶと位置がずれる。
- フレームは全画面ぶん控えに書く（4K で 1 枚 33MB の行コピー）。`backdrop.cc` は Debug ビルドでも
  `-O2` で最適化する。
- ビルドに `libpipewire-0.3-dev` が要る（CI の Linux ジョブ・release の build-linux に追加）。実行時は
  `libpipewire-0.3.so.0` が要る（主要ディストリには標準で入る）。
- 共有のダイアログの承認は人の手が要るため、実機の自動確認はダイアログの手前までになる。

## 関連 Issue・PR・docs

- Issue #180（本決定）、親 #1、#5、#44、#156、#178
- `docs/adr/2026-09-26-loupe-as-single-render-unit.md`、`docs/adr/2026-11-14-prefer-xwayland-on-linux-wayland.md`
- `linux/screen_capture/`、`linux/test/backdrop_test.cc`、`lib/services/live_capture_service.dart`、
  `lib/services/live_loupe_session.dart`、`lib/rendering/live_filter_plan.dart`、`lib/ui/widgets/live_loupe_view.dart`
