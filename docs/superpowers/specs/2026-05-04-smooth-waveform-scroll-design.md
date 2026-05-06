# Smooth Waveform Scroll During Playback — Design

**Date:** 2026-05-04
**Status:** Approved (brainstorming phase)
**Builds on:** `docs/superpowers/specs/2026-05-03-zoomable-waveform-design.md`

## Overview

`just_audio.positionStream` emits position updates at ~5 Hz (one every ~200 ms). The current `WaveformView` calls `followPlayhead(playhead)` once per emission, which advances `windowStart` in 200 ms-of-audio steps — visibly jumpy at 100 px/s ≈ 20 px per step.

Replace the once-per-stream-tick update with a frame-rate `Ticker` that **interpolates** between stream emissions. The position stream sets a baseline `(position, wallClock)`; every frame, the Ticker computes `interpolated = basePosition + (now − baseClock) × playbackSpeed` and feeds that to `followPlayhead` and to the painter's playhead line. Drift between extrapolation and reality is bounded to one stream interval (~200 ms), since each new position emission resets the baseline.

## Goals

- Waveform scrolls at the display's refresh rate during playback (no visible 20 px jumps).
- The on-screen playhead line, drawn from the same interpolated value, stays smooth too.
- Pause: no extrapolation; the playhead stops where the player reports it.
- Seek (any source): the next position emission resets the baseline; visual jumps to the new position immediately.
- The Ticker only runs while playing; when paused there's no per-frame work.
- Designed so when playback-speed UI lands later, smoothing automatically picks up the new rate (single source for `playbackSpeed`, with a TODO marker for speed-change baseline-reset).

## Non-goals

- Adding a playback-speed UI or wiring `setSpeed` to a control. Out of scope; this spec only prepares the seam.
- Subscribing to speed-change events to reset the baseline. When configurable speed lands, drift after a rate change is bounded to one stream interval; that's acceptable for v1 and tightening it is a follow-up.
- Smoothing waveform peaks themselves (cross-fading between tiles, etc.). The flicker-elimination spec already handles tile transitions; this is purely about scroll motion.

## Architecture

### State on `_WaveformViewState`

```dart
late final Ticker _ticker;

Duration _basePosition = Duration.zero;
Duration _baseTickerElapsed = Duration.zero;
Duration _lastTickerElapsed = Duration.zero;

Duration _smoothedPlayhead = Duration.zero;
```

The reference clock is the `Ticker`'s own `elapsed` argument, captured into `_lastTickerElapsed` on every callback. `_basePosition` is the most recent position reported by the stream; `_baseTickerElapsed` is the value of `_lastTickerElapsed` at that moment. Driving extrapolation from `Ticker.elapsed` rather than a `Stopwatch` makes the behavior fully observable in `flutter test` — `tester.pump(Duration)` advances Flutter's scheduler clock, which is what feeds the Ticker callback. `_smoothedPlayhead` is what the painter consumes — set directly from stream updates while paused, set every frame from extrapolation while playing.

### Lifecycle

In `initState`:

- Capture initial baseline: `_basePosition = controller.position; _baseTickerElapsed = Duration.zero; _lastTickerElapsed = Duration.zero;`.
- Set `_smoothedPlayhead = controller.position`.
- Subscribe to `positionStream` (existing) and `playingStream` (existing — already added by the flicker-elimination work).
- Create `Ticker` via `createTicker(_onTick)` (requires adding `SingleTickerProviderStateMixin` to the State class).
- If `controller.playing` is true at mount, start the ticker.

In `dispose`:

- `_ticker.dispose()` in addition to the existing subscription cancellations.

### Position-stream listener (`_onPosition`)

Replace the current body. The stream listener now has two jobs:

1. **Always**: reset baseline. `_basePosition = position; _baseTickerElapsed = _lastTickerElapsed;`.
2. **Only while paused**: update `_smoothedPlayhead = position` and run the existing ensure-visible logic. While playing, the Ticker is responsible for the smoothed value and the `followPlayhead` call — the stream listener doesn't touch them, so the next Ticker tick picks up the new baseline.

### Play/pause listener (`_onPlayingChange`)

Existing listener already does `setState(() => _isPlaying = playing)`. Add: when transitioning, **resync the baseline** (read `controller.position` again — the stream may have lagged). Then start or stop the Ticker.

```dart
void _onPlayingChange(bool playing) {
  if (!mounted || _isPlaying == playing) return;
  final controller = ref.read(playbackControllerProvider);
  _basePosition = controller.position;
  _baseTickerElapsed = _lastTickerElapsed;
  setState(() {
    _isPlaying = playing;
    _smoothedPlayhead = _basePosition;
  });
  if (playing) {
    _ticker.start();
  } else {
    _ticker.stop();
  }
}
```

### Ticker callback (`_onTick`)

```dart
void _onTick(Duration tickerElapsed) {
  if (!mounted) return;
  _lastTickerElapsed = tickerElapsed;
  final delta = tickerElapsed - _baseTickerElapsed;
  final speedScaled = Duration(
    microseconds: (delta.inMicroseconds * _currentPlaybackSpeed()).round(),
  );
  final interpolated = _basePosition + speedScaled;
  // Clamp to [0, totalDuration].
  final clampedMicros = interpolated.inMicroseconds.clamp(
    0,
    _latestTotalDuration.inMicroseconds,
  );
  final clamped = Duration(microseconds: clampedMicros);

  if (_latestTotalDuration <= Duration.zero || _latestViewportWidth <= 0) {
    setState(() => _smoothedPlayhead = clamped);
    return;
  }

  ref.read(waveformViewportProvider.notifier).followPlayhead(
        clamped,
        _latestTotalDuration,
        _latestViewportWidth,
      );
  setState(() => _smoothedPlayhead = clamped);
}
```

`_lastTickerElapsed` is updated on every tick so that the position-stream listener and the play/pause listener can capture it as the new baseline. `setState` is the rebuild driver. `followPlayhead` will also trigger a Riverpod rebuild whenever it actually changes `windowStart`; Flutter coalesces the two within one frame.

### Playback-speed seam

```dart
/// Multiplier applied to wall-clock delta when extrapolating the
/// playhead between position-stream emissions. Today the player runs
/// at fixed 1.0×; when a rate UI lands, replace this with a read from
/// `PlaybackController.speed` (and consider subscribing to a
/// `speedStream` to reset the baseline on rate changes — without that,
/// drift after a rate change is bounded to one stream interval).
double _currentPlaybackSpeed() => 1.0;
```

A single private getter is the entire "future-proofing surface". When `PlaybackController` grows a `speed` field, this becomes `ref.read(playbackControllerProvider).speed`. No call sites change.

### Painter input

The build's existing `StreamBuilder<Duration>` around the painter goes away. The painter receives `playhead: _smoothedPlayhead` directly from the State field. The build runs whenever `setState` fires (Ticker callback) or whenever the viewport notifier changes (Riverpod), which is exactly when something visible to the painter has changed.

## Tests

Tests assert via the **publicly observable side effect** of extrapolation: changes to `windowStart` in `waveformViewportProvider`. Every Ticker callback that does extrapolation also calls `followPlayhead`, which moves `windowStart`. Reading `container.read(waveformViewportProvider).windowStart` after pumping a frame is enough to verify the smoothing is working — no need to reach into the private painter or State internals.

`tester.pump(Duration)` advances Flutter's scheduler clock, which is what the Ticker reads from. So a single `pump(500ms)` simulates 500 ms of wall time and triggers the appropriate ticker callbacks.

Extend `test/presentation/waveform_view_test.dart`:

1. **Position-stream emission while paused doesn't move an in-window viewport.** Pump in default paused state (windowStart = 0, viewport `[0, 8 s]`). `playback.emitPosition(const Duration(seconds: 5))`. `await tester.pump()`. Verify `windowStart` is still `Duration.zero`. (Regression for the existing ensure-visible logic, now sharing `_onPosition` with the smoothing path.)

2. **Position-stream emission while paused, outside the window, re-anchors immediately.** Pump paused. `emitPosition(const Duration(seconds: 30))`. `pump()`. Verify `windowStart ≈ 28 s` (followPlayhead at 25 % of 8 s window). (Same as an existing test, kept as regression after the listener restructure.)

3. **`windowStart` advances continuously while playing.** Pump. `playback.emitPosition(const Duration(seconds: 5))`. `playback.emitPlaying(true)`. `await tester.pump(const Duration(milliseconds: 500))`. Expect `windowStart` to be approximately `5 s + 500 ms − 25% × 8 s = 3500 ms`. Tolerance: ± 50 ms (allowing for whatever the Ticker schedules within the pump).

4. **Pausing stops extrapolation.** Pump. `emitPosition(5 s)`, `emitPlaying(true)`, `pump(100 ms)` (windowStart advances). Capture the current `windowStart`. `emitPlaying(false)`, then `pump(500 ms)`. Verify `windowStart` is unchanged from the captured value.

5. **Seek mid-playback resets baseline.** Pump. `emitPosition(0)`, `emitPlaying(true)`, `pump(100 ms)`. Then `emitPosition(30 s)` (simulates a seek). `pump()`. Verify `windowStart ≈ 28 s` — the new baseline, not the extrapolated continuation of the old one.

6. **Resuming play after pause resyncs baseline to controller.position.** Pump. `emitPosition(5 s)`, `emitPlaying(true)`, `pump(200 ms)` (windowStart now ≈ 3.2 s). `emitPlaying(false)` (pauses). Without emitting a new position, `emitPlaying(true)` again. `pump(100 ms)`. Verify the new `windowStart` is approximately `controller.position + 100 ms − 2 s` — i.e., the play-resume reads `controller.position` (which is whatever the fake's `_pos` is at that moment) rather than continuing from the pre-pause extrapolated value.

The existing `_FakePlayback` in `waveform_view_test.dart` exposes `emitPosition` and `emitPlaying` and tracks `_pos` so `controller.position` returns the latest emitted value. No fake-fake-clock plumbing required.

## Smoke test (after merge)

`flutter run -d macos`. Open an `.m4b`. Press play. The waveform should now scroll continuously rather than in 20-px jumps; the playhead line should stay pinned at 25% from the left and not jitter. Pause; the waveform should freeze where it is. Click the thin overview scrubber to seek; the zoomed view should re-anchor immediately. Resume play; smooth scrolling continues from the new position.

## Files

- Modify: `lib/presentation/widgets/waveform_view.dart` — add `Ticker`, `Stopwatch`, baseline state, `_onTick`, `_currentPlaybackSpeed`, `SingleTickerProviderStateMixin`. Restructure `_onPosition` and `_onPlayingChange` per above. Drop the StreamBuilder<Duration> around the painter; pass `_smoothedPlayhead` directly.
- Modify: `test/presentation/waveform_view_test.dart` — add 6 new tests using the viewport-change-side-effect approach (cleanest assertion path).
