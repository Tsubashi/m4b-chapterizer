# Reorder Chapters by Start Time — Design

**Date:** 2026-05-01
**Status:** Approved (brainstorming phase)

## Overview

When the user changes a chapter's start time, the chapter list automatically re-sorts by start time so the chapters always render in chronological order. Out-of-bounds values are silently clamped; invariant violations (duplicates, first chapter not at zero) are surfaced as snackbars instead of crashes.

## Goals

- Editing a chapter's start time and breaking the monotonic order auto-reorders the list
- The selected chapter follows its move (tracked by identity, not index)
- Negative or beyond-duration values clamp silently to the nearest valid value
- Duplicate-start and first-must-be-zero violations show a user-facing snackbar and revert the field
- The `Audiobook` aggregate's invariants remain unchanged — this is a UI-layer concern

## Non-goals

- Drag-and-drop chapter reordering (separate UX, not in this spec)
- Editing end times directly (we don't expose them; end is derived from next start)
- Undo/redo of reorder operations
- Animations on row movement

## Behavior

| User input on chapter at index `i` | Result |
|---|---|
| New start preserves monotonic order | Update in place; selection unchanged. |
| New start breaks order but is otherwise valid | Sort the list; selection follows the moved chapter to its new index. |
| New start `< Duration.zero` | Silently clamp to `Duration.zero`. Then proceed through the rules above. |
| New start `>= totalDuration` | Silently clamp to `totalDuration - Duration(milliseconds: 1)`. Then proceed. |
| Result has two chapters with the same start | Reject. Field reverts to its original formatted value; snackbar: `"Chapter start times must be unique"`. |
| Result has no chapter at `Duration.zero` (e.g., user moved chapter 0) | Reject. Snackbar: `"First chapter must start at 00:00:00.000"`. |

The clamps run before the duplicate / first-not-zero checks, so a user who types `-5` on a chapter where chapter 0 is at zero will hit the duplicate path.

## Architecture

### Domain layer — unchanged

`Audiobook.validated()` and the `Chapter` model remain exactly as they are. The aggregate's invariant (chapters monotonically increasing, first at zero, last before total duration) is preserved. Reordering is a UI-layer reshape that always commits a valid `Audiobook` to state.

### `EditorNotifier.setChapterStart`

Replace the current implementation, which calls `Audiobook.validated(...)` and lets `ArgumentError` propagate. New semantics:

```dart
enum SetChapterStartError { duplicate, firstNotZero }

/// Returns null on success, or an error code for the UI to surface.
SetChapterStartError? setChapterStart(int index, Duration start) { ... }
```

Algorithm:

1. **Clamp** `start` into `[0, totalDuration - 1ms]`.
2. **Build candidate**: copy the chapter list, replace `chapters[index]` with `chapters[index].copyWith(start: clamped)`.
3. **Capture identity**: hold a reference to the *new* `Chapter` instance — this is what we'll find post-sort.
4. **Sort** the candidate list by `start`.
5. **Validate invariants in order**:
   - Two adjacent equal starts → return `SetChapterStartError.duplicate` (no state change).
   - First chapter's start `!= Duration.zero` → return `SetChapterStartError.firstNotZero` (no state change).
6. **Commit**: build a new `Audiobook` via `Audiobook.validated(...)` (will succeed by construction). Set `state` with the new audiobook and `isDirty: true`.
7. **Update selection** if the originally-edited chapter is no longer at `index`: find its new index (using `identical(...)`) and update `selectedChapterProvider`. Only update if the *moved* chapter was the selected one to avoid surprising the user.

### `ChapterList`'s row submit handler

`_ChapterRow` currently catches `FormatException` from `parseDuration` and silently swallows. Update its `onSubmitted` to also handle `setChapterStart`'s return value:

```dart
onSubmitted: (v) {
  Duration parsed;
  try {
    parsed = parseDuration(v);
  } on FormatException {
    // Restore the controller text from the current chapter; the parse failed.
    _startController.text = formatDuration(widget.chapter.start);
    return;
  }
  final error = widget.onStartChanged(parsed); // now returns SetChapterStartError?
  if (error != null) {
    _startController.text = formatDuration(widget.chapter.start);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text(_messageFor(error))));
  }
},
```

The widget's `onStartChanged` callback signature changes from `ValueChanged<Duration>` to `SetChapterStartError? Function(Duration)`. The callback is wired in `ChapterList` to `notifier.setChapterStart`.

## Tests

### `test/presentation/editor_state_test.dart` (extend)

1. **Auto-reorder on out-of-order start.** 3-chapter book at `[0, 10, 20]`s, total 30s. Call `setChapterStart(1, Duration(seconds: 25))`. Expect: returns `null`, the originally-named-"second" chapter is now at index 2, the chapter that was at index 2 is now at index 1, `selectedChapterProvider` (initially 1) is now 2.

2. **Negative clamp triggers duplicate path.** Same setup. `setChapterStart(1, Duration(seconds: -5))` → clamps to 0 → duplicate of chapter 0 → returns `SetChapterStartError.duplicate`, audiobook state unchanged.

3. **Beyond-total clamp.** Total 30s. `setChapterStart(1, Duration(seconds: 9999))` → clamps to `Duration(milliseconds: 29999)`. Verify the chapter's start equals exactly that value, returns `null`.

4. **Duplicate rejection.** Same 3-chapter book. `setChapterStart(1, Duration.zero)` → returns `SetChapterStartError.duplicate`. Audiobook reference unchanged (verify by `identical(stateBefore, stateAfter)`).

5. **First-not-zero rejection.** `setChapterStart(0, Duration(seconds: 5))` → returns `SetChapterStartError.firstNotZero`. Audiobook reference unchanged.

6. **Selection only follows the moved chapter.** 3-chapter book, selected index 0. Call `setChapterStart(1, Duration(seconds: 25))` (moves chapter 1 to last). Verify `selectedChapterProvider` stays at 0 (we didn't move *the selected* chapter).

### `test/presentation/chapter_list_test.dart` (extend)

7. **Snackbar appears on duplicate.** Open a book; on a chapter row, enter a duplicate start time and submit (`tester.enterText` + `await tester.testTextInput.receiveAction(TextInputAction.done)` or equivalent). Verify a `SnackBar` is shown containing the duplicate-message text and the start-time field's text reverts to the original formatted value.

8. **Reorder updates the rendered row order.** Open a 3-chapter book where chapter titles are distinct. Submit a start time on chapter 1 that reorders it past chapter 2. Pump and verify the rendered titles appear in the new order (use `find.byType(_ChapterRow)` ordering, or assert the title `TextField` controllers' values in the expected sequence).

## Files

- Modify: `lib/presentation/providers/editor_state.dart`
- Modify: `lib/presentation/widgets/chapter_list.dart`
- Modify: `test/presentation/editor_state_test.dart`
- Modify: `test/presentation/chapter_list_test.dart`

## Open items for the implementation plan

- Exact snackbar message strings (provided in the behavior table; the plan will inline them as constants).
- Whether to expose `SetChapterStartError` in the `lib/presentation/providers/` directory or co-locate with the notifier (decision: same file as `EditorNotifier`, since it's part of that contract).
