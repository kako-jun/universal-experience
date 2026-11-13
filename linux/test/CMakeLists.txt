# backend_policy の単体テスト (#178)。linux/CMakeLists.txt (Flutter ビルド) からは
# 参照しない独立プロジェクト。GTK / Flutter 不要。
#   cmake -S linux/test -B <build> && cmake --build <build> && ctest --test-dir <build>
cmake_minimum_required(VERSION 3.10)
project(backend_policy_test LANGUAGES CXX)
enable_testing()

add_executable(backend_policy_test
  backend_policy_test.cc
  ../backend_policy.cc
)
target_compile_features(backend_policy_test PRIVATE cxx_std_14)
target_compile_options(backend_policy_test PRIVATE -Wall -Werror)
target_include_directories(backend_policy_test PRIVATE ..)
# assert を NDEBUG で消さない。
target_compile_options(backend_policy_test PRIVATE -UNDEBUG)

# 1 ケース 1 ctest エントリ（名前は backend_policy_test.cc の kCases と一致）。
set(CASES
  allow_1_no_change
  allow_arbitrary_string_no_change
  allow_empty_is_unset
  allow_0_is_unset
  non_wayland_session_no_change
  session_type_wayland_only_sets
  wayland_display_only_sets
  wayland_display_empty_is_not_wayland
  gdk_backend_x11_no_change
  gdk_backend_x11_wayland_no_change
  gdk_backend_x1_sets
  gdk_backend_wayland_x11_overridden
  gdk_backend_unset_sets
  idempotent
  all_null_no_crash
)
foreach(c ${CASES})
  add_test(NAME ${c} COMMAND backend_policy_test ${c})
endforeach()
