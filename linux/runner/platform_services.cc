#include "platform_services.h"

#include <cstring>
#include <initializer_list>

#include <glib/gstdio.h>

namespace {

// Logical pixels, matching DesktopTitleBar's height and three caption buttons.
constexpr int kTitleBarHeight = 32;
constexpr int kCaptionButtonWidth = 46;

bool IsTitleBar(GtkGesture* gesture, gdouble x, gdouble y) {
  GtkWidget* view = gtk_event_controller_get_widget(GTK_EVENT_CONTROLLER(gesture));
  return x >= 0 && y >= 0 && y < kTitleBarHeight &&
         x < gtk_widget_get_allocated_width(view) - 3 * kCaptionButtonWidth;
}

void ToggleMaximize(GtkWindow* window) {
  if (gtk_window_is_maximized(window)) {
    gtk_window_unmaximize(window);
  } else {
    gtk_window_maximize(window);
  }
}

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

PlatformServices::PlatformServices(FlBinaryMessenger* messenger, GtkWindow* window,
                                   GtkWidget* view)
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

  window_state_handler_ = g_signal_connect(
      window, "window-state-event", G_CALLBACK(HandleWindowState), this);
  // Capture on the public FlView ancestor, before Flutter consumes pointer
  // events in its child. GTK retains the real input device and Wayland serial.
  title_bar_press_ = gtk_gesture_multi_press_new(view);
  title_bar_drag_ = gtk_gesture_drag_new(view);
  gtk_event_controller_set_propagation_phase(
      GTK_EVENT_CONTROLLER(title_bar_press_), GTK_PHASE_CAPTURE);
  gtk_event_controller_set_propagation_phase(
      GTK_EVENT_CONTROLLER(title_bar_drag_), GTK_PHASE_CAPTURE);
  gtk_gesture_group(title_bar_press_, title_bar_drag_);
  g_signal_connect(title_bar_press_, "pressed", G_CALLBACK(HandleTitleBarPress),
                   this);
  g_signal_connect(title_bar_drag_, "drag-begin",
                   G_CALLBACK(HandleTitleBarDragBegin), this);
  g_signal_connect(title_bar_drag_, "drag-update",
                   G_CALLBACK(HandleTitleBarDragUpdate), this);
}

PlatformServices::~PlatformServices() {
  g_autoptr(GObject) window = G_OBJECT(g_weak_ref_get(&window_));
  if (window) g_signal_handler_disconnect(window, window_state_handler_);
  g_clear_object(&title_bar_press_);
  g_clear_object(&title_bar_drag_);
  g_clear_pointer(&title_bar_event_, gdk_event_free);
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

gboolean PlatformServices::HandleWindowState(GtkWidget*,
                                            GdkEventWindowState* event,
                                            gpointer data) {
  if ((event->changed_mask & GDK_WINDOW_STATE_MAXIMIZED) != 0) {
    auto* self = static_cast<PlatformServices*>(data);
    g_autoptr(FlValue) maximized = fl_value_new_bool(
        (event->new_window_state & GDK_WINDOW_STATE_MAXIMIZED) != 0);
    fl_method_channel_invoke_method(self->window_channel_, "windowStateChanged",
                                    maximized, nullptr, nullptr, nullptr);
  }
  return FALSE;
}

void PlatformServices::HandleTitleBarPress(GtkGestureMultiPress* gesture,
                                          gint presses, gdouble x, gdouble y,
                                          gpointer data) {
  if (!IsTitleBar(GTK_GESTURE(gesture), x, y)) {
    gtk_gesture_set_state(GTK_GESTURE(gesture), GTK_EVENT_SEQUENCE_DENIED);
    return;
  }
  if (presses != 2) return;
  auto* self = static_cast<PlatformServices*>(data);
  g_autoptr(GObject) window = G_OBJECT(g_weak_ref_get(&self->window_));
  if (window) {
    ToggleMaximize(GTK_WINDOW(window));
  }
}

void PlatformServices::HandleTitleBarDragBegin(GtkGestureDrag* gesture,
                                              gdouble x, gdouble y,
                                              gpointer data) {
  auto* self = static_cast<PlatformServices*>(data);
  g_clear_pointer(&self->title_bar_event_, gdk_event_free);
  if (!IsTitleBar(GTK_GESTURE(gesture), x, y)) {
    gtk_gesture_set_state(GTK_GESTURE(gesture), GTK_EVENT_SEQUENCE_DENIED);
    return;
  }
  GdkEventSequence* sequence = gtk_gesture_single_get_current_sequence(
      GTK_GESTURE_SINGLE(gesture));
  const GdkEvent* event = gtk_gesture_get_last_event(GTK_GESTURE(gesture), sequence);
  if (event) self->title_bar_event_ = gdk_event_copy(event);
  // Claim after both grouped gestures have recognized the press, but before
  // Flutter receives it. The compositor can consume the release during a move;
  // forwarding only the press would leave Flutter with a stuck mouse button.
  gtk_gesture_set_state(GTK_GESTURE(gesture), GTK_EVENT_SEQUENCE_CLAIMED);
}

void PlatformServices::HandleTitleBarDragUpdate(GtkGestureDrag* gesture,
                                               gdouble offset_x,
                                               gdouble offset_y,
                                               gpointer data) {
  auto* self = static_cast<PlatformServices*>(data);
  if (!self->title_bar_event_) return;
  gdouble x = 0, y = 0;
  gtk_gesture_drag_get_start_point(gesture, &x, &y);
  GtkWidget* view = gtk_event_controller_get_widget(GTK_EVENT_CONTROLLER(gesture));
  if (!gtk_drag_check_threshold(view, x, y, x + offset_x, y + offset_y)) return;
  g_autoptr(GObject) window = G_OBJECT(g_weak_ref_get(&self->window_));
  if (!window) return;

  g_autoptr(GdkEvent) event = self->title_bar_event_;
  self->title_bar_event_ = nullptr;
  gdouble root_x = 0, root_y = 0;
  gdk_event_get_root_coords(event, &root_x, &root_y);
  gtk_gesture_set_state(GTK_GESTURE(gesture), GTK_EVENT_SEQUENCE_CLAIMED);
  gdk_window_begin_move_drag_for_device(
      gtk_widget_get_window(GTK_WIDGET(window)), gdk_event_get_device(event),
      GDK_BUTTON_PRIMARY, root_x, root_y, gdk_event_get_time(event));
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
  } else if (strcmp(method, "windowState") == 0) {
    g_autoptr(GObject) window = G_OBJECT(g_weak_ref_get(&window_));
    g_autoptr(FlValue) maximized = fl_value_new_bool(
        window && gtk_window_is_maximized(GTK_WINDOW(window)));
    Success(call, maximized);
  } else if (strcmp(method, "minimize") == 0 ||
             strcmp(method, "toggleMaximize") == 0 ||
             strcmp(method, "close") == 0) {
    g_autoptr(GObject) window = G_OBJECT(g_weak_ref_get(&window_));
    // Respond before closing can destroy the window and its Flutter engine.
    Success(call);
    if (!window) return;
    if (strcmp(method, "minimize") == 0) {
      gtk_window_iconify(GTK_WINDOW(window));
    } else if (strcmp(method, "toggleMaximize") == 0) {
      ToggleMaximize(GTK_WINDOW(window));
    } else {
      gtk_window_close(GTK_WINDOW(window));
    }
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
  }
}
