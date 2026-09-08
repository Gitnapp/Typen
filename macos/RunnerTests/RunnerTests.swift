import Cocoa
import FlutterMacOS
import XCTest
@testable import Typen

class RunnerTests: XCTestCase {

  @MainActor
  func testCloseFromBackgroundMenuClosesKeyWindow() throws {
    let app = NSApp.delegate as! AppDelegate
    let old = EditorWindow(id: 10001, app: app, pendingPaths: [], cascadingFrom: nil)
    let new = EditorWindow(id: 10002, app: app, pendingPaths: [], cascadingFrom: old)
    defer {
      if old.isVisible { old.close() }
      if new.isVisible { new.close() }
    }
    old.makeKeyAndOrderFront(nil)
    new.makeKeyAndOrderFront(nil)
    // A background XCTest host cannot take desktop focus. Stub only AppKit's
    // focus lookup; both windows and the native channel handler remain real.
    let getter = try XCTUnwrap(class_getInstanceMethod(
      NSApplication.self, #selector(getter: NSApplication.keyWindow)
    ))
    let focusedWindow: @convention(block) (AnyObject) -> NSWindow? = { _ in new }
    let replacement = imp_implementationWithBlock(focusedWindow)
    let original = method_setImplementation(getter, replacement)
    defer {
      method_setImplementation(getter, original)
      imp_removeBlock(replacement)
    }
    XCTAssertTrue(NSApp.keyWindow === new)

    // The shared menu may belong to the background window's Flutter engine.
    old.handle(call: FlutterMethodCall(methodName: "closeWindow", arguments: nil)) { _ in }

    XCTAssertTrue(old.isVisible, "Command-W must preserve the background window")
    XCTAssertFalse(new.isVisible, "Command-W must close the key window")
  }

}
