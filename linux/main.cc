#include "my_application.h"

#include "backend_policy.h"

#include <stdlib.h>

// Wayland ネイティブセッションでは Flutter (GTK) の描画サーフェスが
// "Timed out waiting for subsurface frame" で一度も描画されず、ウィンドウは出るが
// 操作できなくなる環境がある (#178、COSMIC で確認)。そのため Wayland セッションでは
// XWayland (X11 バックエンド) を優先する。XWayland が無い環境では Wayland に
// フォールバックできるよう "x11,wayland" の優先リストにする。
//
// 判定ロジックは backend_policy.cc の純関数 (linux/test/ で単体テスト)。
// 上書きするのは GDK_BACKEND が未設定、または wayland / * を含む場合だけ。先頭が
// x11 の場合や broadway など wayland を含まない明示指定は尊重して何もしない。
// ネイティブ Wayland を試したいときは UE_ALLOW_WAYLAND=1 で従来どおりにできる。
// GDK_BACKEND が "wayland,x11" のようにセッション既定で入っているだけの場合も
// 明示指定とは区別できないため、上書き対象にする。
// 注意: setenv した GDK_BACKEND は子プロセスにも引き継がれる。
// 経緯・代替案・副作用は docs/adr/2026-11-14-prefer-xwayland-on-linux-wayland.md。
static void prefer_x11_backend_on_wayland() {
  const char* backend =
      decide_gdk_backend(getenv("UE_ALLOW_WAYLAND"), getenv("XDG_SESSION_TYPE"),
                         getenv("WAYLAND_DISPLAY"), getenv("GDK_BACKEND"));
  if (backend == nullptr) return;

  // gtk_init (g_application_run 内) より前に設定する必要がある。GTK 3.24 の
  // gdk_display_manager_open_display は GDK_BACKEND を「試す順番」として使い、各候補は
  // gdk_set_allowed_backends() で絞られる。GDK_BACKEND 未設定なら
  // gdk_set_allowed_backends("x11,wayland") だけでも x11 が先になるが、セッションが
  // GDK_BACKEND=wayland などを渡してくる場合はその順番が優先されてしまうため、
  // 環境変数のほうを書き換える。
  setenv("GDK_BACKEND", backend, 1);
}

int main(int argc, char** argv) {
  prefer_x11_backend_on_wayland();
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
