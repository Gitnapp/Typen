import 'dart:io';

/// Multi-window support on hosts without the native window-manager channel
/// (Linux): every Window is its own process running the same binary. This is
/// the same one-engine-per-window model as macOS
/// (`docs/adr/0001-per-window-flutter-engine.md`), just one process further
/// out — `docs/adr/0002-linux-multi-window-via-processes.md`.
///
/// Window identity, focus and the window list have no cross-process
/// equivalent, so those parts of the `Native` API stay no-ops on Linux.
/// Settings/Recents sync across processes happens through the on-disk store:
/// each process re-reads it when its window regains focus.
class Windowing {
  const Windowing._();

  /// File paths handed to this process on the command line, opened by the
  /// first editor Window on boot — the CLI counterpart of Launch Services
  /// queueing opens before Dart is ready.
  static List<String> startupPaths = const [];

  /// Spawns a new window process. A field rather than fixed code so tests can
  /// observe instead of forking.
  static void Function(List<String> args) spawnWindow = _spawn;

  /// Ends this process — i.e. this Window closing. Injectable for tests.
  static void Function() quit = _quit;

  static void _spawn(List<String> args) {
    Process.start(
      Platform.resolvedExecutable,
      args,
      mode: ProcessStartMode.detached,
    );
  }

  static void _quit() => exit(0);

  static List<String> consumeStartupPaths() {
    final paths = startupPaths;
    startupPaths = const [];
    return paths;
  }
}
