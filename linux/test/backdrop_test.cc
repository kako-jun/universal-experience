// screen_capture/backdrop の単体テスト (#180)。1 ケース 1 ctest エントリ。
#include "screen_capture/backdrop.h"

#include <cassert>
#include <cstdio>
#include <cstring>
#include <functional>
#include <string>
#include <vector>

using ue_capture::Backdrop;
using ue_capture::CaptureState;
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

void TrackerPredictsResize() {
  ExclusionTracker t(300, 0);
  // 左上は止まったまま、右端・下端だけが広がる（速いリサイズ）。
  t.Record(1000, Rect{100, 100, 50, 40});
  t.Record(1016, Rect{100, 100, 80, 60});
  auto ex = t.Exclusions(1016);
  assert(ex.size() == 3);
  // 右端 180 → +30*2 = 240、下端 160 → +20*2 = 200。
  const Rect& p = ex[2];
  assert(p.x == 100 && p.y == 100);
  assert(p.right() == 240 && p.bottom() == 200);
}

void TrackerPredictsMoveAndResizeTogether() {
  ExclusionTracker t(300, 0);
  // 左端を左へ引っ張るリサイズ（左上が動き、右端は止まる）。
  t.Record(1000, Rect{100, 0, 50, 10});
  t.Record(1016, Rect{90, 0, 60, 10});
  auto ex = t.Exclusions(1016);
  assert(ex.size() == 3);
  assert(ex[2].x == 70 && ex[2].right() == 150);
}

void CropUnderLimitIsNotDecimated() {
  Backdrop bd;
  auto a = Solid(4, 4, 0, 0, 9);
  bd.Merge(a.data(), 4, 4, 16, PixelOrder::kBgrx, {});
  std::vector<uint8_t> out;
  Rect got;
  int w = 0;
  int h = 0;
  assert(bd.CropRgba(Rect{0, 0, 4, 4}, 16, &out, &got, &w, &h));
  assert(w == 4 && h == 4 && out.size() == 4 * 4 * 4);
}

// 画素の R に x 座標、G に y 座標を入れた w x h のフレーム（BGRX）。
std::vector<uint8_t> Coords(int w, int h) {
  std::vector<uint8_t> v(static_cast<size_t>(w) * h * 4);
  for (int y = 0; y < h; ++y) {
    for (int x = 0; x < w; ++x) {
      uint8_t* p = v.data() + (static_cast<size_t>(y) * w + x) * 4;
      p[0] = 0;
      p[1] = static_cast<uint8_t>(y);
      p[2] = static_cast<uint8_t>(x);
      p[3] = 0;
    }
  }
  return v;
}

void CropDecimatesAcrossFullExtent() {
  Backdrop bd;
  // 幅 11 は step 2 で割り切れない（以前は右端の 1 列を落として縮尺がずれた）。
  auto a = Coords(11, 7);
  bd.Merge(a.data(), 11, 7, 44, PixelOrder::kBgrx, {});
  std::vector<uint8_t> out;
  Rect got;
  int w = 0;
  int h = 0;
  // 77 画素 > 20 → step = ceil(sqrt(3.85)) = 2 → 5 x 3。
  assert(bd.CropRgba(Rect{0, 0, 11, 7}, 20, &out, &got, &w, &h));
  assert(got.width == 11 && got.height == 7);
  assert(w == 5 && h == 3);
  assert(out.size() == static_cast<size_t>(w) * h * 4);
  // 各出力画素は、切り出した全幅・全高を均等に割った区間の中心を読む。
  // x: (2i+1)*11/10 → 1, 3, 5, 7, 9。y: (2j+1)*7/6 → 1, 3, 5。
  const int xs[5] = {1, 3, 5, 7, 9};
  const int ys[3] = {1, 3, 5};
  for (int j = 0; j < h; ++j) {
    for (int i = 0; i < w; ++i) {
      const uint8_t* p = out.data() + (static_cast<size_t>(j) * w + i) * 4;
      assert(p[0] == xs[i]);
      assert(p[1] == ys[j]);
      assert(p[3] == 255);
    }
  }
  // 右端・下端の近く（最後の区間）を必ず読む。
  assert(out[(static_cast<size_t>(h - 1) * w + (w - 1)) * 4] >= 9);
}

void CropDecimatesOffsetRect() {
  Backdrop bd;
  auto a = Coords(20, 20);
  bd.Merge(a.data(), 20, 20, 80, PixelOrder::kBgrx, {});
  std::vector<uint8_t> out;
  Rect got;
  int w = 0;
  int h = 0;
  // (5,5) から 9x9 = 81 > 9 → step 3 → 3 x 3、読む列は 5 + (2i+1)*9/6 = 6, 9, 12。
  assert(bd.CropRgba(Rect{5, 5, 9, 9}, 9, &out, &got, &w, &h));
  assert(w == 3 && h == 3);
  assert(out[0] == 6 && out[1] == 6);
  assert(out[(2 * 3 + 2) * 4] == 12 && out[(2 * 3 + 2) * 4 + 1] == 12);
}

void CropThinRectStaysUnderLimit() {
  Backdrop bd;
  // 幅 1・高さ 1000（細い窓）を 100 画素へ。基本の step = ceil(sqrt(10)) = 4 だと
  // 幅は最小 1 に張り付いて 1x250 になり上限を超える。
  auto a = Coords(1, 1000);
  bd.Merge(a.data(), 1, 1000, 4, PixelOrder::kBgrx, {});
  std::vector<uint8_t> out;
  Rect got;
  int w = 0;
  int h = 0;
  assert(bd.CropRgba(Rect{0, 0, 1, 1000}, 100, &out, &got, &w, &h));
  assert(w == 1);
  assert(static_cast<int64_t>(w) * h <= 100);
  assert(h >= 90);  // 必要以上に縮めない（step 10 → 100）。
  assert(out.size() == static_cast<size_t>(w) * h * 4);
  // 横長も同じ。
  auto b = Coords(1000, 2);
  bd.Merge(b.data(), 1000, 2, 4000, PixelOrder::kBgrx, {});
  assert(bd.CropRgba(Rect{0, 0, 1000, 2}, 50, &out, &got, &w, &h));
  assert(h == 1);
  assert(static_cast<int64_t>(w) * h <= 50);
  assert(w >= 45);
}

void CropDecimationNeverExceedsLimit() {
  Backdrop bd;
  auto a = Solid(300, 300, 0, 0, 1);
  bd.Merge(a.data(), 300, 300, 1200, PixelOrder::kBgrx, {});
  std::vector<uint8_t> out;
  Rect got;
  int w = 0;
  int h = 0;
  const int64_t limits[] = {1, 2, 7, 50, 99, 1000, 4321};
  const Rect rects[] = {Rect{0, 0, 1, 300},  Rect{0, 0, 300, 1},
                        Rect{0, 0, 2, 300},  Rect{0, 0, 300, 3},
                        Rect{0, 0, 300, 300}, Rect{5, 7, 123, 45}};
  for (int64_t limit : limits) {
    for (const Rect& r : rects) {
      assert(bd.CropRgba(r, limit, &out, &got, &w, &h));
      assert(w >= 1 && h >= 1);
      assert(static_cast<int64_t>(w) * h <= limit);
    }
  }
}

void SessionDropsFramesOfOldSession() {
  CaptureState st(300, 0);
  const uint64_t first = st.BeginSession();
  auto a = Solid(4, 4, 0, 0, 10);
  assert(st.MergeFrame(first, a.data(), 4, 4, 16, PixelOrder::kBgrx, 0));
  assert(st.sequence == 1 && st.backdrop.width() == 4);

  // 新しい共有を始めると控えとフレーム番号が空になる。
  const uint64_t second = st.BeginSession();
  assert(second != first);
  assert(st.sequence == 0 && st.backdrop.width() == 0);

  // 古い共有のフレーム（止める直前に届いたもの）は新しい控えに入らない。
  auto old = Solid(4, 4, 0, 0, 99);
  assert(!st.MergeFrame(first, old.data(), 4, 4, 16, PixelOrder::kBgrx, 0));
  assert(st.sequence == 0 && st.backdrop.width() == 0);

  auto b = Solid(4, 4, 0, 0, 20);
  assert(st.MergeFrame(second, b.data(), 4, 4, 16, PixelOrder::kBgrx, 0));
  std::vector<uint8_t> out;
  Rect got;
  assert(st.backdrop.CropRgba(Rect{0, 0, 4, 4}, &out, &got));
  assert(RedAt(out, 4, 0, 0) == 20);
}

void SessionBeginResumesExclusion() {
  CaptureState st(300, 0);
  st.BeginSession();
  st.tracker.Record(0, Rect{0, 0, 2, 2});
  st.tracker.SetHidden(true);
  st.BeginSession();
  assert(!st.tracker.hidden());
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
    {"tracker_predicts_resize", TrackerPredictsResize},
    {"tracker_predicts_move_and_resize_together",
     TrackerPredictsMoveAndResizeTogether},
    {"crop_under_limit_is_not_decimated", CropUnderLimitIsNotDecimated},
    {"crop_decimates_across_full_extent", CropDecimatesAcrossFullExtent},
    {"crop_decimates_offset_rect", CropDecimatesOffsetRect},
    {"crop_thin_rect_stays_under_limit", CropThinRectStaysUnderLimit},
    {"crop_decimation_never_exceeds_limit", CropDecimationNeverExceedsLimit},
    {"session_drops_frames_of_old_session", SessionDropsFramesOfOldSession},
    {"session_begin_resumes_exclusion", SessionBeginResumesExclusion},
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
