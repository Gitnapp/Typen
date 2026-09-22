# Linux multi-window uses one process per window

**Status**: accepted

Typen's macOS multi-window is a hand-rolled per-window Flutter engine (ADR 0001). On Linux there is no native counterpart to build that on top of, and Flutter's own multi-view windowing API remains behind `flutter config --enable-windowing` — the same "eventual right answer, not shippable" judgement from ADR 0001 applies. Linux therefore runs the one-engine-per-window model one level further out: **each Window is its own process** running the same binary (`lib/windowing.dart`).

## How it works

- `Native.newWindow` / `openPath` / `openPreferences` spawn the binary again with arguments (`--preferences`, `--check-updates`, or positional file paths) instead of calling the absent platform channel. `main()` parses those arguments; positional paths land in `Windowing.startupPaths`, consumed by the first editor Window on boot, with extras spawning their own processes.
- The native close path is preserved: `linux/runner/my_application.cc` intercepts the GTK `delete-event`, vetoes it, and asks Dart over `typen/native` (`confirmClose`) — the same method macOS's AppKit flow invokes. Only an explicit Dart `false` vetoes the close; errors and unimplemented replies always let it through, so a window can never be trapped open.
- `Native.setDocument` is answered by the Linux runner too: the GTK header bar shows the file name, prefixed `●` when the buffer is dirty.
- Because the menu bar never draws on Linux, app commands also bind directly in the widget tree (`CallbackShortcuts`), answering each configured ⌘ binding with Ctrl. Flutter's own text-field bindings already cover undo/cut/copy/paste/select-all.
- Settings/Recents sync across processes goes through the on-disk store: a Window re-reads it when it regains focus (`didChangeAppLifecycleState`), standing in for the `settingsChanged` broadcast, and an inotify watch on the backing file's directory makes it live.
- Two plugin-level traps this relies on dodging: shared_preferences' legacy Linux store caches its backing file at first read and `reload()` never invalidates it, so `Settings.refresh()` reads the JSON directly and pushes changes through the plugin setters instead; and the Preferences process — a singleton via GApplication id uniqueness — must register the *same* application id as editors, because path_provider derives the store directory from it (a distinct id silently forks the store).
- The Preferences window is a singleton: it registers the shared application id without `G_APPLICATION_NON_UNIQUE`, so a second spawn forwards an activation to the running instance, which presents its window. Editors stay non-unique and never claim the id.

## Consequences

- Process isolation is even stronger than the macOS per-engine isolation; the cross-window sync problem ADR 0001 notes is inherited unchanged and solved the same way (re-read on focus).
- No cross-process window list or focus control: the 窗口 menu stays empty on Linux, `focusWindow` and `pathOpenElsewhere` are no-ops, and the native "reuse an Empty Window" policy is approximated in Dart (`_openWithPolicy`) for the one case that matters day to day — a blank Untitled window takes the opened file itself.
- Two windows can hold the same file without the app noticing; the pre-save on-disk stamp check (`FileStamp`) is the guard against silent overwrite there.
- The Linux sandbox doesn't exist, so bookmark create/resolve/release are no-ops and Recents carry plain paths.
- Revisit when Flutter's windowing API stabilises for Linux; the shared-isolate model would restore the window list and live settings sync, exactly as ADR 0001 notes for macOS.
