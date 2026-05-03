# Drag-and-Drop to Open Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow the user to drag an `.m4b` file onto the window to open it, with the same dirty-check prompt as the Open… button.

**Architecture:** macOS Swift implements `NSDraggingDestination` in `MainFlutterWindow.swift` and posts events over a new `MethodChannel`. A Riverpod-provided `DragDropChannel` exposes those events as a `Stream<DragEvent>`; a `DragDropOverlay` widget wraps the screen body, paints the overlay during drag, validates dropped paths, and opens the file via the editor. The Open… button and the drop handler share one `confirmReplaceCurrentBook` helper that uses the same three-choice dialog as the exit-confirmation flow.

**Tech Stack:** Flutter 3.41.9, Dart 3.11.5, flutter_riverpod 3.x, Swift 5 / AppKit (`NSDraggingDestination`), `flutter_test` + `mocktail`.

**Spec:** `docs/superpowers/specs/2026-05-03-drag-drop-open-design.md`

---

## File Map

**New Dart files:**
- `lib/presentation/dialogs/unsaved_changes_dialog.dart` — shared `UnsavedChangesDecision` enum + `showUnsavedChangesDialog` widget function
- `lib/presentation/drag_drop/drag_drop_channel.dart` — `DragEvent` sealed class hierarchy, `DragDropChannel` abstract class, `MethodChannelDragDropChannel` impl, `dragDropChannelProvider`
- `lib/presentation/drag_drop/dirty_check.dart` — `confirmReplaceCurrentBook` helper
- `lib/presentation/drag_drop/handle_files_dropped.dart` — validation + open routing
- `lib/presentation/drag_drop/drag_drop_overlay.dart` — `isDragOverProvider` + `DragDropOverlay` widget

**New tests:**
- `test/presentation/dialogs/unsaved_changes_dialog_test.dart`
- `test/presentation/drag_drop/dirty_check_test.dart`
- `test/presentation/drag_drop/handle_files_dropped_test.dart`
- `test/presentation/drag_drop/drag_drop_overlay_test.dart`

**Modified Dart files:**
- `lib/presentation/exit_confirmation.dart` — re-export shared dialog, drop the local enum
- `lib/presentation/keyboard/editor_actions.dart` — replace `_confirmDiscard` with `confirmReplaceCurrentBook`
- `lib/presentation/screens/editor_screen.dart` — wrap body in `DragDropOverlay`
- `lib/main.dart` — override `dragDropChannelProvider`
- `test/presentation/exit_confirmation_test.dart` — update import for `ExitDecision`

**Modified non-Dart:**
- `macos/Runner/MainFlutterWindow.swift` — implement `NSDraggingDestination`, register `MethodChannel`
- `TODO.md` — Windows / Linux drop entries

---

## Task 1: Extract shared unsaved-changes dialog

Pure refactor — move the dialog out of `exit_confirmation.dart` so the drag-drop flow can reuse it.

**Files:**
- Create: `lib/presentation/dialogs/unsaved_changes_dialog.dart`
- Create: `test/presentation/dialogs/unsaved_changes_dialog_test.dart`
- Modify: `lib/presentation/exit_confirmation.dart`
- Modify: `test/presentation/exit_confirmation_test.dart`

- [ ] **Step 1: Create the shared dialog file**

Create `lib/presentation/dialogs/unsaved_changes_dialog.dart`:

```dart
import 'package:flutter/material.dart';

enum UnsavedChangesDecision { cancel, discard, save }

/// Shows the unsaved-changes confirm dialog. Returns the user's pick,
/// or null if the dialog cannot be shown / was dismissed.
Future<UnsavedChangesDecision?> showUnsavedChangesDialog(BuildContext context) {
  return showDialog<UnsavedChangesDecision>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Unsaved changes'),
      content: const Text(
        'Do you want to save your changes before continuing?',
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(ctx).pop(UnsavedChangesDecision.cancel),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(ctx).pop(UnsavedChangesDecision.discard),
          child: const Text('Discard'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(ctx).pop(UnsavedChangesDecision.save),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
```

Note the body text changed slightly: "before continuing" instead of "before exiting" — the dialog is now shared between exit and replace-book flows.

- [ ] **Step 2: Write widget tests for the shared dialog**

Create `test/presentation/dialogs/unsaved_changes_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/presentation/dialogs/unsaved_changes_dialog.dart';

Future<UnsavedChangesDecision?> _show(WidgetTester tester) async {
  UnsavedChangesDecision? result;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await showUnsavedChangesDialog(context);
          },
          child: const Text('go'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  test('UnsavedChangesDecision values are exhaustive', () {
    expect(UnsavedChangesDecision.values, [
      UnsavedChangesDecision.cancel,
      UnsavedChangesDecision.discard,
      UnsavedChangesDecision.save,
    ]);
  });

  testWidgets('Cancel button returns cancel', (tester) async {
    final future = _show(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(await future, UnsavedChangesDecision.cancel);
  });

  testWidgets('Discard button returns discard', (tester) async {
    final future = _show(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Discard'));
    await tester.pumpAndSettle();
    expect(await future, UnsavedChangesDecision.discard);
  });

  testWidgets('Save button returns save', (tester) async {
    final future = _show(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(await future, UnsavedChangesDecision.save);
  });
}
```

- [ ] **Step 3: Run the new tests; verify they pass**

Run: `flutter test test/presentation/dialogs/unsaved_changes_dialog_test.dart`
Expected: 4 passing tests.

- [ ] **Step 4: Replace the old dialog in `exit_confirmation.dart`**

Replace the entire file `lib/presentation/exit_confirmation.dart` with:

```dart
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dialogs/unsaved_changes_dialog.dart';
import 'providers/editor_state.dart';

// Re-export so existing imports of `ExitDecision` keep working until
// callers migrate. The exit flow only uses cancel/discard/save, which
// map 1:1 to UnsavedChangesDecision.
typedef ExitDecision = UnsavedChangesDecision;

/// True if the application should proceed with closing.
///
/// Fast path: if the editor isn't dirty, returns true without showing a
/// dialog. Otherwise shows [showUnsavedChangesDialog] and:
/// - Cancel / dismissed → false
/// - Discard → true
/// - Save → awaits the editor's save, then true
Future<bool> handleExitRequest(BuildContext context, WidgetRef ref) async {
  final state = ref.read(editorProvider);
  if (!state.isDirty) return true;

  final decision = await showUnsavedChangesDialog(context);
  switch (decision) {
    case UnsavedChangesDecision.discard:
      return true;
    case UnsavedChangesDecision.save:
      await ref.read(editorProvider.notifier).save();
      return true;
    case UnsavedChangesDecision.cancel:
    case null:
      return false;
  }
}

// coverage:ignore-start
// Bridge to Flutter's built-in app-exit request mechanism. The OS-level
// close event (red X / Cmd+W on the last window / Cmd+Q) reaches this
// widget through `WidgetsBindingObserver.didRequestAppExit`, which the
// Flutter macOS embedder wires to NSApplicationDelegate's
// `applicationShouldTerminate`. On macOS the AppDelegate sets
// `applicationShouldTerminateAfterLastWindowClosed` to true, so closing
// the only window also routes through this path.
//
// The OS event delivery itself is not exercised by `flutter test`; this
// class is exercised only by smoke tests on a real desktop build. The
// testable logic is in [handleExitRequest] above.

/// Wraps [child] and intercepts OS app-exit requests (red X, Cmd+Q). On
/// request, calls [handleExitRequest] and returns either
/// [AppExitResponse.exit] or [AppExitResponse.cancel].
class WindowCloseGuard extends ConsumerStatefulWidget {
  const WindowCloseGuard({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WindowCloseGuard> createState() => _WindowCloseGuardState();
}

class _WindowCloseGuardState extends ConsumerState<WindowCloseGuard>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    if (!mounted) return AppExitResponse.exit;
    final shouldExit = await handleExitRequest(context, ref);
    return shouldExit ? AppExitResponse.exit : AppExitResponse.cancel;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
// coverage:ignore-end
```

The `typedef ExitDecision = UnsavedChangesDecision` keeps the existing exit-confirmation tests working without changes to their assertions.

- [ ] **Step 5: Run the full test suite to confirm nothing broke**

Run: `flutter test`
Expected: all 186+ tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/dialogs/ lib/presentation/exit_confirmation.dart test/presentation/dialogs/
git commit --no-gpg-sign -m "$(cat <<'EOF'
Extract unsaved-changes dialog into a shared module

The exit-confirmation flow and the upcoming drag-and-drop flow both
need the same Cancel/Discard/Save dialog. Move the dialog and its
enum into lib/presentation/dialogs/unsaved_changes_dialog.dart and
keep exit_confirmation re-exporting the enum as ExitDecision so
existing call sites are unaffected.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Add `confirmReplaceCurrentBook` helper

Build the helper that both the Open… button and the drop handler will call.

**Files:**
- Create: `lib/presentation/drag_drop/dirty_check.dart`
- Create: `test/presentation/drag_drop/dirty_check_test.dart`

- [ ] **Step 1: Write failing tests for `confirmReplaceCurrentBook`**

Create `test/presentation/drag_drop/dirty_check_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/bookbinder.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
import 'package:m4b_chapterizer/presentation/drag_drop/dirty_check.dart';
import 'package:m4b_chapterizer/presentation/providers/editor_state.dart';

class _RecordingBookbinder implements Bookbinder {
  _RecordingBookbinder(this._book);
  final Audiobook _book;
  int writeCount = 0;
  Audiobook? lastWritten;

  @override
  Future<Audiobook> read(String sourcePath) async => _book;

  @override
  Future<void> write({
    required String sourcePath,
    required String destinationPath,
    required Audiobook audiobook,
  }) async {
    writeCount++;
    lastWritten = audiobook;
  }
}

Audiobook _book() => Audiobook.validated(
      title: 'Original',
      chapters: const [Chapter(title: 'C', start: Duration.zero)],
      totalDuration: const Duration(seconds: 10),
    );

Future<bool? Function()> _pumpHarness(
  WidgetTester tester,
  ProviderContainer container,
) async {
  bool? captured;
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(builder: (context, ref, _) {
          return ElevatedButton(
            onPressed: () async {
              captured = await confirmReplaceCurrentBook(context, ref);
            },
            child: const Text('go'),
          );
        }),
      ),
    ),
  ));
  return () => captured;
}

void main() {
  testWidgets('returns true immediately when not dirty', (tester) async {
    final fake = _RecordingBookbinder(_book());
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/tmp/x.m4b');

    final getResult = await _pumpHarness(tester, container);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(getResult(), isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    expect(fake.writeCount, 0);
  });

  testWidgets('returns false when user picks Cancel', (tester) async {
    final fake = _RecordingBookbinder(_book());
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/tmp/x.m4b');
    container.read(editorProvider.notifier).setTitle('Edited');

    final getResult = await _pumpHarness(tester, container);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(getResult(), isFalse);
    expect(fake.writeCount, 0);
  });

  testWidgets('returns true and skips save when user picks Discard',
      (tester) async {
    final fake = _RecordingBookbinder(_book());
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/tmp/x.m4b');
    container.read(editorProvider.notifier).setTitle('Edited');

    final getResult = await _pumpHarness(tester, container);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Discard'));
    await tester.pumpAndSettle();

    expect(getResult(), isTrue);
    expect(fake.writeCount, 0);
  });

  testWidgets('returns true and saves once when user picks Save',
      (tester) async {
    final fake = _RecordingBookbinder(_book());
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/tmp/x.m4b');
    container.read(editorProvider.notifier).setTitle('Edited');

    final getResult = await _pumpHarness(tester, container);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(getResult(), isTrue);
    expect(fake.writeCount, 1);
    expect(fake.lastWritten?.title, 'Edited');
  });
}
```

- [ ] **Step 2: Run tests; verify they fail**

Run: `flutter test test/presentation/drag_drop/dirty_check_test.dart`
Expected: compile error — `confirmReplaceCurrentBook` doesn't exist yet.

- [ ] **Step 3: Implement `confirmReplaceCurrentBook`**

Create `lib/presentation/drag_drop/dirty_check.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dialogs/unsaved_changes_dialog.dart';
import '../providers/editor_state.dart';

/// Returns true if the caller should proceed with replacing the
/// currently-open audiobook, false if the user cancelled.
///
/// - Clean state: returns true immediately, no dialog.
/// - Dirty + Cancel / dismiss: returns false.
/// - Dirty + Discard: returns true (no save).
/// - Dirty + Save: awaits `editor.save()`, returns true. If save throws,
///   the throw propagates and the caller treats that as "abort."
Future<bool> confirmReplaceCurrentBook(
  BuildContext context,
  WidgetRef ref,
) async {
  final state = ref.read(editorProvider);
  if (!state.isDirty) return true;

  final decision = await showUnsavedChangesDialog(context);
  switch (decision) {
    case UnsavedChangesDecision.discard:
      return true;
    case UnsavedChangesDecision.save:
      await ref.read(editorProvider.notifier).save();
      return true;
    case UnsavedChangesDecision.cancel:
    case null:
      return false;
  }
}
```

- [ ] **Step 4: Run tests; verify they pass**

Run: `flutter test test/presentation/drag_drop/dirty_check_test.dart`
Expected: 4 passing tests.

- [ ] **Step 5: Run full suite**

Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/drag_drop/dirty_check.dart test/presentation/drag_drop/dirty_check_test.dart
git commit --no-gpg-sign -m "$(cat <<'EOF'
Add confirmReplaceCurrentBook helper

Shared dirty-check that the Open… button and the upcoming drag-drop
flow will both call before replacing the in-memory audiobook. Reuses
the shared unsaved-changes dialog.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Migrate `EditorActions.open()` to use the shared helper

Replace the local two-choice `_confirmDiscard` dialog with the new three-choice helper.

**Files:**
- Modify: `lib/presentation/keyboard/editor_actions.dart`

- [ ] **Step 1: Replace `EditorActions` with the new implementation**

Replace the entire file `lib/presentation/keyboard/editor_actions.dart` with:

```dart
import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../drag_drop/dirty_check.dart';
import '../providers/editor_state.dart';
import '../util/file_picker_errors.dart';

/// Imperative editor actions shared between the AppBar buttons and
/// the keyboard shortcut bindings.
class EditorActions {
  EditorActions(this.context, this.ref);

  final BuildContext context;
  final WidgetRef ref;

  // coverage:ignore-start
  // FilePicker is a platform plugin and can't be simulated cleanly in a
  // `flutter test` widget environment. The dirty-check is in
  // confirmReplaceCurrentBook (covered by dirty_check_test.dart);
  // open() itself is exercised only by interactive smoke tests.
  Future<void> open() async {
    if (!await confirmReplaceCurrentBook(context, ref)) return;
    if (!context.mounted) return;
    final result = await guardFilePicker(
      context,
      () => FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['m4b'],
      ),
    );
    final path = result?.files.single.path;
    if (path == null) return;
    await ref.read(editorProvider.notifier).open(path);
  }
  // coverage:ignore-end

  Future<void> save() async {
    if (ref.read(editorProvider).audiobook == null) return;
    await ref.read(editorProvider.notifier).save();
  }

  // coverage:ignore-start
  // saveAs() bridges to FilePicker.saveFile, same constraint as open().
  Future<void> saveAs() async {
    if (ref.read(editorProvider).audiobook == null) return;
    final state = ref.read(editorProvider);
    final filename =
        state.path?.split(Platform.pathSeparator).last ?? 'book.m4b';
    final result = await guardFilePicker(
      context,
      () => FilePicker.saveFile(
        type: FileType.custom,
        allowedExtensions: const ['m4b'],
        fileName: filename,
      ),
    );
    if (result == null) return;
    await ref.read(editorProvider.notifier).saveAs(result);
  }
  // coverage:ignore-end
}
```

The local `_confirmDiscard` method is gone; the `open()` body now calls `confirmReplaceCurrentBook`. The save / saveAs paths are unchanged.

- [ ] **Step 2: Run the full suite**

Run: `flutter test`
Expected: all tests pass. `editor_actions_test.dart` still asserts only the save path, which is unchanged.

- [ ] **Step 3: Run the analyzer**

Run: `flutter analyze`
Expected: no issues.

- [ ] **Step 4: Commit**

```bash
git add lib/presentation/keyboard/editor_actions.dart
git commit --no-gpg-sign -m "$(cat <<'EOF'
Use shared dirty-check helper in EditorActions.open

Drops the local two-choice _confirmDiscard dialog in favor of the
three-choice confirmReplaceCurrentBook helper. Open… now offers a
Save button alongside Cancel and Discard, matching the exit flow.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Add `DragEvent` types and `DragDropChannel` interface

The data types and abstract class — no platform code yet. Both the validation logic and the overlay widget will depend on this in subsequent tasks.

**Files:**
- Create: `lib/presentation/drag_drop/drag_drop_channel.dart`

- [ ] **Step 1: Create the channel interface and event types**

Create `lib/presentation/drag_drop/drag_drop_channel.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Events emitted by the platform drag-drop channel as the user drags
/// files over the window.
sealed class DragEvent {
  const DragEvent();
}

/// A drag has entered the window. The overlay should appear.
class DragEntered extends DragEvent {
  const DragEntered();
}

/// The drag exited the window without dropping. The overlay should
/// disappear.
class DragExited extends DragEvent {
  const DragExited();
}

/// The user dropped one or more files. [paths] is the absolute
/// filesystem paths in drop order.
class FilesDropped extends DragEvent {
  const FilesDropped(this.paths);
  final List<String> paths;
}

/// Source of [DragEvent]s. Production binds [MethodChannelDragDropChannel];
/// tests bind a fake.
abstract class DragDropChannel {
  Stream<DragEvent> get events;
}

/// Provider for the drag-drop channel. Tests override; `main.dart`
/// overrides at production startup.
final dragDropChannelProvider = Provider<DragDropChannel>((ref) {
  // coverage:ignore-start
  // Defensive fallback: production wires the override in main(); tests
  // always override before reading.
  throw StateError(
    'dragDropChannelProvider must be overridden at the app or test scope',
  );
  // coverage:ignore-end
});
```

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze`
Expected: no issues.

- [ ] **Step 3: Commit**

```bash
git add lib/presentation/drag_drop/drag_drop_channel.dart
git commit --no-gpg-sign -m "$(cat <<'EOF'
Add DragDropChannel interface and DragEvent types

Sealed class hierarchy (DragEntered, DragExited, FilesDropped) plus an
abstract DragDropChannel that surfaces events as a stream. Production
implementation and Riverpod wiring come in later tasks.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Add `handleFilesDropped` validation + open routing

Pure logic. Heavily tested.

**Files:**
- Create: `lib/presentation/drag_drop/handle_files_dropped.dart`
- Create: `test/presentation/drag_drop/handle_files_dropped_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/presentation/drag_drop/handle_files_dropped_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/bookbinder.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
import 'package:m4b_chapterizer/presentation/drag_drop/handle_files_dropped.dart';
import 'package:m4b_chapterizer/presentation/providers/editor_state.dart';

class _RecordingBookbinder implements Bookbinder {
  _RecordingBookbinder(this._book);
  final Audiobook _book;
  int writeCount = 0;
  final List<String> readPaths = [];

  @override
  Future<Audiobook> read(String sourcePath) async {
    readPaths.add(sourcePath);
    return _book;
  }

  @override
  Future<void> write({
    required String sourcePath,
    required String destinationPath,
    required Audiobook audiobook,
  }) async {
    writeCount++;
  }
}

Audiobook _book() => Audiobook.validated(
      title: 'Original',
      chapters: const [Chapter(title: 'C', start: Duration.zero)],
      totalDuration: const Duration(seconds: 10),
    );

/// Pumps a Consumer that exposes its `BuildContext` and `WidgetRef`
/// through a callback so the test can drive `handleFilesDropped`.
Future<void> _pumpHarness(
  WidgetTester tester,
  ProviderContainer container,
  void Function(BuildContext, WidgetRef) onReady,
) async {
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(builder: (context, ref, _) {
          onReady(context, ref);
          return const SizedBox();
        }),
      ),
    ),
  ));
}

void main() {
  testWidgets('empty list shows multi-file snack and skips open',
      (tester) async {
    final fake = _RecordingBookbinder(_book());
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    late BuildContext ctx;
    late WidgetRef ref0;
    await _pumpHarness(tester, container, (c, r) {
      ctx = c;
      ref0 = r;
    });

    await handleFilesDropped(ctx, ref0, const []);
    await tester.pump();

    expect(find.text('Drop only one .m4b file at a time'), findsOneWidget);
    expect(fake.readPaths, isEmpty);
  });

  testWidgets('two paths show multi-file snack', (tester) async {
    final fake = _RecordingBookbinder(_book());
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    late BuildContext ctx;
    late WidgetRef ref0;
    await _pumpHarness(tester, container, (c, r) {
      ctx = c;
      ref0 = r;
    });

    await handleFilesDropped(ctx, ref0, const ['/a.m4b', '/b.m4b']);
    await tester.pump();

    expect(find.text('Drop only one .m4b file at a time'), findsOneWidget);
    expect(fake.readPaths, isEmpty);
  });

  testWidgets('single non-m4b file shows wrong-extension snack',
      (tester) async {
    final fake = _RecordingBookbinder(_book());
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    late BuildContext ctx;
    late WidgetRef ref0;
    await _pumpHarness(tester, container, (c, r) {
      ctx = c;
      ref0 = r;
    });

    await handleFilesDropped(ctx, ref0, const ['/file.txt']);
    await tester.pump();

    expect(find.text('Only .m4b files can be opened'), findsOneWidget);
    expect(fake.readPaths, isEmpty);
  });

  testWidgets('uppercase .M4B extension is accepted', (tester) async {
    final fake = _RecordingBookbinder(_book());
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    late BuildContext ctx;
    late WidgetRef ref0;
    await _pumpHarness(tester, container, (c, r) {
      ctx = c;
      ref0 = r;
    });

    await handleFilesDropped(ctx, ref0, const ['/Book.M4B']);
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
    expect(fake.readPaths, ['/Book.M4B']);
    expect(container.read(editorProvider).path, '/Book.M4B');
  });

  testWidgets('clean state opens immediately without dialog',
      (tester) async {
    final fake = _RecordingBookbinder(_book());
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    late BuildContext ctx;
    late WidgetRef ref0;
    await _pumpHarness(tester, container, (c, r) {
      ctx = c;
      ref0 = r;
    });

    await handleFilesDropped(ctx, ref0, const ['/new.m4b']);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(fake.readPaths, ['/new.m4b']);
    expect(container.read(editorProvider).path, '/new.m4b');
  });

  testWidgets('dirty + Discard opens new file without saving',
      (tester) async {
    final fake = _RecordingBookbinder(_book());
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/old.m4b');
    container.read(editorProvider.notifier).setTitle('Edited');

    late BuildContext ctx;
    late WidgetRef ref0;
    await _pumpHarness(tester, container, (c, r) {
      ctx = c;
      ref0 = r;
    });

    final future = handleFilesDropped(ctx, ref0, const ['/new.m4b']);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Discard'));
    await future;
    await tester.pumpAndSettle();

    expect(fake.writeCount, 0);
    expect(fake.readPaths, ['/old.m4b', '/new.m4b']);
    expect(container.read(editorProvider).path, '/new.m4b');
  });

  testWidgets('dirty + Save saves then opens new file', (tester) async {
    final fake = _RecordingBookbinder(_book());
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/old.m4b');
    container.read(editorProvider.notifier).setTitle('Edited');

    late BuildContext ctx;
    late WidgetRef ref0;
    await _pumpHarness(tester, container, (c, r) {
      ctx = c;
      ref0 = r;
    });

    final future = handleFilesDropped(ctx, ref0, const ['/new.m4b']);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await future;
    await tester.pumpAndSettle();

    expect(fake.writeCount, 1);
    expect(container.read(editorProvider).path, '/new.m4b');
  });

  testWidgets('dirty + Cancel keeps current book', (tester) async {
    final fake = _RecordingBookbinder(_book());
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/old.m4b');
    container.read(editorProvider.notifier).setTitle('Edited');

    late BuildContext ctx;
    late WidgetRef ref0;
    await _pumpHarness(tester, container, (c, r) {
      ctx = c;
      ref0 = r;
    });

    final future = handleFilesDropped(ctx, ref0, const ['/new.m4b']);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await future;
    await tester.pumpAndSettle();

    expect(fake.writeCount, 0);
    expect(fake.readPaths, ['/old.m4b']);
    expect(container.read(editorProvider).path, '/old.m4b');
  });
}
```

- [ ] **Step 2: Run; verify failure**

Run: `flutter test test/presentation/drag_drop/handle_files_dropped_test.dart`
Expected: compile error — `handleFilesDropped` doesn't exist.

- [ ] **Step 3: Implement `handleFilesDropped`**

Create `lib/presentation/drag_drop/handle_files_dropped.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/editor_state.dart';
import 'dirty_check.dart';

/// Validates a dropped payload and, if it's a single .m4b file,
/// runs the dirty-check and opens the file.
///
/// Validation order (first match wins):
///   1. paths.length != 1  → SnackBar "Drop only one .m4b file at a time"
///   2. extension != .m4b   → SnackBar "Only .m4b files can be opened"
///   3. otherwise           → confirmReplaceCurrentBook → editor.open
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

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
```

- [ ] **Step 4: Run tests; verify pass**

Run: `flutter test test/presentation/drag_drop/handle_files_dropped_test.dart`
Expected: 8 passing tests.

- [ ] **Step 5: Run full suite**

Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/drag_drop/handle_files_dropped.dart test/presentation/drag_drop/handle_files_dropped_test.dart
git commit --no-gpg-sign -m "$(cat <<'EOF'
Add handleFilesDropped validation and open routing

Validates dropped payloads (single .m4b only), shows a SnackBar with a
specific message for invalid drops, runs the dirty-check helper, and
opens the file via the editor notifier on a valid drop.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Add `DragDropOverlay` widget

UI shell that subscribes to the channel, drives the overlay, and routes drop events into `handleFilesDropped`.

**Files:**
- Create: `lib/presentation/drag_drop/drag_drop_overlay.dart`
- Create: `test/presentation/drag_drop/drag_drop_overlay_test.dart`

- [ ] **Step 1: Write failing widget tests**

Create `test/presentation/drag_drop/drag_drop_overlay_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/bookbinder.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
import 'package:m4b_chapterizer/presentation/drag_drop/drag_drop_channel.dart';
import 'package:m4b_chapterizer/presentation/drag_drop/drag_drop_overlay.dart';
import 'package:m4b_chapterizer/presentation/providers/editor_state.dart';

class _FakeChannel implements DragDropChannel {
  final _controller = StreamController<DragEvent>.broadcast();
  @override
  Stream<DragEvent> get events => _controller.stream;
  void send(DragEvent event) => _controller.add(event);
  Future<void> dispose() => _controller.close();
}

class _StubBookbinder implements Bookbinder {
  @override
  Future<Audiobook> read(String sourcePath) async => Audiobook.validated(
        chapters: const [Chapter(title: 'C', start: Duration.zero)],
        totalDuration: const Duration(seconds: 10),
      );
  @override
  Future<void> write({
    required String sourcePath,
    required String destinationPath,
    required Audiobook audiobook,
  }) async {}
}

const _kOverlayText = 'Drop .m4b file here to open';

Future<void> _pump(
  WidgetTester tester,
  _FakeChannel channel,
  ProviderContainer container,
) async {
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: Scaffold(
        body: DragDropOverlay(child: Center(child: Text('body'))),
      ),
    ),
  ));
}

void main() {
  testWidgets('no overlay when not dragging', (tester) async {
    final channel = _FakeChannel();
    final container = ProviderContainer(overrides: [
      dragDropChannelProvider.overrideWithValue(channel),
      bookbinderProvider.overrideWithValue(_StubBookbinder()),
    ]);
    addTearDown(() async {
      await channel.dispose();
      container.dispose();
    });

    await _pump(tester, channel, container);

    expect(find.text(_kOverlayText), findsNothing);
    expect(find.text('body'), findsOneWidget);
  });

  testWidgets('DragEntered shows the overlay', (tester) async {
    final channel = _FakeChannel();
    final container = ProviderContainer(overrides: [
      dragDropChannelProvider.overrideWithValue(channel),
      bookbinderProvider.overrideWithValue(_StubBookbinder()),
    ]);
    addTearDown(() async {
      await channel.dispose();
      container.dispose();
    });

    await _pump(tester, channel, container);
    channel.send(const DragEntered());
    await tester.pump();

    expect(find.text(_kOverlayText), findsOneWidget);
  });

  testWidgets('DragExited hides the overlay', (tester) async {
    final channel = _FakeChannel();
    final container = ProviderContainer(overrides: [
      dragDropChannelProvider.overrideWithValue(channel),
      bookbinderProvider.overrideWithValue(_StubBookbinder()),
    ]);
    addTearDown(() async {
      await channel.dispose();
      container.dispose();
    });

    await _pump(tester, channel, container);
    channel.send(const DragEntered());
    await tester.pump();
    channel.send(const DragExited());
    await tester.pump();

    expect(find.text(_kOverlayText), findsNothing);
  });

  testWidgets('FilesDropped hides overlay and opens the file',
      (tester) async {
    final channel = _FakeChannel();
    final container = ProviderContainer(overrides: [
      dragDropChannelProvider.overrideWithValue(channel),
      bookbinderProvider.overrideWithValue(_StubBookbinder()),
    ]);
    addTearDown(() async {
      await channel.dispose();
      container.dispose();
    });

    await _pump(tester, channel, container);
    channel.send(const DragEntered());
    await tester.pump();
    channel.send(const FilesDropped(['/tmp/book.m4b']));
    await tester.pumpAndSettle();

    expect(find.text(_kOverlayText), findsNothing);
    expect(container.read(editorProvider).path, '/tmp/book.m4b');
  });

  testWidgets('FilesDropped with non-m4b shows snack and does not open',
      (tester) async {
    final channel = _FakeChannel();
    final container = ProviderContainer(overrides: [
      dragDropChannelProvider.overrideWithValue(channel),
      bookbinderProvider.overrideWithValue(_StubBookbinder()),
    ]);
    addTearDown(() async {
      await channel.dispose();
      container.dispose();
    });

    await _pump(tester, channel, container);
    channel.send(const DragEntered());
    await tester.pump();
    channel.send(const FilesDropped(['/tmp/note.txt']));
    await tester.pumpAndSettle();

    expect(find.text('Only .m4b files can be opened'), findsOneWidget);
    expect(container.read(editorProvider).path, isNull);
  });
}
```

- [ ] **Step 2: Run; verify failure**

Run: `flutter test test/presentation/drag_drop/drag_drop_overlay_test.dart`
Expected: compile error — `DragDropOverlay` doesn't exist.

- [ ] **Step 3: Implement `DragDropOverlay`**

Create `lib/presentation/drag_drop/drag_drop_overlay.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'drag_drop_channel.dart';
import 'handle_files_dropped.dart';

/// True while the user is dragging a payload over the window.
final isDragOverProvider = StateProvider<bool>((ref) => false);

/// Wraps [child] and overlays a "Drop .m4b file here to open" panel
/// while the user is dragging files over the window. Routes drop
/// events to [handleFilesDropped].
class DragDropOverlay extends ConsumerStatefulWidget {
  const DragDropOverlay({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DragDropOverlay> createState() => _DragDropOverlayState();
}

class _DragDropOverlayState extends ConsumerState<DragDropOverlay> {
  StreamSubscription<DragEvent>? _sub;

  @override
  void initState() {
    super.initState();
    final channel = ref.read(dragDropChannelProvider);
    _sub = channel.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onEvent(DragEvent event) {
    if (!mounted) return;
    switch (event) {
      case DragEntered():
        ref.read(isDragOverProvider.notifier).state = true;
      case DragExited():
        ref.read(isDragOverProvider.notifier).state = false;
      case FilesDropped(:final paths):
        ref.read(isDragOverProvider.notifier).state = false;
        // Don't await — we want to return control to the stream
        // immediately. handleFilesDropped manages its own dialog state.
        handleFilesDropped(context, ref, paths);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDragOver = ref.watch(isDragOverProvider);
    return Stack(
      children: [
        widget.child,
        if (isDragOver)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: Colors.black.withValues(alpha: 0.35),
                alignment: Alignment.center,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.file_download, size: 48),
                        SizedBox(height: 12),
                        Text(
                          'Drop .m4b file here to open',
                          style: TextStyle(fontSize: 18),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run tests; verify pass**

Run: `flutter test test/presentation/drag_drop/drag_drop_overlay_test.dart`
Expected: 5 passing tests.

- [ ] **Step 5: Run full suite + analyzer**

Run: `flutter test`
Run: `flutter analyze`
Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/drag_drop/drag_drop_overlay.dart test/presentation/drag_drop/drag_drop_overlay_test.dart
git commit --no-gpg-sign -m "$(cat <<'EOF'
Add DragDropOverlay widget

Wraps the editor body, listens to DragDropChannel events, paints the
'Drop .m4b file here to open' overlay during drag, and routes drop
events to handleFilesDropped.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Implement `MethodChannelDragDropChannel`

The platform-glue impl. Coverage-ignored: OS event delivery is exercised by smoke tests, not unit tests.

**Files:**
- Modify: `lib/presentation/drag_drop/drag_drop_channel.dart`

- [ ] **Step 1: Append the impl class to `drag_drop_channel.dart`**

Edit `lib/presentation/drag_drop/drag_drop_channel.dart`. Add at the top of the file, alongside the existing imports:

```dart
import 'dart:async';

import 'package:flutter/services.dart';
```

Then append after the existing `dragDropChannelProvider` declaration:

```dart
// coverage:ignore-start
// Production implementation. The platform side (Swift on macOS, future
// C++ on Windows, GTK on Linux) sends three method calls over this
// channel: 'dragEntered' (no args), 'dragExited' (no args), and
// 'filesDropped' with `paths: List<String>`. Exercised only by smoke
// tests on a real desktop build.

/// Platform-channel-backed drag-drop event stream.
class MethodChannelDragDropChannel implements DragDropChannel {
  MethodChannelDragDropChannel({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('m4b_chapterizer/drag_drop') {
    _channel.setMethodCallHandler(_onCall);
  }

  final MethodChannel _channel;
  final StreamController<DragEvent> _controller =
      StreamController<DragEvent>.broadcast();

  @override
  Stream<DragEvent> get events => _controller.stream;

  Future<void> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'dragEntered':
        _controller.add(const DragEntered());
      case 'dragExited':
        _controller.add(const DragExited());
      case 'filesDropped':
        final raw = (call.arguments as Map?)?['paths'] as List? ?? const [];
        _controller.add(FilesDropped(raw.cast<String>()));
    }
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    _controller.close();
  }
}
// coverage:ignore-end
```

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze`
Expected: no issues.

- [ ] **Step 3: Run tests**

Run: `flutter test`
Expected: all tests pass (the impl is unused so far; tests still go through the fake).

- [ ] **Step 4: Commit**

```bash
git add lib/presentation/drag_drop/drag_drop_channel.dart
git commit --no-gpg-sign -m "$(cat <<'EOF'
Add MethodChannelDragDropChannel implementation

Production impl that listens on the m4b_chapterizer/drag_drop
MethodChannel for dragEntered/dragExited/filesDropped from the native
side and emits DragEvents on a broadcast stream. Coverage-ignored;
exercised only by smoke tests on a real desktop build.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Wire `DragDropOverlay` into the editor screen

**Files:**
- Modify: `lib/presentation/screens/editor_screen.dart`

- [ ] **Step 1: Wrap `Scaffold.body` in `DragDropOverlay`**

Edit `lib/presentation/screens/editor_screen.dart`. Add the import:

```dart
import '../drag_drop/drag_drop_overlay.dart';
```

Replace the existing `body:` argument of the `Scaffold` (the conditional that picks between the empty-state `Center` and the populated `Column`) by wrapping its expression in `DragDropOverlay(child: ...)`. Concretely the new shape is:

```dart
body: DragDropOverlay(
  child: state.audiobook == null
      ? const Center(child: Text('Open an .m4b file to begin'))
      : const Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: 280,
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          CoverPanel(),
                          MetadataForm(),
                        ],
                      ),
                    ),
                  ),
                  VerticalDivider(width: 1),
                  Expanded(child: ChapterList()),
                ],
              ),
            ),
            Divider(height: 1),
            PlaybackControls(),
          ],
        ),
),
```

The AppBar stays outside the overlay — dragging onto the title bar will not trigger the overlay (the body is the drop region).

- [ ] **Step 2: Update `editor_screen_test.dart` if necessary**

Run: `flutter test test/presentation/editor_screen_test.dart`

If the test fails because `dragDropChannelProvider` isn't overridden, edit the test setup to add a fake channel override. Specifically: import `drag_drop_channel.dart` and add `dragDropChannelProvider.overrideWithValue(_StubChannel())` to each test's `ProviderContainer` / `ProviderScope`. The fake can be:

```dart
class _StubChannel implements DragDropChannel {
  @override
  Stream<DragEvent> get events => const Stream.empty();
}
```

Add this class once near the top of the file and reuse it.

- [ ] **Step 3: Run full suite + analyzer**

Run: `flutter test`
Run: `flutter analyze`
Expected: all green.

- [ ] **Step 4: Commit**

```bash
git add lib/presentation/screens/editor_screen.dart test/presentation/editor_screen_test.dart
git commit --no-gpg-sign -m "$(cat <<'EOF'
Wire DragDropOverlay into the editor screen

Wraps Scaffold.body so the drop region covers the whole content area
below the AppBar.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Override `dragDropChannelProvider` in `main.dart`

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Add the override**

Replace `lib/main.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/bundled_binary_resolver.dart';
import 'data/ffmpeg_bookbinder.dart';
import 'data/process_runner.dart';
import 'presentation/app.dart';
import 'presentation/drag_drop/drag_drop_channel.dart';
import 'presentation/providers/editor_state.dart';

void main() {
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
        dragDropChannelProvider.overrideWithValue(
          MethodChannelDragDropChannel(),
        ),
      ],
      child: const M4bChapterizerApp(),
    ),
  );
}
```

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze`
Expected: no issues. (`main.dart` is excluded from coverage by the existing config; no test changes needed.)

- [ ] **Step 3: Commit**

```bash
git add lib/main.dart
git commit --no-gpg-sign -m "$(cat <<'EOF'
Wire MethodChannelDragDropChannel at app startup

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Implement macOS native drag-drop in `MainFlutterWindow.swift`

Implement `NSDraggingDestination` and post events over the `m4b_chapterizer/drag_drop` channel.

**Files:**
- Modify: `macos/Runner/MainFlutterWindow.swift`

- [ ] **Step 1: Replace `MainFlutterWindow.swift` with the drag-aware version**

Replace the entire file `macos/Runner/MainFlutterWindow.swift` with:

```swift
import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  // Holds a reference to the drag-drop channel so it isn't deallocated
  // while the window is alive.
  private var dragDropChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Become our own NSWindowDelegate so we can intercept the red-X
    // close. Without this the window would close before Flutter's
    // didRequestAppExit got a chance to show its unsaved-changes dialog,
    // leaving the app running with no visible window.
    self.delegate = self

    // Minimum window size: keep the chapter list's Add / Delete / Match
    // Playhead OverflowBar on a single line. Below ~578px the
    // OverflowBar wraps the buttons to a column, which looks crowded.
    // This also comfortably exceeds the chapter row's natural minimum
    // (cover panel 280 + divider 1 + ~142 row minimum = 423), so the
    // earlier RenderFlex overflow at narrow widths is also prevented.
    self.minSize = NSSize(width: 578, height: 300)

    // Drag-and-drop file open. We register the *window* as the dragging
    // destination so the entire window — including the empty-state
    // body — accepts file drags. Events are forwarded to Dart over a
    // MethodChannel; Dart handles validation and the unsaved-changes
    // prompt.
    self.registerForDraggedTypes([.fileURL])
    self.dragDropChannel = FlutterMethodChannel(
      name: "m4b_chapterizer/drag_drop",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  // Convert a window-close click into an application-terminate request.
  // Flutter's macOS embedder routes applicationShouldTerminate to
  // didRequestAppExit on the Dart side, where our WindowCloseGuard runs
  // the unsaved-changes dialog and returns AppExitResponse.exit or
  // .cancel. We return `false` here so the window stays open while the
  // dialog is up; if the user picks Discard or Save, NSApplication
  // terminates and the window goes away naturally.
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    NSApplication.shared.terminate(nil)
    return false
  }

  // MARK: - NSDraggingDestination

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    dragDropChannel?.invokeMethod("dragEntered", arguments: nil)
    return .copy
  }

  override func draggingExited(_ sender: NSDraggingInfo?) {
    dragDropChannel?.invokeMethod("dragExited", arguments: nil)
  }

  override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
    return true
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let pasteboard = sender.draggingPasteboard
    let urls = pasteboard.readObjects(
      forClasses: [NSURL.self], options: nil
    ) as? [URL] ?? []
    let paths = urls.map { $0.path }
    dragDropChannel?.invokeMethod(
      "filesDropped", arguments: ["paths": paths]
    )
    return true
  }
}
```

- [ ] **Step 2: Build the macOS app to verify the Swift compiles**

Run: `flutter build macos --debug`
Expected: build succeeds with no Swift compiler errors.

- [ ] **Step 3: Commit**

```bash
git add macos/Runner/MainFlutterWindow.swift
git commit --no-gpg-sign -m "$(cat <<'EOF'
Implement macOS drag-drop file open

MainFlutterWindow now registers as an NSDraggingDestination for file
URLs and posts dragEntered/dragExited/filesDropped events over a new
m4b_chapterizer/drag_drop MethodChannel. The Dart side handles
validation and the unsaved-changes prompt.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 4: Smoke test (manual, post-merge)**

Launch the macOS app: `flutter run -d macos`. Then walk through the smoke-test plan in the spec (`docs/superpowers/specs/2026-05-03-drag-drop-open-design.md`, "Smoke-test plan" section, ten cases).

---

## Task 11: Add Windows / Linux drop entries to `TODO.md`

**Files:**
- Modify: `TODO.md`

- [ ] **Step 1: Append new bullets under "Cross-platform desktop polish"**

Edit `TODO.md`. Locate the existing line:

```markdown
- [ ] **Set the window minimum size on Windows and Linux** to match macOS's 423×300. macOS uses `self.minSize` in `MainFlutterWindow.swift`; Windows uses `WM_GETMINMAXINFO` in `windows/runner/flutter_window.cpp`; Linux uses `gtk_widget_set_size_request` (or `gtk_window_set_geometry_hints`) in `linux/my_application.cc`.
```

Append directly after it:

```markdown
- [ ] **Implement drag-and-drop file open on Windows** — `windows/runner/flutter_window.cpp` registers an `IDropTarget` (or uses `DragAcceptFiles` + `WM_DROPFILES`) and posts `dragEntered` / `dragExited` / `filesDropped` over the existing `m4b_chapterizer/drag_drop` MethodChannel. Dart-side validation already lives in `lib/presentation/drag_drop/handle_files_dropped.dart`.
- [ ] **Implement drag-and-drop file open on Linux** — `linux/my_application.cc` wires GTK `drag-data-received` / `drag-motion` / `drag-leave` and posts the same three events on the same channel.
```

- [ ] **Step 2: Commit**

```bash
git add TODO.md
git commit --no-gpg-sign -m "$(cat <<'EOF'
Track Windows/Linux drag-drop equivalents in TODO.md

The Dart side of the drag-drop feature is platform-agnostic; only the
native event source needs to be added on Windows and Linux.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Verification

After all tasks land:

- [ ] **Final test run**

Run: `flutter test`
Expected: all tests pass; no flakes.

- [ ] **Final analyzer run**

Run: `flutter analyze`
Expected: no issues.

- [ ] **Coverage check**

Run: `flutter test --coverage`
Run: `dart tool/coverage_summary.dart coverage/lcov.info`
Expected: filtered total stays at or above the previous baseline (~98%).

- [ ] **Manual smoke test on macOS** — walk through the ten smoke-test cases in the spec.
