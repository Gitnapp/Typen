import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Fixed window title; centered horizontally in the title bar by default
    // since there's no toolbar.
    self.title = "Typen"
    self.titleVisibility = .visible

    RegisterGeneratedPlugins(registry: flutterViewController)

    let registrar = flutterViewController.registrar(forPlugin: "TypenFileOpen")
    let channel = FlutterMethodChannel(
      name: "typen/file_open",
      binaryMessenger: registrar.messenger
    )
    if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
      appDelegate.attachFileOpenChannel(channel)
    }

    super.awakeFromNib()
  }
}
