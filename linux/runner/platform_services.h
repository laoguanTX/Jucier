#ifndef JUCIER_PLATFORM_SERVICES_H_
#define JUCIER_PLATFORM_SERVICES_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// Implements the shared desktop contract using GTK/GIO and an XDG config file.
class PlatformServices {
 public:
  PlatformServices(FlBinaryMessenger* messenger, GtkWindow* window,
                   GtkWidget* view);
  ~PlatformServices();

  PlatformServices(const PlatformServices&) = delete;
  PlatformServices& operator=(const PlatformServices&) = delete;

 private:
  static void HandlePlatform(FlMethodChannel*, FlMethodCall*, gpointer);
  static void HandleWindow(FlMethodChannel*, FlMethodCall*, gpointer);
  static gboolean HandleWindowState(GtkWidget*, GdkEventWindowState*, gpointer);
  static void HandleTitleBarPress(GtkGestureMultiPress*, gint, gdouble, gdouble,
                                 gpointer);
  static void HandleTitleBarDragBegin(GtkGestureDrag*, gdouble, gdouble,
                                     gpointer);
  static void HandleTitleBarDragUpdate(GtkGestureDrag*, gdouble, gdouble,
                                      gpointer);
  void HandlePlatformCall(FlMethodCall* call);
  void HandleWindowCall(FlMethodCall* call);
  bool SavePreferences(GError** error);

  FlMethodChannel* platform_channel_;
  FlMethodChannel* window_channel_;
  FlValue* preferences_;
  gchar* preferences_path_;
  GWeakRef window_;
  gulong window_state_handler_;
  GtkGesture* title_bar_press_;
  GtkGesture* title_bar_drag_;
  GdkEvent* title_bar_event_ = nullptr;
};

#endif  // JUCIER_PLATFORM_SERVICES_H_
