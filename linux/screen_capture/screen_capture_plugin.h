// ルーペ窓のライブ画面キャプチャを Dart へ渡す MethodChannel（#180）。
// チャネル名・メソッドは lib/services/live_capture_service.dart と対で決める。
#ifndef UE_SCREEN_CAPTURE_SCREEN_CAPTURE_PLUGIN_H_
#define UE_SCREEN_CAPTURE_SCREEN_CAPTURE_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

void screen_capture_plugin_register(FlPluginRegistrar* registrar);

G_END_DECLS

#endif  // UE_SCREEN_CAPTURE_SCREEN_CAPTURE_PLUGIN_H_
