# Waveform Tile-Boundary Flicker Elimination — Design

**Date:** 2026-05-04
**Status:** Approved (brainstorming phase)
**Builds on:** `docs/superpowers/specs/2026-05-03-zoomable-waveform-refinements-design.md`

## Overview

Two complementary changes to `WaveformView` so the waveform doesn't visibly disappear when the viewport crosses into a new tile during playback:

1. **Prefetch the next tile while playing.** Watch `tileIndex + 1`'s family entry as a side effect during playback so its peaks are loaded before the boundary is crossed.
2. **Fall back to the last successfully loaded tile** while the current tile is loading. The painter consumes the last good tile's peaks if they cover any part of the visible viewport, so the wave keeps rendering instead of blanking.

Together these turn the typical tile-boundary transition from "loading flash + brief blank waveform" into a seamless flip; in the rare case extraction is slower than the viewport advance, the waveform's right edge thins out gradually instead of flickering.

## Goals

- During continuous follow at 1× speed, no visible loading state and no missing waveform when the viewport crosses a tile boundary.
- If extraction is slow enough that the next tile isn't ready by the boundary crossing, the painter keeps rendering from the previous tile's overlap region (the previous tile covers the full viewport for one viewport-duration past the boundary; only the right edge thins out as the playhead advances further).
- Zoom changes and big seeks (where the new tile's range doesn't usefully overlap any cached tile) keep showing the loading indicator. That's the "you asked for something new — wait a moment" state we want to preserve.
- File-open resets all caches.

## Non-goals

- Painting from the union of two tiles simultaneously to produce zero gap even at the right edge during slow extractions. Marginal benefit beyond the proposed fallback.
- Multi-resolution peak pyramids. Out of scope per the parent spec.
- Backwards prefetch (`tileIndex - 1`) for rewind. Continuous playback only ever advances forward; pan and seek are user-driven and we can't predict them.
- Prefetching during pause.

## Architecture

### Prefetch (next-tile keep-warm)

In `_WaveformViewState.build`, after computing the current `tileKey`, also compute `nextTileKey` (with `tileIndex + 1` and otherwise identical fields). When `controller.playing` is `true`, add a second `ref.watch(zoomedWaveformPeaksProvider(nextTileKey))`. The result is intentionally unused — the watch's side effect is enough to enter Riverpod's family cache, where it stays warm until needed.

When `controller.playing` is `false`, omit the prefetch watch. Pause-time pan and zoom are user-driven and the cost of speculatively loading neighbouring tiles isn't worth it.

If the next tile would be entirely past the file end, `computeTileBounds` already returns zero duration and the family resolves to an empty `WaveformTilePeaks` immediately — no ffmpeg invocation, no error path. No special-case needed.

### Last-good fallback

Add a single field to `_WaveformViewState`:

```dart
WaveformTilePeaks? _lastTile;
```

In `build`:

- After `final tileAsync = ref.watch(zoomedWaveformPeaksProvider(tileKey));`, if `tileAsync.hasValue` and the resolved tile has a non-zero `tileDuration`, copy it into `_lastTile`.
- Compute `effectiveTile = tileAsync.maybeWhen(data: (t) => t, orElse: () => _lastTile)` (with a final fallback to the existing empty `WaveformTilePeaks` if both are null).
- Pass `effectiveTile` to `_WaveformPainter`. The painter is unchanged — it already draws only pixels whose time falls inside the tile's range, so a tile that covers part but not all of the viewport just leaves the uncovered pixels blank.

In the existing `ref.listen<String?>(editorProvider.select((s) => s.path), ...)` handler, when the path changes set `_lastTile = null` (alongside the existing `viewport.reset(...)` call) so the previous file's data can't bleed into the new file's first frame.

**A note on cross-zoom fallback.** When the user zooms, the new tile key has a different `pixelsPerSecond`, so the new tile is loading. `_lastTile` was extracted at the previous zoom — its peaks are denser or sparser per second of audio. This is fine: the painter maps each pixel to a time, then to a bin index inside whichever tile it's drawing from. Sampling an old tile's peaks at the new zoom just produces visually-correct (lower- or higher-resolution) waveform until the new tile arrives. No stretching, no misaligned audio.

### Loading indicator visibility

The current rule (`if (tileAsync.isLoading) showLoadingOverlay`) becomes:

```dart
final overlaps = _lastTile != null && _tileOverlapsViewport(_lastTile!, viewport, width);
final showLoading = tileAsync.isLoading && !overlaps;
```

Where `_tileOverlapsViewport` is a pure helper that checks whether `[tile.tileStart, tile.tileStart + tile.tileDuration)` intersects `[viewport.windowStart, viewport.windowStart + windowDuration)`. When the previous tile covers any part of the viewport, the painter has something to draw and the loading overlay would be visual noise — hide it. When the previous tile is null (file just opened) or doesn't overlap (big seek or extreme zoom change), show the loading overlay so the user understands why the body is empty.

## Test plan

Extend `test/presentation/waveform_view_test.dart`. The existing `_pump` helper already overrides `zoomedWaveformPeaksProvider` family-wide with a single canned `WaveformTilePeaks` — extend it to support per-key behaviour for the prefetch and fallback tests.

1. **Painter falls back to last tile while current tile is loading and overlaps.** Pump with the canned tile resolved (so `_lastTile` populates), then transition the active key into a never-resolving future. Verify the loading text is *not* shown. (Painter coverage is implicit — `tester.takeException()` null and `find.byType(CustomPaint)` present.)
2. **Painter shows loading when current tile is loading and `_lastTile` is null.** Pump with the active key in the never-resolving state from the start. Verify "Generating waveform…" appears.
3. **Painter shows loading when `_lastTile` exists but doesn't overlap the current viewport.** Pump with a canned tile covering `[0, 4 s]`. Then pan the viewport to `windowStart = 50 s` (no overlap with `_lastTile`) and put the active key into a never-resolving state. Verify the loading indicator appears.
4. **`_lastTile` resets on path change.** Pump, let canned tile load, switch path to a second file whose tile is in never-resolving state. Verify the loading indicator appears (no bleed-through from the old file's tile).
5. **Prefetch: during playback, next tile's family key is queried.** Override `zoomedWaveformPeaksProvider` with a recording function that pushes every `WaveformTileKey` it sees onto a list. Pump with `controller.playing = true`. Verify the recording list contains both the current `tileIndex` and `tileIndex + 1`.
6. **No prefetch while paused.** Same recording override. Pump with `controller.playing = false`. Verify only the current `tileIndex` was queried.

Tests 5 and 6 verify the prefetch's wiring without trying to assert "the cache is warm" (Riverpod doesn't expose that cleanly). Counting queries is sufficient: a watch is the only way the family resolver runs for a given key, and that's exactly what populates the cache.

## Files

- Modify: `lib/presentation/widgets/waveform_view.dart` — add `_lastTile` field, prefetch watch, fallback / loading-gate logic, `_tileOverlapsViewport` helper.
- Modify: `test/presentation/waveform_view_test.dart` — extend `_pump` helper for per-key overrides; add 6 new tests.
