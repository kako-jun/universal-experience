#include "include/color_vision_filter/color_vision_filter_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <cstring>
#include <string>

#define COLOR_VISION_FILTER_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), color_vision_filter_plugin_get_type(), \
                              ColorVisionFilterPlugin))

struct _ColorVisionFilterPlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(ColorVisionFilterPlugin, color_vision_filter_plugin, g_object_get_type())

// Plugin state
static std::string current_type = "none";
static float current_intensity = 1.0f;
static bool is_active = false;

// Called when a method call is received from Flutter.
static void color_vision_filter_plugin_handle_method_call(
    ColorVisionFilterPlugin* self,
    FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;

  const gchar* method = fl_method_call_get_name(method_call);

  if (strcmp(method, "apply") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    if (fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* type_value = fl_value_lookup_string(args, "type");
      FlValue* intensity_value = fl_value_lookup_string(args, "intensity");

      if (type_value != nullptr) {
        current_type = fl_value_get_string(type_value);
      }
      if (intensity_value != nullptr) {
        current_intensity = static_cast<float>(fl_value_get_float(intensity_value));
      }

      is_active = (current_type != "none");

      // Linux doesn't have system-wide color filter API like Windows Magnification
      // Return true to indicate the request was processed (but effect is in-app only)
      g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    } else {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "INVALID_ARGUMENT", "Invalid arguments", nullptr));
    }
  } else if (strcmp(method, "setIntensity") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    if (fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* intensity_value = fl_value_lookup_string(args, "intensity");
      if (intensity_value != nullptr) {
        current_intensity = static_cast<float>(fl_value_get_float(intensity_value));
      }
      g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    } else {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "INVALID_ARGUMENT", "Invalid arguments", nullptr));
    }
  } else if (strcmp(method, "remove") == 0) {
    is_active = false;
    current_type = "none";
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "getState") == 0) {
    g_autoptr(FlValue) state = fl_value_new_map();
    fl_value_set_string_take(state, "type", fl_value_new_string(current_type.c_str()));
    fl_value_set_string_take(state, "intensity", fl_value_new_float(static_cast<double>(current_intensity)));
    fl_value_set_string_take(state, "isActive", fl_value_new_bool(is_active));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(state));
  } else if (strcmp(method, "hasPermission") == 0) {
    // Linux doesn't require special permissions
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "requestPermission") == 0) {
    // No permission needed
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void color_vision_filter_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(color_vision_filter_plugin_parent_class)->dispose(object);
}

static void color_vision_filter_plugin_class_init(ColorVisionFilterPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = color_vision_filter_plugin_dispose;
}

static void color_vision_filter_plugin_init(ColorVisionFilterPlugin* self) {}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  ColorVisionFilterPlugin* plugin = COLOR_VISION_FILTER_PLUGIN(user_data);
  color_vision_filter_plugin_handle_method_call(plugin, method_call);
}

void color_vision_filter_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  ColorVisionFilterPlugin* plugin = COLOR_VISION_FILTER_PLUGIN(
      g_object_new(color_vision_filter_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "color_vision_filter",
                            FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_object_unref(plugin);
}
