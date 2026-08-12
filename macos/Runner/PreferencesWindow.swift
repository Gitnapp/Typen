import Cocoa
import FlutterMacOS

/// The Preferences window: a singleton, native window with its own Flutter
/// engine — same one-engine-per-window model as `EditorWindow` (see
/// `docs/adr/0001-per-window-flutter-engine.md`), but outside the `windows`
/// registry entirely. It carries no Document, so it plays no part in
/// duplicate-path detection, the Window menu, or the quit sequence.
///
/// Its engine is told apart from an Editor's by a Dart entrypoint argument
/// rather than a second entrypoint function — a named second entrypoint would
/// need `@pragma('vm:entry-point')` to survive release-mode tree shaking, and
/// this app always ships release builds.
final class PreferencesWindow: NSWindow, NSWindowDelegate {
  private unowned let app: AppDelegate
  private let controller: FlutterViewController
  private let channel: FlutterMethodChannel

  /// An update check asked for before Dart was ready to react — consumed the
  /// same way `EditorWindow.pendingPaths` is.
  private var pendingCheckUpdates: Bool
  private var dartReady = false

  private static let frameAutosaveName = "TypenPreferencesWindow"
  private static let defaultContentSize = NSSize(width: 720, height: 480)

  init(app: AppDelegate, checkUpdatesOnReady: Bool = false) {
    self.app = app
    self.pendingCheckUpdates = checkUpdatesOnReady

    let project = FlutterDartProject()
    project.dartEntrypointArguments = ["--preferences"]
    let engine = FlutterEngine(
      name: "io.typen.preferences",
      project: project,
      allowHeadlessExecution: true
    )
    _ = engine.run(withEntrypoint: nil)
    RegisterGeneratedPlugins(registry: engine)

    let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
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

    isReleasedWhenClosed = false
    // Matches the reference look: traffic lights sitting over the sidebar,
    // no title text, content drawn edge-to-edge under them.
    titlebarAppearsTransparent = true
    titleVisibility = .hidden
    title = "偏好设置"
    minSize = NSSize(width: 640, height: 420)

    contentViewController = controller
    setContentSize(Self.defaultContentSize)
    delegate = self
    if !setFrameUsingName(Self.frameAutosaveName) { center() }
    setFrameAutosaveName(Self.frameAutosaveName)

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      self.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "closeWindow":
      performClose(nil)
      result(nil)

    case "settingsChanged":
      app.settingsChanged()
      result(nil)

    case "consumePendingCheckUpdates":
      let pending = pendingCheckUpdates
      pendingCheckUpdates = false
      dartReady = true
      result(pending)

    case "verifySignature":
      let args = call.arguments as? [String: Any]
      result(app.verifySignature(path: args?["path"] as? String))

    case "relaunchAfterQuit":
      let args = call.arguments as? [String: Any]
      app.relaunchAfterQuit(bundlePath: args?["path"] as? String)
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Tells an already-running Preferences engine to jump to 关于 and run a
  /// check. If Dart hasn't consumed the pending flag yet (a request arrived
  /// while this Window was still booting), queue it instead of racing the
  /// boot handshake.
  func requestUpdateCheck() {
    guard dartReady else { pendingCheckUpdates = true; return }
    channel.invokeMethod("checkUpdates", arguments: nil)
  }

  /// ⌘W is bound only inside each Editor's own `PlatformMenuBar`, and the
  /// menu bar belongs to whichever Editor engine rendered it last — this
  /// window never touches it. Without this override, ⌘W here would silently
  /// close that background Editor instead of the window the user is looking
  /// at.
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
       event.charactersIgnoringModifiers == "w" {
      performClose(nil)
      return true
    }
    return super.performKeyEquivalent(with: event)
  }

  func windowWillClose(_ notification: Notification) {
    channel.setMethodCallHandler(nil)
    delegate = nil
    contentViewController = nil
    controller.engine.shutDownEngine()
    app.preferencesWindowClosed()
  }
}
