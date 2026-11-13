#ifndef BACKEND_POLICY_H_
#define BACKEND_POLICY_H_

// Wayland セッションで GDK_BACKEND に設定すべき値を決める純関数 (#178)。
// GTK / Flutter / glib に依存しない（linux/test/ で単体テストする）。
//
// 引数はそれぞれ getenv の結果（未設定は nullptr）:
//   allow          UE_ALLOW_WAYLAND
//   session_type   XDG_SESSION_TYPE
//   wayland_display WAYLAND_DISPLAY
//   gdk_backend    GDK_BACKEND
//
// 戻り値: 設定すべき GDK_BACKEND の値（静的文字列）。何もしないときは nullptr。
#ifdef __cplusplus
extern "C" {
#endif

const char* decide_gdk_backend(const char* allow, const char* session_type,
                               const char* wayland_display,
                               const char* gdk_backend);

#ifdef __cplusplus
}
#endif

#endif  // BACKEND_POLICY_H_
