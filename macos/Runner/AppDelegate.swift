import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var pendingPaths: [String] = []
  private var channel: FlutterMethodChannel?
  private var dartReady = false

  /// Security-scoped URLs we currently hold access to, keyed by path. Access
  /// must be balanced with `stopAccessingSecurityScopedResource`.
  private var securityScoped: [String: URL] = [:]

  /// Set once the user has answered the unsaved-changes prompt, so closing the
  /// window and then terminating does not ask twice.
  private var closeApproved = false

  override func applicationShouldTerminateAfterLastWindowClosed(
    _ sender: NSApplication
  ) -> Bool {
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
    let files = urls.filter { $0.isFileURL }
    for url in files { deliver(path: url.path) }

    let rest = urls.filter { !$0.isFileURL }
    if !rest.isEmpty { super.application(application, open: rest) }
  }

  // ─── Never quit on top of unsaved work ───────────────────────────────────

  /// Deliberately does not call `super`: FlutterAppDelegate's implementation
  /// runs its own `.terminateLater` handshake, and two pending replies to
  /// `reply(toApplicationShouldTerminate:)` is undefined behaviour. This app's
  /// save prompt replaces it.
  override func applicationShouldTerminate(
    _ sender: NSApplication
  ) -> NSApplication.TerminateReply {
    guard !closeApproved, dartReady, let channel = channel else {
      return .terminateNow
    }
    channel.invokeMethod("confirmClose", arguments: nil) { reply in
      // The Dart handler is total — it always answers with a Bool. Anything
      // else means the engine is gone, in which case blocking the quit would
      // protect nothing and only trap the user.
      let ok = (reply as? Bool) ?? true
      if ok { self.closeApproved = true }
      NSApp.reply(toApplicationShouldTerminate: ok)
    }
    return .terminateLater
  }

  /// Same prompt for ⌘W. Returns false and closes later, once Dart answers.
  func confirmWindowClose(_ window: NSWindow) -> Bool {
    if closeApproved { return true }
    guard dartReady, let channel = channel else { return true }
    channel.invokeMethod("confirmClose", arguments: nil) { reply in
      if (reply as? Bool) ?? true {
        self.closeApproved = true
        window.close()
      }
    }
    return false
  }

  override func applicationDidBecomeActive(_ notification: Notification) {
    guard dartReady else { return }
    channel?.invokeMethod("activated", arguments: nil)
  }

  override func applicationWillTerminate(_ notification: Notification) {
    for url in securityScoped.values { url.stopAccessingSecurityScopedResource() }
    securityScoped.removeAll()
  }

  // ─── Channel ─────────────────────────────────────────────────────────────

  func attach(channel: FlutterMethodChannel) {
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      let args = call.arguments as? [String: Any] ?? [:]

      switch call.method {
      case "consumePendingOpens":
        let paths = self.pendingPaths
        self.pendingPaths.removeAll()
        self.dartReady = true
        result(paths)

      case "setDocument":
        self.setDocument(
          path: args["path"] as? String,
          edited: args["edited"] as? Bool ?? false
        )
        result(nil)

      case "writeAtomically":
        self.writeAtomically(args: args, result: result)

      case "bookmarkCreate":
        result(self.bookmarkCreate(path: args["path"] as? String))

      case "bookmarkResolve":
        result(self.bookmarkResolve(data: args["data"] as? String))

      case "bookmarkRelease":
        if let path = args["path"] as? String,
           let url = self.securityScoped.removeValue(forKey: path) {
          url.stopAccessingSecurityScopedResource()
        }
        result(nil)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // ─── Window chrome ───────────────────────────────────────────────────────

  private func setDocument(path: String?, edited: Bool) {
    guard let window = mainFlutterWindow else { return }
    window.isDocumentEdited = edited
    if let path = path {
      window.representedURL = URL(fileURLWithPath: path)
      window.title = (path as NSString).lastPathComponent
    } else {
      window.representedURL = nil
      window.title = "Untitled"
    }
  }

  // ─── Atomic write ────────────────────────────────────────────────────────

  /// Foundation's `.atomic` write does the temp-file-plus-exchange dance using
  /// the sandbox-aware APIs and preserves the original file's attributes —
  /// doing the same by hand from Dart would break under App Sandbox.
  private func writeAtomically(args: [String: Any], result: @escaping FlutterResult) {
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

  private func bookmarkCreate(path: String?) -> String? {
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

  private func bookmarkResolve(data: String?) -> String? {
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

  // ─── Pending open queue ──────────────────────────────────────────────────

  private func deliver(path: String) {
    if dartReady, let channel = channel {
      channel.invokeMethod("openFile", arguments: path)
    } else {
      pendingPaths.append(path)
    }
  }
}
