#include "platform_services.h"

#include <cstring>
#include <initializer_list>

#include <glib/gstdio.h>

namespace {

void Success(FlMethodCall* call, FlValue* value = nullptr) {
  fl_method_call_respond_success(call, value, nullptr);
}

void Error(FlMethodCall* call, const char* code, const char* message) {
  fl_method_call_respond_error(call, code, message, nullptr, nullptr);
}

struct Preference {
  const char* getter;
  const char* setter;
  const char* fallback;
  const char* choices[4];
};

const Preference kPreferences[] = {
    {"themeMode", "setThemeMode", "system", {"system", "light", "dark"}},
    {"compressionPerformance", "setCompressionPerformance", "balanced",
     {"balanced", "speed", "resourceSaving"}},
    {"archiveOpenMode", "setArchiveOpenMode", "open", {"open", "extract"}},
    {"singleEntryExtractionMode", "setSingleEntryExtractionMode",
     "preserveArchiveStructure", {"preserveArchiveStructure", "selectedOnly"}},
    {"smartExtractionEnabled", "setSmartExtractionEnabled", nullptr, {}},
    {"archiveColumnPreferences", "setArchiveColumnPreferences", nullptr, {}},
};

bool IsValid(const Preference& preference, FlValue* value) {
  if (preference.fallback != nullptr) {
    if (fl_value_get_type(value) != FL_VALUE_TYPE_STRING) return false;
    for (const char* choice : preference.choices) {
      if (choice && strcmp(fl_value_get_string(value), choice) == 0) return true;
    }
    return false;
  }
  if (strcmp(preference.getter, "smartExtractionEnabled") == 0) {
    return fl_value_get_type(value) == FL_VALUE_TYPE_BOOL;
  }
  if (fl_value_get_type(value) != FL_VALUE_TYPE_MAP) return false;
  for (const char* key : {"compression", "extraction"}) {
    FlValue* columns = fl_value_lookup_string(value, key);
    if (!columns || fl_value_get_type(columns) != FL_VALUE_TYPE_LIST) return false;
    for (size_t i = 0; i < fl_value_get_length(columns); ++i) {
      if (fl_value_get_type(fl_value_get_list_value(columns, i)) !=
          FL_VALUE_TYPE_STRING) return false;
    }
  }
  return true;
}

}  // namespace

PlatformServices::PlatformServices(FlBinaryMessenger* messenger, GtkWindow* window)
    : preferences_(fl_value_new_map()),
      preferences_path_(g_build_filename(g_get_user_config_dir(), "jucier",
                                        "preferences.json", nullptr)) {
  g_weak_ref_init(&window_, G_OBJECT(window));
  g_autoptr(FlJsonMessageCodec) json = fl_json_message_codec_new();
  gchar* contents = nullptr;
  gsize length = 0;
  if (g_file_get_contents(preferences_path_, &contents, &length, nullptr)) {
    g_autoptr(GBytes) bytes = g_bytes_new_take(contents, length);
    g_autoptr(FlValue) decoded = fl_message_codec_decode_message(
        FL_MESSAGE_CODEC(json), bytes, nullptr);
    if (decoded && fl_value_get_type(decoded) == FL_VALUE_TYPE_MAP) {
      fl_value_unref(preferences_);
      preferences_ = fl_value_ref(decoded);
    }
  }

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  platform_channel_ = fl_method_channel_new(
      messenger, "dev.jucier/platform", FL_METHOD_CODEC(codec));
  window_channel_ = fl_method_channel_new(
      messenger, "dev.jucier/window", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(platform_channel_, HandlePlatform,
                                          this, nullptr);
  fl_method_channel_set_method_call_handler(window_channel_, HandleWindow,
                                          this, nullptr);
}

PlatformServices::~PlatformServices() {
  fl_method_channel_set_method_call_handler(platform_channel_, nullptr, nullptr,
                                          nullptr);
  fl_method_channel_set_method_call_handler(window_channel_, nullptr, nullptr,
                                          nullptr);
  g_clear_object(&platform_channel_);
  g_clear_object(&window_channel_);
  fl_value_unref(preferences_);
  g_free(preferences_path_);
  g_weak_ref_clear(&window_);
}

bool PlatformServices::SavePreferences(GError** error) {
  g_autofree gchar* directory = g_path_get_dirname(preferences_path_);
  if (g_mkdir_with_parents(directory, 0700) != 0) {
    g_set_error_literal(error, G_FILE_ERROR, G_FILE_ERROR_FAILED,
                        "无法创建设置目录");
    return false;
  }
  g_autoptr(FlJsonMessageCodec) codec = fl_json_message_codec_new();
  g_autoptr(GBytes) bytes = fl_message_codec_encode_message(
      FL_MESSAGE_CODEC(codec), preferences_, error);
  if (!bytes) return false;
  gsize length = 0;
  const gchar* data = static_cast<const gchar*>(g_bytes_get_data(bytes, &length));
  return g_file_set_contents(preferences_path_, data, length, error);
}

void PlatformServices::HandlePlatform(FlMethodChannel*, FlMethodCall* call,
                                      gpointer data) {
  static_cast<PlatformServices*>(data)->HandlePlatformCall(call);
}

void PlatformServices::HandlePlatformCall(FlMethodCall* call) {
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  for (const auto& preference : kPreferences) {
    if (strcmp(method, preference.getter) == 0) {
      FlValue* value = fl_value_lookup_string(preferences_, preference.getter);
      if (value && IsValid(preference, value)) {
        Success(call, value);
      } else if (preference.fallback) {
        g_autoptr(FlValue) fallback = fl_value_new_string(preference.fallback);
        Success(call, fallback);
      } else if (strcmp(method, "smartExtractionEnabled") == 0) {
        g_autoptr(FlValue) fallback = fl_value_new_bool(TRUE);
        Success(call, fallback);
      } else {
        Success(call);
      }
      return;
    }
    if (strcmp(method, preference.setter) == 0) {
      if (!IsValid(preference, args)) {
        Error(call, "invalid_preference", "设置值无效");
        return;
      }
      fl_value_set_string(preferences_, preference.getter, args);
      g_autoptr(GError) error = nullptr;
      if (!SavePreferences(&error)) {
        Error(call, "preferences_write_failed", error->message);
      } else {
        Success(call);
      }
      return;
    }
  }

  if (strcmp(method, "fileAccessStatus") == 0 ||
      strcmp(method, "requestFileAccess") == 0) {
    // Linux uses the current user's permissions, with no macOS bookmarks.
    g_autoptr(FlValue) status = fl_value_new_map();
    fl_value_set_string_take(status, "requested", fl_value_new_bool(TRUE));
    fl_value_set_string_take(status, "granted", fl_value_new_bool(TRUE));
    Success(call, status);
  } else if (strcmp(method, "openFile") == 0) {
    if (fl_value_get_type(args) != FL_VALUE_TYPE_STRING ||
        !g_path_is_absolute(fl_value_get_string(args)) ||
        !g_file_test(fl_value_get_string(args), G_FILE_TEST_EXISTS)) {
      Error(call, "invalid_path", "文件或文件夹不存在");
      return;
    }
    g_autofree gchar* uri = g_filename_to_uri(fl_value_get_string(args), nullptr,
                                             nullptr);
    g_autoptr(GError) error = nullptr;
    if (!uri || !g_app_info_launch_default_for_uri(uri, nullptr, &error)) {
      Error(call, "open_failed", error ? error->message : "无法打开文件");
    } else {
      Success(call);
    }
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
  }
}

void PlatformServices::HandleWindow(FlMethodChannel*, FlMethodCall* call,
                                    gpointer data) {
  static_cast<PlatformServices*>(data)->HandleWindowCall(call);
}

void PlatformServices::HandleWindowCall(FlMethodCall* call) {
  const gchar* method = fl_method_call_get_name(call);
  if (strcmp(method, "prepareOperationWindow") == 0 ||
      strcmp(method, "finishOperationWindow") == 0) {
    // Linux reuses its normal window for external extraction operations.
    g_autoptr(FlValue) result = fl_value_new_bool(FALSE);
    Success(call, result);
  } else if (strcmp(method, "showMainWindow") == 0 ||
             strcmp(method, "showPreparedWindow") == 0) {
    g_autoptr(GObject) window = G_OBJECT(g_weak_ref_get(&window_));
    if (window) gtk_window_present(GTK_WINDOW(window));
    Success(call);
  } else if (strcmp(method, "resizeOperationWindow") == 0) {
    Success(call);
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
  }
}
