#include "backend_policy.h"

#include <string.h>

// 経緯と設計は docs/adr/2026-11-14-prefer-xwayland-on-linux-wayland.md (#178)。
extern "C" const char* decide_gdk_backend(const char* allow,
                                          const char* session_type,
                                          const char* wayland_display,
                                          const char* gdk_backend) {
  if (allow != nullptr && allow[0] != '\0' && strcmp(allow, "0") != 0) {
    return nullptr;
  }

  const bool is_wayland =
      (session_type != nullptr && strcmp(session_type, "wayland") == 0) ||
      (wayland_display != nullptr && wayland_display[0] != '\0');
  if (!is_wayland) return nullptr;

  if (gdk_backend != nullptr && gdk_backend[0] != '\0') {
    // 先頭の候補が x11 そのもの ("x11" / "x11,..." 。"x11foo" は別物) なら、すでに
    // X11 優先なので何もしない。
    if (strncmp(gdk_backend, "x11", 3) == 0 &&
        (gdk_backend[3] == '\0' || gdk_backend[3] == ',')) {
      return nullptr;
    }
    // wayland / * を含まない明示指定 (broadway など) は利用者の意思として尊重する。
    // 空文字列は未設定と同じ扱い (上書きする)。
    if (strstr(gdk_backend, "wayland") == nullptr &&
        strchr(gdk_backend, '*') == nullptr) {
      return nullptr;
    }
  }

  return "x11,wayland";
}
