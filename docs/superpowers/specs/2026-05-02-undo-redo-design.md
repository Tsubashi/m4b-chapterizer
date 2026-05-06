# Undo / Redo — Design

**Date:** 2026-05-02
**Status:** Approved (brainstorming phase)

## Overview

Add `Cmd+Z` (undo) and `Cmd+Shift+Z` (redo) for editor mutations. Continuous edits within a single text field count as one undo step. While a text field is focused with an in-progress edit, `Cmd+Z` cancels the edit (reverts and defocuses) instead of popping the undo stack.

## Goals

- Recover from accidental chapter delete (`⌫`) and other discrete mutations with `Cmd+Z`.
- Editing a text field collapses to a single undo step regardless of typing speed.
- `Cmd+Z` while typing in a field reverts the in-flight edit and defocuses, so the user can quickly abandon mistakes without polluting the undo stack.
- Redo via `Cmd+Shift+Z` reverses the last undo, until any new mutation clears the redo stack.
- Opening a different file clears undo/redo history; saving leaves it intact.

## Non-goals

- Persisting undo history across app restarts.
- A linear "edit history" panel or visual representation of the stack.
- Bounded stack size (unbounded for MVP — `Audiobook` is small and shared `Uint8List` cover bytes don't multiply across snapshots that don't change the cover).
- Toolbar buttons for undo/redo. Keyboard shortcuts only for MVP.
- An "edit menu" entry. Out of scope.

## Conceptual model

Two kinds of state-changing mutations:

| Kind | Behavior | Examples |
|---|---|---|
| **Discrete** | Atomic, push to undo stack on every call | `addChapter`, `deleteChapter`, `setChapterStart`, `replaceCover`, `clearCover` |
| **Continuous** | Update state directly; never push themselves. A single push happens when the surrounding **field-edit session** ends | `setTitle`, `setAuthor`, `setNarrator`, `setAlbum`, `setGenre`, `setDescription`, `setYear`, `renameChapter` |

A **field-edit session** is the period between a text field gaining focus and losing focus. The `Audiobook` snapshot taken at focus-gained is what gets pushed to the undo stack at focus-lost — but only if the audiobook actually changed during the session.

If a discrete op fires while a field-edit session is active (e.g., user is typing in the title field, then clicks "+ Add"), the discrete op closes the session first (pushes the session's snapshot if changed), then performs and pushes its own step.

## Behavior table

| Context | `Cmd+Z` | `Cmd+Shift+Z` |
|---|---|---|
| A text field has focus, edit in progress (state changed since focus-gained) | `cancelFieldEdit()` — revert to focus-gained snapshot, defocus the field. Undo stack unchanged. | No-op. |
| A text field has focus, no change yet | `cancelFieldEdit()` — defocus. Stack unchanged (no-op since snapshot already equals current). | No-op. |
| No text field focused (or no in-progress session) | `undo()` — pop `undoStack`, push current state onto `redoStack`. | `redo()` — pop `redoStack`, push current state onto `undoStack`. |
| Stack empty | No-op. | No-op. |

## Architecture

### `EditorState` additions

```dart
class EditorState {
  // existing: audiobook, path, isDirty
  final List<Audiobook> undoStack;
  final List<Audiobook> redoStack;

  bool get canUndo => undoStack.isNotEmpty;
  bool get canRedo => redoStack.isNotEmpty;
}
```

The `_editSnapshot` field-edit session state lives on `EditorNotifier` (not on `EditorState`) — it's transient bookkeeping, not part of the immutable view state.

### `EditorNotifier` API additions

```dart
class EditorNotifier extends Notifier<EditorState> {
  Audiobook? _editSnapshot;

  // Field-edit session lifecycle
  void beginFieldEdit();
  void endFieldEdit();
  void cancelFieldEdit();

  // Undo/redo
  void undo();
  void redo();
}
```

### Method semantics

- `beginFieldEdit()` — captures `_editSnapshot = state.audiobook`. No-op if a session is already active (so re-focusing the same field doesn't reset the snapshot).
- `endFieldEdit()` — if `_editSnapshot != null && state.audiobook != null && _editSnapshot != state.audiobook`, push `_editSnapshot` to `undoStack`, clear `redoStack`. Always clear `_editSnapshot`.
- `cancelFieldEdit()` — if `_editSnapshot != null`, set `state.audiobook = _editSnapshot`. Always clear `_editSnapshot`. Don't touch the stacks.
- Discrete ops (`addChapter`, etc.) — call `endFieldEdit()` first, then push the current state to `undoStack`, clear `redoStack`, perform the mutation.
- Continuous ops (`setTitle`, etc.) — just update state. No stack manipulation.
- `undo()` — if `undoStack` non-empty: push current `audiobook` onto `redoStack`, pop `undoStack` to current. If `_editSnapshot != null`, clear it (a Cmd+Z while focused should have already cancelled the field edit, but defensively).
- `redo()` — symmetric: push current onto `undoStack`, pop `redoStack` to current.
- `open(path)` — load file, clear both stacks, clear `_editSnapshot`.
- `save()` / `saveAs()` — unchanged. Stacks untouched.

### Field widgets

Each text field wraps a `FocusNode` with a listener:

```dart
focusNode.addListener(() {
  final hasFocus = focusNode.hasFocus;
  if (hasFocus) {
    ref.read(editorProvider.notifier).beginFieldEdit();
  } else {
    ref.read(editorProvider.notifier).endFieldEdit();
  }
});
```

Fields that need this: chapter title, chapter start, all 7 metadata fields (title/author/narrator/album/genre/year/description). Cover replace/remove are discrete ops, not text-field edits — no session.

### Keyboard shortcuts

Two new modifier intents:

```dart
class UndoIntent extends Intent { const UndoIntent(); }
class RedoIntent extends Intent { const RedoIntent(); }
```

Keymap entries:

```dart
cmd(LogicalKeyboardKey.keyZ): const UndoIntent(),
cmd(LogicalKeyboardKey.keyZ, shift: true): const RedoIntent(),
```

Action implementations check focus context and dispatch:

```dart
UndoIntent: CallbackAction<UndoIntent>(onInvoke: (_) {
  final notifier = ref.read(editorProvider.notifier);
  if (_isEditableTextFocused()) {
    notifier.cancelFieldEdit();
    FocusManager.instance.primaryFocus?.unfocus();
  } else {
    notifier.undo();
  }
  return null;
}),
RedoIntent: CallbackAction<RedoIntent>(onInvoke: (_) {
  if (_isEditableTextFocused()) return null;
  ref.read(editorProvider.notifier).redo();
  return null;
}),
```

These are NOT `_BareKeyAction` — they're modifier shortcuts and we want them to always fire, with the focus check inside the body to choose between cancel-edit and undo.

## Tests

### `test/presentation/editor_state_test.dart` (extend)

1. **Discrete op pushes one undo step.** `addChapter()` then `undo()` returns chapter count to original.
2. **Continuous op without session does not push.** `setTitle('Foo')` outside a session, `undo()` is a no-op.
3. **Empty session pushes nothing.** `beginFieldEdit()` then `endFieldEdit()` with no mutation in between leaves stack empty.
4. **Session with mutations pushes one step.** `beginFieldEdit()`, two `setTitle` calls, `endFieldEdit()`. Stack length 1. Undo reverts to original title.
5. **`cancelFieldEdit` reverts state and pushes nothing.** `beginFieldEdit()`, `setTitle('Foo')`, `cancelFieldEdit()`. Title reverted, stack empty.
6. **Discrete op during a session closes the session first.** `beginFieldEdit()`, `setTitle('Foo')`, `addChapter()`. Stack length 2. Two undos return to the start.
7. **`undo()` populates redo; `redo()` re-applies.** After step 4, `undo()`, then `redo()`. Title is `'Bar'` again.
8. **New mutation after undo clears redo stack.** After undo, `addChapter()`. `canRedo` is false.
9. **`open(path)` clears both stacks.** Build history, `open(differentPath)`. Both stacks empty.
10. **Stacks survive `save()`.** Build history, `save()`. Stacks unchanged.

### `test/presentation/keyboard_shortcuts_test.dart` (extend)

11. **`Cmd+Z` undoes when no field is focused.** `addChapter()` programmatically, `Cmd+Z`. Chapter count back to baseline.
12. **`Cmd+Z` while focused cancels the in-flight edit and defocuses.** Focus the chapter title field, send a key event that mutates state (we do this by calling the editor notifier's setTitle directly to simulate typing — since `tester.sendKeyEvent` doesn't insert text), then `Cmd+Z`. Title reverted, primary focus no longer in EditableText, undo stack still empty.
13. **`Cmd+Shift+Z` redoes when no field is focused.** Set up an undo, then redo via shortcut. State re-applied.
14. **`Cmd+Shift+Z` while focused is a no-op.** Set up state, focus a field, mutate, `Cmd+Shift+Z`. State and stacks unchanged.

### `test/presentation/chapter_list_test.dart` (extend)

15. **Focus → mutate → blur on chapter title pushes one undo step.** Focus chapter title field, mutate state via the controller, blur (e.g. by tapping outside). Verify `undoStack.length == 1`.

### `test/presentation/metadata_form_test.dart` (extend)

16. **Focus → mutate → blur on a metadata field pushes one undo step.** Same shape as test 15 but for the title metadata field.

## Files

- Modify: `lib/presentation/providers/editor_state.dart` — stack fields, session methods, undo/redo, discrete-op session-closing, continuous-op no-push.
- Modify: `lib/presentation/keyboard/shortcuts.dart` — `UndoIntent`, `RedoIntent`, keymap entries, action wiring.
- Modify: `lib/presentation/widgets/chapter_list.dart` — `_ChapterRowState` adds a focus listener for `_titleFocusNode`. Add `_startFocusNode` with the same listener attached.
- Modify: `lib/presentation/widgets/metadata_form.dart` — each text field gets a `FocusNode` with a begin/end listener.
- Modify: `test/presentation/editor_state_test.dart`
- Modify: `test/presentation/keyboard_shortcuts_test.dart`
- Modify: `test/presentation/chapter_list_test.dart`
- Modify: `test/presentation/metadata_form_test.dart`

## Open items for the implementation plan

- Exact `FocusNode` placement in `metadata_form.dart` — the form is a `ConsumerStatefulWidget` already with `TextEditingController`s in field state. Add parallel `FocusNode`s; wire each `TextField`'s `focusNode:` parameter.
- Whether the implementation plan moves `selectedChapterProvider` and `chapterTitleFocusNodesProvider` is unrelated and out of scope.
