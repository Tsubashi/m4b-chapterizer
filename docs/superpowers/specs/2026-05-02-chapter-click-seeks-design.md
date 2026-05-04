# Chapter Navigation Seeks Playhead — Design

**Date:** 2026-05-02
**Status:** Approved (brainstorming phase)

## Overview

Three user actions navigate to a chapter today: clicking a row, pressing `↑`/`↓`, and editing a chapter's start time (which may also reorder). All three should additionally move the playback playhead so the user immediately hears the audio at the chosen position.

## Goals

- Clicking a chapter row seeks the playhead to that chapter's start.
- Pressing `↑` or `↓` to move chapter selection seeks the playhead to the new chapter's start.
- Editing a chapter's start time seeks the playhead to the new start (so the user can verify the audio at that location).
- Playback state (playing/paused) is unchanged by any of the three.
- A failed `setChapterStart` (duplicate, firstNotZero) does not seek.

## Non-goals

- Auto-playing on chapter click — only seek.
- A "preview" mode that plays a few seconds and pauses.
- Seeking when chapter selection changes for a reason other than the three listed (none currently exist; no opt-out is needed).

## Behavior

| Trigger | Seek target | Notes |
|---|---|---|
| `_ChapterRow.onTap` (click anywhere on the row, including the title and start fields) | `chapter.start` | Selection update unchanged |
| `MoveChapterSelectionIntent` (arrow keys) | `book.chapters[next].start` | Where `next` is the clamped target index |
| `EditorNotifier.setChapterStart` success | the clamped new `start` value the user just set | Fires only on success, never on `duplicate` or `firstNotZero` rejection |

Clicking a chapter that is already selected still triggers a seek — useful when the user has been editing and wants to jump back to "here".

## Architecture

Three one-line additions, each at the user-action callsite. No new abstractions. The seek logic stays at the callsite (rather than centralized in a listener) because the seek *target* differs between the navigation case (`chapters[idx].start`) and the edit case (the value the user just typed, post-clamp).

```dart
// _ChapterRow construction in ChapterList:
onTap: () {
  ref.read(selectedChapterProvider.notifier).state = i;
  ref.read(playbackControllerProvider).seek(chapter.start);
},

// MoveChapterSelectionIntent action body:
final next = (cur + intent.delta).clamp(0, book.chapters.length - 1);
ref.read(selectedChapterProvider.notifier).state = next;
ref.read(playbackControllerProvider).seek(book.chapters[next].start);

// EditorNotifier.setChapterStart, after the successful `state = ...` commit:
ref.read(playbackControllerProvider).seek(clamped);
```

`EditorNotifier` already has Riverpod `ref` available (it's a `Notifier`); it just gains an import for `playbackControllerProvider`.

## Tests

`test/presentation/chapter_list_test.dart` (extend):

1. **Tap on a chapter row seeks to that chapter's start.** Override `playbackControllerProvider` with a recording fake. Tap row 1 (start `00:00:10`). Assert `fake.seeks.last == const Duration(seconds: 10)`.

`test/presentation/keyboard_shortcuts_test.dart` (extend):

2. **`ArrowDown` seeks to the next chapter's start.** Selected = 0; chapter 1 starts at 10s. Send `arrowDown`. Assert `fake.seeks.last == const Duration(seconds: 10)`.
3. **`ArrowUp` from selection 0 does not move selection and does not seek.** Selected = 0; send `arrowUp`. Assert `selectedChapterProvider == 0` and `fake.seeks.isEmpty`. (No-op when the index doesn't change.)

`test/presentation/editor_state_test.dart` (extend):

4. **Successful `setChapterStart` seeks to the new start.** Override `playbackControllerProvider` with a recording fake. Call `setChapterStart(1, Duration(seconds: 25))` on a 3-chapter book. Assert `fake.seeks.last == const Duration(seconds: 25)`.
5. **Rejected `setChapterStart` does not seek.** Same setup; call `setChapterStart(1, Duration.zero)` (duplicate). Assert `fake.seeks.isEmpty`.

To make tests 4 and 5 work, the existing `editor_state_test.dart` test container needs to pass an override for `playbackControllerProvider`. Currently the file overrides only `bookbinderProvider`. The `playbackControllerProvider` is not read by the existing tests; with this change it will be, so the override must be added. The fake records `seek` calls and silently no-ops everything else.

## Files

- Modify: `lib/presentation/widgets/chapter_list.dart`
- Modify: `lib/presentation/keyboard/shortcuts.dart`
- Modify: `lib/presentation/providers/editor_state.dart`
- Modify: `test/presentation/chapter_list_test.dart`
- Modify: `test/presentation/keyboard_shortcuts_test.dart`
- Modify: `test/presentation/editor_state_test.dart`
