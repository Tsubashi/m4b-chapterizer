# Chapter-List Keyboard Navigation — Design

**Date:** 2026-05-03
**Status:** Approved (brainstorming phase)

## Overview

Two related changes to the keyboard model for the chapter list:

1. **Tab walks through chapter fields.** While focus is on a chapter title or start-time field, **Tab** advances through the sequence `(selected.title) → (selected.start) → (next.title) → (next.start) → …`, wrapping at the end. **Shift+Tab** moves the same sequence in reverse.
2. **Up / Down inside chapter fields jump rows.** While focus is on a chapter title or start-time field, **Arrow Up** and **Arrow Down** commit any pending edit and move focus to the corresponding field of the chapter above or below (in the **pre-commit** order — see "Reorder semantics" below). Up/Down inside metadata fields keeps the default text-cursor behavior. Up/Down with no field focused keeps today's chapter-selection behavior (move + seek).

## Goals

- Tab and Shift+Tab cycle through chapter title and start-time fields when focus is already on one of those fields, with wrap-around at the ends of the list.
- Up/Down inside chapter title or start-time fields commits the edit and jumps to the corresponding field of the row above or below.
- The chapter selected after the jump is determined by the **pre-commit** row index plus the delta — even if the commit reorders the list.
- Up/Down inside metadata fields (title, author, narrator, album, genre, description, year) does **not** affect the chapter list — the keys keep their built-in text-cursor behavior (e.g. line navigation in multi-line text fields).
- Up/Down with no field focused keeps the current behavior (move chapter selection + seek to chapter start).
- Tab from outside the chapter list (metadata field or no-focus state) follows standard Flutter focus traversal — it does **not** force entry into the chapter list.

## Non-goals

- Adding a "next field" affordance to metadata fields. Their tab order remains the default Flutter traversal.
- Supporting Tab cycling between cover panel, metadata, chapter list, and playback controls in any specific order. The cross-pane traversal is whatever Flutter's default produces.
- Auto-scrolling to the newly-focused row. The existing `chapterScrollRequestProvider` ensure-visible mechanism is bumped when selection changes, so it Just Works.

## Behavior tables

### Tab and Shift+Tab

Cycle position is `(chapterIndex, field)` where field ∈ {title, start}. Cycle order:

```
(0, title) → (0, start) → (1, title) → (1, start) → … → (N-1, start) → (0, title) → …
```

| Current focus | Tab → | Shift+Tab → |
|---|---|---|
| `(i, title)` | `(i, start)` | `(i-1, start)` (wraps to `(N-1, start)` when `i == 0`) |
| `(i, start)` | `(i+1, title)` (wraps to `(0, title)` when `i == N-1`) | `(i, title)` |
| Anywhere else (metadata, no focus, etc.) | Default Flutter traversal | Default Flutter traversal |

Selection follows the cycle: when Tab/Shift+Tab moves to another chapter, `selectedChapterProvider` is updated to that chapter. The playhead does **not** seek on Tab/Shift+Tab — Tab is for editing, not navigation. (This differs from Up/Down, which does seek; see below.)

### Up and Down

| Current focus | ArrowUp | ArrowDown |
|---|---|---|
| `(i, title)` with `i > 0` | Commit, move to `(i-1, title)`, update selection, seek | Commit, move to `(i+1, title)`, update selection, seek |
| `(i, start)` with `i > 0` | Commit, move to `(i-1, start)`, update selection, seek | Commit, move to `(i+1, start)`, update selection, seek |
| `(0, title)` or `(0, start)` + ArrowUp | No-op (don't commit, don't move) | — |
| `(N-1, title)` or `(N-1, start)` + ArrowDown | — | No-op (don't commit, don't move) |
| Metadata field | Default text-cursor behavior | Default text-cursor behavior |
| No field focused | Move selection + seek (existing behavior) | Move selection + seek (existing behavior) |

"Commit" depends on the field type:

- **Title field**: title text is committed continuously via `onChanged`, so the move just shifts focus. The focus listener's `endFieldEdit` closes the undo session for the prior title.
- **Start-time field**: parse the controller's text and call `EditorNotifier.setChapterStart(i, parsed)`. If the parse fails (`FormatException`) or `setChapterStart` returns a `SetChapterStartError`, **revert** the controller text to the chapter's current start and proceed with the focus move — same shape as today's `onSubmitted` revert. No SnackBar — the field flashing back to its old value communicates the failure, and Up/Down is a navigation gesture where blocking on a parse error would be surprising.

### Reorder semantics

"Pre-commit row index" means: when the user presses Up/Down (or Tab/Shift+Tab) while editing chapter `C` at index `i`, and the commit would reorder the list, the destination is determined from the **pre-commit** list, not the post-commit list.

Algorithm:

1. Read `preCommitIdx = selectedChapterProvider`.
2. Compute `targetIdx = preCommitIdx + delta` (delta = ±1 for Up/Down, +1/-1 for Tab/Shift+Tab tile boundaries).
3. Capture the **chapter object reference** at `book.chapters[targetIdx]`.
4. Commit the current edit. The commit may reorder the chapter list. The captured target reference is unaffected because `setChapterStart` only replaces the moved chapter's object via `copyWith`; sibling chapters keep their identity.
5. Read the new chapter list. Find the captured target via `indexWhere((c) => identical(c, target))` → `newIdx`.
6. Set `selectedChapterProvider = newIdx`.
7. Look up the focus node for the destination field (`chapterTitleFocusNodes[newIdx]` or `chapterStartFocusNodes[newIdx]`) and call `requestFocus()` on it.
8. (Up/Down only) seek the playhead to `newBook.chapters[newIdx].start`.

The lookup in step 7 uses the new index because chapter rows are keyed by index; their internal `FocusNode`s are owned by the row state at that index, not by the chapter object. After reorder, the `FocusNode` at index `newIdx` belongs to the row currently rendering the captured chapter — which is what we want.

## Architecture

### State

A new `chapterStartFocusNodesProvider` mirroring the existing `chapterTitleFocusNodesProvider`:

```dart
final chapterStartFocusNodesProvider =
    Provider<Map<int, FocusNode>>((ref) => <int, FocusNode>{});
```

Plus a new commit-callback registry that the shortcut action invokes to commit a start field's pending typed text:

```dart
final chapterStartCommitProvider =
    Provider<Map<int, void Function()>>((ref) => <int, void Function()>{});
```

Each `_ChapterRowState` registers the focus node and the commit callback in `initState` and unregisters in `dispose` — same pattern as the existing title focus node registry.

The commit callback for a row does:

```dart
void _commitStart() {
  final text = _startController.text;
  Duration parsed;
  try {
    parsed = parseDuration(text);
  } on FormatException {
    _startController.text = formatDuration(widget.chapter.start);
    return;
  }
  final error = widget.onStartChanged(parsed);
  if (error != null) {
    _startController.text = formatDuration(widget.chapter.start);
  }
}
```

(Same logic as today's `onSubmitted`, factored out so the shortcut and the Enter-key path share it.)

### Intents and shortcuts

One new intent in `lib/presentation/keyboard/shortcuts.dart`:

```dart
class ChapterFieldTabIntent extends Intent {
  const ChapterFieldTabIntent(this.delta);
  final int delta; // +1 for Tab, -1 for Shift+Tab
}
```

The Up/Down keys keep their existing `MoveChapterSelectionIntent`; the action gains additional branches for the chapter-field-focused and metadata-focused cases.

Bindings (added to `editorShortcuts()`):

```dart
const SingleActivator(LogicalKeyboardKey.tab):
    const ChapterFieldTabIntent(1),
const SingleActivator(LogicalKeyboardKey.tab, shift: true):
    const ChapterFieldTabIntent(-1),
```

Up/Down keep their existing bindings to `MoveChapterSelectionIntent`. The behavior split (chapter-field vs. metadata vs. no-focus) lives in the action.

### Actions

The two new actions go alongside the existing ones in `_EditorShortcutsState.build`'s `actions:` map.

`ChapterFieldTabIntent` action:

- If `primaryFocus` is **not** a chapter title or start node → return `null` and let the default Flutter focus traversal handle it. (Action returns nothing, but the trick is to *also* return `KeyEventResult.ignored` from the surrounding `Shortcuts`. We do this with the same `_BareKeyAction`-style pattern: an `isEnabled` override that returns `false` when not in a chapter field, plus a matching `consumesKey` override.)
- If in a chapter title or start node, compute `(currentIdx, currentField)`. Compute next position per the cycle table (with wrap). Capture target chapter reference. (No commit needed for tab from a title field, but if from a start field, invoke `chapterStartCommitProvider[currentIdx]?()`.) Update selection. `requestFocus` on the destination's node.

`MoveChapterSelectionIntent` action (modified):

- If `primaryFocus` is a chapter title or start node:
  - Compute `targetIdx = currentIdx + delta`. If out of bounds, no-op (return `null` without consuming the key further — or rather, do consume it so the field doesn't see the arrow).
  - Capture target chapter reference.
  - If current is start: invoke `chapterStartCommitProvider[currentIdx]?()`.
  - Look up target's new index. Update selection. `requestFocus` on the destination's corresponding-field node. Seek the playhead.
- Else if `primaryFocus` is some other `EditableText` (metadata field) → return ignored, default text behavior.
- Else (no field focused) → existing behavior: move selection + seek.

The "is chapter title/start node" check is a helper function:

```dart
({int index, _ChapterField field})? _focusedChapterField(WidgetRef ref) {
  final focused = FocusManager.instance.primaryFocus;
  if (focused == null) return null;
  final titles = ref.read(chapterTitleFocusNodesProvider);
  for (final entry in titles.entries) {
    if (entry.value == focused) return (index: entry.key, field: _ChapterField.title);
  }
  final starts = ref.read(chapterStartFocusNodesProvider);
  for (final entry in starts.entries) {
    if (entry.value == focused) return (index: entry.key, field: _ChapterField.start);
  }
  return null;
}

enum _ChapterField { title, start }
```

This lives in `shortcuts.dart` (private to that file).

### `_ChapterRow` changes

- Register `_startFocusNode` in `chapterStartFocusNodesProvider` from `initState`, unregister in `dispose`. Update on index change in `didUpdateWidget`. Same pattern as the existing title registration.
- Register a `_commitStart` callback in `chapterStartCommitProvider` similarly.
- Refactor the existing `onSubmitted` body into `_commitStart` so Enter and the shortcut both reach the same code path.

## Tests

### `test/presentation/keyboard_shortcuts_test.dart` (extend)

Add a new group `'Chapter-list keyboard navigation'`:

1. **Tab from selected chapter title focuses its start field.** Pump editor with 3 chapters, select chapter 1, focus its title node. Press Tab. Expect `chapterStartFocusNodes[1]` to be the primary focus.
2. **Tab from selected chapter start focuses next chapter's title.** Same setup but starting in chapter 1's start. Press Tab. Expect `chapterTitleFocusNodes[2]` to be focused. Expect `selectedChapterProvider` to be 2.
3. **Tab wraps from last chapter's start to first chapter's title.** Select last chapter, focus its start. Press Tab. Expect `chapterTitleFocusNodes[0]` focused; `selectedChapterProvider == 0`.
4. **Shift+Tab from chapter start goes to that chapter's title.** Select chapter 1, focus its start. Press Shift+Tab. Expect `chapterTitleFocusNodes[1]` focused.
5. **Shift+Tab wraps from first chapter's title to last chapter's start.** Select chapter 0, focus its title. Press Shift+Tab. Expect `chapterStartFocusNodes[N-1]` focused; selection == N-1.
6. **Tab in a metadata field follows default focus traversal** (i.e. the chapter-list cycle does not fire). Pump editor, focus the metadata title field. Press Tab. Expect `selectedChapterProvider` unchanged. (Don't assert what gets focused — that's Flutter's default and not our concern.)
7. **ArrowDown in a chapter title commits and focuses next chapter's title.** Select chapter 0, focus title, type "New Title". Press ArrowDown. Expect chapter 0 title in editor state == "New Title", `chapterTitleFocusNodes[1]` focused, `selectedChapterProvider == 1`, playback controller's last seek target == chapter 1's start.
8. **ArrowUp in a chapter start commits and focuses previous chapter's start.** Select chapter 1, focus start, no edit. Press ArrowUp. Expect `chapterStartFocusNodes[0]` focused, selection == 0.
9. **ArrowUp in chapter start with valid new time that reorders.** Four chapters: A=0, B=10s, C=30s, D=40s. Select C (idx 2), focus start, type "00:00:00.005" (which would put C just after A). Press ArrowUp. Pre-reorder target was B (index 1). Expect commit → reorder to [A, C, B, D]; B's new index is 2; selection == 2; `chapterStartFocusNodes[2]` focused. (This case exercises the post-reorder index lookup: target B was at 1 pre-commit but is at 2 post-commit because C moved into B's old slot.)
10. **ArrowUp at first chapter is no-op.** Select chapter 0, focus title. Press ArrowUp. Expect title still focused; selection unchanged; no seek.
11. **ArrowDown at last chapter is no-op.** Select last chapter, focus start. Press ArrowDown. Expect start still focused; selection unchanged.
12. **ArrowDown in a metadata field does not move chapter selection.** Focus metadata title field. Press ArrowDown. Expect `selectedChapterProvider` unchanged.
13. **ArrowDown in chapter start with unparseable text reverts and moves.** Select chapter 0, focus start, replace text with "garbage". Press ArrowDown. Expect chapter 0's start in editor state still == its original value; `chapterStartFocusNodes[1]` focused; selection == 1.
14. **ArrowDown with no field focused keeps existing behavior.** No focus on any field. Press ArrowDown. Expect selection moves down by 1 and playback seeks (regression coverage for the existing path).

### `test/presentation/chapter_list_test.dart` (extend)

15. **Pressing Enter in a chapter start field commits via the shared `_commitStart`.** Today's behavior, but the refactor should preserve it. (Existing tests likely already cover this; add an explicit one if not.)

## Files

- Modify: `lib/presentation/widgets/chapter_list.dart` — add `chapterStartFocusNodesProvider`, `chapterStartCommitProvider`, register/unregister in `_ChapterRowState`, factor `onSubmitted` body into `_commitStart`.
- Modify: `lib/presentation/keyboard/shortcuts.dart` — add `ChapterFieldTabIntent`, `ChapterFieldRowJumpIntent` (or extend `MoveChapterSelectionIntent`), bind Tab / Shift+Tab, add helper `_focusedChapterField`, modify the move/tab actions per the rules above.
- Modify: `test/presentation/keyboard_shortcuts_test.dart` — add the 14 new tests.
- Modify: `test/presentation/chapter_list_test.dart` — extend if needed.
