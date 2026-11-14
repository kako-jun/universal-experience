#include "screen_capture_plugin.h"

#include <gtk/gtk.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include <cmath>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include "backdrop.h"
#include "screen_cast.h"

namespace {

using ue_capture::Backdrop;
using ue_capture::ExclusionTracker;
using ue_capture::PixelOrder;
using ue_capture::Rect;
using ue_capture::ScreenCast;
using ue_capture::StartError;
using ue_capture::StartResult;

constexpr const char* kChannel = "universal_experience/live_capture";

// 窓の位置の履歴を除外に使う長さと、除外矩形を広げる量（キャプチャのピクセル）。
// 合成器のフレームと窓の位置の通知のずれ（移動中の 1〜数フレーム）を覆う値。
constexpr int64_t kExclusionHistoryMs = 300;
constexpr int kExclusionMargin = 24;

struct Plugin {
  FlMethodChannel* channel = nullptr;
  FlView* view = nullptr;
  ScreenCast cast;

  std::mutex mutex;  // 以下はストリームのスレッドと共有する。
  Backdrop backdrop;
  ExclusionTracker tracker{kExclusionHistoryMs, kExclusionMargin};
  int64_t sequence = 0;

  // メインスレッドだけで使う。
  FlMethodCall* pending_start = nullptr;
  int64_t last_sent_sequence = -1;
  Rect last_sent_rect;
};

int64_t NowMs() { return g_get_monotonic_time() / 1000; }

bool IsX11Backend(FlView* view) {
#ifdef GDK_WINDOWING_X11
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(view));
  return GDK_IS_X11_DISPLAY(display);
#else
  (void)view;
  return false;
#endif
}

// 窓の矩形（ビュー＝Flutter の描画域、枠込みの外形）を、キャプチャのピクセル座標で求める。
// X11（XWayland を含む）のルート座標を、窓のいるモニタの範囲でフレームの大きさへ写す。
bool WindowRects(Plugin* self, int frame_w, int frame_h, Rect* view_rect,
                 Rect* outer_rect) {
  GtkWidget* widget = GTK_WIDGET(self->view);
  GdkWindow* window = gtk_widget_get_window(widget);
  if (window == nullptr || frame_w <= 0 || frame_h <= 0) return false;
  GdkWindow* toplevel = gdk_window_get_toplevel(window);
  const int scale = gdk_window_get_scale_factor(window);

  int ox = 0;
  int oy = 0;
  gdk_window_get_origin(window, &ox, &oy);
  const int vw = gtk_widget_get_allocated_width(widget);
  const int vh = gtk_widget_get_allocated_height(widget);
  GdkRectangle frame;
  gdk_window_get_frame_extents(toplevel, &frame);

  GdkDisplay* display = gdk_window_get_display(toplevel);
  GdkMonitor* monitor = gdk_display_get_monitor_at_window(display, toplevel);
  if (monitor == nullptr) return false;
  GdkRectangle geometry;
  gdk_monitor_get_geometry(monitor, &geometry);
  if (geometry.width <= 0 || geometry.height <= 0) return false;

  // ルート座標（GDK 単位 × scale = X11 のピクセル）→ フレームのピクセル。
  const double sx = static_cast<double>(frame_w) / (geometry.width * scale);
  const double sy = static_cast<double>(frame_h) / (geometry.height * scale);
  auto map = [&](int x, int y, int w, int h) {
    const double x0 = (x - geometry.x) * scale * sx;
    const double y0 = (y - geometry.y) * scale * sy;
    const double x1 = (x + w - geometry.x) * scale * sx;
    const double y1 = (y + h - geometry.y) * scale * sy;
    Rect r;
    r.x = static_cast<int>(std::floor(x0));
    r.y = static_cast<int>(std::floor(y0));
    r.width = static_cast<int>(std::ceil(x1)) - r.x;
    r.height = static_cast<int>(std::ceil(y1)) - r.y;
    return r;
  };
  *view_rect = map(ox, oy, vw, vh);
  *outer_rect = map(frame.x, frame.y, frame.width, frame.height);
  return true;
}

// 今の窓の外形を除外の履歴へ記録する（mutex を取った状態で呼ぶ）。
void RecordWindowLocked(Plugin* self) {
  Rect view_rect;
  Rect outer_rect;
  if (WindowRects(self, self->backdrop.width(), self->backdrop.height(),
                  &view_rect, &outer_rect)) {
    self->tracker.Record(NowMs(), outer_rect);
  }
}

gboolean OnConfigure(GtkWidget*, GdkEvent*, gpointer user_data) {
  auto* self = static_cast<Plugin*>(user_data);
  std::lock_guard<std::mutex> lock(self->mutex);
  RecordWindowLocked(self);
  return FALSE;
}

FlValue* StartResultValue(const StartResult& result) {
  FlValue* map = fl_value_new_map();
  fl_value_set_string_take(map, "error",
                           fl_value_new_string(StartErrorName(result.error)));
  fl_value_set_string_take(map, "message",
                           fl_value_new_string(result.message.c_str()));
  fl_value_set_string_take(map, "restoreToken",
                           fl_value_new_string(result.restore_token.c_str()));
  return map;
}

void Respond(FlMethodCall* call, FlValue* value) {
  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_success_response_new(value));
  fl_method_call_respond(call, response, nullptr);
}

std::string ParentWindow(Plugin* self) {
#ifdef GDK_WINDOWING_X11
  GdkWindow* window = gtk_widget_get_window(GTK_WIDGET(self->view));
  if (window != nullptr && GDK_IS_X11_WINDOW(window)) {
    char buf[32];
    std::snprintf(buf, sizeof(buf), "x11:%lx",
                  static_cast<unsigned long>(
                      gdk_x11_window_get_xid(gdk_window_get_toplevel(window))));
    return buf;
  }
#endif
  return "";
}

void HandleStart(Plugin* self, FlMethodCall* call) {
  if (self->pending_start != nullptr) {
    // 前の開始の応答を返してから新しい開始に置き換える。
    StartResult cancelled;
    cancelled.error = StartError::kFailed;
    cancelled.message = "superseded";
    g_autoptr(FlValue) v = StartResultValue(cancelled);
    Respond(self->pending_start, v);
    g_clear_object(&self->pending_start);
  }
  FlValue* args = fl_method_call_get_args(call);
  std::string token;
  if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
    FlValue* t = fl_value_lookup_string(args, "restoreToken");
    if (t != nullptr && fl_value_get_type(t) == FL_VALUE_TYPE_STRING) {
      token = fl_value_get_string(t);
    }
  }
  {
    std::lock_guard<std::mutex> lock(self->mutex);
    self->backdrop = Backdrop();
    self->sequence = 0;
    self->tracker.SetHidden(false);
  }
  self->last_sent_sequence = -1;
  self->pending_start = FL_METHOD_CALL(g_object_ref(call));
  self->cast.Start(
      ParentWindow(self), token,
      [self](const uint8_t* data, int w, int h, int stride, PixelOrder order) {
        std::lock_guard<std::mutex> lock(self->mutex);
        self->backdrop.Merge(data, w, h, stride, order,
                             self->tracker.Exclusions(NowMs()));
        ++self->sequence;
      },
      [self](const StartResult& result) {
        if (self->pending_start == nullptr) return;
        g_autoptr(FlValue) v = StartResultValue(result);
        Respond(self->pending_start, v);
        g_clear_object(&self->pending_start);
      },
      [self](const std::string& reason) {
        g_autoptr(FlValue) args = fl_value_new_map();
        fl_value_set_string_take(args, "reason",
                                 fl_value_new_string(reason.c_str()));
        fl_method_channel_invoke_method(self->channel, "stopped", args,
                                        nullptr, nullptr, nullptr);
      });
}

// 窓の描画域ぶんの控えを RGBA で返す。前回から何も変わっていなければ null。
FlValue* ReadFrame(Plugin* self, int64_t max_pixels) {
  std::vector<uint8_t> rgba;
  Rect got;
  int64_t sequence = 0;
  bool unprimed = false;
  {
    std::lock_guard<std::mutex> lock(self->mutex);
    if (self->sequence == 0) return fl_value_new_null();
    Rect view_rect;
    Rect outer_rect;
    if (!WindowRects(self, self->backdrop.width(), self->backdrop.height(),
                     &view_rect, &outer_rect)) {
      return fl_value_new_null();
    }
    self->tracker.Record(NowMs(), outer_rect);
    sequence = self->sequence;
    if (sequence == self->last_sent_sequence &&
        view_rect.x == self->last_sent_rect.x &&
        view_rect.y == self->last_sent_rect.y &&
        view_rect.width == self->last_sent_rect.width &&
        view_rect.height == self->last_sent_rect.height) {
      return fl_value_new_null();
    }
    self->last_sent_rect = view_rect;
    if (!self->backdrop.CropRgba(view_rect, &rgba, &got)) {
      return fl_value_new_null();
    }
    unprimed = self->backdrop.has_unprimed();
  }
  self->last_sent_sequence = sequence;

  // 大きすぎる窓（全画面など）は間引いて Dart へ渡す量を抑える。
  int step = 1;
  const int64_t pixels = static_cast<int64_t>(got.width) * got.height;
  if (max_pixels > 0 && pixels > max_pixels) {
    step = static_cast<int>(
        std::ceil(std::sqrt(static_cast<double>(pixels) / max_pixels)));
  }
  int out_w = got.width;
  int out_h = got.height;
  if (step > 1) {
    out_w = got.width / step;
    out_h = got.height / step;
    std::vector<uint8_t> small(static_cast<size_t>(out_w) * out_h * 4);
    for (int y = 0; y < out_h; ++y) {
      const uint8_t* src =
          rgba.data() + (static_cast<size_t>(y) * step * got.width) * 4;
      uint8_t* dst = small.data() + static_cast<size_t>(y) * out_w * 4;
      for (int x = 0; x < out_w; ++x) {
        std::memcpy(dst + x * 4, src + static_cast<size_t>(x) * step * 4, 4);
      }
    }
    rgba.swap(small);
  }

  FlValue* map = fl_value_new_map();
  fl_value_set_string_take(map, "sequence", fl_value_new_int(sequence));
  fl_value_set_string_take(map, "width", fl_value_new_int(out_w));
  fl_value_set_string_take(map, "height", fl_value_new_int(out_h));
  fl_value_set_string_take(map, "unprimed", fl_value_new_bool(unprimed));
  fl_value_set_string_take(map, "pixels",
                           fl_value_new_uint8_list(rgba.data(), rgba.size()));
  return map;
}

int64_t IntArg(FlValue* args, const char* key, int64_t fallback) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }
  FlValue* v = fl_value_lookup_string(args, key);
  if (v == nullptr || fl_value_get_type(v) != FL_VALUE_TYPE_INT) {
    return fallback;
  }
  return fl_value_get_int(v);
}

void HandleMethodCall(FlMethodChannel*, FlMethodCall* call,
                      gpointer user_data) {
  auto* self = static_cast<Plugin*>(user_data);
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);

  if (std::strcmp(method, "probe") == 0) {
    g_autoptr(FlValue) map = fl_value_new_map();
    const char* reason = nullptr;
    if (!IsX11Backend(self->view)) {
      reason = "unsupportedBackend";
    } else if (!ScreenCast::PortalAvailable()) {
      reason = "portalUnavailable";
    }
    fl_value_set_string_take(map, "available",
                             fl_value_new_bool(reason == nullptr));
    fl_value_set_string_take(
        map, "reason",
        reason != nullptr ? fl_value_new_string(reason) : fl_value_new_null());
    Respond(call, map);
  } else if (std::strcmp(method, "start") == 0) {
    HandleStart(self, call);
  } else if (std::strcmp(method, "stop") == 0) {
    self->cast.Stop();
    if (self->pending_start != nullptr) {
      StartResult cancelled;
      cancelled.error = StartError::kDenied;
      cancelled.message = "stopped";
      g_autoptr(FlValue) v = StartResultValue(cancelled);
      Respond(self->pending_start, v);
      g_clear_object(&self->pending_start);
    }
    Respond(call, nullptr);
  } else if (std::strcmp(method, "setHidden") == 0) {
    bool hidden = false;
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* v = fl_value_lookup_string(args, "hidden");
      hidden = v != nullptr && fl_value_get_type(v) == FL_VALUE_TYPE_BOOL &&
               fl_value_get_bool(v);
    }
    int64_t sequence = 0;
    {
      std::lock_guard<std::mutex> lock(self->mutex);
      self->tracker.SetHidden(hidden);
      if (!hidden) RecordWindowLocked(self);
      sequence = self->sequence;
    }
    g_autoptr(FlValue) v = fl_value_new_int(sequence);
    Respond(call, v);
  } else if (std::strcmp(method, "frameSequence") == 0) {
    int64_t sequence = 0;
    {
      std::lock_guard<std::mutex> lock(self->mutex);
      sequence = self->sequence;
    }
    g_autoptr(FlValue) v = fl_value_new_int(sequence);
    Respond(call, v);
  } else if (std::strcmp(method, "readFrame") == 0) {
    g_autoptr(FlValue) v = ReadFrame(self, IntArg(args, "maxPixels", 0));
    Respond(call, v);
  } else {
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    fl_method_call_respond(call, response, nullptr);
  }
}

}  // namespace

void screen_capture_plugin_register(FlPluginRegistrar* registrar) {
  auto* self = new Plugin();
  self->view = fl_plugin_registrar_get_view(registrar);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            kChannel, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->channel, HandleMethodCall, self, [](gpointer data) {
        delete static_cast<Plugin*>(data);
      });
  if (self->view != nullptr) {
    GtkWidget* toplevel = gtk_widget_get_toplevel(GTK_WIDGET(self->view));
    if (toplevel != nullptr) {
      g_signal_connect(toplevel, "configure-event", G_CALLBACK(OnConfigure),
                       self);
    }
  }
}
