import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
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
