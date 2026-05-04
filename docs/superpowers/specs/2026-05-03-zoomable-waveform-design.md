# Zoomable Waveform View — Design

**Date:** 2026-05-03
**Status:** Approved (brainstorming phase)

## Overview

Add a tall, zoomable waveform display above the existing thin `ChapterScrubber` inside `PlaybackControls`. The new view shares the same peak data as the scrubber but is zoomable from "whole file fits" out to 2000 px/s in. During playback the viewport continuously follows the playhead so the user can watch the audio scroll past in real time. The existing `ChapterScrubber` stays unchanged as the always-visible whole-file overview.

## Goals

- A 120-px-tall waveform widget rendered immediately above `ChapterScrubber`.
- Default zoom on file open is 100 px/s, with the viewport starting at time 0.
- Zoom in and out via Cmd+scroll / Cmd+pinch (cursor-centered) and via `−` / `+` buttons (playhead-centered).
- Pan via plain horizontal scroll / two-finger drag / drag-the-waveform-body (paused only).
- Tap on the waveform body seeks the playhead to that time.
- During playback, the viewport continuously follows the playhead at 25 % from the left edge.
- Chapter ticks render at the same pixel positions as `ChapterScrubber` but only those visible in the current zoom window draw.
- Reuse the existing `waveformPeaksProvider` (4096 peaks per file). No re-extraction on zoom.
- Reset to default zoom + windowStart 0 whenever a new file is opened.

## Non-goals

- Re-extracting peaks at higher resolution when zoomed in. (At max zoom, ~125 peaks fit a typical viewport — visually adequate. If we hit limits later, on-demand re-extraction is a follow-up.)
- Keyboard shortcuts for zoom (Cmd+= / Cmd+−). Follow-up.
- Vertical (amplitude) zoom.
- Drag-to-edit chapter boundaries directly on the waveform. Chapter starts are still edited via the chapter list and the **Match Playhead** button.
- Selection / range highlighting.
- Persisting zoom state across file open. The viewport resets every time.
- A "follow playhead" toggle button. Follow is automatic during playback.
- Snap-to-tick on click in the zoomed view. (Snap is only useful when ticks are visually adjacent to the cursor; in a zoomed view, ticks are typically off-screen.)

## Visual layout

Inside `PlaybackControls`, top-to-bottom:

```
┌─ WaveformView (120 px tall) ─────────────────────────────┐
│                                                  [−] [+] │
│  ┌───────────────────────────────────────────────────┐   │
│  │ tall waveform with chapter ticks + playhead line  │   │
│  └───────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────┘
┌─ ChapterScrubber (24 px tall, unchanged) ────────────────┐
│  thin overview track                                     │
└──────────────────────────────────────────────────────────┘
[ ▶ play ] [ 00:23:45 / 08:12:33 ]              [ Save ▾ ]
```

The `−` and `+` buttons sit in the top-right corner of the `WaveformView`. The waveform body fills the rest of the widget. A vertical playhead line spans the full waveform height at the current playhead time.

## Zoom model

Zoom is measured as `pixelsPerSecond` (px/s).

- **Min zoom:** `viewportWidth / totalDuration.inSeconds` — i.e. exactly fits the whole file.
- **Max zoom:** 2000 px/s (≈ 0.5 ms per pixel).
- **Default on file open:** `max(100, minPxPerSec)` — 100 px/s for any file longer than `viewportWidth / 100` seconds, else "whole file fits."
- **Steps:** doubling for `+`, halving for `−`. Cmd+scroll and Cmd+pinch use a fractional step proportional to the gesture's signed magnitude (clamped per event so a single tick can't blow through multiple steps).

Window duration is derived: `windowDuration = viewportWidth / pixelsPerSecond`.

## Pan & follow behavior

Two modes:

- **Playing:** the viewport continuously follows the playhead. On every position update, `windowStart` is set to `playhead - 0.25 * windowDuration`, then clamped to `[0, totalDuration - windowDuration]`.
  - **Pan is disabled** during playback. Drag and plain-scroll pan handlers are no-ops while `controller.playing == true`. (The user pauses to look elsewhere.)
  - **Zoom remains functional** — `−` / `+` buttons, Cmd+scroll, and Cmd+pinch all change `pixelsPerSecond`. `windowStart` is then re-anchored on the playhead by the next follow tick, so the zoomed view stays centered on the audio that's playing.
- **Paused:** no follow. The viewport stays wherever it was last placed. Pan and zoom move it freely.

When the user clicks **Play**, the viewport snaps to the follow position on the first position update. There is no manual "follow" toggle.

## State

A new `WaveformViewport` immutable record:

```dart
@immutable
class WaveformViewport {
  const WaveformViewport({
    required this.pixelsPerSecond,
    required this.windowStart,
  });

  final double pixelsPerSecond;
  final Duration windowStart;
}
```

A new `WaveformViewportNotifier extends Notifier<WaveformViewport>` exposes:

- `zoomTo(double pxPerSec, Duration centerTime, Duration totalDuration, double viewportWidth)` — sets the new zoom and adjusts `windowStart` so `centerTime` lands at the same screen X as before. Clamps `pxPerSec` to `[minFor(totalDuration, viewportWidth), 2000]` and `windowStart` to `[0, totalDuration - windowDuration]`.
- `zoomIn(Duration centerTime, Duration totalDuration, double viewportWidth)` — convenience: `zoomTo(pixelsPerSecond * 2, ...)`.
- `zoomOut(Duration centerTime, Duration totalDuration, double viewportWidth)` — convenience: `zoomTo(pixelsPerSecond / 2, ...)`.
- `panBy(double deltaPixels, Duration totalDuration, double viewportWidth)` — converts `deltaPixels` to a `Duration` using current `pixelsPerSecond` and shifts `windowStart` (clamped).
- `followPlayhead(Duration playhead, Duration totalDuration, double viewportWidth, {double anchorFraction = 0.25})` — sets `windowStart = playhead - anchorFraction * windowDuration`, clamped.
- `reset(Duration totalDuration, double viewportWidth)` — `pixelsPerSecond = max(100, minFor(...))`, `windowStart = Duration.zero`. Called when the editor's path changes.

The notifier never reads `ref.watch(...)`; all dependencies (totalDuration, viewportWidth) are passed as method arguments. This keeps the notifier easy to test with no provider scaffolding.

`waveformViewportProvider = NotifierProvider<WaveformViewportNotifier, WaveformViewport>(WaveformViewportNotifier.new);` lives in `lib/presentation/providers/waveform_viewport.dart`.

## Architecture (Dart files)

- `lib/presentation/providers/waveform_viewport.dart` — new
  - `WaveformViewport` (immutable record)
  - `WaveformViewportNotifier` (the methods listed above)
  - `waveformViewportProvider`
- `lib/presentation/widgets/waveform_view.dart` — new
  - `WaveformView extends ConsumerStatefulWidget` — wires gesture handlers, listens to `playbackControllerProvider.positionStream`, listens to `editorProvider.select((s) => s.path)` to call `reset(...)` on file change, owns a `LayoutBuilder` that hands viewport width down to children and to the notifier methods.
  - `_WaveformPainter extends CustomPainter` — paints the waveform from the viewport's `windowStart` to `windowStart + windowDuration`, the chapter ticks, and the vertical playhead line.
  - `_ZoomButtons` — the `−` / `+` corner controls.
  - Gesture handling:
    - `Listener` (raw pointer events) for `PointerScrollEvent`. If `Cmd` is held → zoom centered on cursor; else → pan by `event.scrollDelta.dy` (pixels).
    - `Listener` for `PointerPanZoomStartEvent` / `PointerPanZoomUpdateEvent` (trackpad). Pinch component (`event.scale`) → zoom centered on cursor when Cmd held. Pan component (`event.panDelta`) → pan.
    - `GestureDetector` for `onTapUp` (seek), `onHorizontalDragUpdate` (pan, paused only).
- `lib/presentation/widgets/playback_controls.dart` — modify
  - Insert `WaveformView` in the `Column` directly above `ChapterScrubber`.
  - No other changes.

## Painter details

`_WaveformPainter` parameters: `peaks`, `windowStart`, `windowDuration`, `playhead`, `chapterStarts`, `playedColor`, `unplayedColor`, `tickColor`, `playheadColor`.

Paint loop:

1. For each pixel column `x` in `[0, viewportWidth)`:
   - `t = windowStart + (x / viewportWidth) * windowDuration`
   - `peakIndex = (t.inMicroseconds / totalDuration.inMicroseconds * peaks.length).floor()`, clamped to `[0, peaks.length - 1]`
   - Draw vertical bar from `(x, centerY - peak * halfHeight)` to `(x, centerY + peak * halfHeight)` with `playedColor` if `t <= playhead`, else `unplayedColor`. `halfHeight = 50` (so the wave fills 100 of the 120 px, leaving 10 px padding top and bottom).
2. For each `chapterStart` in the visible window: draw a 2 px vertical line full-height in `tickColor`.
3. Draw the playhead: a 2 px vertical line from top to bottom at `x = (playhead - windowStart) / windowDuration * viewportWidth`, in `playheadColor`. Skip if `playhead` is outside the window (e.g. follow temporarily lagging at file end).

`shouldRepaint` compares all parameters (no identity tricks; the painter is cheap enough).

## Gesture details

- **Tap (touch or click):** `onSeek(time)` where `time = windowStart + (tapX / viewportWidth) * windowDuration`.
- **Drag (paused only):** call `panBy(-deltaX, ...)` on every `onHorizontalDragUpdate`. Drag right shifts the window left (i.e. content moves with the finger). During playback, drag is suppressed — `onHorizontalDragUpdate` is a no-op.
- **Mouse wheel scroll, no Cmd:** `panBy(event.scrollDelta.dy, ...)`. Vertical scroll → horizontal pan. (Mouse wheel on a tall waveform is most useful as a pan; horizontal pan via `scrollDelta.dx` would also be summed if a horizontal-scroll mouse is used.)
- **Mouse wheel scroll with Cmd held:** `zoomTo(...)` with new `pxPerSec = pixelsPerSecond * exp(-event.scrollDelta.dy * 0.005)` (approx — small wheel ticks → small zoom changes). Centered on cursor.
- **Trackpad pinch (PointerPanZoom with `scale != 1`) with Cmd held:** `zoomTo(pixelsPerSecond * event.scale, ...)` centered on cursor.
- **Trackpad two-finger pan (PointerPanZoom `panDelta`):** `panBy(panDelta.dx)`. Cmd suppressed during pinch via the same handler.
- **Buttons:** `−` calls `zoomOut(playheadTime, ...)`; `+` calls `zoomIn(playheadTime, ...)`.

Cmd detection: `HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.metaLeft) || ...metaRight`. Also accept `Ctrl` on non-mac platforms via `Platform.isMacOS` check (this codebase is currently macOS-only but the check costs nothing).

## Testing

### `test/presentation/providers/waveform_viewport_test.dart` (new) — pure logic

For all tests below, "totalDuration = 60 s, viewportWidth = 800". `minPxPerSec = 800/60 ≈ 13.33`. Default `pxPerSec = max(100, 13.33) = 100`.

1. **`reset` returns to default state.** After arbitrary state, `reset(60s, 800)` → `pixelsPerSecond = 100`, `windowStart = 0`.
2. **`reset` clamps to whole-file fit for short files.** `totalDuration = 4 s`, `viewportWidth = 800` → `minPxPerSec = 200`. `reset(4s, 800)` → `pixelsPerSecond = 200`, `windowStart = 0`.
3. **`zoomIn` doubles px/s and re-centers on `centerTime`.** Start at `(100, 10s)` (windowDuration = 8 s). `zoomIn(centerTime: 12s, ...)` → new `pxPerSec = 200`, new windowDuration = 4 s, and `12 s` is at the same screen fraction as before (i.e. `(12 - oldStart) / 8 == (12 - newStart) / 4`).
4. **`zoomOut` halves and re-centers; clamped at min.** Start at `(100, 10s)`. `zoomOut(centerTime: 14s, ...)` → `pxPerSec = 50`. Then again → `pxPerSec = 25`. Then again → `pxPerSec = 13.33` (clamped). Window stays in `[0, totalDuration - windowDuration]`.
5. **`panBy` shifts windowStart and clamps left.** At `(100, 10s)`, `panBy(-2000 px, ...)` → would move start to `-10 s`; clamped to `0 s`.
6. **`panBy` clamps right.** `panBy(+10000 px, ...)` at `(100, 10s)` → would move past end; clamped so `windowStart + windowDuration == totalDuration`.
7. **`followPlayhead` puts playhead at 25 % from left.** `followPlayhead(playhead: 30s, ...)` at `(100, 0s)` (windowDuration = 8 s) → `windowStart = 30 - 0.25 * 8 = 28 s`.
8. **`followPlayhead` clamps when playhead is near file start.** `followPlayhead(playhead: 1s, ...)` → `windowStart = 0` (clamped, can't be negative).
9. **`followPlayhead` clamps when playhead is near file end.** `followPlayhead(playhead: 59s, ...)` at `(100, ...)` → `windowStart = 60 - 8 = 52 s` (clamped so end == totalDuration).

### `test/presentation/widgets/waveform_view_test.dart` (new) — widget

Use a `_FakePlayback` (already-established pattern from `editor_screen_test.dart`) and override `waveformPeaksProvider` with a small list. Provide a `_FakeBookbinder` that produces a 60-second audiobook with two chapter starts.

10. **Renders without exception with empty peaks.** Pump with `peaks = []`. `tester.takeException()` is null. No waveform bars; `−` / `+` buttons present.
11. **Renders without exception with non-empty peaks.** Pump with `peaks = [0.0, 0.5, 1.0, 0.5, 0.0]`. No exception.
12. **Tap on the waveform body calls `playback.seek` with the time at that x position.** Pump at default zoom (100 px/s), tap at `x = 200`. Expected seek time: `windowStart (0) + 200 / 800 * 8 s = 2 s`.
13. **`+` button doubles the zoom.** Tap the `+` button. Verify `pixelsPerSecond` is now 200.
14. **`−` button halves the zoom and clamps at min.** Tap `−` repeatedly. After enough taps, verify `pixelsPerSecond == minPxPerSec`.
15. **Reset on file open.** Set zoom to 400 px/s. Open a new file (change `editorProvider.path`). Verify viewport reset to default.
16. **Auto-follow during playback.** Wire `_FakePlayback` to emit `position = 30s` while `playing = true`. Pump a frame. Verify `windowStart ≈ 30 - 0.25 * windowDuration`.
17. **No auto-follow while paused.** With `playing = false`, emit position updates. Verify `windowStart` is unchanged.
18. **Drag pans during pause.** With `playing = false`, simulate `onHorizontalDragUpdate(delta: -200)`. Verify `windowStart` advanced by `200 / 100 = 2 s`.
19. **Drag is a no-op during playback.** With `playing = true`, simulate the same drag. Verify `windowStart` is the follow value, not the dragged value.

Cmd-scroll and pinch tests are out of scope here; those gestures are exercised at the smoke-test level.

### `test/presentation/widgets/playback_controls_test.dart` (extend)

20. **`WaveformView` is present above `ChapterScrubber`.** Pump `PlaybackControls` with a loaded book. Find both widgets in the tree and assert the `WaveformView`'s render box top is above the `ChapterScrubber`'s.

## Smoke-test plan

After merge, on macOS:

1. Open an `.m4b`. Waveform view appears above the thin scrubber, default zoom shows roughly 8 seconds of audio (at 800 px viewport).
2. Cmd+scroll up over the waveform — zoom in. Cursor's time stays under the cursor.
3. Cmd+scroll down — zoom out. Stops at "whole file fits."
4. Click `+` — zoom in one step, centered on the playhead.
5. Click `−` — zoom out one step.
6. Drag the waveform horizontally — viewport pans. Stops at file edges.
7. Two-finger trackpad swipe horizontally — viewport pans.
8. Click on the waveform — playhead seeks to that time.
9. Press play — viewport begins continuously following; the playhead stays anchored at ~25 % from the left edge while the audio scrolls underneath.
10. Press pause — follow stops. Drag freely.
11. Open a different `.m4b` — viewport resets to default zoom and windowStart 0.
12. Open a very short test file (less than 8 s) — default zoom drops to "whole file fits"; can't zoom out further.

## Files

- Create: `lib/presentation/providers/waveform_viewport.dart`
- Create: `lib/presentation/widgets/waveform_view.dart`
- Create: `test/presentation/providers/waveform_viewport_test.dart`
- Create: `test/presentation/widgets/waveform_view_test.dart`
- Modify: `lib/presentation/widgets/playback_controls.dart` (insert `WaveformView`)
- Modify: `test/presentation/playback_controls_test.dart` (assert `WaveformView` is above `ChapterScrubber`)

## Open items for the implementation plan

- The exact gesture-recognizer wiring on Flutter desktop for trackpad pinch — Flutter macOS exposes pinch via `PointerPanZoom*` events. The implementation plan will spell out the `Listener`-based handler that distinguishes "Cmd + pinch → zoom" from "two-finger pan → pan."
- Whether `Cmd` should also be detected via `RawKeyboard` for environments where `HardwareKeyboard` lags. Default to `HardwareKeyboard`; revisit if smoke-test reveals lag.
