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

using ue_capture::CaptureState;
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
  ~Plugin() {
    // ストリームのスレッドは下の mutex / backdrop を使う。メンバの破棄順（宣言の
    // 逆順）では cast より先にそれらが壊れるので、先にスレッドを止める。
    cast.Stop();
    if (toplevel != nullptr) {
      if (configure_handler != 0) {
        g_signal_handler_disconnect(toplevel, configure_handler);
      }
      g_object_remove_weak_pointer(G_OBJECT(toplevel),
                                   reinterpret_cast<gpointer*>(&toplevel));
    }
    g_clear_object(&pending_start);
  }

  FlMethodChannel* channel = nullptr;
  FlView* view = nullptr;
  // configure-event を繋いだ窓（弱参照。窓が先に壊れたら null になる）。
  GtkWidget* toplevel = nullptr;
  gulong configure_handler = 0;
  ScreenCast cast;

  std::mutex mutex;  // 以下はストリームのスレッドと共有する。
  CaptureState state{kExclusionHistoryMs, kExclusionMargin};

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
  GtkWidget* toplevel_widget = gtk_widget_get_toplevel(widget);
  if (toplevel_widget == nullptr || !gtk_widget_is_toplevel(toplevel_widget)) {
    return false;
  }
  GdkWindow* toplevel = gtk_widget_get_window(toplevel_widget);
  if (toplevel == nullptr || frame_w <= 0 || frame_h <= 0) return false;
  const int scale = gdk_window_get_scale_factor(toplevel);

  // FlView（GtkBox）は自分の GdkWindow を持たないので、gtk_widget_get_window は
  // 窓全体の GdkWindow を返す。その原点に、窓の中でのビューの位置（GNOME の CSD の
  // ヘッダーバー・影の分）を足して、ビューの左上のルート座標にする。
  int ox = 0;
  int oy = 0;
  gdk_window_get_origin(toplevel, &ox, &oy);
  int dx = 0;
  int dy = 0;
  if (gtk_widget_translate_coordinates(widget, toplevel_widget, 0, 0, &dx,
                                       &dy)) {
    ox += dx;
    oy += dy;
  }
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
  if (WindowRects(self, self->state.backdrop.width(),
                  self->state.backdrop.height(),
                  &view_rect, &outer_rect)) {
    self->state.tracker.Record(NowMs(), outer_rect);
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
  // 先に古いストリームを止めてから控えを空にする（逆だと、止まる直前に届いた
  // 古い共有のフレームが新しい控えに入る）。止めた後に遅れて来たフレームも、
  // 共有の番号の不一致で捨てる（CaptureState::MergeFrame）。
  self->cast.Stop();
  uint64_t session = 0;
  {
    std::lock_guard<std::mutex> lock(self->mutex);
    session = self->state.BeginSession();
  }
  self->last_sent_sequence = -1;
  self->last_sent_rect = Rect();
  self->pending_start = FL_METHOD_CALL(g_object_ref(call));
  self->cast.Start(
      ParentWindow(self), token,
      [self, session](const uint8_t* data, int w, int h, int stride,
                      PixelOrder order) {
        std::lock_guard<std::mutex> lock(self->mutex);
        self->state.MergeFrame(session, data, w, h, stride, order, NowMs());
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
// 大きすぎる窓（全画面など）は、切り出しと同時に間引いて Dart へ渡す量を抑える。
FlValue* ReadFrame(Plugin* self, int64_t max_pixels) {
  std::vector<uint8_t> rgba;
  Rect got;
  int out_w = 0;
  int out_h = 0;
  int64_t sequence = 0;
  bool unprimed = false;
  {
    std::lock_guard<std::mutex> lock(self->mutex);
    if (self->state.sequence == 0) return fl_value_new_null();
    Rect view_rect;
    Rect outer_rect;
    if (!WindowRects(self, self->state.backdrop.width(),
                     self->state.backdrop.height(),
                     &view_rect, &outer_rect)) {
      return fl_value_new_null();
    }
    self->state.tracker.Record(NowMs(), outer_rect);
    sequence = self->state.sequence;
    if (sequence == self->last_sent_sequence &&
        view_rect.x == self->last_sent_rect.x &&
        view_rect.y == self->last_sent_rect.y &&
        view_rect.width == self->last_sent_rect.width &&
        view_rect.height == self->last_sent_rect.height) {
      return fl_value_new_null();
    }
    if (!self->state.backdrop.CropRgba(view_rect, max_pixels, &rgba, &got,
                                       &out_w, &out_h)) {
      return fl_value_new_null();
    }
    // 切り出せたときだけ「送った」とする（失敗した矩形で次の比較を誤らない）。
    self->last_sent_rect = view_rect;
    unprimed = self->state.backdrop.has_unprimed();
  }
  self->last_sent_sequence = sequence;

  FlValue* map = fl_value_new_map();
  fl_value_set_string_take(map, "sequence", fl_value_new_int(sequence));
  fl_value_set_string_take(map, "width", fl_value_new_int(out_w));
  fl_value_set_string_take(map, "height", fl_value_new_int(out_h));
  fl_value_set_string_take(map, "unprimed", fl_value_new_bool(unprimed));
  fl_value_set_string_take(map, "pixels",
                           fl_value_new_uint8_list(rgba.data(), rgba.size()));
  return map;
}

// probe の応答。reason が null なら使える。
void RespondProbe(FlMethodCall* call, const char* reason) {
  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "available",
                           fl_value_new_bool(reason == nullptr));
  fl_value_set_string_take(
      map, "reason",
      reason != nullptr ? fl_value_new_string(reason) : fl_value_new_null());
  Respond(call, map);
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
    if (!IsX11Backend(self->view)) {
      RespondProbe(call, "unsupportedBackend");
      return;
    }
    // ポータルへの問い合わせは非同期（起動時のメインループを止めない）。応答は
    // call への参照だけで返すので、plugin が先に壊れても安全。
    FlMethodCall* held = FL_METHOD_CALL(g_object_ref(call));
    ScreenCast::QueryPortalAvailable([held](bool available) {
      RespondProbe(held, available ? nullptr : "portalUnavailable");
      g_object_unref(held);
    });
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
      self->state.tracker.SetHidden(hidden);
      if (!hidden) RecordWindowLocked(self);
      sequence = self->state.sequence;
    }
    g_autoptr(FlValue) v = fl_value_new_int(sequence);
    Respond(call, v);
  } else if (std::strcmp(method, "frameSequence") == 0) {
    int64_t sequence = 0;
    {
      std::lock_guard<std::mutex> lock(self->mutex);
      sequence = self->state.sequence;
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
      // plugin の破棄（~Plugin）で切る。窓が先に壊れたら弱参照が null になる。
      self->toplevel = toplevel;
      g_object_add_weak_pointer(G_OBJECT(toplevel),
                                reinterpret_cast<gpointer*>(&self->toplevel));
      self->configure_handler = g_signal_connect(
          toplevel, "configure-event", G_CALLBACK(OnConfigure), self);
    }
  }
}
