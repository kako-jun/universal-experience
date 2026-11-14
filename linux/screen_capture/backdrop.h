// ルーペ窓の「下の画面」の控え（#180）。
//
// Wayland の画面キャプチャ（xdg-desktop-portal ScreenCast）は自分の窓を除外して
// 撮れない。そのまま窓の矩形を切り出すと、自分が描いたフィルタ済みの絵を撮って
// もう一度フィルタする帰還（フィードバック）になる。そこで、フレームごとに
// 「自分の窓が写っている矩形（除外矩形）」以外だけを控えへ書き込み、窓の下は
// 窓が来る前（または窓を一瞬隠した間）に撮れた画素を使う。
//
// GTK / PipeWire に依存しない純粋なロジック。linux/test/ で単体テストする。
#ifndef UE_SCREEN_CAPTURE_BACKDROP_H_
#define UE_SCREEN_CAPTURE_BACKDROP_H_

#include <cstdint>
#include <vector>

namespace ue_capture {

// 画面上の矩形（右端・下端は含まない）。単位はキャプチャのピクセル。
struct Rect {
  int x = 0;
  int y = 0;
  int width = 0;
  int height = 0;

  bool empty() const { return width <= 0 || height <= 0; }
  int right() const { return x + width; }
  int bottom() const { return y + height; }
};

// 2 つの矩形の共通部分（交わらなければ空）。
Rect Intersect(const Rect& a, const Rect& b);

// 矩形を四方に margin だけ広げる（負なら縮める）。
Rect Inflate(const Rect& r, int margin);

// 入力フレームの 1 画素 4 バイトの並び。
enum class PixelOrder {
  kBgrx,  // B, G, R, X（または A）
  kRgbx,  // R, G, B, X（または A）
};

// 全画面ぶんの控え。フレームの画素は入力の並びのまま保持し（行ごとの memcpy で
// 済ませる）、切り出し時だけ RGBA へ並べ替える。
class Backdrop {
 public:
  Backdrop() = default;

  int width() const { return width_; }
  int height() const { return height_; }

  // まだ一度も書き込まれていない画素が残っているか（窓の下を一度も撮れていない）。
  bool has_unprimed() const { return unprimed_count_ > 0; }

  // フレームを書き込む。exclusions のどれかに入る画素は書き込まない（前の値を残す）。
  // フレームの大きさ・並びが変わったら控えを作り直す（全画素が未取得に戻る）。
  void Merge(const uint8_t* src, int width, int height, int stride,
             PixelOrder order, const std::vector<Rect>& exclusions);

  // rect（控えの範囲で切り詰める）を RGBA（A=255）で out に書き出す。
  // 一度も書き込まれていない画素は不透明の黒。切り詰めた結果が空なら false。
  // out_rect には実際に切り出した矩形を返す。
  bool CropRgba(const Rect& rect, std::vector<uint8_t>* out,
                Rect* out_rect) const {
    return CropRgba(rect, 0, out, out_rect, nullptr, nullptr);
  }

  // 上と同じだが、切り詰めた矩形の画素数が max_pixels（0 以下なら無制限）を超える
  // ときは、縦横を同じ整数 step（ceil(sqrt(画素数 / max_pixels))）で割った大きさ
  // （切り捨て、最小 1）へ最近傍で間引いて書き出す。間引いた画素は切り出した矩形の
  // 全幅・全高へ均等に割り付ける（右端・下端を取りこぼして縮尺がずれないように）。
  // out_width / out_height には書き出した大きさを返す（null 可）。
  bool CropRgba(const Rect& rect, int64_t max_pixels, std::vector<uint8_t>* out,
                Rect* out_rect, int* out_width, int* out_height) const;

 private:
  void Reset(int width, int height, PixelOrder order);

  int width_ = 0;
  int height_ = 0;
  PixelOrder order_ = PixelOrder::kBgrx;
  std::vector<uint8_t> pixels_;   // width_ * height_ * 4、入力の並び。
  std::vector<uint8_t> primed_;   // 画素ごとに書き込み済みなら 1。
  int64_t unprimed_count_ = 0;
};

// 窓の位置の履歴から、フレームを控えへ書き込むときの除外矩形を決める。
//
// 合成器がフレームを描いた瞬間の窓の位置と、こちらが知っている位置は少しずれる
// （移動中・リサイズ中は特に）。そのため、直近 history_ms の間に窓があった矩形を
// すべて除外し、さらに直近 2 件の四辺それぞれの変化量（移動と幅・高さの増減）から
// 次の矩形を外挿した矩形も除外する。各矩形は margin だけ広げる（影・枠の取りこぼし
// 対策）。
class ExclusionTracker {
 public:
  ExclusionTracker(int64_t history_ms, int margin)
      : history_ms_(history_ms), margin_(margin) {}

  // now_ms 時点で窓が rect にあったことを記録する。
  void Record(int64_t now_ms, const Rect& rect);

  // 窓を隠している間は除外しない（窓の下をそのまま撮る）。
  void SetHidden(bool hidden) { hidden_ = hidden; }
  bool hidden() const { return hidden_; }

  // now_ms 時点の除外矩形。
  std::vector<Rect> Exclusions(int64_t now_ms) const;

 private:
  struct Sample {
    int64_t at_ms;
    Rect rect;
  };

  int64_t history_ms_;
  int margin_;
  bool hidden_ = false;
  std::vector<Sample> samples_;
};

}  // namespace ue_capture

#endif  // UE_SCREEN_CAPTURE_BACKDROP_H_
