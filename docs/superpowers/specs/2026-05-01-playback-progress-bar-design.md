# Playback Progress Bar — Design

**Date:** 2026-05-01
**Status:** Approved (brainstorming phase)

## Overview

Add a horizontal playback progress bar above the existing playback controls in the editor, with chapter markers and tap/drag-to-seek interaction.

## Goals

- Visualize current playback position vs. total duration as a scrubbable bar
- Show a tick mark on the bar at every chapter start
- Tapping anywhere on the bar seeks to that position
- Tapping within 6px of a chapter tick snaps to that chapter's exact start
- Dragging the playhead seeks once on drag-end (not continuously)
- Works correctly when the surface is narrow (regression-safe against the layout class of bug fixed in 2dc4675)

## Non-goals

- Audio waveform rendering on the bar (separate feature, design 4 of this batch)
- Keyboard scrubbing (separate feature, design 3 of this batch)
- Showing chapter title on hover or in a tooltip
- Animations on seek (jump cuts are fine for an editor)
- Preview thumbnails or other media-player polish

## Architecture

A new stateful widget `ChapterScrubber` with a stateless-feeling external API. The widget owns no app state; it takes plain `Duration` and `List<Duration>` inputs and emits a single `onSeek` callback. Internal state holds only the in-progress drag position.

`PlaybackControls` wraps `ChapterScrubber` in a `StreamBuilder<Duration>` over the existing `PlaybackController.positionStream` and arranges it above today's row of play/pause + time + "Set start to playhead".

The scrubber knows nothing about Riverpod, `PlaybackController`, or the `Audiobook` model. This keeps it trivially testable in isolation and reusable for the future audio waveform feature.

## Widget contract

```dart
class ChapterScrubber extends StatefulWidget {
  const ChapterScrubber({
    super.key,
    required this.position,
    required this.totalDuration,
    required this.chapterStarts,
    required this.onSeek,
  });

  final Duration position;
  final Duration totalDuration;
  final List<Duration> chapterStarts;
  final ValueChanged<Duration> onSeek;
}
```

Position values outside `0..totalDuration` are clamped before rendering. Empty `chapterStarts` is valid (no ticks drawn).

## Behaviors

| Gesture | Effect |
|---|---|
| Tap on bar | `onSeek(positionForX)` |
| Tap within 6px of a chapter tick | `onSeek(chapterStarts[nearest])` |
| Drag start | Local drag-position state begins tracking the finger |
| Drag update | Playhead follows the finger; `onSeek` is **not** called |
| Drag end | `onSeek(finalDragPosition)` fires once |

Drag-update without firing `onSeek` is intentional — emitting on every pixel would seek the audio engine many times per second and produce audible artifacts.

## Visual layout

```
        chapter tick   chapter tick
        ▼              ▼
━━━━━●━━━━━━━━━━│━━━━━━━━│━━━━━━━━━━━━━━━━━━━━━━
     ↑
     playhead
```

| Element | Size | Color (Material 3) |
|---|---|---|
| Track | 4px high, rounded | `colorScheme.surfaceContainerHighest` |
| Filled portion (left of playhead) | same as track | `colorScheme.primary` |
| Chapter ticks | 12px tall (extending above + below track), 2px wide | `colorScheme.outline` |
| Playhead | 12px-diameter filled circle | `colorScheme.primary` |
| Hit area | 24px tall — track centered | (transparent) |
| Horizontal padding | 12px on each end | so the playhead at 0 or end isn't clipped |

The widget's vertical extent is 24px (the hit area). Horizontal extent is whatever its parent gives it.

## Integration

`lib/presentation/widgets/playback_controls.dart` changes from a single `Row` to a `Column` with two children:

1. `Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: StreamBuilder<Duration>(...))` — the scrubber row
2. The existing `Row` with play/pause, position text, and "Set start to playhead"

The `StreamBuilder` reads `controller.positionStream` (initial value: `controller.position`). Inside, it builds:

```dart
ChapterScrubber(
  position: snapshot.data ?? controller.position,
  totalDuration: book.totalDuration,
  chapterStarts: [for (final c in book.chapters) c.start],
  onSeek: controller.seek,
)
```

`PlaybackControls` already reads the editor state via `ref.watch(editorProvider)` to get the selected chapter index for "Set start to playhead"; it now also reads `audiobook` from the same state for `chapterStarts` and `totalDuration`. If `audiobook` is null, the scrubber row is omitted.

## Testing

### `test/presentation/chapter_scrubber_test.dart` (new)

Pump `ChapterScrubber` directly inside a sized box. No Riverpod needed.

1. **Tap at 25% of width seeks to ~25% of duration.** Pump at 400px width with `totalDuration = 100s`, no chapter starts. Tap at x=100 (25% of width minus padding). Expect `onSeek` called once with a value within ±2s of `25s` (tolerance for hit-area math).
2. **Tap near a chapter tick snaps to that chapter.** Pump with `chapterStarts = [0s, 30s, 60s]` and `totalDuration = 100s`. Compute the pixel x for `30s`. Tap at that x ± 5px. Expect `onSeek` called with exactly `30s`.
3. **Drag updates do not fire onSeek; drag end fires once.** Use `tester.startGesture` + `moveBy` + `up`. Expect `onSeek` called exactly once with the final position.
4. **Empty chapterStarts.** Tap dispatches a position, no exceptions.
5. **Position outside range is clamped.** Pump with `position = -10s` and `totalDuration = 100s`. Expect playhead drawn at x=0, no exceptions.
6. **Renders at 180px width without overflow.** Pump under `BoxConstraints(maxWidth: 180)`. Expect `tester.takeException()` is null.

### `test/presentation/playback_controls_test.dart` (extend)

Extend `_FakePlayback` to expose a `StreamController<Duration>` for `positionStream`. Add tests:

7. **Scrubber appears once an audiobook is loaded.** Find a `ChapterScrubber` widget; assert `findsOneWidget`.
8. **Scrubber's onSeek invokes controller.seek.** Tap the scrubber; verify the fake controller recorded a `seek` call.

The existing "Set start to playhead" test should continue to pass without changes.

## Files

- Create: `lib/presentation/widgets/chapter_scrubber.dart`
- Create: `test/presentation/chapter_scrubber_test.dart`
- Modify: `lib/presentation/widgets/playback_controls.dart`
- Modify: `test/presentation/playback_controls_test.dart`

## Open items for the implementation plan

- Exact pixel-snapping math (we'll specify it in the plan once the painter is laid out, but it's straightforward: `x = padding + (position / totalDuration) * (width - 2*padding)`).
