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

    // Minimum window size: enough room for the fixed-width 280px
    // cover/metadata panel plus the 1px divider plus 142px for the
    // chapter list (the row layout's natural minimum). Below this the
    // chapter list's row Row would overflow its fixed 8px title-to-start
    // gap and Flutter's RenderFlex throws.
    self.minSize = NSSize(width: 423, height: 300)

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
