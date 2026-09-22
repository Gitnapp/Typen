#ifndef FLUTTER_MY_APPLICATION_H_
#define FLUTTER_MY_APPLICATION_H_

#include <gtk/gtk.h>

G_DECLARE_FINAL_TYPE(MyApplication,
                     my_application,
                     MY,
                     APPLICATION,
                     GtkApplication)

/**
 * my_application_new:
 * @is_preferences: whether this process is a Preferences window. Preferences
 * is a singleton — it registers the shared application id *without*
 * G_APPLICATION_NON_UNIQUE, so a second spawn forwards an activation to the
 * running instance (which presents its window) instead of opening another.
 * Editor windows stay non-unique: every spawn is a new window, and they never
 * claim the id, so the singleton claim never collides with them. The id must
 * stay shared: path_provider derives the SharedPreferences directory from it.
 *
 * Creates a new Flutter-based application.
 *
 * Returns: a new #MyApplication.
 */
MyApplication* my_application_new(gboolean is_preferences);

#endif  // FLUTTER_MY_APPLICATION_H_
