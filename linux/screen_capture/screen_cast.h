// Linux のライブ画面キャプチャ（#180）: xdg-desktop-portal ScreenCast で
// モニタの共有を受け、PipeWire のストリームからフレームを受け取る。
//
// - ポータルとの対話（CreateSession → SelectSources → Start →
//   OpenPipeWireRemote）は GDBus の非同期呼び出しで、GLib のメインループ上で進む。
// - フレームは PipeWire のスレッドループ上で受け取り、FrameSink へ渡す。
// - 共有メモリ（MemFd / MemPtr）のフレームだけを扱う（DMA-BUF を求める
//   修飾子を提示しないので、合成器は共有メモリで送ってくる）。
#ifndef UE_SCREEN_CAPTURE_SCREEN_CAST_H_
#define UE_SCREEN_CAPTURE_SCREEN_CAST_H_

#include <gio/gio.h>

#include <cstdint>
#include <functional>
#include <string>

#include "backdrop.h"

struct pw_thread_loop;
struct pw_context;
struct pw_core;
struct pw_stream;
struct spa_pod;

namespace ue_capture {

// 開始の失敗の分類。Dart 側の文言・復帰の分岐に使う。
enum class StartError {
  kNone,
  kUnavailable,  // ポータル（ScreenCast）が無い・応答しない
  kDenied,       // 利用者が共有を取り消した・拒否した（Response 1）
  kFailed,       // それ以外（Response 2・PipeWire の失敗など）
};

const char* StartErrorName(StartError e);

struct StartResult {
  StartError error = StartError::kNone;
  std::string message;
  std::string restore_token;
};

// ポータル経由でモニタを 1 つ共有し、PipeWire からフレームを受け取る。
// 1 インスタンスで同時に 1 セッションだけ。メインスレッドから使う。
class ScreenCast {
 public:
  // フレームを受け取る（PipeWire のスレッドから呼ばれる）。
  using FrameSink = std::function<void(const uint8_t* data, int width,
                                       int height, int stride,
                                       PixelOrder order)>;
  // 開始の結果（メインスレッドで呼ばれる）。
  using StartCallback = std::function<void(const StartResult&)>;
  // 開始後にストリームが止まった（メインスレッドで呼ばれる）。
  using StoppedCallback = std::function<void(const std::string& reason)>;

  ScreenCast();
  ~ScreenCast();

  ScreenCast(const ScreenCast&) = delete;
  ScreenCast& operator=(const ScreenCast&) = delete;

  // ポータルの ScreenCast がモニタの共有を提供しているか（同期で問い合わせる）。
  static bool PortalAvailable();

  // 共有を始める。parent_window はポータルのダイアログの親（"x11:<16進 XID>" か空）。
  // restore_token が有効なら、合成器は前回の選択を再利用してダイアログを省ける。
  void Start(const std::string& parent_window, const std::string& restore_token,
             FrameSink sink, StartCallback on_started,
             StoppedCallback on_stopped);

  // 共有を止める（進行中の開始も取り消す）。何度呼んでもよい。
  void Stop();

  bool running() const { return stream_ != nullptr; }

 private:
  struct Request;

  void Fail(StartError error, const std::string& message);
  void CallWithRequest(const char* method, GVariant* parameters,
                       const std::string& token,
                       std::function<void(uint32_t, GVariant*)> on_response);
  void OnSessionCreated(uint32_t response, GVariant* results);
  void OnSourcesSelected(uint32_t response, GVariant* results);
  void OnStarted(uint32_t response, GVariant* results);
  void OpenRemote(uint32_t node_id);
  bool StartStream(int fd, uint32_t node_id, std::string* error);
  void CloseSession();

  // PipeWire のコールバック（static で受けて this へ転送する）。
  static void OnStreamStateChanged(void* data, int old_state, int state,
                                   const char* error);
  static void OnStreamParamChanged(void* data, uint32_t id,
                                   const struct spa_pod* param);
  static void OnStreamProcess(void* data);
  void NotifyStoppedFromStreamThread(const std::string& reason);

  GDBusConnection* bus_ = nullptr;
  std::string session_handle_;
  std::string parent_window_;
  std::string restore_token_;
  std::string new_restore_token_;
  uint64_t generation_ = 0;  // Stop() で進め、古い応答を無視する。
  int token_counter_ = 0;
  Request* pending_ = nullptr;

  FrameSink sink_;
  StartCallback on_started_;
  StoppedCallback on_stopped_;

  pw_thread_loop* loop_ = nullptr;
  pw_context* context_ = nullptr;
  pw_core* core_ = nullptr;
  pw_stream* stream_ = nullptr;
  void* stream_listener_ = nullptr;  // spa_hook（ヘッダを公開しないため不透明に持つ）
  int frame_width_ = 0;
  int frame_height_ = 0;
  PixelOrder frame_order_ = PixelOrder::kBgrx;
  bool stop_notified_ = false;
};

}  // namespace ue_capture

#endif  // UE_SCREEN_CAPTURE_SCREEN_CAST_H_
