# Zoomable Waveform — Refinements Design

**Date:** 2026-05-03
**Status:** Approved (brainstorming phase)
**Builds on:** `docs/superpowers/specs/2026-05-03-zoomable-waveform-design.md`

## Overview

Three refinements driven by smoke-test feedback on the original zoomable-waveform implementation:

1. **Loading state UI** in the `WaveformView` body so the user knows why the waveform is empty.
2. **Tile-based windowed extraction** so the waveform stays visually useful at high zoom (where the existing whole-file 4096-peak extract collapses to ~1 peak across the visible window).
3. **Ensure-visible on seek while paused** so clicking the thin overview scrubber doesn't leave the playhead off-screen in the zoomed view.

The existing whole-file `waveformPeaksProvider` stays as-is; the thin `ChapterScrubber` keeps using it. The new tile-based provider is layered on top for the zoomed view only.

## Goals

- A centered loading state ("Generating waveform…" with a small `CircularProgressIndicator`) renders inside the empty `WaveformView` whenever the active tile is loading.
- Waveform resolution at any zoom is roughly one peak per pixel of viewport width.
- Continuous follow during playback does **not** trigger a loading flash on every frame — tiles are quantized to coarse boundaries so a re-extract happens only when the viewport advances by a full tile-stride.
- A seek that puts the playhead outside the current viewport (e.g. clicking the thin scrubber while paused) re-anchors the zoomed view so the playhead is visible.
- A drag-pan while paused stays put as long as the playhead doesn't change.

## Non-goals

- A multi-resolution peak pyramid or pre-fetched neighboring tiles. The single-tile cache via Riverpod's family is enough; revisited tiles are still hit because Riverpod auto-caches.
- Improvement of the thin `ChapterScrubber`'s waveform — it stays at the existing whole-file 4096-peak resolution (already visually adequate at 800 px showing the entire file).
- Fading or animated transitions between loaded tiles. The painter draws whatever peaks the active tile has; transitions are instant.
- Using `extractRange` for the *whole-file* `waveformPeaksProvider`. That provider keeps the existing whole-file `extract()` call.

## Refinement 1: Loading state

`WaveformView` shows a centered loading indicator when the active tile's `AsyncValue` is in the loading state. The indicator is:

- A `CircularProgressIndicator` (small — `SizedBox(width: 24, height: 24)`).
- Below it, the text `Generating waveform…` in the `colorScheme.onSurfaceVariant` color, body-medium style.
- Centered both axes inside the 120-px-tall waveform body.
- The chapter ticks and playhead line still render on top of the loading indicator (so the user keeps the time reference even while peaks come in).
- `peaks` (the painter input) is `[]` while loading — same as today's empty-peak path, which already paints just the ticks and playhead.

The error and data-with-empty-list states render the same way as today (no waveform bars, no loading indicator). Only the *loading* `AsyncValue` triggers the new indicator.

## Refinement 2: Tile-based windowed extraction

### Tile geometry

A tile is a contiguous time range that comfortably contains the viewport. Family key:

```dart
@immutable
class WaveformTileKey {
  const WaveformTileKey({
    required this.path,
    required this.tileIndex,
    required this.viewportDurationMicros,
    required this.pixelsPerSecond,
  });
  // operator==, hashCode
}
```

- `viewportDurationMicros` = `viewportWidthPx / pixelsPerSecond * 1e6`, computed by the widget at the current frame.
- `tileIndex = floor(windowStart.inMicroseconds / viewportDurationMicros)`.
- The tile **covers** `[tileIndex * viewportDurationMicros - viewportDurationMicros, tileIndex * viewportDurationMicros + 2 * viewportDurationMicros]` — i.e. one viewport-width of margin before and after the aligned start, total 3 × viewport.
- The provider clamps that range to `[0, totalDuration]` before invoking ffmpeg.
- `targetPeaks = ceil(actualTileDurationSeconds * pixelsPerSecond)` — one peak per pixel at the current zoom.

The 3 × viewport tile size means the visible viewport is always ⊃ inside the tile's interior by one viewport-width on each side. Continuous follow at 1× speed advances `windowStart` by `viewportDurationSeconds` of audio per `viewportDurationSeconds` of wall-clock time, so a new tile is fetched **roughly once per `viewportDurationSeconds` of follow** — at default zoom (8-second viewport), a new tile every 8 s. Riverpod's family auto-cache means once a tile has been visited it's instant on revisit.

### `WaveformExtractor.extractRange`

New method on `WaveformExtractor` that wraps ffmpeg with `-ss` and `-t`:

```dart
/// Like [extract], but only for the half-open audio window
/// [start, start + duration). Uses ffmpeg's `-ss` (input seek) and
/// `-t` (duration) flags. Returns [targetPeaks] bins.
Future<List<double>> extractRange({
  required String path,
  required Duration start,
  required Duration duration,
  required int targetPeaks,
}) async { ... }
```

ffmpeg invocation:

```
<ffmpeg> -loglevel error -ss <start_seconds> -i <path> -t <duration_seconds> -map 0:a -f s16le -ac 1 -ar 8000 -
```

`-ss` is placed *before* `-i` for fast seek (uses the container index; sub-millisecond accuracy is not needed since we're just binning amplitudes). `-t` after `-i` limits the output duration.

The binning loop is identical to the existing `extract()`; the only difference is computing `samplesPerBin` from `duration` (not `totalDuration`). Refactor to share the binning loop in a private helper:

```dart
Future<List<double>> _binStream({
  required Stream<List<int>> stdout,
  required int totalSamples,
  required int targetPeaks,
}) async { /* shared loop */ }
```

`extract()` calls `_binStream` with `totalSamples = totalDurationSeconds * 8000`; `extractRange` calls it with `totalSamples = durationSeconds * 8000`.

### `zoomedWaveformPeaksProvider`

New `FutureProvider.family` keyed on `WaveformTileKey`:

```dart
class WaveformTilePeaks {
  const WaveformTilePeaks({
    required this.tileStart,
    required this.tileDuration,
    required this.peaks,
  });
  final Duration tileStart;
  final Duration tileDuration;
  final List<double> peaks;
}

final zoomedWaveformPeaksProvider =
    FutureProvider.family<WaveformTilePeaks, WaveformTileKey>(
  (ref, key) async {
    final book = ref.read(editorProvider).audiobook;
    if (book == null) {
      return const WaveformTilePeaks(
        tileStart: Duration.zero,
        tileDuration: Duration.zero,
        peaks: [],
      );
    }
    final viewportDuration =
        Duration(microseconds: key.viewportDurationMicros);
    final unclampedStart = Duration(
      microseconds: key.tileIndex * key.viewportDurationMicros -
          key.viewportDurationMicros,
    );
    final tileStart =
        unclampedStart < Duration.zero ? Duration.zero : unclampedStart;
    final unclampedEnd = unclampedStart + viewportDuration * 3;
    final tileEnd =
        unclampedEnd > book.totalDuration ? book.totalDuration : unclampedEnd;
    final tileDuration = tileEnd - tileStart;
    if (tileDuration <= Duration.zero) {
      return WaveformTilePeaks(
        tileStart: tileStart,
        tileDuration: Duration.zero,
        peaks: const [],
      );
    }
    final targetPeaks = (tileDuration.inMicroseconds /
            Duration.microsecondsPerSecond *
            key.pixelsPerSecond)
        .ceil()
        .clamp(1, 1 << 30);
    // Production: a new extractor per tile so concurrent tiles don't
    // share cancel state. Tests override this provider with canned
    // values.
    final extractor = WaveformExtractor(
      binaries: ref.read(binaryResolverProvider),
      processStarter: Process.start,
    );
    ref.onDispose(extractor.cancel);
    final peaks = await extractor.extractRange(
      path: key.path,
      start: tileStart,
      duration: tileDuration,
      targetPeaks: targetPeaks,
    );
    return WaveformTilePeaks(
      tileStart: tileStart,
      tileDuration: tileDuration,
      peaks: peaks,
    );
  },
);
```

The construction of `WaveformExtractor` and `Process.start` is `coverage:ignore`-marked (production-only wiring); tests override the family with `overrideWith` and inspect / inject canned `WaveformTilePeaks`.

### `WaveformView` integration

- Compute `WaveformTileKey` from the current viewport and viewport width.
- Watch `zoomedWaveformPeaksProvider(key)`. The result is `AsyncValue<WaveformTilePeaks>`.
- Pass `WaveformTilePeaks` to `_WaveformPainter` (replacing the current `peaks` argument).
- The painter's `_paintWaveform` is updated to map pixel `x` → time `t` (already does), then map `t` → bin index inside the tile's peaks: `binIndex = floor((t - tileStart).inMicroseconds / tileDuration.inMicroseconds * peaks.length)`. Pixels mapped to times outside `[tileStart, tileStart + tileDuration]` simply skip drawing — the painter renders only the slice of the tile that's currently visible.
- The whole-file `waveformPeaksProvider` is **no longer read by `WaveformView`**. The thin `ChapterScrubber` continues to read it via `PlaybackControls`.

### Loading-state interaction

- `peaksAsync.isLoading` → render the loading indicator over an empty waveform body.
- `peaksAsync.hasValue` → render `_paintWaveform` with the tile's peaks.
- `peaksAsync.hasError` → render no waveform bars, no loading indicator (same as today's error path on the whole-file provider).

## Refinement 3: Ensure-visible on seek while paused

The existing position-stream listener is:

```dart
void _onPosition(Duration playhead) {
  final controller = ref.read(playbackControllerProvider);
  if (!controller.playing) return;
  // ... followPlayhead ...
}
```

Replace with:

```dart
void _onPosition(Duration playhead) {
  if (_latestTotalDuration <= Duration.zero || _latestViewportWidth <= 0) {
    return;
  }
  final controller = ref.read(playbackControllerProvider);
  final notifier = ref.read(waveformViewportProvider.notifier);

  if (controller.playing) {
    notifier.followPlayhead(
      playhead, _latestTotalDuration, _latestViewportWidth,
    );
    return;
  }
  // Paused: ensure visible only.
  final viewport = ref.read(waveformViewportProvider);
  final windowMicros = (_latestViewportWidth / viewport.pixelsPerSecond * 1e6).round();
  final windowEnd = viewport.windowStart + Duration(microseconds: windowMicros);
  if (playhead < viewport.windowStart || playhead > windowEnd) {
    notifier.followPlayhead(
      playhead, _latestTotalDuration, _latestViewportWidth,
    );
  }
}
```

Behavior:

- **Playing**: continuous follow at 25 % from the left (unchanged).
- **Paused, playhead inside viewport**: do nothing — preserves the user's manual pan / zoom position.
- **Paused, playhead outside viewport**: re-anchor via `followPlayhead` so the new position lands at 25 % from the left.

## Tests

### `test/data/waveform_extractor_test.dart` (extend)

Existing tests for `extract()` stay. Add tests for `extractRange()`:

1. **`extractRange` invokes ffmpeg with `-ss` and `-t` flags in the correct positions.** Use a fake `processStarter` that records the args list and emits empty stdout. Call `extractRange(path: '/x', start: 10s, duration: 30s, targetPeaks: 100)`. Assert the args list contains `'-ss', '10.0', '-i', '/x'` followed by `'-t', '30.0'` (and the rest of the existing flags).
2. **`extractRange` bins synthetic PCM correctly.** Use the existing fake-processStarter helper (whatever the existing tests use). Inject 240,000 samples of `0x4000` (full half-amplitude) with `processStarter` returning that as stdout. Call `extractRange(path: '/x', start: 0s, duration: 30s, targetPeaks: 10)`. Expected `samplesPerBin = 240000 / 10 = 24000`. Assert 10 peaks of `0.5 ± 0.001`.
3. **`extractRange` cancellation.** Same as the existing `extract` cancellation test, but for `extractRange`.

### `test/presentation/providers/waveform_viewport_test.dart` (no changes)

Tile-key arithmetic doesn't live on the viewport notifier; it lives in `WaveformView`'s build path. Existing 11 viewport tests stay.

### `test/presentation/providers/zoomed_waveform_peaks_test.dart` (new)

Pure-logic tests for the family provider's tile-bound clamping. The family closure is testable by overriding `binaryResolverProvider` and providing a fake extractor in production-style wiring — but simpler is to **factor the tile-bound math into a free function** `computeTileBounds(book, key)` and unit-test that:

```dart
class TileBounds {
  const TileBounds({required this.start, required this.duration, required this.targetPeaks});
  final Duration start;
  final Duration duration;
  final int targetPeaks;
}

TileBounds computeTileBounds(Audiobook book, WaveformTileKey key);
```

4. **Tile in the middle of the file.** book = 60 s, key = (path, tileIndex=2, viewportDurationMicros=8e6, pxPerSec=100). Expected: `start = 1 * 8e6 = 8 s`, `duration = 24 s`, `targetPeaks = 24 * 100 = 2400`.
5. **Tile clamped at the file start.** key.tileIndex = 0. Unclamped start = `-8 s`; clamped to 0 s. Duration = `2 * 8 s = 16 s` (one viewport short on the left). targetPeaks = 1600.
6. **Tile clamped at the file end.** book = 30 s, key.tileIndex = 2 (so unclamped start = 8 s, unclamped end = 32 s). Clamped: start = 8 s, end = 30 s, duration = 22 s, targetPeaks = 2200.
7. **Tile entirely past file end produces empty.** book = 5 s, key.tileIndex = 10. Unclamped start = 72 s, beyond 5 s. Result: start clamped to 5 s, duration = 0, targetPeaks = 0 (or 1 — ceil(0 * 100) = 0; clamp to ≥1 in the production code; the math function returns 0 and the production wrapper clamps).

### `test/presentation/waveform_view_test.dart` (extend)

Existing 10 tests need updates because the family they need to override changes. Replace the override of `waveformPeaksProvider('/tmp/x.m4b')` with overrides of `zoomedWaveformPeaksProvider(key)` for the keys the tests will produce. The test harness can compute the expected key from the default viewport (default state: tileIndex 0, viewportDurationMicros = 8_000_000, pxPerSec = 100) and override that one key.

For tests that change zoom or pan, override the new keys too — or, simpler, **override the provider as a family with a single `(ref, key) async => fakePeaks`** so any key returns the canned data.

New tests:

8. **Loading state shows when tile is loading.** Override `zoomedWaveformPeaksProvider` to return a never-completing future. Pump. Find the loading text "Generating waveform…" and one `CircularProgressIndicator` inside the `WaveformView`.
9. **Loading state hidden when tile resolves.** Same setup but resolve the future. Find no loading text, no `CircularProgressIndicator`.
10. **Seek-to-outside-viewport while paused re-anchors.** Default state (paused, viewport [0, 8 s] at 100 px/s). Emit a position update of 30 s. Verify `windowStart` advances so the playhead is visible (followPlayhead at 25 % → 28 s).
11. **Seek-to-inside-viewport while paused does NOT move viewport.** Default state. Emit a position update of 4 s (inside viewport). `windowStart` stays at 0.
12. **Drag-pan + seek-inside-pan-region while paused does NOT move viewport.** Pan to make `windowStart = 30 s`. Emit a position update of 32 s (inside the panned viewport [30 s, 38 s]). `windowStart` stays at 30 s.

### `test/presentation/playback_controls_test.dart` (no functional changes)

The existing layout-order test continues to pass. The fact that `WaveformView` now reads a different family doesn't affect the test, which only checks vertical positions.

## Files

- Create: `lib/presentation/providers/zoomed_waveform_peaks.dart` — `WaveformTileKey`, `WaveformTilePeaks`, `computeTileBounds`, `zoomedWaveformPeaksProvider`.
- Create: `test/presentation/providers/zoomed_waveform_peaks_test.dart` — `computeTileBounds` tests (4 cases).
- Modify: `lib/data/waveform_extractor.dart` — add `extractRange`; refactor binning loop into `_binStream`.
- Modify: `test/data/waveform_extractor_test.dart` — add `extractRange` tests (3 cases).
- Modify: `lib/presentation/widgets/waveform_view.dart` — switch to tile-based provider; loading indicator; ensure-visible logic.
- Modify: `test/presentation/waveform_view_test.dart` — update existing 10 tests' override; add 5 new tests (loading-shown, loading-hidden, seek-outside, seek-inside, drag-then-seek-inside).

## Smoke-test plan (to walk after merge)

1. Open an `.m4b`. Loading indicator briefly appears in the waveform body, then peaks fill in.
2. Default zoom is now visually informative (peaks show roughly one bar per pixel of viewport width).
3. Press play. Waveform follows continuously. No loading flash on every tick — only a brief flash roughly every viewport-duration of follow when crossing into a new tile.
4. Pause. Pan the waveform — no flash; the cached tile covers the pan range until you exceed it, then a brief flash for the new tile.
5. Zoom in (Cmd+scroll). Waveform re-extracts at higher resolution (one flash, then sharp peaks).
6. Click on the thin overview scrubber to a time outside the zoomed view. The zoomed view jumps so the new playhead is at 25 % from the left.
7. Pause, drag-pan to a different region, then click the overview scrubber to a time *inside* the panned viewport. The zoomed view does NOT jump.
