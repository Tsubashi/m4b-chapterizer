# Exit Confirmation When Dirty — Design

**Date:** 2026-05-02
**Status:** Approved (brainstorming phase)

## Overview

When the user attempts to close the application window or quit while the editor has unsaved changes, show a dialog with three buttons: **Cancel**, **Discard**, and **Save**. Cancel keeps the window open; Discard exits without saving; Save saves first then exits. When the editor is clean, the close proceeds immediately.

## Goals

- Window-close attempts with `isDirty == true` show the confirm dialog.
- The Cancel button keeps the app running; nothing else changes.
- The Discard button exits without writing the m4b.
- The Save button saves the audiobook, then exits.
- Clean state (no unsaved edits) closes the window without a prompt.
- Coverage of `handleExitRequest` is full; the thin `window_manager` glue is `coverage:ignore`'d with a clear reason.

## Non-goals

- Save-As dialog from the exit prompt. (Plain Save is sufficient — if the file has never been saved, the app's existing Save behavior handles that path; we don't add a special "save to where" branch from the exit dialog.)
- Persisting partial edits via crash-recovery / autosave.
- Confirming on `open` (already handled separately by `EditorActions._confirmDiscard`).

## Behavior

| State | Trigger | Result |
|---|---|---|
| `isDirty == false` | Window close (red X / `⌘W` / `⌘Q`) | Window destroys immediately. |
| `isDirty == true` | Window close | Dialog appears. |
| Dialog: **Cancel** | — | Dialog dismisses. Window stays. No state change. |
| Dialog: **Discard** | — | Window destroys. State is discarded (the in-memory `Audiobook` is lost). |
| Dialog: **Save** | — | `editorProvider.notifier.save()` runs to completion. Window destroys. |

The "Save" path treats save errors as terminal: if `save()` throws, the window does not destroy. The user sees the unhandled error in console (today; future polish could surface a snackbar). For MVP, we propagate the throw and the window stays open.

## Architecture

### `pubspec.yaml`

Add `window_manager: ^0.4.0` to `dependencies`. Latest stable as of mid-2026 supports macOS/Windows/Linux for the close-listener API we need.

### `lib/presentation/exit_confirmation.dart` (new)

Three exports:

```dart
enum ExitDecision { cancel, discard, save }

/// Shows the unsaved-changes confirm dialog. Returns the user's pick,
/// or `null` if the dialog can't be shown (e.g., context unmounted).
Future<ExitDecision?> showExitConfirmDialog(BuildContext context);

/// Returns `true` if the application should proceed with exit. Handles the
/// not-dirty fast path. On Save, awaits `editorProvider.notifier.save()`
/// before returning.
Future<bool> handleExitRequest(BuildContext context, WidgetRef ref);

/// Wraps a child widget. Initializes a `WindowListener` so the OS-level
/// close attempt (red X / Cmd+W / Cmd+Q) is intercepted. On close, calls
/// `handleExitRequest` and either `windowManager.destroy()`s or stays.
class WindowCloseGuard extends ConsumerStatefulWidget;
```

`handleExitRequest` is pure UI logic: dialog + decision dispatch. Fully testable in widget tests.

`WindowCloseGuard` wraps `windowManager.addListener(this)` and `windowManager.destroy()`. Marked `// coverage:ignore-start` / `// coverage:ignore-end` because the native close-event delivery requires the OS window-manager channel that doesn't run in `flutter test`.

### `lib/main.dart`

Add window-manager initialization before `runApp`, and wrap the app in `WindowCloseGuard`:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setPreventClose(true);

  final resolver = BundledBinaryResolver();
  runApp(
    ProviderScope(
      overrides: [
        binaryResolverProvider.overrideWithValue(resolver),
        bookbinderProvider.overrideWithValue(
          FfmpegBookbinder(
            runner: const SystemProcessRunner(),
            binaries: resolver,
          ),
        ),
      ],
      child: const WindowCloseGuard(child: M4bChapterizerApp()),
    ),
  );
}
```

`setPreventClose(true)` tells `window_manager` that the OS close should fire `onWindowClose` instead of immediately tearing down the window. Our listener then decides whether to call `windowManager.destroy()`.

### Dialog layout

```
┌─────────────────────────────────────────┐
│  Unsaved changes                        │
│                                         │
│  Do you want to save your changes       │
│  before exiting?                        │
│                                         │
│           [Cancel]  [Discard]  [ Save ] │
└─────────────────────────────────────────┘
```

Cancel: `TextButton`. Discard: `TextButton`. Save: `FilledButton` (primary action).

`barrierDismissible: false` — the user must explicitly choose. Closing the dialog without picking is treated as Cancel.

## Tests

`test/presentation/exit_confirmation_test.dart` (new). The tests pump a small harness with a button that captures the `handleExitRequest` return value:

```dart
Future<bool?> _trigger(WidgetTester tester, ProviderContainer container) async {
  bool? result;
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(builder: (context, ref, _) {
          return ElevatedButton(
            onPressed: () async {
              result = await handleExitRequest(context, ref);
            },
            child: const Text('exit'),
          );
        }),
      ),
    ),
  ));
  await tester.tap(find.text('exit'));
  await tester.pumpAndSettle();
  return () => result;  // closure captures result for later assertion
}
```

(Implementation detail; the plan will spell out the exact harness.)

Tests:

1. **Not dirty → returns true; no dialog shown.** Open a clean book; trigger; assert return is `true` and no `AlertDialog` is in the tree.
2. **Dirty + Cancel → returns false.** Make state dirty (`setTitle('Foo')` outside a session is a continuous op that doesn't push undo but DOES set `isDirty`). Trigger; tap "Cancel"; assert return is `false`.
3. **Dirty + Discard → returns true; save NOT called.** Trigger; tap "Discard"; assert return is `true` and the fake bookbinder's `write` was never invoked.
4. **Dirty + Save → returns true; save called once with the dirty audiobook.** Trigger; tap "Save"; assert return is `true` and `bookbinder.write` was called once with the post-edit audiobook.

## Files

- Create: `lib/presentation/exit_confirmation.dart`
- Create: `test/presentation/exit_confirmation_test.dart`
- Modify: `lib/main.dart`
- Modify: `pubspec.yaml`

## Open items for the implementation plan

- The exact `_trigger` harness shape — straightforward but worth pinning down in the plan so the implementer doesn't fight async + dialog timing.
- Whether `window_manager` requires platform-specific Podfile/CMake changes on macOS/Linux/Windows. The package is well-behaved but the implementer should verify by running `flutter build macos --debug` after adding it.
