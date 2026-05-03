# Deferred work

Items intentionally out of scope for the current cycle but worth doing later.

## CI / build infrastructure

- [ ] **Pin per-platform ffmpeg SHAs in `tool/fetch_ffmpeg.dart`** for `windows-x64`, `linux-x64`, and `macos-x64`. Currently CI relies on system ffmpeg via `tool/stage_system_ffmpeg.dart`; production builds for those platforms don't yet bundle ffmpeg.
- [ ] **Add macOS-equivalent "Bundle ffmpeg binaries" build steps for Windows and Linux** so production builds on those platforms also ship the pinned ffmpeg.
- [ ] **Coverage reporting service** (Codecov or Coveralls) so coverage is visible on PRs without reading raw logs.
- [ ] **Coverage-floor gate**: extend `tool/coverage_summary.dart` with `--ci-fail-under <pct>` and wire into CI to fail builds if filtered coverage drops below ~95%.
- [ ] **Build-artifact upload** for the `.app`, `.exe`, and Linux bundle so PRs can ship test-able artifacts.
- [ ] **Test-failure artifact upload** (golden diffs, widget screenshots) for diagnosing CI-only failures.
- [ ] **README status badge** for the CI workflow.

## Cross-platform desktop polish

- [ ] **Set the window minimum size on Windows and Linux** to match macOS's 423×300. macOS uses `self.minSize` in `MainFlutterWindow.swift`; Windows uses `WM_GETMINMAXINFO` in `windows/runner/flutter_window.cpp`; Linux uses `gtk_widget_set_size_request` (or `gtk_window_set_geometry_hints`) in `linux/my_application.cc`.

## Other

- (Add new items here as they come up.)
