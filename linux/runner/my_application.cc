#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* main_window;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

/// Per-window state for the `typen/native` channel. The Dart side is the same
/// one as on macOS; here the channel answers `setDocument` (window title) and
/// originates `confirmClose` (the WM close button must run the
/// unsaved-changes prompt instead of killing the process — see
/// `docs/adr/0002-linux-multi-window-via-processes.md`).
typedef struct {
  GtkWindow* window;
  GtkHeaderBar* header_bar;  // nullptr when the traditional title bar is used
  FlMethodChannel* channel;
  gboolean close_approved;
} WindowContext;

static void on_confirm_close_ready(GObject* source, GAsyncResult* result,
                                   gpointer user_data) {
  WindowContext* ctx = static_cast<WindowContext*>(user_data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(FlMethodResponse) response =
      fl_method_channel_invoke_method_finish(FL_METHOD_CHANNEL(source), result,
                                             &error);
  // Anything that is not an explicit Dart `false` lets the close through:
  // errors and "not implemented" (e.g. the Preferences window, which has no
  // document to protect) must never trap a window open.
  gboolean allow = TRUE;
  if (response != nullptr && FL_IS_METHOD_SUCCESS_RESPONSE(response)) {
    FlValue* r = fl_method_success_response_get_result(
        FL_METHOD_SUCCESS_RESPONSE(response));
    if (r != nullptr && fl_value_get_type(r) == FL_VALUE_TYPE_BOOL) {
      allow = fl_value_get_bool(r);
    }
  }
  if (allow) {
    ctx->close_approved = TRUE;
    gtk_widget_destroy(GTK_WIDGET(ctx->window));
  }
}

static gboolean on_window_delete_event(GtkWidget* window, GdkEvent* event,
                                       gpointer user_data) {
  WindowContext* ctx = static_cast<WindowContext*>(user_data);
  if (ctx->close_approved) return FALSE;
  // Veto for now; the async Dart answer destroys the window if it allows.
  fl_method_channel_invoke_method(ctx->channel, "confirmClose", nullptr,
                                  nullptr, on_confirm_close_ready, ctx);
  return TRUE;
}

static void on_window_destroy(GtkWidget* window, gpointer user_data) {
  WindowContext* ctx = static_cast<WindowContext*>(user_data);
  g_clear_object(&ctx->channel);
  g_free(ctx);
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* call,
                           gpointer user_data) {
  WindowContext* ctx = static_cast<WindowContext*>(user_data);
  const gchar* method = fl_method_call_get_name(call);
  if (g_strcmp0(method, "setDocument") == 0) {
    const gchar* path = nullptr;
    gboolean edited = FALSE;
    FlValue* args = fl_method_call_get_args(call);
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* p = fl_value_lookup_string(args, "path");
      if (p != nullptr && fl_value_get_type(p) == FL_VALUE_TYPE_STRING) {
        path = fl_value_get_string(p);
      }
      FlValue* e = fl_value_lookup_string(args, "edited");
      if (e != nullptr && fl_value_get_type(e) == FL_VALUE_TYPE_BOOL) {
        edited = fl_value_get_bool(e);
      }
    }
    g_autofree gchar* base =
        path != nullptr ? g_path_get_basename(path) : g_strdup("Untitled");
    g_autofree gchar* title =
        edited ? g_strdup_printf("● %s", base) : g_strdup(base);
    // The header bar draws its own label; the window's own title still drives
    // WM_NAME, which is what the taskbar / window switcher / X11 tools read.
    gtk_window_set_title(ctx->window, title);
    if (ctx->header_bar != nullptr) {
      gtk_header_bar_set_title(ctx->header_bar, title);
    }
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else if (g_strcmp0(method, "setDarkMode") == 0) {
    // Flutter draws the content but GTK draws the header bar — the Dart side
    // reports the resolved brightness so the chrome follows the same theme.
    FlValue* args = fl_method_call_get_args(call);
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* d = fl_value_lookup_string(args, "dark");
      if (d != nullptr && fl_value_get_type(d) == FL_VALUE_TYPE_BOOL) {
        g_object_set(gtk_settings_get_default(),
                     "gtk-application-prefer-dark-theme",
                     fl_value_get_bool(d), nullptr);
      }
    }
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else if (g_strcmp0(method, "launch") == 0) {
    // Spawns another window process through GTK's launch machinery so the
    // user's current input event rides along as an activation token (startup
    // notification / xdg-activation). A bare Process.start carries none, and
    // without one mutter refuses to raise or focus the target window — it
    // just posts a "window is ready" notification instead.
    g_autoptr(GError) error = nullptr;
    g_autofree gchar* exe = g_file_read_link("/proc/self/exe", &error);
    FlValue* args = fl_method_call_get_args(call);
    FlValue* list = (args != nullptr &&
                     fl_value_get_type(args) == FL_VALUE_TYPE_MAP)
                        ? fl_value_lookup_string(args, "args")
                        : nullptr;
    if (exe != nullptr && list != nullptr &&
        fl_value_get_type(list) == FL_VALUE_TYPE_LIST) {
      g_autoptr(GString) cmd = g_string_new(g_shell_quote(exe));
      for (size_t i = 0; i < fl_value_get_length(list); i++) {
        FlValue* v = fl_value_get_list_value(list, i);
        if (fl_value_get_type(v) == FL_VALUE_TYPE_STRING) {
          g_autofree gchar* quoted = g_shell_quote(fl_value_get_string(v));
          g_string_append_c(cmd, ' ');
          g_string_append(cmd, quoted);
        }
      }
      g_autoptr(GAppInfo) info = g_app_info_create_from_commandline(
          cmd->str, "Typen", G_APP_INFO_CREATE_NONE, &error);
      if (info != nullptr) {
        GdkAppLaunchContext* launch_ctx =
            gdk_display_get_app_launch_context(gdk_display_get_default());
        gdk_app_launch_context_set_timestamp(launch_ctx,
                                             gtk_get_current_event_time());
        g_app_info_launch(info, nullptr, G_APP_LAUNCH_CONTEXT(launch_ctx),
                          &error);
      }
    }
    if (error != nullptr) g_warning("launch failed: %s", error->message);
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
  }
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static void on_main_window_destroy(GtkWidget* window, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  self->main_window = nullptr;
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  // A second Preferences spawn lands here (its application id is unique);
  // front the existing window instead of opening another.
  if (self->main_window != nullptr) {
    gtk_window_present(self->main_window);
    return;
  }
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->main_window = window;
  g_signal_connect(window, "destroy", G_CALLBACK(on_main_window_destroy),
                   self);

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  gboolean is_preferences = FALSE;
  for (char** arg = self->dart_entrypoint_arguments;
       arg != nullptr && *arg != nullptr; arg++) {
    if (g_strcmp0(*arg, "--preferences") == 0) is_preferences = TRUE;
  }
  const gchar* window_title = is_preferences ? "偏好设置" : "Typen";

  GtkHeaderBar* header_bar = nullptr;
  // Set the window title even when a header bar draws the visible one — the
  // window's own title drives WM_NAME (taskbar, window switcher, X11 tools).
  gtk_window_set_title(window, window_title);

  // Window icon (taskbar/alt-tab on X11; Wayland reads the .desktop file).
  // The PNG ships inside the bundle via Flutter assets.
  {
    g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
    if (exe != nullptr) {
      g_autofree gchar* dir = g_path_get_dirname(exe);
      g_autofree gchar* icon = g_build_filename(
          dir, "data", "flutter_assets", "assets", "brand", "typen.png",
          nullptr);
      if (g_file_test(icon, G_FILE_TEST_EXISTS)) {
        gtk_window_set_icon_from_file(window, icon, nullptr);
      }
    }
  }
  if (use_header_bar) {
    // Slim down the default Adwaita header bar (~46px) — the app draws its
    // own title/status strip, so a full-height header bar is wasted space.
    g_autoptr(GtkCssProvider) css = gtk_css_provider_new();
    gtk_css_provider_load_from_data(
        css,
        "headerbar { min-height: 34px; padding-top: 2px; padding-bottom: 2px; }"
        "headerbar button { min-height: 24px; min-width: 24px; padding: 2px; }",
        -1, nullptr);
    gtk_style_context_add_provider_for_screen(
        gtk_window_get_screen(window), GTK_STYLE_PROVIDER(css),
        GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);

    header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, window_title);
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  }

  // Portrait by default, the way Typora/Xcode open: a Markdown reading column
  // makes a wide landscape window mostly empty margin.
  gtk_window_set_default_size(window, is_preferences ? 720 : 860,
                              is_preferences ? 560 : 1000);
  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

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

  // The typen/native channel: `setDocument` (window title) comes in here, and
  // the WM close button is routed through Dart's `confirmClose` prompt.
  WindowContext* ctx = g_new0(WindowContext, 1);
  ctx->window = window;
  ctx->header_bar = header_bar;
  FlEngine* engine = fl_view_get_engine(view);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  ctx->channel = fl_method_channel_new(fl_engine_get_binary_messenger(engine),
                                       "typen/native", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(ctx->channel, method_call_cb, ctx,
                                            nullptr);
  g_signal_connect(window, "delete-event", G_CALLBACK(on_window_delete_event),
                   ctx);
  g_signal_connect(window, "destroy", G_CALLBACK(on_window_destroy), ctx);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new(gboolean is_preferences) {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(
      my_application_get_type(),
      // Preferences is a singleton: registering *without* NON_UNIQUE makes
      // GApplication forward a second spawn's activation to the running
      // instance instead of opening another window. It must keep the SAME
      // application id as editor windows though — path_provider derives the
      // SharedPreferences directory from it, and a distinct id would give
      // the Preferences window its own private store that editors never see.
      // (Editors never claim the id: NON_UNIQUE skips D-Bus registration.)
      "application-id", APPLICATION_ID,
      "flags",
      is_preferences ? G_APPLICATION_DEFAULT_FLAGS : G_APPLICATION_NON_UNIQUE,
      nullptr));
}
