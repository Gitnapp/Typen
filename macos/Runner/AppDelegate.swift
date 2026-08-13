import Cocoa
import FlutterMacOS
import Security

@main
class AppDelegate: FlutterAppDelegate {
  /// The window registry, in creation order. Each `EditorWindow` carries its
  /// own document/channel/engine state; this array is the only strong
  /// reference to them and the single source of truth for the Window menu,
  /// duplicate-path detection and the quit sequence.
  private var windows: [EditorWindow] = []
  private var nextWindowID = 1

  /// The Preferences window, if one is open. A singleton kept outside
  /// `windows` — it carries no Document, so none of that registry's policies
  /// (dedup, quit sequencing, the Window menu) apply to it.
  private var preferencesWindow: PreferencesWindow?

  /// Security-scoped URLs we currently hold access to, keyed by path. Access
  /// must be balanced with `stopAccessingSecurityScopedResource`, and the same
  /// path can be reached from more than one window over time — so a release is
  /// real only once no window still holds it.
  private var securityScoped: [String: URL] = [:]

  /// Set by `relaunchAfterQuit`; consumed in `applicationWillTerminate` once
  /// the normal quit sequence (including unsaved-work prompts) has actually
  /// let termination proceed.
  private var pendingRelaunchPath: String?

  // ─── Launch ──────────────────────────────────────────────────────────────

  /// `applicationDidFinishLaunching` never reaches this delegate — Flutter's
  /// app delegate owns that hook — so launch bootstrapping happens here.
  /// Deferring one runloop turn lets Launch Services deliver its documents
  /// first: a launch that opened a file must not also get a blank window.
  override func applicationWillFinishLaunching(_ notification: Notification) {
    super.applicationWillFinishLaunching(notification)
    observeReactivation()
    DispatchQueue.main.async {
      if self.windows.isEmpty { self.newWindow() }
    }
  }

  /// Closing every window leaves the app running, the way Finder and Mail do;
  /// only ⌘Q quits.
  override func applicationShouldTerminateAfterLastWindowClosed(
    _ sender: NSApplication
  ) -> Bool {
    return false
  }

  /// Clicking the Dock icon with nothing open gives the user a window back,
  /// rather than a running app with no way into it.
  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if windows.isEmpty { newWindow() }
    return true
  }

  override func applicationSupportsSecureRestorableState(
    _ app: NSApplication
  ) -> Bool {
    return true
  }

  // ─── Documents handed to us by Launch Services ───────────────────────────

  /// This — not `application:openFile:` — is what actually gets called.
  /// `FlutterAppDelegate` implements `application:openURLs:`, and AppKit only
  /// falls back to the older `openFile:`/`openFiles:` hooks when the delegate
  /// does *not* respond to this one. Overriding those alone silently does
  /// nothing.
  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls where url.isFileURL { openPath(url.path) }

    let rest = urls.filter { !$0.isFileURL }
    if !rest.isEmpty { super.application(application, open: rest) }
  }

  /// `applicationDidBecomeActive` never actually reaches this delegate (the
  /// override runs zero times — verified with logging), so the engines only
  /// ever hear the *leaving* half of the app-lifecycle pair and stay in
  /// `AppLifecycleState.hidden` forever. Key and mouse events still arrive in
  /// Dart, but the framework's focus system ignores them while it believes
  /// the app is hidden — that is the "window goes dead after switching apps"
  /// bug. Observing the notifications directly is the reliable path, and the
  /// state is pushed per engine because each window runs its own.
  private func observeReactivation() {
    let center = NotificationCenter.default
    for name in [
      NSApplication.didBecomeActiveNotification,
      NSApplication.didUnhideNotification,
    ] {
      center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        self?.broadcastLifecycle("AppLifecycleState.resumed")
      }
    }
  }

  private func broadcastLifecycle(_ state: String) {
    for window in windows { window.notifyLifecycle(state) }
    preferencesWindow?.notifyLifecycle(state)
  }

  // ─── Windows ─────────────────────────────────────────────────────────────

  /// Always a brand-new window with a blank Untitled Document. `pendingPaths`
  /// seeds the queue its Dart side drains on boot.
  ///
  /// Booting a Flutter engine — what `EditorWindow.init` does before the
  /// window even exists — is synchronous and runs on the main thread; with
  /// several engines already resident it can take long enough to read as the
  /// whole app hanging, not just the new window being slow to open. Deferring
  /// to the next run-loop turn doesn't make that work any faster, but it does
  /// let the event that triggered this (⌘N, a menu click) finish being
  /// handled first, rather than that event's own dispatch being what blocks.
  func newWindow(pendingPaths: [String] = []) {
    DispatchQueue.main.async {
      let window = EditorWindow(
        id: self.nextWindowID,
        app: self,
        pendingPaths: pendingPaths,
        cascadingFrom: self.windows.last
      )
      self.nextWindowID += 1
      self.windows.append(window)
      window.makeKeyAndOrderFront(nil)
      self.windowsChanged()
    }
  }

  /// The single entry point for "the user picked a file to open" — ⌘O,
  /// Recents, Finder, the Dock.
  func openPath(_ path: String) {
    // Never the same Document in two windows.
    if let existing = windows.first(where: { $0.holds(path) }) {
      existing.makeKeyAndOrderFront(nil)
      return
    }
    // An untouched window is one the user is offering us.
    if let empty = frontmostWindow, empty.isEmpty {
      empty.deliver(path: path)
      empty.makeKeyAndOrderFront(nil)
      return
    }
    newWindow(pendingPaths: [path])
  }

  func focusWindow(id: Int) {
    windows.first { $0.id == id }?.makeKeyAndOrderFront(nil)
  }

  /// Save As must not silently point a second window at a path another
  /// window already has open — `openPath`'s dedup only guards the *open*
  /// path, not a path a window arrives at by saving.
  func pathOpenElsewhere(_ path: String, excluding window: EditorWindow) -> Bool {
    windows.contains { $0 !== window && $0.holds(path) }
  }

  func windowClosed(_ window: EditorWindow) {
    windows.removeAll { $0 === window }
    if window.ownsFrameAutosaveName {
      window.releaseFrameAutosaveName()
      // From the registry, not the screen: the window being closed is still
      // in AppKit's ordered list at this point.
      windows.first?.claimFrameAutosaveName()
    }
    if let path = window.path { bookmarkRelease(path: path, from: window) }
    windowsChanged()
  }

  /// Pushes the window list to every window, because the menu bar belongs to
  /// whichever engine rendered it last. A native `NSMenu` cannot serve here:
  /// Flutter's `PlatformMenuBar` rebuilds `NSApp.mainMenu` from Dart on every
  /// re-render and drops anything it did not put there — verified against this
  /// app, a native menu added afterwards survives until the next rebuild only.
  func windowsChanged() {
    let list = windows.map {
      ["id": $0.id, "title": $0.menuTitle, "isKey": $0.isKeyWindow] as [String: Any]
    }
    for window in windows { window.notifyWindowList(list) }
  }

  private var frontmostWindow: EditorWindow? {
    NSApp.orderedWindows.first { $0 is EditorWindow } as? EditorWindow
      ?? windows.last
  }

  // ─── Preferences ─────────────────────────────────────────────────────────

  func showPreferences(checkUpdates: Bool = false) {
    if let window = preferencesWindow {
      window.makeKeyAndOrderFront(nil)
      if checkUpdates { window.requestUpdateCheck() }
      return
    }
    let window = PreferencesWindow(app: self, checkUpdatesOnReady: checkUpdates)
    preferencesWindow = window
    window.makeKeyAndOrderFront(nil)
  }

  func preferencesWindowClosed() {
    preferencesWindow = nil
  }

  /// A setting changed in some Window — every other Window runs its own
  /// engine with its own cached copy of it, so each is told to re-read it.
  /// Mirrors `windowsChanged()`: same reason (per-window channel instances),
  /// same shape.
  func settingsChanged() {
    for window in windows { window.notifySettingsChanged() }
  }

  // ─── Never quit on top of unsaved work ───────────────────────────────────

  /// Deliberately does not call `super`: FlutterAppDelegate's implementation
  /// runs its own `.terminateLater` handshake, and two pending replies to
  /// `reply(toApplicationShouldTerminate:)` is undefined behaviour. This app's
  /// save prompt replaces it.
  override func applicationShouldTerminate(
    _ sender: NSApplication
  ) -> NSApplication.TerminateReply {
    let dirty = windows.filter { $0.needsCloseConfirmation }
    if dirty.isEmpty { return .terminateNow }
    confirm(dirty[...]) { NSApp.reply(toApplicationShouldTerminate: $0) }
    return .terminateLater
  }

  /// One window at a time, each brought to front as it is asked, stopping the
  /// moment the user cancels — prompting every window at once would stack
  /// dialogs the user cannot attribute to a document.
  private func confirm(
    _ queue: ArraySlice<EditorWindow>,
    done: @escaping (Bool) -> Void
  ) {
    guard let window = queue.first else { done(true); return }
    window.makeKeyAndOrderFront(nil)
    window.confirmClose { ok in
      guard ok else { done(false); return }
      self.confirm(queue.dropFirst(), done: done)
    }
  }

  /// `FlutterAppDelegate`'s whole job for these callbacks is forwarding them
  /// to every registered engine and plugin as app-lifecycle events — see
  /// `FlutterAppLifecycleDelegate`, which lists
  /// `applicationDidBecomeActive`/`WillResignActive` among them.
  ///
  /// Overriding this *without* calling super swallowed the "app is active
  /// again" half of that pair while `applicationWillResignActive` (not
  /// overridden, so super still handled it) kept delivering the other half.
  /// Every engine therefore went inactive on the way out and never came
  /// back: the window kept painting its last frame but stopped reacting to
  /// hover and clicks, which reads as it freezing after you switch to
  /// another app and back — and as *other* windows freezing too, since the
  /// events are app-wide, not per-window.
  override func applicationDidBecomeActive(_ notification: Notification) {
    super.applicationDidBecomeActive(notification)
    for window in windows { window.notifyActivated() }
  }

  override func applicationWillTerminate(_ notification: Notification) {
    super.applicationWillTerminate(notification)
    for url in securityScoped.values { url.stopAccessingSecurityScopedResource() }
    securityScoped.removeAll()

    // Fired via `Process`, not `NSWorkspace.openApplication`'s async
    // completion handler: `open` forks and detaches immediately, so it
    // survives this process exiting a moment later. The async API's
    // completion could otherwise race the exit and never fire.
    if let path = pendingRelaunchPath {
      let task = Process()
      task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
      task.arguments = ["-n", path]
      try? task.run()
    }
  }

  // ─── One-click update ────────────────────────────────────────────────────

  /// Verifies an extracted bundle is genuinely signed by this app's own
  /// Developer ID before anything is installed from it — the only real
  /// security boundary in the update pipeline, since the download URL itself
  /// is just taken from the GitHub API response.
  func verifySignature(path: String?) -> Bool {
    guard let path = path else { return false }
    var staticCode: SecStaticCode?
    let url = URL(fileURLWithPath: path)
    guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
          let code = staticCode else { return false }

    var requirement: SecRequirement?
    let requirementString =
      "anchor apple generic and certificate leaf[subject.OU] = \"R9Q763J4DV\""
        as CFString
    guard SecRequirementCreateWithString(requirementString, [], &requirement) == errSecSuccess,
          let req = requirement else { return false }

    let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures)
    return SecStaticCodeCheckValidity(code, flags, req) == errSecSuccess
  }

  /// Queues a relaunch at `bundlePath` and runs the normal quit sequence to
  /// get there — `applicationShouldTerminate` still prompts for unsaved work
  /// in any open Editor window exactly as ⌘Q would, and the relaunch is
  /// skipped entirely if the user cancels that prompt.
  func relaunchAfterQuit(bundlePath: String?) {
    guard let bundlePath = bundlePath else { return }
    pendingRelaunchPath = bundlePath
    NSApp.terminate(nil)
  }

  // ─── Atomic write ────────────────────────────────────────────────────────

  /// Foundation's `.atomic` write does the temp-file-plus-exchange dance using
  /// the sandbox-aware APIs and preserves the original file's attributes —
  /// doing the same by hand from Dart would break under App Sandbox.
  func writeAtomically(args: [String: Any], result: @escaping FlutterResult) {
    guard let path = args["path"] as? String,
          let data = args["bytes"] as? FlutterStandardTypedData else {
      result(FlutterError(code: "bad_args", message: "path/bytes missing", details: nil))
      return
    }
    do {
      try data.data.write(to: URL(fileURLWithPath: path), options: [.atomic])
      result(true)
    } catch {
      result(FlutterError(
        code: "write_failed",
        message: error.localizedDescription,
        details: path
      ))
    }
  }

  // ─── Security-scoped bookmarks ───────────────────────────────────────────

  func bookmarkCreate(path: String?) -> String? {
    guard let path = path else { return nil }
    // Outside the sandbox this throws; a nil bookmark simply means the plain
    // path is enough, which it is.
    return try? URL(fileURLWithPath: path)
      .bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      .base64EncodedString()
  }

  func bookmarkResolve(data: String?) -> String? {
    guard let base64 = data, let blob = Data(base64Encoded: base64) else { return nil }
    var stale = false
    guard let url = try? URL(
      resolvingBookmarkData: blob,
      options: .withSecurityScope,
      relativeTo: nil,
      bookmarkDataIsStale: &stale
    ) else { return nil }

    if url.startAccessingSecurityScopedResource() {
      securityScoped[url.path] = url
    }
    return url.path
  }

  /// Access is app-wide, so it must outlive the releasing window whenever
  /// another window still has the same file open.
  func bookmarkRelease(path: String, from window: EditorWindow) {
    if windows.contains(where: { $0 !== window && $0.holds(path) }) { return }
    securityScoped.removeValue(forKey: path)?.stopAccessingSecurityScopedResource()
  }

  // ─── Startup background colour ──────────────────────────────────────────

  /// Typen's own `surface0` — the exact hex values `AppPalette.light`/`.dark`
  /// use in `theme.dart` — resolved the same way Dart resolves them: an
  /// explicit light/dark override from Settings if the user set one,
  /// current system appearance otherwise. `NSColor.windowBackgroundColor`
  /// (a generic system colour) isn't a close enough match in either mode —
  /// dark mode's system grey is nothing like Typen's near-black, and if the
  /// user has forced a theme that disagrees with the system appearance, a
  /// system-adaptive colour is wrong in exactly the case it exists to avoid.
  /// Every new-window class needs to set both `backgroundColor` (native) and
  /// `controller.backgroundColor` to this before showing itself, or it gets
  /// a startup flash back — see the ADR.
  static func startingBackgroundColor() -> NSColor {
    let isDark: Bool
    switch UserDefaults.standard.string(forKey: "flutter.theme_mode") {
    case "light": isDark = false
    case "dark": isDark = true
    default:
      isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
    return isDark
      ? NSColor(red: 0x0A / 255, green: 0x0A / 255, blue: 0x0A / 255, alpha: 1)
      : NSColor(red: 0xFC / 255, green: 0xFC / 255, blue: 0xFB / 255, alpha: 1)
  }
}
