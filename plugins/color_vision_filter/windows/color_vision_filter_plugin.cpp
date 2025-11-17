#include "color_vision_filter_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>
#include <magnification.h>
#include <memory>
#include <sstream>

#pragma comment(lib, "Magnification.lib")

namespace color_vision_filter {

// Static member initialization
std::string ColorVisionFilterPlugin::current_type_ = "none";
float ColorVisionFilterPlugin::current_intensity_ = 1.0f;
bool ColorVisionFilterPlugin::is_active_ = false;
bool ColorVisionFilterPlugin::mag_initialized_ = false;

// Register plugin
void ColorVisionFilterPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "color_vision_filter",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<ColorVisionFilterPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

ColorVisionFilterPlugin::ColorVisionFilterPlugin() {}

ColorVisionFilterPlugin::~ColorVisionFilterPlugin() {
  if (mag_initialized_) {
    MagUninitialize();
  }
}

void ColorVisionFilterPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

  const auto method_name = method_call.method_name();

  if (method_name == "apply") {
    const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (arguments) {
      std::string type = "none";
      float intensity = 1.0f;

      auto type_it = arguments->find(flutter::EncodableValue("type"));
      if (type_it != arguments->end()) {
        type = std::get<std::string>(type_it->second);
      }

      auto intensity_it = arguments->find(flutter::EncodableValue("intensity"));
      if (intensity_it != arguments->end()) {
        intensity = static_cast<float>(std::get<double>(intensity_it->second));
      }

      bool success = ApplyFilter(type, intensity);
      result->Success(flutter::EncodableValue(success));
    } else {
      result->Error("INVALID_ARGUMENT", "Invalid arguments");
    }
  }
  else if (method_name == "setIntensity") {
    const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (arguments) {
      float intensity = 1.0f;

      auto intensity_it = arguments->find(flutter::EncodableValue("intensity"));
      if (intensity_it != arguments->end()) {
        intensity = static_cast<float>(std::get<double>(intensity_it->second));
      }

      bool success = SetIntensity(intensity);
      result->Success(flutter::EncodableValue(success));
    } else {
      result->Error("INVALID_ARGUMENT", "Invalid arguments");
    }
  }
  else if (method_name == "remove") {
    bool success = RemoveFilter();
    result->Success(flutter::EncodableValue(success));
  }
  else if (method_name == "getState") {
    flutter::EncodableMap state;
    state[flutter::EncodableValue("type")] = flutter::EncodableValue(current_type_);
    state[flutter::EncodableValue("intensity")] = flutter::EncodableValue(static_cast<double>(current_intensity_));
    state[flutter::EncodableValue("isActive")] = flutter::EncodableValue(is_active_);
    result->Success(flutter::EncodableValue(state));
  }
  else if (method_name == "hasPermission") {
    // Windows doesn't require special permissions for Magnification API
    result->Success(flutter::EncodableValue(true));
  }
  else if (method_name == "requestPermission") {
    // No permission needed
    result->Success(flutter::EncodableValue(true));
  }
  else {
    result->NotImplemented();
  }
}

bool ColorVisionFilterPlugin::InitializeMagnification() {
  if (!mag_initialized_) {
    mag_initialized_ = MagInitialize();
  }
  return mag_initialized_;
}

bool ColorVisionFilterPlugin::ApplyFilter(const std::string& type, float intensity) {
  current_type_ = type;
  current_intensity_ = intensity;
  is_active_ = (type != "none");

  if (!is_active_) {
    return RemoveFilter();
  }

  if (!InitializeMagnification()) {
    return false;
  }

  MAGCOLOREFFECT effect = GetColorEffect(type, intensity);
  BOOL result = MagSetFullscreenColorEffect(&effect);

  return result != FALSE;
}

bool ColorVisionFilterPlugin::SetIntensity(float intensity) {
  current_intensity_ = intensity;

  if (is_active_ && current_type_ != "none") {
    return ApplyFilter(current_type_, intensity);
  }

  return true;
}

bool ColorVisionFilterPlugin::RemoveFilter() {
  is_active_ = false;

  if (!mag_initialized_) {
    return true;
  }

  // Apply identity matrix to remove effect
  MAGCOLOREFFECT identity = {};
  for (int i = 0; i < 5; i++) {
    for (int j = 0; j < 5; j++) {
      identity.transform[i][j] = (i == j) ? 1.0f : 0.0f;
    }
  }

  BOOL result = MagSetFullscreenColorEffect(&identity);
  return result != FALSE;
}

MAGCOLOREFFECT ColorVisionFilterPlugin::GetColorEffect(
    const std::string& type, float intensity) {

  MAGCOLOREFFECT effect = {};
  float transform[3][3];

  // Get transformation matrix based on type
  if (type == "protanopia") {
    float mat[3][3] = {
      {0.0f, 2.02344f, -2.52581f},
      {0.0f, 1.0f, 0.0f},
      {0.0f, 0.0f, 1.0f}
    };
    memcpy(transform, mat, sizeof(transform));
  }
  else if (type == "deuteranopia") {
    float mat[3][3] = {
      {1.0f, 0.0f, 0.0f},
      {0.494207f, 0.0f, 1.24827f},
      {0.0f, 0.0f, 1.0f}
    };
    memcpy(transform, mat, sizeof(transform));
  }
  else if (type == "tritanopia") {
    float mat[3][3] = {
      {1.0f, 0.0f, 0.0f},
      {0.0f, 1.0f, 0.0f},
      {-0.395913f, 0.801109f, 0.0f}
    };
    memcpy(transform, mat, sizeof(transform));
  }
  else if (type == "achromatopsia") {
    float mat[3][3] = {
      {0.299f, 0.587f, 0.114f},
      {0.299f, 0.587f, 0.114f},
      {0.299f, 0.587f, 0.114f}
    };
    memcpy(transform, mat, sizeof(transform));
  }
  else {
    // Identity matrix
    float mat[3][3] = {
      {1.0f, 0.0f, 0.0f},
      {0.0f, 1.0f, 0.0f},
      {0.0f, 0.0f, 1.0f}
    };
    memcpy(transform, mat, sizeof(transform));
  }

  // Build 5x5 MAGCOLOREFFECT with intensity interpolation
  for (int i = 0; i < 3; i++) {
    for (int j = 0; j < 3; j++) {
      float identity = (i == j) ? 1.0f : 0.0f;
      float value = transform[i][j];
      effect.transform[i][j] = identity + (value - identity) * intensity;
    }
    effect.transform[i][3] = 0.0f;
    effect.transform[i][4] = 0.0f;
  }

  // Alpha row
  effect.transform[3][0] = 0.0f;
  effect.transform[3][1] = 0.0f;
  effect.transform[3][2] = 0.0f;
  effect.transform[3][3] = 1.0f;
  effect.transform[3][4] = 0.0f;

  // Translation row
  effect.transform[4][0] = 0.0f;
  effect.transform[4][1] = 0.0f;
  effect.transform[4][2] = 0.0f;
  effect.transform[4][3] = 0.0f;
  effect.transform[4][4] = 1.0f;

  return effect;
}

}  // namespace color_vision_filter
