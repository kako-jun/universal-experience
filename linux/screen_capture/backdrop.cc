#include "backdrop.h"

#include <algorithm>
#include <cmath>
#include <cstring>

namespace ue_capture {

Rect Intersect(const Rect& a, const Rect& b) {
  const int x0 = std::max(a.x, b.x);
  const int y0 = std::max(a.y, b.y);
  const int x1 = std::min(a.right(), b.right());
  const int y1 = std::min(a.bottom(), b.bottom());
  if (x1 <= x0 || y1 <= y0) return Rect{};
  return Rect{x0, y0, x1 - x0, y1 - y0};
}

Rect Inflate(const Rect& r, int margin) {
  return Rect{r.x - margin, r.y - margin, r.width + 2 * margin,
              r.height + 2 * margin};
}

void Backdrop::Reset(int width, int height, PixelOrder order) {
  width_ = width;
  height_ = height;
  order_ = order;
  const size_t n = static_cast<size_t>(width) * static_cast<size_t>(height);
  pixels_.assign(n * 4, 0);
  primed_.assign(n, 0);
  unprimed_count_ = static_cast<int64_t>(n);
}

void Backdrop::Merge(const uint8_t* src, int width, int height, int stride,
                     PixelOrder order, const std::vector<Rect>& exclusions) {
  if (src == nullptr || width <= 0 || height <= 0 || stride < width * 4) {
    return;
  }
  if (width != width_ || height != height_ || order != order_) {
    Reset(width, height, order);
  }
  const Rect bounds{0, 0, width, height};
  std::vector<Rect> clipped;
  clipped.reserve(exclusions.size());
  for (const Rect& e : exclusions) {
    const Rect c = Intersect(e, bounds);
    if (!c.empty()) clipped.push_back(c);
  }

  // 行ごとに、除外区間を除いた区間だけを memcpy する。
  std::vector<std::pair<int, int>> spans;
  for (int y = 0; y < height; ++y) {
    spans.clear();
    for (const Rect& c : clipped) {
      if (y >= c.y && y < c.bottom()) spans.emplace_back(c.x, c.right());
    }
    std::sort(spans.begin(), spans.end());
    const uint8_t* src_row = src + static_cast<size_t>(y) * stride;
    uint8_t* dst_row = pixels_.data() + static_cast<size_t>(y) * width * 4;
    uint8_t* primed_row = primed_.data() + static_cast<size_t>(y) * width;
    int x = 0;
    size_t i = 0;
    while (x < width) {
      // x 以降で最初に始まる除外区間（x を含むものも）を探す。
      int next_start = width;
      int next_end = width;
      for (; i < spans.size(); ++i) {
        if (spans[i].second <= x) continue;
        next_start = std::max(spans[i].first, x);
        next_end = spans[i].second;
        break;
      }
      if (next_start > x) {
        const int n = next_start - x;
        std::memcpy(dst_row + x * 4, src_row + x * 4,
                    static_cast<size_t>(n) * 4);
        // 全画素が取得済みになった後は印を数え直さない（毎フレームの負荷を抑える）。
        if (unprimed_count_ > 0) {
          for (int k = x; k < next_start; ++k) {
            if (!primed_row[k]) {
              primed_row[k] = 1;
              --unprimed_count_;
            }
          }
        }
      }
      if (next_start >= width) break;
      // 重なった除外区間をまとめて飛ばす。
      int skip_to = next_end;
      for (size_t j = i + 1; j < spans.size() && spans[j].first <= skip_to;
           ++j) {
        skip_to = std::max(skip_to, spans[j].second);
      }
      x = skip_to;
    }
  }
}

bool Backdrop::CropRgba(const Rect& rect, int64_t max_pixels,
                        std::vector<uint8_t>* out, Rect* out_rect,
                        int* out_width, int* out_height) const {
  const Rect c = Intersect(rect, Rect{0, 0, width_, height_});
  if (c.empty() || out == nullptr) return false;

  int step = 1;
  const int64_t pixels = static_cast<int64_t>(c.width) * c.height;
  if (max_pixels > 0 && pixels > max_pixels) {
    step = static_cast<int>(
        std::ceil(std::sqrt(static_cast<double>(pixels) / max_pixels)));
    // 短い辺が step 未満だと出力は最小 1 に張り付き、長い辺 / step だけで上限を
    // 超えうる（例: 1x10000 を 100 画素へ → step 10 で 1x1000）。そのときは長い辺の
    // 出力が max_pixels 以下になる step（floor(長い辺 / (max_pixels + 1)) + 1 以上）まで
    // 大きくする。両辺とも step 以上なら (w/step)(h/step) <= 画素数/step^2 <= 上限。
    const int short_side = std::min(c.width, c.height);
    const int long_side = std::max(c.width, c.height);
    if (short_side < step) {
      const int64_t need = long_side / (max_pixels + 1) + 1;
      if (need > step) step = static_cast<int>(need);
    }
  }
  const int ow = std::max(1, c.width / step);
  const int oh = std::max(1, c.height / step);
  // 出力の各列・各行が読む控えの列・行。間引かないときは恒等。間引くときは
  // 出力の画素の中心を切り出した矩形の全幅・全高へ均等に写す。
  std::vector<int> cols(static_cast<size_t>(ow));
  for (int x = 0; x < ow; ++x) {
    cols[x] = c.x + static_cast<int>((static_cast<int64_t>(2 * x + 1) *
                                      c.width) /
                                     (2 * static_cast<int64_t>(ow)));
  }

  out->resize(static_cast<size_t>(ow) * oh * 4);
  uint8_t* dst = out->data();
  const bool bgr = order_ == PixelOrder::kBgrx;
  for (int oy = 0; oy < oh; ++oy) {
    const int y = c.y + static_cast<int>((static_cast<int64_t>(2 * oy + 1) *
                                          c.height) /
                                         (2 * static_cast<int64_t>(oh)));
    const size_t row_start = static_cast<size_t>(y) * width_;
    const uint8_t* src_row = pixels_.data() + row_start * 4;
    const uint8_t* primed_row = primed_.data() + row_start;
    for (int ox = 0; ox < ow; ++ox) {
      const int x = cols[ox];
      const uint8_t* src = src_row + static_cast<size_t>(x) * 4;
      if (primed_row[x]) {
        dst[0] = bgr ? src[2] : src[0];
        dst[1] = src[1];
        dst[2] = bgr ? src[0] : src[2];
      } else {
        dst[0] = dst[1] = dst[2] = 0;
      }
      dst[3] = 255;
      dst += 4;
    }
  }
  if (out_rect != nullptr) *out_rect = c;
  if (out_width != nullptr) *out_width = ow;
  if (out_height != nullptr) *out_height = oh;
  return true;
}

void ExclusionTracker::Record(int64_t now_ms, const Rect& rect) {
  samples_.push_back(Sample{now_ms, rect});
  // 古い記録を捨てる。ただし最新の 1 件は必ず残す（窓が止まっていても除外は続く）。
  while (samples_.size() > 1 && samples_.front().at_ms < now_ms - history_ms_) {
    samples_.erase(samples_.begin());
  }
}

std::vector<Rect> ExclusionTracker::Exclusions(int64_t now_ms) const {
  std::vector<Rect> out;
  if (hidden_ || samples_.empty()) return out;
  for (const Sample& s : samples_) {
    if (&s != &samples_.back() && s.at_ms < now_ms - history_ms_) continue;
    out.push_back(Inflate(s.rect, margin_));
  }
  // 直近 2 件の四辺の変化量から次の矩形を外挿する（移動中の先端・速いリサイズで
  // 広がる辺の取りこぼし対策）。左上の移動だけでなく、右端・下端の移動（幅・高さの
  // 増減）も別々に見込む。
  if (samples_.size() >= 2) {
    const Rect& a = samples_[samples_.size() - 2].rect;
    const Rect& b = samples_.back().rect;
    const int dl = b.x - a.x;
    const int dt = b.y - a.y;
    const int dr = b.right() - a.right();
    const int db = b.bottom() - a.bottom();
    if (dl != 0 || dt != 0 || dr != 0 || db != 0) {
      // 2 回分先まで見込む（合成器の 1〜2 フレームの先行を覆う）。
      const int left = b.x + dl * 2;
      const int top = b.y + dt * 2;
      const int right = b.right() + dr * 2;
      const int bottom = b.bottom() + db * 2;
      if (right > left && bottom > top) {
        out.push_back(
            Inflate(Rect{left, top, right - left, bottom - top}, margin_));
      }
    }
  }
  return out;
}

uint64_t CaptureState::BeginSession() {
  backdrop = Backdrop();
  sequence = 0;
  tracker.SetHidden(false);
  return ++session_;
}

bool CaptureState::MergeFrame(uint64_t session, const uint8_t* src, int width,
                              int height, int stride, PixelOrder order,
                              int64_t now_ms) {
  if (session != session_) return false;
  backdrop.Merge(src, width, height, stride, order, tracker.Exclusions(now_ms));
  ++sequence;
  return true;
}

}  // namespace ue_capture
