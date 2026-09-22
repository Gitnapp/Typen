#include "my_application.h"

int main(int argc, char** argv) {
  gboolean is_preferences = FALSE;
  for (int i = 1; i < argc; i++) {
    if (g_strcmp0(argv[i], "--preferences") == 0) is_preferences = TRUE;
  }
  g_autoptr(MyApplication) app = my_application_new(is_preferences);
  return g_application_run(G_APPLICATION(app), argc, argv);
}
