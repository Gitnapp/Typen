# Multi-window support uses a hand-rolled per-window Flutter engine, not desktop_multi_window or Flutter's native multi-view API

**Status**: accepted

Typen needs true multi-window support — each Window an independent Document with its own buffer/undo/dirty state. Flutter's own multi-view windowing API (`RegularWindowController`, one shared isolate across windows) is the architecturally cleanest option, but as of Flutter 3.44 it's experimental, only available on the master channel behind `--enable-windowing`, and has open gaps (no initial background color, no per-window first-frame signal, incomplete plugin/accessibility/text-input support) — not shippable today. The `desktop_multi_window` package implements the alternative model (one Flutter engine per window) but hasn't been updated in ~9 months and its own docs recommend a patched fork to be reliable.

We're building the one-engine-per-window model by hand in `AppDelegate.swift`/`MainFlutterWindow.swift` instead: each Window owns its own `FlutterEngine`/`FlutterViewController` and its own `typen/native` channel instance, keyed by window identity.

## Considered Options

- Flutter native multi-view API (`RegularWindowController`) — rejected: unstable and unshippable today, though it's the eventual "right" answer if/when it stabilizes for macOS.
- `desktop_multi_window` package — rejected: stale (~9 months), requires a patched fork to be reliable.
- Hand-rolled per-window engine — accepted.

## Consequences

- No shared Dart heap across windows — `Settings` and `Recents` (previously trivially shared in a single-window app) now require explicit re-sync across engines. The first version reads them once per window-open rather than live-pushing updates to already-open windows.
- Native state that used to be a single global in `AppDelegate.swift` (the `typen/native` channel, `dartReady`, `pendingPaths`, `closeApproved`) all become keyed by window identity instead.
- Revisit if/when Flutter's native windowing API stabilizes for macOS — the shared-isolate model would remove the cross-window sync problem entirely and is worth migrating to.
- Every new window is a black flash unless the native side sets a background colour explicitly: `FlutterViewController.backgroundColor` (and, separately, the `NSWindow`'s own) defaults to black until Dart's first frame paints, and `makeKeyAndOrderFront` shows the window before that happens — this is documented directly on `FlutterViewController.backgroundColor` in `FlutterMacOS.framework`'s own header. Fast enough in optimised release builds that it's rarely visible, but reliably visible in debug builds (slower isolate/JIT startup) and gets worse under system load — exactly the same underlying mechanism as any "new window looks like it's hanging" complaint, one frame further along. Both `EditorWindow.init` and `PreferencesWindow.init` set `backgroundColor = .windowBackgroundColor` (native window) and `controller.backgroundColor = .windowBackgroundColor` (FlutterViewController) before `contentViewController` is assigned — `windowBackgroundColor` is a system-adaptive semantic colour, so it tracks light/dark without the native layer needing to know Typen's own (Dart-side) theme. Any *new* window type added later needs the same two lines, or it gets the black flash back.
