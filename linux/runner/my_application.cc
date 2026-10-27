#include "my_application.h"

#include <flutter_linux/flutter_linux.h>

#include "flutter/generated_plugin_registrant.h"
#include "platform_services.h"

struct _MyApplication {
  GtkApplication parent_instance;
  FlMethodChannel* archive_open_channel;
  FlValue* pending_files;
  PlatformServices* platform_services;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GList* windows = gtk_application_get_windows(GTK_APPLICATION(application));
  if (windows) {
    gtk_window_present(GTK_WINDOW(windows->data));
    return;
  }
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  gtk_window_set_title(window, "Jucier");
  // Flutter paints the title bar. An empty GTK titlebar opts into client-side
  // decorations on X11 and Wayland while retaining GTK's resize borders and
  // shadows. Removing decorations entirely would also remove those borders.
  GtkWidget* titlebar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  gtk_widget_set_name(titlebar, "jucier-titlebar");
  g_autoptr(GtkCssProvider) titlebar_css = gtk_css_provider_new();
  gtk_css_provider_load_from_data(
      titlebar_css,
      "#jucier-titlebar { min-height: 0; min-width: 0; padding: 0;"
      " margin: 0; border: 0; background: transparent; box-shadow: none; }",
      -1, nullptr);
  gtk_style_context_add_provider(
      gtk_widget_get_style_context(titlebar),
      GTK_STYLE_PROVIDER(titlebar_css), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
  gtk_widget_show(titlebar);
  gtk_window_set_titlebar(window, titlebar);

  gtk_window_set_default_size(window, 1280, 720);
  gtk_window_set_icon_name(window, APPLICATION_ID);

  g_autoptr(FlDartProject) project = fl_dart_project_new();

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  FlBinaryMessenger* messenger =
      fl_engine_get_binary_messenger(fl_view_get_engine(view));
  self->platform_services = new PlatformServices(messenger, window,
                                                 GTK_WIDGET(view));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->archive_open_channel = fl_method_channel_new(
      messenger, "dev.jucier/archive_open", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->archive_open_channel,
      [](FlMethodChannel*, FlMethodCall* call, gpointer data) {
        MyApplication* app = MY_APPLICATION(data);
        const gchar* method = fl_method_call_get_name(call);
        if (g_strcmp0(method, "takePendingOpenFiles") == 0) {
          fl_method_call_respond_success(call, app->pending_files, nullptr);
          fl_value_unref(app->pending_files);
          app->pending_files = fl_value_new_list();
        } else if (g_strcmp0(method, "quitApplication") == 0) {
          fl_method_call_respond_success(call, nullptr, nullptr);
          g_application_quit(G_APPLICATION(app));
        } else {
          fl_method_call_respond_not_implemented(call, nullptr);
        }
      },
      self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Queue absolute paths before notifying Dart. Both cold and running launches
// use the same drain, so opening another archive reuses the existing window.
static void queue_file(MyApplication* self, GFile* file) {
  g_autofree gchar* path = g_file_get_path(file);
  if (path) fl_value_append_take(self->pending_files, fl_value_new_string(path));
}

static void notify_files(MyApplication* self) {
  if (self->archive_open_channel) {
    fl_method_channel_invoke_method(self->archive_open_channel,
                                   "archiveFilesAvailable", nullptr, nullptr,
                                   nullptr, nullptr);
  }
}

static int my_application_command_line(GApplication* application,
                                       GApplicationCommandLine* command_line) {
  MyApplication* self = MY_APPLICATION(application);
  int count = 0;
  g_auto(GStrv) args = g_application_command_line_get_arguments(command_line,
                                                              &count);
  for (int i = 1; i < count; ++i) {
    if (g_strcmp0(args[i], "--") == 0) continue;
    g_autoptr(GFile) file =
        g_application_command_line_create_file_for_arg(command_line, args[i]);
    queue_file(self, file);
  }
  g_application_activate(application);
  notify_files(self);
  return 0;
}

static void my_application_open(GApplication* application, GFile** files,
                                gint count, const gchar*) {
  MyApplication* self = MY_APPLICATION(application);
  for (gint i = 0; i < count; ++i) queue_file(self, files[i]);
  g_application_activate(application);
  notify_files(self);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  delete self->platform_services;
  self->platform_services = nullptr;
  g_clear_object(&self->archive_open_channel);
  g_clear_pointer(&self->pending_files, fl_value_unref);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->command_line = my_application_command_line;
  G_APPLICATION_CLASS(klass)->open = my_application_open;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->pending_files = fl_value_new_list();
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);
  g_set_application_name("Jucier");

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_HANDLES_COMMAND_LINE |
                                         G_APPLICATION_HANDLES_OPEN,
                                     nullptr));
}
