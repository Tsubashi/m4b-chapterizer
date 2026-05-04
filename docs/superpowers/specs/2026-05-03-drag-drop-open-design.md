# Drag-and-Drop to Open — Design

**Date:** 2026-05-03
**Status:** Approved (brainstorming phase)

## Overview

When the user drags a file from Finder (or another app) onto the m4b chapterizer window, an overlay appears across the body that says **"Drop .m4b file here to open."** On drop:

- A single `.m4b` file → open it (after the unsaved-changes prompt, if needed).
- Anything else (wrong extension, multiple files, a folder) → SnackBar explaining what's wrong; nothing opens.

The drag-open path shares a single dirty-check helper with the existing `Open…` button so both flows offer the same Cancel / Discard / Save dialog.

## Goals

- Dragging *any* file or folder over the window shows the overlay.
- Dragging out (or pressing Esc) without dropping dismisses the overlay; no SnackBar.
- Dropping a single `.m4b` opens that file; if the editor is dirty, the user gets the three-choice prompt first.
- Dropping anything invalid leaves the editor untouched and shows a SnackBar with a specific reason.
- The Open… AppBar button uses the **same** dirty-check helper, replacing the existing two-choice `_confirmDiscard` dialog.
- Overlay covers the body (everything below the AppBar) and works in both empty-state and book-loaded views.
- macOS implementation lands now. Windows and Linux are added to `TODO.md` and share the same Dart-side contract.

## Non-goals

- No filtering of the dragged payload at the native layer. Native code reports what was dropped; Dart decides what to do with it. (Trades the standard "no drop" cursor for portability across platforms.)
- No MIME-sniffing or magic-byte detection. Extension check only — same trust model as `FilePicker.pickFiles(allowedExtensions: ['m4b'])`.
- No "drag to add cover image" or any other drag-target besides "open this audiobook." Out of scope.
- No per-platform drop policy. The Dart-side validation rules are the canonical behavior.
- No Windows / Linux native implementation in this cycle (tracked in `TODO.md`).

## Behavior

| Dropped payload | Overlay during drag | On drop | SnackBar |
|---|---|---|---|
| Single `.m4b` file | Visible | Overlay dismisses; book opens (after dirty-check, if dirty) | none |
| Single non-`.m4b` file | Visible | Overlay dismisses; nothing opens | `"Only .m4b files can be opened"` |
| A folder | Visible | Overlay dismisses; nothing opens | `"Only .m4b files can be opened"` |
| Multiple files (any mix) | Visible | Overlay dismisses; nothing opens | `"Drop only one .m4b file at a time"` |
| Drag exits / Esc | Visible while inside; dismisses on `dragExited` | — | none |

**Validation order** (the first match wins, so SnackBar text is deterministic):

1. `paths.length != 1` → `"Drop only one .m4b file at a time"`
2. `!paths.single.toLowerCase().endsWith('.m4b')` → `"Only .m4b files can be opened"`
3. Otherwise → run the dirty-check, then `editor.open(path)`.

**Dirty-check (unified with Open…)**

| Editor state | Dialog | Result |
|---|---|---|
| `!isDirty` | none | Open immediately. |
| `isDirty`, user picks **Cancel** / dismisses | three-choice | Abort; nothing changes. |
| `isDirty`, user picks **Discard** | three-choice | Skip save; open the new file. |
| `isDirty`, user picks **Save** | three-choice | `await editor.save()`, then open. If save throws, propagate; the new file does not open. |

## Architecture

### Native (macOS) — `macos/Runner/MainFlutterWindow.swift`

Extend the existing `MainFlutterWindow`:

- Implement `NSDraggingDestination` on the window (or on the Flutter view; window is simpler given the existing structure).
- Register for `NSPasteboard.PasteboardType.fileURL` via `registerForDraggedTypes(...)`.
- Override:
  - `draggingEntered(_:)` → post `dragEntered` over the channel; return `.copy` so the OS shows the green-plus cursor.
  - `draggingExited(_:)` → post `dragExited`.
  - `performDragOperation(_:)` → extract `[String]` of file paths from the pasteboard's `NSURL` items, post `filesDropped` with that list; return `true`.
  - `prepareForDragOperation(_:)` → return `true`.
- Set up a `FlutterMethodChannel(name: "m4b_chapterizer/drag_drop", binaryMessenger: flutterViewController.engine.binaryMessenger)` once during `awakeFromNib`. The channel is only used for sends from native to Dart, but we keep the receive side wired so Dart can answer back if needed in the future.
- All of this code stays in `MainFlutterWindow.swift` — no new Swift files, no `@objc` plugins.

### Dart bridge — `lib/presentation/drag_drop/drag_drop_channel.dart` (new)

```dart
sealed class DragEvent {}
class DragEntered extends DragEvent {}
class DragExited extends DragEvent {}
class FilesDropped extends DragEvent {
  FilesDropped(this.paths);
  final List<String> paths;
}

abstract class DragDropChannel {
  Stream<DragEvent> get events;
}

class MethodChannelDragDropChannel implements DragDropChannel { /* ... */ }

final dragDropChannelProvider = Provider<DragDropChannel>((ref) {
  // coverage:ignore-start — production wiring; tests override.
  throw StateError('dragDropChannelProvider must be overridden');
  // coverage:ignore-end
});
```

The `MethodChannelDragDropChannel` listens to `MethodChannel("m4b_chapterizer/drag_drop")`'s `setMethodCallHandler` and pushes `DragEvent`s through a `StreamController.broadcast()`. The thin platform-channel wiring is `coverage:ignore`'d (same pattern as `WindowCloseGuard`); the `DragEvent` types and any logic above the channel stay measured.

`main.dart` overrides the provider with `MethodChannelDragDropChannel(...)` at startup.

### Dart UI — `lib/presentation/drag_drop/drag_drop_overlay.dart` (new)

```dart
final isDragOverProvider = StateProvider<bool>((ref) => false);

class DragDropOverlay extends ConsumerStatefulWidget {
  const DragDropOverlay({super.key, required this.child});
  final Widget child;
  // ...
}
```

`_DragDropOverlayState`:

- `initState()` subscribes to `dragDropChannelProvider.events`.
- On `DragEntered` → set `isDragOverProvider` true.
- On `DragExited` → set false.
- On `FilesDropped(paths)` → set false, call `handleFilesDropped(context, ref, paths)`.
- Build returns a `Stack` with `child` at the bottom and, when `isDragOverProvider` is true, a tinted `IgnorePointer`-wrapped `Center` containing a Material card with an icon + "Drop .m4b file here to open."

### Dart logic — `lib/presentation/drag_drop/handle_files_dropped.dart` (new)

```dart
Future<void> handleFilesDropped(
  BuildContext context,
  WidgetRef ref,
  List<String> paths,
) async {
  if (paths.length != 1) {
    _snack(context, 'Drop only one .m4b file at a time');
    return;
  }
  final path = paths.single;
  if (!path.toLowerCase().endsWith('.m4b')) {
    _snack(context, 'Only .m4b files can be opened');
    return;
  }
  if (!await confirmReplaceCurrentBook(context, ref)) return;
  if (!context.mounted) return;
  await ref.read(editorProvider.notifier).open(path);
}
```

`_snack` wraps `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)))`.

### Dart logic — `lib/presentation/drag_drop/dirty_check.dart` (new)

```dart
/// Returns true if the caller should proceed with replacing the
/// currently-open audiobook. False means "abort; user said cancel."
///
/// - Clean state: returns true immediately, no dialog.
/// - Dirty + Discard: returns true.
/// - Dirty + Save: awaits `editor.save()`, returns true. If save throws,
///   the throw propagates and the caller treats that as "abort."
/// - Dirty + Cancel/dismiss: returns false.
Future<bool> confirmReplaceCurrentBook(
  BuildContext context,
  WidgetRef ref,
) async { /* ... */ }
```

The dialog UI is **the same widget** as the exit-confirmation dialog. We extract `showExitConfirmDialog` and the `ExitDecision` enum into a shared spot so both flows reuse them. Concretely: rename to `showUnsavedChangesDialog` returning `UnsavedChangesDecision { cancel, discard, save }` and live in `lib/presentation/dialogs/unsaved_changes_dialog.dart`. Both `exit_confirmation.dart` and `dirty_check.dart` import from there.

### Editor wiring — `lib/presentation/screens/editor_screen.dart`

Wrap `Scaffold.body` (the existing conditional `Center` / `Column`) in `DragDropOverlay(child: ...)`. The Flutter overlay paints over the body only, but the macOS native side registers `registerForDraggedTypes` on the entire `NSWindow`, so AppKit accepts drops over the title bar too. The overlay's tinted background paints *behind* the title bar in that region, which is a minor cosmetic limitation but doesn't impede functionality.

### Open… button — `lib/presentation/keyboard/editor_actions.dart`

Replace the existing `_confirmDiscard` two-choice dialog with `confirmReplaceCurrentBook`. The body of `open()` becomes:

```dart
Future<void> open() async {
  if (!await confirmReplaceCurrentBook(context, ref)) return;
  if (!context.mounted) return;
  final result = await guardFilePicker(/* ... unchanged ... */);
  final path = result?.files.single.path;
  if (path == null) return;
  await ref.read(editorProvider.notifier).open(path);
}
```

`_confirmDiscard` is deleted.

### Exit-confirmation refactor — `lib/presentation/exit_confirmation.dart`

`handleExitRequest` switches its imports to use the shared `showUnsavedChangesDialog` and `UnsavedChangesDecision` from `lib/presentation/dialogs/unsaved_changes_dialog.dart`. Behavior is unchanged.

### `lib/main.dart`

Add the dragDropChannel provider override alongside the existing `bookbinderProvider` / `binaryResolverProvider` overrides.

### `TODO.md`

New entries under "Cross-platform desktop polish":

- **Implement drag-and-drop file open on Windows** — `flutter_window.cpp` registers a `IDropTarget` (or uses `DragAcceptFiles` + `WM_DROPFILES`) and posts `dragEntered`/`dragExited`/`filesDropped` over the same `m4b_chapterizer/drag_drop` MethodChannel.
- **Implement drag-and-drop file open on Linux** — `my_application.cc` wires GTK `drag-data-received` / `drag-motion` / `drag-leave` and posts the same events on the same channel.

## Testing

### `test/presentation/drag_drop/handle_files_dropped_test.dart` (new)

Use `MockBuildContext` + fake editor (mock `EditorNotifier` via Riverpod overrides, fake `ScaffoldMessenger` via a `MaterialApp` test harness):

- Empty list → SnackBar "Drop only one .m4b file at a time"; `editor.open` not called.
- Two paths → same SnackBar; `editor.open` not called.
- Single `.txt` → SnackBar "Only .m4b files can be opened"; `editor.open` not called.
- Single `.M4B` (uppercase) → no SnackBar; `editor.open(path)` called.
- Single `.m4b`, clean state → no dialog; `editor.open(path)` called.
- Single `.m4b`, dirty + Discard → dialog shown; `editor.open(path)` called; `editor.save` not called.
- Single `.m4b`, dirty + Save → dialog shown; `editor.save()` awaited; `editor.open(path)` called.
- Single `.m4b`, dirty + Cancel → dialog shown; `editor.open` not called; `editor.save` not called.

### `test/presentation/drag_drop/drag_drop_overlay_test.dart` (new)

Use a `FakeDragDropChannel` with a controllable `StreamController`:

- Initial render → no overlay text.
- Push `DragEntered` → overlay visible with the expected text.
- Push `DragExited` → overlay gone.
- Push `FilesDropped(['/tmp/foo.m4b'])` → overlay gone; `editor.open` called once.

### `test/presentation/dialogs/unsaved_changes_dialog_test.dart` (new)

Direct widget test of the shared dialog: pump the dialog, tap each button, assert the returned `UnsavedChangesDecision`. Three test cases (one per outcome) plus one for "tap outside / system back → returns `cancel`."

### `test/presentation/exit_confirmation_test.dart` (update)

Existing tests for `handleExitRequest`'s decision routing (cancel / discard / save) stay. The only change is import paths — the enum and dialog function move to the shared `unsaved_changes_dialog.dart`. No behavior change to assert against.

### `test/presentation/drag_drop/dirty_check_test.dart` (new)

Mirror of `exit_confirmation_test.dart`'s structure but for `confirmReplaceCurrentBook`: clean → returns true with no dialog; dirty + each of the three dialog outcomes → returns the documented bool and (for Save) calls `editor.save()`.

### Coverage discipline

- `MethodChannelDragDropChannel` (the platform glue) is `coverage:ignore`'d with a one-line reason: "OS event delivery is exercised only by smoke tests on a real desktop build."
- `DragDropOverlay`'s subscription wiring (`initState`/`dispose`) is `coverage:ignore`'d only if the widget tests can't reach it; aim to keep it measured.
- Native Swift code is not measured by `flutter test` and is exercised by manual smoke tests post-merge.

## Smoke-test plan

After merge, on macOS:

1. Empty state, drag a `.m4b` over the window → overlay appears, drop → file opens.
2. Book loaded + clean, drag another `.m4b` → overlay → drop → second book replaces the first.
3. Edit the title (mark dirty), drag a `.m4b` → drop → three-choice dialog → Cancel → still on the original book, edits intact.
4. Same setup, Discard → second book replaces the first; dirty cleared.
5. Same setup, Save → first book saves, second book replaces it; dirty cleared.
6. Drag a `.txt` → overlay → drop → SnackBar; nothing opens.
7. Drag two `.m4b`s → overlay → drop → SnackBar; nothing opens.
8. Drag a `.m4b` over the window then drag back out without dropping → overlay dismisses; nothing else changes.
9. AppBar title region: drag a `.m4b` over the title bar → overlay appears and drop is accepted (drop region is the entire native window). The overlay's tinted background paints behind the title bar; that's expected.
10. Open… button still works and shows the same three-choice dialog when dirty.
