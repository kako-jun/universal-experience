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
// 利用者が GDK_BACKEND で明示的に X11 を選んでいる (先頭が x11) 場合は何もしない。
// ネイティブ Wayland を試したいときは UE_ALLOW_WAYLAND=1 で従来どおりにできる。
// GDK_BACKEND が "wayland,x11" のようにセッション既定で入っているだけの場合も
// 明示指定とは区別できないため、上書き対象にする。
static void prefer_x11_backend_on_wayland() {
  const char* backend =
      decide_gdk_backend(getenv("UE_ALLOW_WAYLAND"), getenv("XDG_SESSION_TYPE"),
                         getenv("WAYLAND_DISPLAY"), getenv("GDK_BACKEND"));
  if (backend == nullptr) return;

  // gtk_init (g_application_run 内) より前に設定する必要がある。GTK3 は環境変数
  // GDK_BACKEND が設定されているとそちらを優先し gdk_set_allowed_backends() を
  // 無視するため、環境変数のほうを書き換える。
  setenv("GDK_BACKEND", backend, 1);
}

int main(int argc, char** argv) {
  prefer_x11_backend_on_wayland();
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
