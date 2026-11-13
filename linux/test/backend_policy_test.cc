// decide_gdk_backend の単体テスト (#178)。gtest 不使用、assert ベース。
// 引数順: allow, session_type, wayland_display, gdk_backend
#undef NDEBUG
#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "backend_policy.h"

static const char* const kSet = "x11,wayland";

static void expect_set(const char* r) {
  assert(r != nullptr);
  assert(strcmp(r, kSet) == 0);
}

static void allow_1_no_change() {
  assert(decide_gdk_backend("1", "wayland", "wayland-0", nullptr) == nullptr);
}
static void allow_arbitrary_string_no_change() {
  assert(decide_gdk_backend("yes", "wayland", "wayland-0", nullptr) == nullptr);
}
static void allow_empty_is_unset() {
  expect_set(decide_gdk_backend("", "wayland", "wayland-0", nullptr));
}
static void allow_0_is_unset() {
  expect_set(decide_gdk_backend("0", "wayland", "wayland-0", nullptr));
}
static void non_wayland_session_no_change() {
  assert(decide_gdk_backend(nullptr, "x11", nullptr, nullptr) == nullptr);
}
static void session_type_wayland_only_sets() {
  expect_set(decide_gdk_backend(nullptr, "wayland", nullptr, nullptr));
}
static void wayland_display_only_sets() {
  expect_set(decide_gdk_backend(nullptr, nullptr, "wayland-0", nullptr));
}
static void wayland_display_empty_is_not_wayland() {
  assert(decide_gdk_backend(nullptr, nullptr, "", nullptr) == nullptr);
}
static void gdk_backend_x11_no_change() {
  assert(decide_gdk_backend(nullptr, "wayland", "wayland-0", "x11") == nullptr);
}
static void gdk_backend_x11_wayland_no_change() {
  assert(decide_gdk_backend(nullptr, "wayland", "wayland-0", "x11,wayland") ==
         nullptr);
}
static void gdk_backend_x1_sets() {
  // strncmp(.., "x11", 3) の境界: "x1" は先頭一致しない。
  expect_set(decide_gdk_backend(nullptr, "wayland", "wayland-0", "x1"));
}
static void gdk_backend_wayland_x11_overridden() {
  expect_set(decide_gdk_backend(nullptr, "wayland", "wayland-0", "wayland,x11"));
}
static void gdk_backend_unset_sets() {
  expect_set(decide_gdk_backend(nullptr, "wayland", "wayland-0", nullptr));
}
static void idempotent() {
  const char* first = decide_gdk_backend(nullptr, "wayland", "wayland-0", nullptr);
  expect_set(first);
  // 結果を GDK_BACKEND として再入力すると何もしない。
  assert(decide_gdk_backend(nullptr, "wayland", "wayland-0", first) == nullptr);
}
static void all_null_no_crash() {
  assert(decide_gdk_backend(nullptr, nullptr, nullptr, nullptr) == nullptr);
}

struct Case {
  const char* name;
  void (*fn)();
};
#define C(n) {#n, n}
static const Case kCases[] = {
    C(allow_1_no_change),
    C(allow_arbitrary_string_no_change),
    C(allow_empty_is_unset),
    C(allow_0_is_unset),
    C(non_wayland_session_no_change),
    C(session_type_wayland_only_sets),
    C(wayland_display_only_sets),
    C(wayland_display_empty_is_not_wayland),
    C(gdk_backend_x11_no_change),
    C(gdk_backend_x11_wayland_no_change),
    C(gdk_backend_x1_sets),
    C(gdk_backend_wayland_x11_overridden),
    C(gdk_backend_unset_sets),
    C(idempotent),
    C(all_null_no_crash),
};

int main(int argc, char** argv) {
  const char* only = argc > 1 ? argv[1] : nullptr;
  int ran = 0;
  for (const Case& c : kCases) {
    if (only != nullptr && strcmp(only, c.name) != 0) continue;
    c.fn();
    printf("ok %s\n", c.name);
    ran++;
  }
  if (ran == 0) {
    fprintf(stderr, "no such case: %s\n", only ? only : "(none)");
    return 1;
  }
  return 0;
}
