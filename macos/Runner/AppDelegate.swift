import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var pendingPaths: [String] = []
  private var fileOpenChannel: FlutterMethodChannel?
  private var dartReady = false

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    deliver(path: filename)
    return true
  }

  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    for path in filenames {
      deliver(path: path)
    }
    sender.reply(toOpenOrPrint: .success)
  }

  func attachFileOpenChannel(_ channel: FlutterMethodChannel) {
    fileOpenChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      if call.method == "consumePending" {
        let paths = self.pendingPaths
        self.pendingPaths.removeAll()
        self.dartReady = true
        result(paths)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func deliver(path: String) {
    if dartReady, let channel = fileOpenChannel {
      channel.invokeMethod("openFile", arguments: path)
    } else {
      pendingPaths.append(path)
    }
  }
}
