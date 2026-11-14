#include "backdrop.h"

#include <algorithm>
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

bool Backdrop::CropRgba(const Rect& rect, std::vector<uint8_t>* out,
                        Rect* out_rect) const {
  const Rect c = Intersect(rect, Rect{0, 0, width_, height_});
  if (c.empty() || out == nullptr) return false;
  out->resize(static_cast<size_t>(c.width) * c.height * 4);
  uint8_t* dst = out->data();
  const bool bgr = order_ == PixelOrder::kBgrx;
  for (int y = c.y; y < c.bottom(); ++y) {
    const size_t row_start = static_cast<size_t>(y) * width_ + c.x;
    const uint8_t* src = pixels_.data() + row_start * 4;
    const uint8_t* primed = primed_.data() + row_start;
    for (int x = 0; x < c.width; ++x) {
      if (primed[x]) {
        dst[0] = bgr ? src[2] : src[0];
        dst[1] = src[1];
        dst[2] = bgr ? src[0] : src[2];
      } else {
        dst[0] = dst[1] = dst[2] = 0;
      }
      dst[3] = 255;
      src += 4;
      dst += 4;
    }
  }
  if (out_rect != nullptr) *out_rect = c;
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
  // 直近 2 件の移動量から次の位置を外挿する（移動中の先端の取りこぼし対策）。
  if (samples_.size() >= 2) {
    const Rect& a = samples_[samples_.size() - 2].rect;
    const Rect& b = samples_.back().rect;
    const int dx = b.x - a.x;
    const int dy = b.y - a.y;
    if (dx != 0 || dy != 0) {
      Rect predicted = b;
      // 2 回分先まで見込む（合成器の 1〜2 フレームの先行を覆う）。
      predicted.x += dx * 2;
      predicted.y += dy * 2;
      out.push_back(Inflate(predicted, margin_));
    }
  }
  return out;
}

}  // namespace ue_capture
