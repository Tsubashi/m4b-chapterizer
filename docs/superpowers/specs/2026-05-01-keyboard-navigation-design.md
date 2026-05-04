# Keyboard Navigation — Design

**Date:** 2026-05-01
**Status:** Approved (brainstorming phase)

## Overview

Add a comprehensive keyboard shortcut system to the editor: media controls, file operations, chapter list navigation, and chapter manipulation. Bare-key shortcuts (`Space`, arrows, `Enter`, `Delete`) are inactive while a `TextField` has focus so they don't interfere with text input. Modifier shortcuts (`⌘`/`Ctrl`-prefixed) are always active.

## Goals

- Common audiobook-editor actions reachable from the keyboard with no chording
- Bare keys (`Space`, arrows, `Delete`, `Enter`) cleanly defer to focused `TextField`s — they only fire when no field is focused
- Modifier shortcuts work in any focus context
- Platform-correct: `⌘` on macOS, `Ctrl` on Windows/Linux
- All shortcut behavior covered by widget tests using the Flutter test harness's synthesized key events

## Non-goals

- User-customizable shortcuts (a settings UI is out of scope)
- Vim-style modal navigation
- Discoverability via menu bar or tooltips (could come later)
- Repeat-on-hold for arrow scrubbing (Flutter handles this naturally; we don't add throttling)

## Shortcut table

| Keys | Action | Active when |
|---|---|---|
| `Space` | Toggle play/pause | No `TextField` focused |
| `←` / `→` | Scrub ±5s | No `TextField` focused |
| `Shift+←` / `Shift+→` | Scrub ±30s | No `TextField` focused |
| `↑` / `↓` | Move chapter selection ±1 | No `TextField` focused; audiobook loaded |
| `⏎` (Enter) | Focus title field of selected chapter | No `TextField` focused; audiobook loaded |
| `⌫` (Backspace) | Delete the selected chapter | No `TextField` focused; audiobook loaded |
| `Esc` | Defocus the current `TextField` | A `TextField` is focused |
| `⌘N` / `Ctrl+N` | Add a new chapter | Audiobook loaded |
| `⌘S` / `Ctrl+S` | Save | Audiobook loaded |
| `⌘⇧S` / `Ctrl+Shift+S` | Save As | Audiobook loaded |
| `⌘O` / `Ctrl+O` | Open file | Always |
| `⌘B` / `Ctrl+B` | Set selected chapter start to playhead | Audiobook loaded |

Shortcuts that require an audiobook loaded silently no-op when none is.

## How TextField focus is handled

Flutter's `EditableText` widget consumes bare-key events (`Space`, arrows, `Enter`, `Backspace`) when focused. It stops event propagation if the key was consumed. Therefore, registering bare-key shortcuts at the *root* level of the editor screen automatically defers to focused fields — `EditableText` handles the input first, and our `Shortcuts` widget never sees the event.

This is the entire mechanism. There is no explicit "is a TextField focused" check anywhere in our code; we rely on Flutter's keyboard event flow.

Modifier shortcuts (`⌘`-prefixed) are NOT consumed by `EditableText` — it ignores key events whose modifier set isn't recognized as a text-edit binding. So `⌘S` propagates up regardless of focus.

## Architecture

### `lib/presentation/keyboard/shortcuts.dart` (new)

Three pieces:

**Intent classes** — one per action, all extending `Intent`. A few carry a payload:

```dart
class PlayPauseIntent extends Intent { const PlayPauseIntent(); }
class ScrubIntent extends Intent {
  const ScrubIntent(this.delta);
  final Duration delta; // negative for backward
}
class MoveChapterSelectionIntent extends Intent {
  const MoveChapterSelectionIntent(this.delta);
  final int delta; // -1 or +1
}
class FocusSelectedChapterTitleIntent extends Intent { const FocusSelectedChapterTitleIntent(); }
class DeleteSelectedChapterIntent extends Intent { const DeleteSelectedChapterIntent(); }
class AddChapterIntent extends Intent { const AddChapterIntent(); }
class SaveIntent extends Intent { const SaveIntent(); }
class SaveAsIntent extends Intent { const SaveAsIntent(); }
class OpenFileIntent extends Intent { const OpenFileIntent(); }
class SetChapterToPlayheadIntent extends Intent { const SetChapterToPlayheadIntent(); }
class DefocusIntent extends Intent { const DefocusIntent(); }
```

**Keymap function** — `Map<ShortcutActivator, Intent> editorShortcuts()`. Uses `SingleActivator` with `meta: Platform.isMacOS, control: !Platform.isMacOS` for the `⌘`-or-`Ctrl` shortcuts. Returns the full mapping, which is identity-stable so `Shortcuts` widget can hold it as a final field.

**`EditorShortcuts` widget** — a `ConsumerWidget` that builds:

```dart
return Shortcuts(
  shortcuts: editorShortcuts(),
  child: Actions(
    actions: <Type, Action<Intent>>{
      PlayPauseIntent: CallbackAction<PlayPauseIntent>(onInvoke: (_) { ... }),
      // ... one entry per intent
    },
    child: Focus(autofocus: true, child: child),
  ),
);
```

The `Focus(autofocus: true, …)` ensures the editor screen has keyboard focus on first build so shortcuts respond before any field is focused.

### Action callbacks

Each action's body runs in the `EditorShortcuts` widget's build, where `ref` is in scope:

```dart
PlayPauseIntent: CallbackAction<PlayPauseIntent>(onInvoke: (_) {
  final c = ref.read(playbackControllerProvider);
  c.playing ? c.pause() : c.play();
  return null;
}),
ScrubIntent: CallbackAction<ScrubIntent>(onInvoke: (intent) {
  final c = ref.read(playbackControllerProvider);
  final book = ref.read(editorProvider).audiobook;
  if (book == null) return null;
  final target = c.position + intent.delta;
  final clamped = target < Duration.zero
      ? Duration.zero
      : (target > book.totalDuration ? book.totalDuration : target);
  c.seek(clamped);
  return null;
}),
// etc.
```

### Open / Save As handler extraction

The current `EditorScreen.build` defines the Open and Save As callbacks inline within the `AppBar.actions`. The plan extracts them into private methods on a new helper class `EditorActions` (also in `shortcuts.dart` or a sibling file), parameterized by `BuildContext` and `WidgetRef`. The toolbar buttons and the keyboard actions both call into this helper — DRY.

### Chapter title focus nodes

`FocusSelectedChapterTitleIntent` requires a `FocusNode` on each chapter row's title `TextField` that the action can `requestFocus()` on. We add a Riverpod provider:

```dart
final chapterTitleFocusNodesProvider =
    Provider<Map<int, FocusNode>>((ref) => {});
```

`_ChapterRowState.initState` registers a `FocusNode` in this map under its `widget.index`; `dispose` removes it. The action reads `selectedChapterProvider`, looks up the corresponding focus node in the map, and calls `requestFocus()`.

Edge case: when chapters reorder, the FocusNode-per-index map is invalidated for shifted rows. We re-register on every `didUpdateWidget` to keep the map in sync.

## Tests

`test/presentation/keyboard_shortcuts_test.dart` (new):

A small helper `_pumpEditor(tester)` returns a `(container, fakePlayback)` pair after wiring `EditorScreen` with `_StubBookbinder` + `_FakePlayback`. The fakes are similar to ones in existing tests — copy and adapt.

1. **`Space` toggles play/pause when no field is focused.** Send `LogicalKeyboardKey.space`. Assert `fake.playing == true`.
2. **`Space` is consumed by a focused `TextField`.** Tap the title field, send `Space`, assert `fake.playing == false` and the title field's text now contains a leading/trailing space.
3. **`ArrowLeft` calls `seek(position - 5s)`.** Set fake position to 30s. Send `arrowLeft`. Assert the most recent seek was `Duration(seconds: 25)`.
4. **`Shift+ArrowRight` scrubs +30s, clamped to totalDuration.** Set position near the end. Send `Shift+arrowRight`. Assert seek was clamped to `totalDuration`.
5. **`ArrowDown` increments `selectedChapterProvider`, clamped to `chapters.length - 1`.**
6. **`ArrowUp` decrements, clamped to `0`.**
7. **`⌘S` triggers save.** Pump with dirty state, send `meta+keyS`, assert the fake bookbinder's `write` recorded a call.
8. **`⌘B` calls `setChapterStart` with current playback position.** Selected = 1, position = 14.5s. Send `meta+keyB`. Assert chapter 1's start is `14500ms`.
9. **`⌘N` adds a chapter.** Verify `chapters.length` grew by 1.
10. **`⌫` deletes the selected chapter.** Selected = 1 in a 3-chapter book. Send `backspace`. Assert length is 2 and the right title is gone.
11. **`Esc` unfocuses.** Focus a `TextField`, send `escape`, assert `FocusManager.instance.primaryFocus` is no longer the editable.
12. **`⏎` focuses the selected chapter's title field.** Selected = 1. Send `enter`. Assert the focus node for chapter 1's title has primary focus.
13. **Platform-aware activators.** Stub `Platform.isMacOS = true`; assert the keymap entry for `SaveIntent` uses `meta: true, control: false`. Repeat with `Platform.isMacOS = false`.

For modifier tests, use the test helper:

```dart
Future<void> _sendCmdKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pump();
}
```

## Files

- Create: `lib/presentation/keyboard/shortcuts.dart`
- Create: `test/presentation/keyboard_shortcuts_test.dart`
- Modify: `lib/presentation/screens/editor_screen.dart`
- Modify: `lib/presentation/widgets/chapter_list.dart` (register focus nodes per row)

## Open items for the implementation plan

- Exact platform-detection approach: `Platform.isMacOS` from `dart:io` works on desktop. We rely on it directly; no need for an abstraction.
- Whether `OpenFileIntent`'s discard-confirm dialog is awaitable from the keyboard handler the same way the toolbar handler does it (yes — both call into the same async helper).
