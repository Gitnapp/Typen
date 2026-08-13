import Cocoa
import FlutterMacOS

/// One Window, one Document, one Flutter engine.
///
/// Each window boots its own `FlutterViewController` (and with it its own
/// engine running `main.dart`) and owns its own `typen/native` channel — see
/// `docs/adr/0001-per-window-flutter-engine.md`. The instance doubles as the
/// registry entry `AppDelegate` keeps: `path`/`edited` mirror what this
/// window's Dart side last reported, and the app-wide policies (duplicate
/// detection, Empty-window reuse, quit sequencing) read them from here.
final class EditorWindow: NSWindow, NSWindowDelegate {
  /// Identity for the Window menu. AppKit's `windowNumber` is recycled, ours
  /// is not.
  let id: Int

  /// The document this window holds, as last reported by `setDocument`.
  private(set) var path: String?
  private(set) var edited = false

  private unowned let app: AppDelegate
  private let controller: FlutterViewController
  private let channel: FlutterMethodChannel

  /// Paths handed to this window before its Dart side asked for them.
  private var pendingPaths: [String]
  private var dartReady = false

  /// One shared autosave name: every window opens where the user last left
  /// one. Only the window currently holding the name writes back to it.
  private static let frameAutosaveName = "TypenMainWindow"

  private static let defaultContentSize = NSSize(width: 800, height: 600)

  init(
    id: Int,
    app: AppDelegate,
    pendingPaths: [String],
    cascadingFrom previous: EditorWindow?
  ) {
    self.id = id
    self.app = app
    self.pendingPaths = pendingPaths

    // Loading the view is what boots this window's engine, and the plugin
    // registrar is only meaningful behind a running engine — so both happen
    // before the window exists to hold the controller.
    let controller = FlutterViewController()
    // See PreferencesWindow: `.inKeyWindow` (Flutter's default) drops hover
    // whenever this window isn't key, which with several windows open is
    // most of the time.
    controller.mouseTrackingMode = .inActiveApp
    _ = controller.view
    RegisterGeneratedPlugins(registry: controller)
    self.controller = controller
    let registrar = controller.registrar(forPlugin: "TypenNative")
    channel = FlutterMethodChannel(
      name: "typen/native",
      binaryMessenger: registrar.messenger
    )

    super.init(
      contentRect: NSRect(origin: .zero, size: Self.defaultContentSize),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )

    // Windows are owned by the registry; letting AppKit release this one on
    // close would leave the registry holding freed memory.
    isReleasedWhenClosed = false
    // One Document per Window — merging them into tabs would put two
    // Documents behind one set of window chrome.
    tabbingMode = .disallowed
    // Same unified, traffic-lights-over-content look as PreferencesWindow.
    // Title text stays hidden rather than synced to match — an unsynced
    // native title would draw in whatever text colour the *system's*
    // light/dark mode implies, which has no relation to Typen's own (Dart-
    // driven) theme and can end up unreadable against it. The filename lives
    // in the Dart-drawn title strip instead, which always gets this right.
    titlebarAppearsTransparent = true
    titleVisibility = .hidden

    // FlutterView's background defaults to black until Dart's first frame
    // paints (documented on FlutterViewController.backgroundColor), and this
    // window is shown before that happens — without this, opening any window
    // is a black flash that resolves once Flutter catches up, worse the
    // slower that is (debug builds, a loaded machine). See
    // AppDelegate.startingBackgroundColor — a generic system colour isn't
    // enough here, it has to be Typen's own palette.
    let startColor = AppDelegate.startingBackgroundColor()
    backgroundColor = startColor
    controller.backgroundColor = startColor

    contentViewController = controller
    // Adopting a view controller resizes the window down to that view, which
    // has no size of its own yet — so the intended size is set afterwards.
    setContentSize(Self.defaultContentSize)
    // `representedURL`/`isDocumentEdited`, driven from Dart via
    // `setDocument`, still matter — the edited dot in the close button and
    // the Dock still read them even with the title itself hidden.
    title = "Untitled"
    delegate = self
    place(after: previous)

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      self.handle(call: call, result: result)
    }
  }

  // ─── Registry queries ────────────────────────────────────────────────────

  /// Empty means: no Document of its own, never edited, and nothing on its way
  /// in. Opening a file reuses such a window instead of spawning one.
  var isEmpty: Bool { path == nil && !edited && pendingPaths.isEmpty }

  /// True when this window already owns the given path — either loaded, or
  /// queued for the boot that is still in flight.
  func holds(_ candidate: String) -> Bool {
    let wanted = Self.standardized(candidate)
    if let path = path, Self.standardized(path) == wanted { return true }
    return pendingPaths.contains { Self.standardized($0) == wanted }
  }

  /// Nothing to lose means nothing to ask. An answered prompt is never
  /// remembered: a quit the user cancels on a later window must leave this
  /// one exactly as it was, prompt included.
  var needsCloseConfirmation: Bool { edited && dartReady }

  /// Filename, or "Untitled" — what the Window menu lists.
  var menuTitle: String {
    guard let path = path else { return "Untitled" }
    return (path as NSString).lastPathComponent
  }

  private static func standardized(_ path: String) -> String {
    URL(fileURLWithPath: path).standardizedFileURL.path
  }

  // ─── Native -> Dart ──────────────────────────────────────────────────────

  /// Hands a path to this window's Document, queueing it when Dart has not
  /// booted far enough to take it.
  func deliver(path: String) {
    if dartReady {
      channel.invokeMethod("openFile", arguments: path)
    } else {
      pendingPaths.append(path)
    }
  }

  func notifyActivated() {
    guard dartReady else { return }
    channel.invokeMethod("activated", arguments: nil)
  }

  func notifyWindowList(_ windows: [[String: Any]]) {
    guard dartReady else { return }
    channel.invokeMethod("windowsChanged", arguments: windows)
  }

  /// A setting changed in the Preferences window (or another Editor); this
  /// one's own in-memory copy is now stale.
  func notifySettingsChanged() {
    guard dartReady else { return }
    channel.invokeMethod("settingsChanged", arguments: nil)
  }

  /// Asks this window's Document whether it may go, answering true when there
  /// is nothing to lose.
  func confirmClose(_ done: @escaping (Bool) -> Void) {
    guard needsCloseConfirmation else { done(true); return }
    channel.invokeMethod("confirmClose", arguments: nil) { reply in
      // The Dart handler is total — it always answers with a Bool. Anything
      // else means the engine is gone, in which case blocking the close would
      // protect nothing and only trap the user.
      done((reply as? Bool) ?? true)
    }
  }

  // ─── Dart -> Native ──────────────────────────────────────────────────────

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]

    switch call.method {
    case "consumePendingOpens":
      let paths = pendingPaths
      pendingPaths.removeAll()
      dartReady = true
      result(paths)
      // This window can only render the Window menu once it is listening.
      app.windowsChanged()

    case "setDocument":
      setDocument(
        path: args["path"] as? String,
        edited: args["edited"] as? Bool ?? false
      )
      result(nil)

    case "writeAtomically":
      app.writeAtomically(args: args, result: result)

    case "bookmarkCreate":
      result(app.bookmarkCreate(path: args["path"] as? String))

    case "bookmarkResolve":
      result(app.bookmarkResolve(data: args["data"] as? String))

    case "bookmarkRelease":
      if let path = args["path"] as? String {
        app.bookmarkRelease(path: path, from: self)
      }
      result(nil)

    case "newWindow":
      app.newWindow()
      result(nil)

    case "openPreferences":
      let checkUpdates = (call.arguments as? [String: Any])?["checkUpdates"] as? Bool ?? false
      app.showPreferences(checkUpdates: checkUpdates)
      result(nil)

    case "closeWindow":
      // Same door as the red button: performClose still runs
      // windowShouldClose, so the unsaved-changes confirm is unchanged.
      performClose(nil)
      result(nil)

    // `openPath` and `focusWindow` take the argument map the other methods
    // use, or the bare value on its own.
    case "openPath":
      if let path = args["path"] as? String ?? call.arguments as? String {
        app.openPath(path)
      }
      result(nil)

    case "focusWindow":
      if let id = args["id"] as? Int ?? call.arguments as? Int {
        app.focusWindow(id: id)
      }
      result(nil)

    case "pathOpenElsewhere":
      if let path = args["path"] as? String ?? call.arguments as? String {
        result(app.pathOpenElsewhere(path, excluding: self))
      } else {
        result(false)
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // ─── Window chrome ───────────────────────────────────────────────────────

  private func setDocument(path: String?, edited: Bool) {
    self.path = path
    self.edited = edited
    isDocumentEdited = edited
    if let path = path {
      representedURL = URL(fileURLWithPath: path)
      title = (path as NSString).lastPathComponent
    } else {
      representedURL = nil
      title = "Untitled"
    }
    app.windowsChanged()
  }

  /// Opens where the user last left a window, offset from the one before it so
  /// a new window never lands exactly on top of an existing one.
  private func place(after previous: EditorWindow?) {
    if !setFrameUsingName(Self.frameAutosaveName) { center() }
    guard let previous = previous else {
      // The only window on screen is the one that remembers where it was.
      claimFrameAutosaveName()
      return
    }
    // Cascading from `NSZeroPoint` leaves `previous` where it is and answers
    // the point one step down-right of it — where this window belongs.
    _ = cascadeTopLeft(from: previous.cascadeTopLeft(from: .zero))
  }

  /// Takes over persisting the frame, so exactly one open window writes it.
  func claimFrameAutosaveName() {
    setFrameAutosaveName(Self.frameAutosaveName)
  }

  var ownsFrameAutosaveName: Bool {
    frameAutosaveName == Self.frameAutosaveName
  }

  func releaseFrameAutosaveName() {
    setFrameAutosaveName("")
  }

  // ─── Lifecycle ───────────────────────────────────────────────────────────

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if !needsCloseConfirmation { return true }
    confirmClose { ok in if ok { self.close() } }
    return false
  }

  func windowWillClose(_ notification: Notification) {
    channel.setMethodCallHandler(nil)
    delegate = nil
    contentViewController = nil
    controller.engine.shutDownEngine()
    app.windowClosed(self)
  }

  func windowDidBecomeKey(_ notification: Notification) {
    app.windowsChanged()
  }
}
