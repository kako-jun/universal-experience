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
  gdk_backend_x1_no_change
  gdk_backend_x11foo_no_change
  gdk_backend_x11foo_wayland_sets
  gdk_backend_x11_star_no_change
  gdk_backend_star_x11_overridden
  gdk_backend_broadway_wayland_overridden
  gdk_backend_uppercase_wayland_no_change
  gdk_backend_broadway_no_change
  gdk_backend_wayland_only_overridden
  gdk_backend_star_overridden
  gdk_backend_empty_is_unset
  gdk_backend_wayland_x11_overridden
  gdk_backend_unset_sets
  idempotent
  all_null_no_crash
)
foreach(c ${CASES})
  add_test(NAME ${c} COMMAND backend_policy_test ${c})
endforeach()

# screen_capture/backdrop の単体テスト (#180)。PipeWire / GTK 不要。
add_executable(backdrop_test
  backdrop_test.cc
  ../screen_capture/backdrop.cc
)
target_compile_features(backdrop_test PRIVATE cxx_std_14)
target_compile_options(backdrop_test PRIVATE -Wall -Werror -UNDEBUG)
target_include_directories(backdrop_test PRIVATE ..)

set(BACKDROP_CASES
  merge_without_exclusion_copies_and_swizzles
  rgbx_order_is_kept
  excluded_pixels_keep_previous_frame
  overlapping_exclusions_are_merged
  unprimed_pixels_are_black_until_captured
  size_change_resets
  stride_larger_than_row_is_honoured
  crop_is_clipped_to_bounds
  invalid_frame_is_ignored
  tracker_inflates_by_margin
  tracker_keeps_history_and_predicts
  tracker_predicts_resize
  tracker_predicts_move_and_resize_together
  crop_under_limit_is_not_decimated
  crop_decimates_across_full_extent
  crop_decimates_offset_rect
  tracker_drops_old_but_keeps_latest
  tracker_hidden_excludes_nothing
)
foreach(c ${BACKDROP_CASES})
  add_test(NAME backdrop_${c} COMMAND backdrop_test ${c})
endforeach()
