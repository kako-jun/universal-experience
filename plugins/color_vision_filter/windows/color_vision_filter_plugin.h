#ifndef FLUTTER_PLUGIN_COLOR_VISION_FILTER_PLUGIN_H_
#define FLUTTER_PLUGIN_COLOR_VISION_FILTER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <windows.h>
#include <magnification.h>
#include <memory>
#include <string>

namespace color_vision_filter {

class ColorVisionFilterPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  ColorVisionFilterPlugin();

  virtual ~ColorVisionFilterPlugin();

  // Disallow copy and assign.
  ColorVisionFilterPlugin(const ColorVisionFilterPlugin&) = delete;
  ColorVisionFilterPlugin& operator=(const ColorVisionFilterPlugin&) = delete;

 private:
  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Initialize Windows Magnification API
  bool InitializeMagnification();

  // Apply color vision filter
  bool ApplyFilter(const std::string& type, float intensity);

  // Set filter intensity
  bool SetIntensity(float intensity);

  // Remove current filter
  bool RemoveFilter();

  // Get MAGCOLOREFFECT structure for given CVD type
  MAGCOLOREFFECT GetColorEffect(const std::string& type, float intensity);

  // Plugin state
  static std::string current_type_;
  static float current_intensity_;
  static bool is_active_;
  static bool mag_initialized_;
};

}  // namespace color_vision_filter

#endif  // FLUTTER_PLUGIN_COLOR_VISION_FILTER_PLUGIN_H_
