import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  // Holds a reference to the drag-drop channel so it isn't deallocated
  // while the window is alive.
  private var dragDropChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Become our own NSWindowDelegate so we can intercept the red-X
    // close. Without this the window would close before Flutter's
    // didRequestAppExit got a chance to show its unsaved-changes dialog,
    // leaving the app running with no visible window.
    self.delegate = self

    // Minimum window size: keep the chapter list's Add / Delete / Match
    // Playhead OverflowBar on a single line. Below ~578px the
    // OverflowBar wraps the buttons to a column, which looks crowded.
    // This also comfortably exceeds the chapter row's natural minimum
    // (cover panel 280 + divider 1 + ~142 row minimum = 423), so the
    // earlier RenderFlex overflow at narrow widths is also prevented.
    self.minSize = NSSize(width: 578, height: 300)

    // Drag-and-drop file open. We register the *window* as the dragging
    // destination so the entire window — including the empty-state
    // body — accepts file drags. Events are forwarded to Dart over a
    // MethodChannel; Dart handles validation and the unsaved-changes
    // prompt.
    self.registerForDraggedTypes([.fileURL])
    self.dragDropChannel = FlutterMethodChannel(
      name: "m4b_chapterizer/drag_drop",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  // Convert a window-close click into an application-terminate request.
  // Flutter's macOS embedder routes applicationShouldTerminate to
  // didRequestAppExit on the Dart side, where our WindowCloseGuard runs
  // the unsaved-changes dialog and returns AppExitResponse.exit or
  // .cancel. We return `false` here so the window stays open while the
  // dialog is up; if the user picks Discard or Save, NSApplication
  // terminates and the window goes away naturally.
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    NSApplication.shared.terminate(nil)
    return false
  }

}

// MARK: - NSDraggingDestination
//
// NSWindow conforms to NSDraggingDestination at the Objective-C level
// via NSResponder, but Swift doesn't expose these methods as
// overridable on the class directly — they're provided by ObjC
// categories. Declare them in an extension without `override`; the
// Objective-C runtime picks up the implementations via the dragging
// machinery once `registerForDraggedTypes(_:)` has been called on the
// window.
extension MainFlutterWindow {
  public func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    dragDropChannel?.invokeMethod("dragEntered", arguments: nil)
    return .copy
  }

  public func draggingExited(_ sender: (any NSDraggingInfo)?) {
    dragDropChannel?.invokeMethod("dragExited", arguments: nil)
  }

  public func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    return true
  }

  public func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    let pasteboard = sender.draggingPasteboard
    let urls = pasteboard.readObjects(
      forClasses: [NSURL.self], options: nil
    ) as? [URL] ?? []
    let paths = urls.map { $0.path }
    dragDropChannel?.invokeMethod(
      "filesDropped", arguments: ["paths": paths]
    )
    return true
  }
}
