// screen_capture/backdrop の単体テスト (#180)。1 ケース 1 ctest エントリ。
#include "screen_capture/backdrop.h"

#include <cassert>
#include <cstdio>
#include <cstring>
#include <functional>
#include <string>
#include <vector>

using ue_capture::Backdrop;
using ue_capture::ExclusionTracker;
using ue_capture::PixelOrder;
using ue_capture::Rect;

namespace {

// 全画素が同じ色（B, G, R, X の並び）の w x h のフレーム。
std::vector<uint8_t> Solid(int w, int h, uint8_t b, uint8_t g, uint8_t r) {
  std::vector<uint8_t> v(static_cast<size_t>(w) * h * 4);
  for (size_t i = 0; i < v.size(); i += 4) {
    v[i] = b;
    v[i + 1] = g;
    v[i + 2] = r;
    v[i + 3] = 0;
  }
  return v;
}

// 切り出した RGBA の (x, y) の R 値。
uint8_t RedAt(const std::vector<uint8_t>& rgba, int width, int x, int y) {
  return rgba[(static_cast<size_t>(y) * width + x) * 4];
}

void MergeWithoutExclusionCopiesAndSwizzles() {
  Backdrop bd;
  auto f = Solid(4, 3, 10, 20, 30);
  bd.Merge(f.data(), 4, 3, 16, PixelOrder::kBgrx, {});
  std::vector<uint8_t> out;
  Rect got;
  assert(bd.CropRgba(Rect{0, 0, 4, 3}, &out, &got));
  assert(got.width == 4 && got.height == 3);
  assert(out[0] == 30 && out[1] == 20 && out[2] == 10 && out[3] == 255);
  assert(!bd.has_unprimed());
}

void RgbxOrderIsKept() {
  Backdrop bd;
  auto f = Solid(2, 2, 10, 20, 30);  // バイト列そのものは 10,20,30
  bd.Merge(f.data(), 2, 2, 8, PixelOrder::kRgbx, {});
  std::vector<uint8_t> out;
  Rect got;
  assert(bd.CropRgba(Rect{0, 0, 2, 2}, &out, &got));
  assert(out[0] == 10 && out[1] == 20 && out[2] == 30 && out[3] == 255);
}

void ExcludedPixelsKeepPreviousFrame() {
  Backdrop bd;
  auto a = Solid(8, 8, 0, 0, 100);
  bd.Merge(a.data(), 8, 8, 32, PixelOrder::kBgrx, {});
  auto b = Solid(8, 8, 0, 0, 200);
  // (2,2)-(5,5) は自分の窓が写っているとして書き込まない。
  bd.Merge(b.data(), 8, 8, 32, PixelOrder::kBgrx, {Rect{2, 2, 4, 4}});
  std::vector<uint8_t> out;
  Rect got;
  assert(bd.CropRgba(Rect{0, 0, 8, 8}, &out, &got));
  assert(RedAt(out, 8, 0, 0) == 200);
  assert(RedAt(out, 8, 2, 2) == 100);
  assert(RedAt(out, 8, 5, 5) == 100);
  assert(RedAt(out, 8, 6, 5) == 200);
  assert(RedAt(out, 8, 5, 6) == 200);
}

void OverlappingExclusionsAreMerged() {
  Backdrop bd;
  auto a = Solid(10, 2, 0, 0, 1);
  bd.Merge(a.data(), 10, 2, 40, PixelOrder::kBgrx, {});
  auto b = Solid(10, 2, 0, 0, 2);
  bd.Merge(b.data(), 10, 2, 40, PixelOrder::kBgrx,
           {Rect{1, 0, 3, 2}, Rect{2, 0, 4, 2}, Rect{8, 0, 1, 2}});
  std::vector<uint8_t> out;
  Rect got;
  assert(bd.CropRgba(Rect{0, 0, 10, 2}, &out, &got));
  const uint8_t expect[10] = {2, 1, 1, 1, 1, 1, 2, 2, 1, 2};
  for (int x = 0; x < 10; ++x) assert(RedAt(out, 10, x, 1) == expect[x]);
}

void UnprimedPixelsAreBlackUntilCaptured() {
  Backdrop bd;
  auto a = Solid(4, 4, 0, 0, 50);
  bd.Merge(a.data(), 4, 4, 16, PixelOrder::kBgrx, {Rect{0, 0, 2, 2}});
  assert(bd.has_unprimed());
  std::vector<uint8_t> out;
  Rect got;
  assert(bd.CropRgba(Rect{0, 0, 4, 4}, &out, &got));
  assert(RedAt(out, 4, 0, 0) == 0 && out[3] == 255);
  assert(RedAt(out, 4, 3, 3) == 50);
  bd.Merge(a.data(), 4, 4, 16, PixelOrder::kBgrx, {});
  assert(!bd.has_unprimed());
}

void SizeChangeResets() {
  Backdrop bd;
  auto a = Solid(4, 4, 0, 0, 50);
  bd.Merge(a.data(), 4, 4, 16, PixelOrder::kBgrx, {});
  auto b = Solid(6, 4, 0, 0, 60);
  bd.Merge(b.data(), 6, 4, 24, PixelOrder::kBgrx, {Rect{0, 0, 1, 1}});
  assert(bd.width() == 6);
  assert(bd.has_unprimed());
}

void StrideLargerThanRowIsHonoured() {
  Backdrop bd;
  std::vector<uint8_t> f(2 * 8, 0);  // 幅 1・stride 8（後ろ 4 バイトは詰め物）
  f[2] = 77;                         // 1 行目の R
  f[8 + 2] = 88;                     // 2 行目の R
  bd.Merge(f.data(), 1, 2, 8, PixelOrder::kBgrx, {});
  std::vector<uint8_t> out;
  Rect got;
  assert(bd.CropRgba(Rect{0, 0, 1, 2}, &out, &got));
  assert(RedAt(out, 1, 0, 0) == 77 && RedAt(out, 1, 0, 1) == 88);
}

void CropIsClippedToBounds() {
  Backdrop bd;
  auto a = Solid(4, 4, 0, 0, 9);
  bd.Merge(a.data(), 4, 4, 16, PixelOrder::kBgrx, {});
  std::vector<uint8_t> out;
  Rect got;
  assert(bd.CropRgba(Rect{-2, 2, 4, 10}, &out, &got));
  assert(got.x == 0 && got.y == 2 && got.width == 2 && got.height == 2);
  assert(out.size() == 2 * 2 * 4);
  assert(!bd.CropRgba(Rect{10, 10, 2, 2}, &out, &got));
}

void InvalidFrameIsIgnored() {
  Backdrop bd;
  auto a = Solid(4, 4, 0, 0, 9);
  bd.Merge(a.data(), 4, 4, 8, PixelOrder::kBgrx, {});  // stride が足りない
  assert(bd.width() == 0);
  bd.Merge(nullptr, 4, 4, 16, PixelOrder::kBgrx, {});
  assert(bd.width() == 0);
}

void TrackerInflatesByMargin() {
  ExclusionTracker t(300, 5);
  t.Record(1000, Rect{10, 10, 20, 20});
  auto ex = t.Exclusions(1000);
  assert(ex.size() == 1);
  assert(ex[0].x == 5 && ex[0].y == 5 && ex[0].width == 30);
}

void TrackerKeepsHistoryAndPredicts() {
  ExclusionTracker t(300, 0);
  t.Record(1000, Rect{0, 0, 10, 10});
  t.Record(1016, Rect{20, 0, 10, 10});
  auto ex = t.Exclusions(1016);
  // 2 つの履歴 + 外挿（20 + 20*2 = 60）。
  assert(ex.size() == 3);
  assert(ex[0].x == 0 && ex[1].x == 20 && ex[2].x == 60);
}

void TrackerDropsOldButKeepsLatest() {
  ExclusionTracker t(300, 0);
  t.Record(0, Rect{0, 0, 10, 10});
  t.Record(100, Rect{0, 0, 10, 10});
  auto ex = t.Exclusions(10000);
  // 古い記録は落ちるが、止まっている窓（最新）は除外し続ける。
  assert(ex.size() == 1);
  t.Record(10000, Rect{50, 0, 10, 10});
  ex = t.Exclusions(10000);
  // 0ms・100ms の記録は 10000-300 より古いので消え、最新 1 件だけ残る
  // （履歴が 1 件なので外挿もしない）。
  assert(ex.size() == 1);
  assert(ex[0].x == 50);
}

void TrackerHiddenExcludesNothing() {
  ExclusionTracker t(300, 4);
  t.Record(0, Rect{0, 0, 10, 10});
  t.SetHidden(true);
  assert(t.Exclusions(0).empty());
  t.SetHidden(false);
  assert(t.Exclusions(0).size() == 1);
}

struct Case {
  const char* name;
  std::function<void()> run;
};

const Case kCases[] = {
    {"merge_without_exclusion_copies_and_swizzles",
     MergeWithoutExclusionCopiesAndSwizzles},
    {"rgbx_order_is_kept", RgbxOrderIsKept},
    {"excluded_pixels_keep_previous_frame", ExcludedPixelsKeepPreviousFrame},
    {"overlapping_exclusions_are_merged", OverlappingExclusionsAreMerged},
    {"unprimed_pixels_are_black_until_captured",
     UnprimedPixelsAreBlackUntilCaptured},
    {"size_change_resets", SizeChangeResets},
    {"stride_larger_than_row_is_honoured", StrideLargerThanRowIsHonoured},
    {"crop_is_clipped_to_bounds", CropIsClippedToBounds},
    {"invalid_frame_is_ignored", InvalidFrameIsIgnored},
    {"tracker_inflates_by_margin", TrackerInflatesByMargin},
    {"tracker_keeps_history_and_predicts", TrackerKeepsHistoryAndPredicts},
    {"tracker_drops_old_but_keeps_latest", TrackerDropsOldButKeepsLatest},
    {"tracker_hidden_excludes_nothing", TrackerHiddenExcludesNothing},
};

}  // namespace

int main(int argc, char** argv) {
  for (const Case& c : kCases) {
    if (argc < 2 || std::strcmp(argv[1], c.name) == 0) {
      c.run();
      std::printf("ok %s\n", c.name);
      if (argc >= 2) return 0;
    }
  }
  if (argc >= 2) {
    std::printf("unknown case %s\n", argv[1]);
    return 1;
  }
  return 0;
}
