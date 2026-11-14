#include "screen_cast.h"

#include <gio/gunixfdlist.h>
#include <pipewire/pipewire.h>
#include <spa/param/video/format-utils.h>
#include <spa/param/video/type-info.h>
#include <spa/utils/result.h>
#include <unistd.h>

#include <cstring>
#include <utility>

namespace ue_capture {

namespace {

constexpr const char* kPortalBus = "org.freedesktop.portal.Desktop";
constexpr const char* kPortalPath = "/org/freedesktop/portal/desktop";
constexpr const char* kScreenCastIface = "org.freedesktop.portal.ScreenCast";
constexpr const char* kRequestIface = "org.freedesktop.portal.Request";
constexpr const char* kSessionIface = "org.freedesktop.portal.Session";

// ScreenCast の SourceType / CursorMode / PersistMode（ポータル仕様の値）。
constexpr uint32_t kSourceMonitor = 1;
constexpr uint32_t kCursorHidden = 1;
constexpr uint32_t kPersistUntilRevoked = 2;

// D-Bus の一意名 ":1.42" を、リクエストのオブジェクトパスに使う "1_42" へ変える。
std::string SenderToPathElement(const char* unique_name) {
  std::string s = unique_name != nullptr ? unique_name : "";
  if (!s.empty() && s[0] == ':') s.erase(0, 1);
  for (char& c : s) {
    if (c == '.') c = '_';
  }
  return s;
}

// PipeWire の初期化はプロセスで一度だけ。
void EnsurePipeWireInit() {
  static bool initialized = false;
  if (!initialized) {
    pw_init(nullptr, nullptr);
    initialized = true;
  }
}

struct StoppedNotice {
  ScreenCast* self;
  std::weak_ptr<bool> alive;
  uint64_t generation;
  std::string reason;
};

}  // namespace

const char* StartErrorName(StartError e) {
  switch (e) {
    case StartError::kNone:
      return "none";
    case StartError::kUnavailable:
      return "unavailable";
    case StartError::kDenied:
      return "denied";
    case StartError::kFailed:
      return "failed";
  }
  return "failed";
}

struct ScreenCast::Request {
  ScreenCast* self = nullptr;
  uint64_t generation = 0;
  uint64_t id = 0;
  std::string path;
  guint subscription = 0;
  std::function<void(uint32_t, GVariant*)> on_response;
};

ScreenCast::ScreenCast() = default;

ScreenCast::~ScreenCast() {
  Stop();
  // 以後に届く非同期の応答・通知は this に触れずに捨てる。
  *alive_ = false;
  alive_.reset();
  g_clear_object(&bus_);
}

namespace {

struct PortalProbe {
  std::function<void(bool)> done;
};

void FinishPortalProbe(PortalProbe* probe, bool available) {
  probe->done(available);
  delete probe;
}

}  // namespace

void ScreenCast::QueryPortalAvailable(std::function<void(bool)> done) {
  auto* probe = new PortalProbe{std::move(done)};
  g_bus_get(
      G_BUS_TYPE_SESSION, nullptr,
      [](GObject*, GAsyncResult* res, gpointer user_data) {
        auto* probe = static_cast<PortalProbe*>(user_data);
        g_autoptr(GError) error = nullptr;
        GDBusConnection* bus = g_bus_get_finish(res, &error);
        if (bus == nullptr) {
          FinishPortalProbe(probe, false);
          return;
        }
        g_dbus_connection_call(
            bus, kPortalBus, kPortalPath, "org.freedesktop.DBus.Properties",
            "Get",
            g_variant_new("(ss)", kScreenCastIface, "AvailableSourceTypes"),
            G_VARIANT_TYPE("(v)"), G_DBUS_CALL_FLAGS_NONE,
            kPortalProbeTimeoutMs, nullptr,
            [](GObject* source, GAsyncResult* res, gpointer user_data) {
              auto* probe = static_cast<PortalProbe*>(user_data);
              g_autoptr(GError) error = nullptr;
              g_autoptr(GVariant) reply = g_dbus_connection_call_finish(
                  G_DBUS_CONNECTION(source), res, &error);
              bool available = false;
              if (reply != nullptr) {
                g_autoptr(GVariant) value = nullptr;
                g_variant_get(reply, "(v)", &value);
                available = g_variant_is_of_type(value, G_VARIANT_TYPE_UINT32) &&
                            (g_variant_get_uint32(value) & kSourceMonitor) != 0;
              }
              FinishPortalProbe(probe, available);
            },
            probe);
        g_object_unref(bus);  // 呼び出しが参照を持つ。
      },
      probe);
}

void ScreenCast::Start(const std::string& parent_window,
                       const std::string& restore_token, FrameSink sink,
                       StartCallback on_started, StoppedCallback on_stopped) {
  Stop();
  sink_ = std::move(sink);
  on_started_ = std::move(on_started);
  on_stopped_ = std::move(on_stopped);
  parent_window_ = parent_window;
  restore_token_ = restore_token;
  new_restore_token_.clear();
  stop_notified_ = false;

  if (bus_ == nullptr) {
    g_autoptr(GError) error = nullptr;
    bus_ = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);
    if (bus_ == nullptr) {
      Fail(StartError::kUnavailable,
           error != nullptr ? error->message : "no session bus");
      return;
    }
  }

  const std::string token = "ue_create_" + std::to_string(++token_counter_);
  const std::string session_token =
      "ue_session_" + std::to_string(token_counter_);
  GVariantBuilder options;
  g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
  g_variant_builder_add(&options, "{sv}", "handle_token",
                        g_variant_new_string(token.c_str()));
  g_variant_builder_add(&options, "{sv}", "session_handle_token",
                        g_variant_new_string(session_token.c_str()));
  CallWithRequest("CreateSession", g_variant_new("(a{sv})", &options), token,
                  [this](uint32_t response, GVariant* results) {
                    OnSessionCreated(response, results);
                  });
}

void ScreenCast::Fail(StartError error, const std::string& message) {
  StartCallback cb = std::move(on_started_);
  on_started_ = nullptr;
  Stop();
  if (cb) {
    StartResult result;
    result.error = error;
    result.message = message;
    cb(result);
  }
}

namespace {

struct CallContext {
  ScreenCast* self;
  std::weak_ptr<bool> alive;
  uint64_t generation;
  uint64_t request_id;
};

}  // namespace

namespace {

// Request の応答シグナルを path で購読する。
guint SubscribeResponse(GDBusConnection* bus, const std::string& path,
                        GDBusSignalCallback callback, gpointer user_data) {
  return g_dbus_connection_signal_subscribe(
      bus, kPortalBus, kRequestIface, "Response", path.c_str(), nullptr,
      G_DBUS_SIGNAL_FLAGS_NO_MATCH_RULE, callback, user_data, nullptr);
}

}  // namespace

void ScreenCast::CallWithRequest(
    const char* method, GVariant* parameters, const std::string& token,
    std::function<void(uint32_t, GVariant*)> on_response) {
  // ポータル仕様（v0.9 以降）で決まるリクエストのパス。呼び出しの応答 (o) が
  // これと違えば（古いポータル）、応答で返ったパスへ購読を移す。
  const std::string path = std::string(kPortalPath) + "/request/" +
                           SenderToPathElement(
                               g_dbus_connection_get_unique_name(bus_)) +
                           "/" + token;
  static const GDBusSignalCallback on_signal =
      [](GDBusConnection* bus, const gchar*, const gchar*, const gchar*,
         const gchar*, GVariant* params, gpointer user_data) {
        auto* r = static_cast<Request*>(user_data);
        g_dbus_connection_signal_unsubscribe(bus, r->subscription);
        ScreenCast* self = r->self;
        if (self->pending_ == r) self->pending_ = nullptr;
        if (r->generation == self->generation_) {
          uint32_t response = 2;
          GVariant* results = nullptr;
          g_variant_get(params, "(u@a{sv})", &response, &results);
          r->on_response(response, results);
          if (results != nullptr) g_variant_unref(results);
        }
        delete r;
      };

  auto* request = new Request();
  request->self = this;
  request->generation = generation_;
  request->id = ++request_counter_;
  request->path = path;
  request->on_response = std::move(on_response);
  // 応答シグナルは呼び出しより先に購読する（取りこぼし防止）。購読は Stop() か
  // 応答の受信で外すので、user_data の request は this より長生きしない。
  request->subscription = SubscribeResponse(bus_, path, on_signal, request);
  pending_ = request;

  auto* ctx = new CallContext{this, alive_, generation_, request->id};
  g_dbus_connection_call(
      bus_, kPortalBus, kPortalPath, kScreenCastIface, method, parameters,
      G_VARIANT_TYPE("(o)"), G_DBUS_CALL_FLAGS_NONE, -1, nullptr,
      [](GObject* source, GAsyncResult* res, gpointer user_data) {
        auto* c = static_cast<CallContext*>(user_data);
        g_autoptr(GError) error = nullptr;
        g_autoptr(GVariant) reply = g_dbus_connection_call_finish(
            G_DBUS_CONNECTION(source), res, &error);
        auto alive = c->alive.lock();
        ScreenCast* self = c->self;
        if (alive && *alive && c->generation == self->generation_) {
          if (reply == nullptr) {
            // ポータルが無い・インタフェースが無い等。
            self->Fail(StartError::kUnavailable,
                       error != nullptr ? error->message : "call failed");
          } else if (self->pending_ != nullptr &&
                     self->pending_->id == c->request_id) {
            // 応答のパスが購読したパスと違えば、そちらへ購読を移す。
            const gchar* handle = nullptr;
            g_variant_get(reply, "(&o)", &handle);
            Request* r = self->pending_;
            if (handle != nullptr && r->path != handle) {
              g_dbus_connection_signal_unsubscribe(self->bus_,
                                                   r->subscription);
              r->path = handle;
              r->subscription =
                  SubscribeResponse(self->bus_, r->path, on_signal, r);
            }
          }
        }
        delete c;
      },
      ctx);
}

void ScreenCast::OnSessionCreated(uint32_t response, GVariant* results) {
  if (response != 0) {
    Fail(response == 1 ? StartError::kDenied : StartError::kFailed,
         "CreateSession response " + std::to_string(response));
    return;
  }
  const gchar* handle = nullptr;
  if (!g_variant_lookup(results, "session_handle", "&s", &handle) ||
      handle == nullptr) {
    Fail(StartError::kFailed, "no session_handle");
    return;
  }
  session_handle_ = handle;
  SubscribeSessionClosed();

  const std::string token = "ue_select_" + std::to_string(++token_counter_);
  GVariantBuilder options;
  g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
  g_variant_builder_add(&options, "{sv}", "handle_token",
                        g_variant_new_string(token.c_str()));
  g_variant_builder_add(&options, "{sv}", "types",
                        g_variant_new_uint32(kSourceMonitor));
  g_variant_builder_add(&options, "{sv}", "multiple",
                        g_variant_new_boolean(FALSE));
  g_variant_builder_add(&options, "{sv}", "cursor_mode",
                        g_variant_new_uint32(kCursorHidden));
  g_variant_builder_add(&options, "{sv}", "persist_mode",
                        g_variant_new_uint32(kPersistUntilRevoked));
  if (!restore_token_.empty()) {
    g_variant_builder_add(&options, "{sv}", "restore_token",
                          g_variant_new_string(restore_token_.c_str()));
  }
  CallWithRequest(
      "SelectSources",
      g_variant_new("(oa{sv})", session_handle_.c_str(), &options), token,
      [this](uint32_t r, GVariant* res) { OnSourcesSelected(r, res); });
}

void ScreenCast::OnSourcesSelected(uint32_t response, GVariant* /*results*/) {
  if (response != 0) {
    Fail(response == 1 ? StartError::kDenied : StartError::kFailed,
         "SelectSources response " + std::to_string(response));
    return;
  }
  const std::string token = "ue_start_" + std::to_string(++token_counter_);
  GVariantBuilder options;
  g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
  g_variant_builder_add(&options, "{sv}", "handle_token",
                        g_variant_new_string(token.c_str()));
  CallWithRequest("Start",
                  g_variant_new("(osa{sv})", session_handle_.c_str(),
                                parent_window_.c_str(), &options),
                  token,
                  [this](uint32_t r, GVariant* res) { OnStarted(r, res); });
}

void ScreenCast::OnStarted(uint32_t response, GVariant* results) {
  if (response != 0) {
    Fail(response == 1 ? StartError::kDenied : StartError::kFailed,
         "Start response " + std::to_string(response));
    return;
  }
  const gchar* token = nullptr;
  if (g_variant_lookup(results, "restore_token", "&s", &token) &&
      token != nullptr) {
    new_restore_token_ = token;
  }
  g_autoptr(GVariant) streams =
      g_variant_lookup_value(results, "streams", G_VARIANT_TYPE("a(ua{sv})"));
  if (streams == nullptr || g_variant_n_children(streams) == 0) {
    Fail(StartError::kFailed, "no streams");
    return;
  }
  uint32_t node_id = 0;
  g_autoptr(GVariant) props = nullptr;
  g_variant_get_child(streams, 0, "(u@a{sv})", &node_id, &props);
  OpenRemote(node_id);
}

void ScreenCast::OpenRemote(uint32_t node_id) {
  GVariantBuilder options;
  g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
  struct OpenContext {
    ScreenCast* self;
    std::weak_ptr<bool> alive;
    uint64_t generation;
    uint32_t node_id;
  };
  auto* ctx = new OpenContext{this, alive_, generation_, node_id};
  g_dbus_connection_call_with_unix_fd_list(
      bus_, kPortalBus, kPortalPath, kScreenCastIface, "OpenPipeWireRemote",
      g_variant_new("(oa{sv})", session_handle_.c_str(), &options),
      G_VARIANT_TYPE("(h)"), G_DBUS_CALL_FLAGS_NONE, -1, nullptr, nullptr,
      [](GObject* source, GAsyncResult* res, gpointer user_data) {
        auto* c = static_cast<OpenContext*>(user_data);
        GUnixFDList* fds = nullptr;
        g_autoptr(GError) error = nullptr;
        g_autoptr(GVariant) reply =
            g_dbus_connection_call_with_unix_fd_list_finish(
                G_DBUS_CONNECTION(source), &fds, res, &error);
        ScreenCast* self = c->self;
        auto alive = c->alive.lock();
        const bool current =
            alive && *alive && c->generation == self->generation_;
        int fd = -1;
        if (reply != nullptr && fds != nullptr) {
          gint32 index = 0;
          g_variant_get(reply, "(h)", &index);
          fd = g_unix_fd_list_get(fds, index, nullptr);
        }
        g_clear_object(&fds);
        if (!current) {
          if (fd >= 0) close(fd);
        } else if (fd < 0) {
          self->Fail(StartError::kFailed,
                     error != nullptr ? error->message
                                      : "OpenPipeWireRemote failed");
        } else {
          std::string message;
          if (!self->StartStream(fd, c->node_id, &message)) {
            self->Fail(StartError::kFailed, message);
          } else if (self->on_started_) {
            StartCallback cb = std::move(self->on_started_);
            self->on_started_ = nullptr;
            StartResult result;
            result.restore_token = self->new_restore_token_;
            cb(result);
          }
        }
        delete c;
      },
      ctx);
}

namespace {

const struct pw_stream_events* StreamEvents() {
  static struct pw_stream_events events = [] {
    struct pw_stream_events e;
    std::memset(&e, 0, sizeof(e));
    e.version = PW_VERSION_STREAM_EVENTS;
    return e;
  }();
  return &events;
}

}  // namespace

bool ScreenCast::StartStream(int fd, uint32_t node_id, std::string* error) {
  EnsurePipeWireInit();
  loop_ = pw_thread_loop_new("ue-screen-capture", nullptr);
  if (loop_ == nullptr) {
    close(fd);
    *error = "pw_thread_loop_new failed";
    return false;
  }
  context_ = pw_context_new(pw_thread_loop_get_loop(loop_), nullptr, 0);
  if (context_ == nullptr || pw_thread_loop_start(loop_) < 0) {
    close(fd);
    *error = "pw_context_new / start failed";
    return false;
  }
  pw_thread_loop_lock(loop_);
  // 成功すれば fd の所有は core へ移る。失敗したときは閉じられない（PipeWire 1.x の
  // 実装: core_new の失敗は fd に触れず、プロトコルへの接続の失敗も close しない。
  // ヘッダの「error で閉じる」は実装と食い違う）ので、こちらで閉じる。
  core_ = pw_context_connect_fd(context_, fd, nullptr, 0);
  if (core_ == nullptr) {
    close(fd);
    pw_thread_loop_unlock(loop_);
    *error = "pw_context_connect_fd failed";
    return false;
  }
  stream_ = pw_stream_new(
      core_, "universal-experience-loupe",
      pw_properties_new(PW_KEY_MEDIA_TYPE, "Video", PW_KEY_MEDIA_CATEGORY,
                        "Capture", PW_KEY_MEDIA_ROLE, "Screen", nullptr));
  if (stream_ == nullptr) {
    pw_thread_loop_unlock(loop_);
    *error = "pw_stream_new failed";
    return false;
  }

  static struct pw_stream_events events = *StreamEvents();
  events.state_changed = [](void* data, enum pw_stream_state old_state,
                            enum pw_stream_state state, const char* err) {
    OnStreamStateChanged(data, old_state, state, err);
  };
  events.param_changed = [](void* data, uint32_t id,
                            const struct spa_pod* param) {
    OnStreamParamChanged(data, id, param);
  };
  events.process = [](void* data) { OnStreamProcess(data); };
  auto* hook = new spa_hook();
  std::memset(hook, 0, sizeof(*hook));
  stream_listener_ = hook;
  pw_stream_add_listener(stream_, hook, &events, this);

  uint8_t buffer[1024];
  struct spa_pod_builder b;
  spa_pod_builder_init(&b, buffer, sizeof(buffer));
  struct spa_rectangle size_def = SPA_RECTANGLE(1920, 1080);
  struct spa_rectangle size_min = SPA_RECTANGLE(1, 1);
  struct spa_rectangle size_max = SPA_RECTANGLE(16384, 16384);
  struct spa_fraction rate_def = SPA_FRACTION(60, 1);
  struct spa_fraction rate_min = SPA_FRACTION(0, 1);
  struct spa_fraction rate_max = SPA_FRACTION(144, 1);
  const struct spa_pod* params[1] = {nullptr};
  params[0] = static_cast<const struct spa_pod*>(spa_pod_builder_add_object(
      &b, SPA_TYPE_OBJECT_Format, SPA_PARAM_EnumFormat, SPA_FORMAT_mediaType,
      SPA_POD_Id(SPA_MEDIA_TYPE_video), SPA_FORMAT_mediaSubtype,
      SPA_POD_Id(SPA_MEDIA_SUBTYPE_raw), SPA_FORMAT_VIDEO_format,
      SPA_POD_CHOICE_ENUM_Id(5, SPA_VIDEO_FORMAT_BGRx, SPA_VIDEO_FORMAT_BGRx,
                             SPA_VIDEO_FORMAT_RGBx, SPA_VIDEO_FORMAT_BGRA,
                             SPA_VIDEO_FORMAT_RGBA),
      SPA_FORMAT_VIDEO_size,
      SPA_POD_CHOICE_RANGE_Rectangle(&size_def, &size_min, &size_max),
      SPA_FORMAT_VIDEO_framerate,
      SPA_POD_CHOICE_RANGE_Fraction(&rate_def, &rate_min, &rate_max)));

  const int res = pw_stream_connect(
      stream_, PW_DIRECTION_INPUT, node_id,
      static_cast<enum pw_stream_flags>(PW_STREAM_FLAG_AUTOCONNECT |
                                        PW_STREAM_FLAG_MAP_BUFFERS),
      const_cast<const struct spa_pod**>(params), 1);
  pw_thread_loop_unlock(loop_);
  if (res < 0) {
    *error = std::string("pw_stream_connect failed: ") + spa_strerror(res);
    return false;
  }
  return true;
}

void ScreenCast::OnStreamStateChanged(void* data, int /*old_state*/,
                                      int state, const char* error) {
  auto* self = static_cast<ScreenCast*>(data);
  if (state == PW_STREAM_STATE_ERROR) {
    self->NotifyStoppedFromStreamThread(error != nullptr ? error
                                                         : "stream error");
  } else if (state == PW_STREAM_STATE_UNCONNECTED) {
    self->NotifyStoppedFromStreamThread("stream disconnected");
  }
}

void ScreenCast::OnStreamParamChanged(void* data, uint32_t id,
                                      const struct spa_pod* param) {
  auto* self = static_cast<ScreenCast*>(data);
  if (param == nullptr || id != SPA_PARAM_Format) return;
  struct spa_video_info_raw info;
  std::memset(&info, 0, sizeof(info));
  uint32_t media_type = 0;
  uint32_t media_subtype = 0;
  if (spa_format_parse(param, &media_type, &media_subtype) < 0 ||
      media_type != SPA_MEDIA_TYPE_video ||
      media_subtype != SPA_MEDIA_SUBTYPE_raw) {
    return;
  }
  if (spa_format_video_raw_parse(param, &info) < 0) return;
  self->frame_width_ = static_cast<int>(info.size.width);
  self->frame_height_ = static_cast<int>(info.size.height);
  self->frame_order_ = (info.format == SPA_VIDEO_FORMAT_RGBx ||
                        info.format == SPA_VIDEO_FORMAT_RGBA)
                           ? PixelOrder::kRgbx
                           : PixelOrder::kBgrx;

  // 共有メモリのバッファだけを受け取る。
  uint8_t buffer[512];
  struct spa_pod_builder b;
  spa_pod_builder_init(&b, buffer, sizeof(buffer));
  const struct spa_pod* params[2];
  params[0] = static_cast<const struct spa_pod*>(spa_pod_builder_add_object(
      &b, SPA_TYPE_OBJECT_ParamBuffers, SPA_PARAM_Buffers,
      SPA_PARAM_BUFFERS_dataType,
      SPA_POD_CHOICE_FLAGS_Int((1 << SPA_DATA_MemPtr) |
                               (1 << SPA_DATA_MemFd))));
  params[1] = static_cast<const struct spa_pod*>(spa_pod_builder_add_object(
      &b, SPA_TYPE_OBJECT_ParamMeta, SPA_PARAM_Meta, SPA_PARAM_META_type,
      SPA_POD_Id(SPA_META_Header), SPA_PARAM_META_size,
      SPA_POD_Int(sizeof(struct spa_meta_header))));
  pw_stream_update_params(self->stream_, params, 2);
}

void ScreenCast::OnStreamProcess(void* data) {
  auto* self = static_cast<ScreenCast*>(data);
  // 溜まっていたら最新の 1 枚だけを使う。
  struct pw_buffer* latest = nullptr;
  while (struct pw_buffer* b = pw_stream_dequeue_buffer(self->stream_)) {
    if (latest != nullptr) pw_stream_queue_buffer(self->stream_, latest);
    latest = b;
  }
  if (latest == nullptr) return;
  struct spa_buffer* buf = latest->buffer;
  auto* header = static_cast<struct spa_meta_header*>(
      spa_buffer_find_meta_data(buf, SPA_META_Header,
                                sizeof(struct spa_meta_header)));
  const bool corrupted =
      header != nullptr && (header->flags & SPA_META_HEADER_FLAG_CORRUPTED);
  struct spa_data* d = &buf->datas[0];
  if (!corrupted && d->data != nullptr && d->chunk != nullptr &&
      d->chunk->size > 0 && !(d->chunk->flags & SPA_CHUNK_FLAG_CORRUPTED) &&
      self->frame_width_ > 0 && self->frame_height_ > 0 && self->sink_) {
    const int stride =
        d->chunk->stride > 0 ? d->chunk->stride : self->frame_width_ * 4;
    const auto* pixels =
        static_cast<const uint8_t*>(d->data) + d->chunk->offset;
    if (static_cast<int64_t>(stride) * self->frame_height_ <=
        static_cast<int64_t>(d->maxsize) - d->chunk->offset) {
      self->sink_(pixels, self->frame_width_, self->frame_height_, stride,
                  self->frame_order_);
    }
  }
  pw_stream_queue_buffer(self->stream_, latest);
}

void ScreenCast::NotifyStoppedFromStreamThread(const std::string& reason) {
  // alive_ はメインスレッドの破棄より前に Stop() がこのスレッドを止めるので、
  // ここで読んでも競合しない。
  auto* notice = new StoppedNotice{this, alive_, generation_, reason};
  g_idle_add(
      [](gpointer user_data) -> gboolean {
        auto* n = static_cast<StoppedNotice*>(user_data);
        ScreenCast* self = n->self;
        auto alive = n->alive.lock();
        if (alive && *alive && n->generation == self->generation_ &&
            self->stream_ != nullptr && !self->stop_notified_) {
          self->stop_notified_ = true;
          StoppedCallback cb = self->on_stopped_;
          self->Stop();
          if (cb) cb(n->reason);
        }
        delete n;
        return G_SOURCE_REMOVE;
      },
      notice);
}

void ScreenCast::SubscribeSessionClosed() {
  if (bus_ == nullptr || session_handle_.empty()) return;
  // 合成器・ポータル側で共有が終わった（利用者がパネルから止めた等）ら Closed が
  // 来る。購読は CloseSession() で外すので、user_data の this より長生きしない。
  session_closed_subscription_ = g_dbus_connection_signal_subscribe(
      bus_, kPortalBus, kSessionIface, "Closed", session_handle_.c_str(),
      nullptr, G_DBUS_SIGNAL_FLAGS_NO_MATCH_RULE,
      [](GDBusConnection*, const gchar*, const gchar*, const gchar*,
         const gchar*, GVariant*, gpointer user_data) {
        static_cast<ScreenCast*>(user_data)->OnSessionClosed();
      },
      this, nullptr);
}

void ScreenCast::OnSessionClosed() {
  // ポータルがもう閉じたセッションへ Close を送らない。
  if (bus_ != nullptr && session_closed_subscription_ != 0) {
    g_dbus_connection_signal_unsubscribe(bus_, session_closed_subscription_);
    session_closed_subscription_ = 0;
  }
  session_handle_.clear();
  if (on_started_) {
    // 開始の途中で閉じられた（ダイアログの取り消し等）。
    Fail(StartError::kDenied, "session closed");
    return;
  }
  if (stop_notified_) return;
  stop_notified_ = true;
  StoppedCallback cb = on_stopped_;
  Stop();
  if (cb) cb("session closed");
}

void ScreenCast::CloseSession() {
  if (bus_ != nullptr && session_closed_subscription_ != 0) {
    g_dbus_connection_signal_unsubscribe(bus_, session_closed_subscription_);
    session_closed_subscription_ = 0;
  }
  if (bus_ != nullptr && !session_handle_.empty()) {
    g_dbus_connection_call(bus_, kPortalBus, session_handle_.c_str(),
                           kSessionIface, "Close", nullptr, nullptr,
                           G_DBUS_CALL_FLAGS_NONE, -1, nullptr, nullptr,
                           nullptr);
  }
  session_handle_.clear();
}

void ScreenCast::Stop() {
  ++generation_;
  if (pending_ != nullptr) {
    g_dbus_connection_signal_unsubscribe(bus_, pending_->subscription);
    delete pending_;
    pending_ = nullptr;
  }
  if (loop_ != nullptr) {
    pw_thread_loop_lock(loop_);
    if (stream_ != nullptr) {
      pw_stream_disconnect(stream_);
      pw_stream_destroy(stream_);
      stream_ = nullptr;
    }
    if (core_ != nullptr) {
      pw_core_disconnect(core_);
      core_ = nullptr;
    }
    pw_thread_loop_unlock(loop_);
    pw_thread_loop_stop(loop_);
    if (context_ != nullptr) {
      pw_context_destroy(context_);
      context_ = nullptr;
    }
    pw_thread_loop_destroy(loop_);
    loop_ = nullptr;
  }
  delete static_cast<spa_hook*>(stream_listener_);
  stream_listener_ = nullptr;
  frame_width_ = 0;
  frame_height_ = 0;
  CloseSession();
}

}  // namespace ue_capture
