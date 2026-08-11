import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // The title, proxy icon and edited dot are driven from Dart via
    // `setDocument` so the window reflects the actual document, the way every
    // other macOS editor behaves.
    self.title = "Untitled"

    // Remember where the user put the window between launches.
    self.setFrameAutosaveName("TypenMainWindow")
    _ = self.setFrameUsingName("TypenMainWindow")

    self.delegate = self

    RegisterGeneratedPlugins(registry: flutterViewController)

    let registrar = flutterViewController.registrar(forPlugin: "TypenNative")
    let channel = FlutterMethodChannel(
      name: "typen/native",
      binaryMessenger: registrar.messenger
    )
    (NSApplication.shared.delegate as? AppDelegate)?.attach(channel: channel)

    super.awakeFromNib()
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else {
      return true
    }
    return appDelegate.confirmWindowClose(self)
  }
}
