# Exit Confirmation When Dirty — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Confirm before quitting when the editor has unsaved changes. Three-button dialog (Cancel / Discard / Save).

**Architecture:** A pure-Dart `handleExitRequest(context, ref) → bool` is the testable core. A `WindowCloseGuard` widget bridges to `window_manager`'s OS-level close event and is `coverage:ignore`'d.

**Tech Stack:** `window_manager: ^0.4.0` for cross-desktop window close interception.

**Reference design:** `docs/superpowers/specs/2026-05-02-exit-confirmation-design.md`

**Conventions:** `--no-gpg-sign` REQUIRED on every commit. Run `flutter test`, `flutter analyze`, and `dart run tool/coverage_summary.dart` before each commit.

---

## Task 1: Add `window_manager`, write `handleExitRequest` + dialog

**Files:**
- Create: `lib/presentation/exit_confirmation.dart`
- Create: `test/presentation/exit_confirmation_test.dart`
- Modify: `pubspec.yaml`

### Step 1: Add the dependency

Edit `pubspec.yaml`. Under `dependencies:` add:

```yaml
  window_manager: ^0.4.0
```

Run:

```bash
flutter pub get
```

Expected: `window_manager` resolves cleanly. (Should bring in transitive `screen_retriever` and platform-specific channels.)

### Step 2: Write the failing tests

Create `test/presentation/exit_confirmation_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/bookbinder.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
import 'package:m4b_chapterizer/presentation/exit_confirmation.dart';
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

/// Pumps a widget that exposes a button which calls [handleExitRequest] and
/// stores the result in a closure. Returns a getter so the test can read
/// the value after later interactions.
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
              captured = await handleExitRequest(context, ref);
            },
            child: const Text('exit'),
          );
        }),
      ),
    ),
  ));
  return () => captured;
}

void main() {
  test('ExitDecision values are exhaustive', () {
    expect(ExitDecision.values,
        [ExitDecision.cancel, ExitDecision.discard, ExitDecision.save]);
  });

  testWidgets('returns true immediately when not dirty', (tester) async {
    final fake = _RecordingBookbinder(_book());
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/tmp/x.m4b');

    final getResult = await _pumpHarness(tester, container);
    await tester.tap(find.text('exit'));
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
    expect(container.read(editorProvider).isDirty, isTrue);

    final getResult = await _pumpHarness(tester, container);
    await tester.tap(find.text('exit'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(getResult(), isFalse);
    expect(fake.writeCount, 0);
  });

  testWidgets('returns true and does NOT save when user picks Discard',
      (tester) async {
    final fake = _RecordingBookbinder(_book());
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/tmp/x.m4b');
    container.read(editorProvider.notifier).setTitle('Edited');

    final getResult = await _pumpHarness(tester, container);
    await tester.tap(find.text('exit'));
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
    await tester.tap(find.text('exit'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(getResult(), isTrue);
    expect(fake.writeCount, 1);
    expect(fake.lastWritten?.title, 'Edited');
  });
}
```

### Step 3: Run tests, see failures

Run: `flutter test test/presentation/exit_confirmation_test.dart`
Expected: FAIL — `exit_confirmation.dart` doesn't exist; `handleExitRequest` and `ExitDecision` are undefined.

### Step 4: Implement `exit_confirmation.dart`

Create `lib/presentation/exit_confirmation.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'providers/editor_state.dart';

enum ExitDecision { cancel, discard, save }

/// Shows the unsaved-changes confirm dialog. Returns the user's pick,
/// or null if the dialog cannot be shown.
Future<ExitDecision?> showExitConfirmDialog(BuildContext context) {
  return showDialog<ExitDecision>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Unsaved changes'),
      content: const Text(
        'Do you want to save your changes before exiting?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(ExitDecision.cancel),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(ExitDecision.discard),
          child: const Text('Discard'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(ExitDecision.save),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

/// True if the application should proceed with closing.
///
/// Fast path: if the editor isn't dirty, returns true without showing a
/// dialog. Otherwise shows [showExitConfirmDialog] and:
/// - Cancel / dismissed → false
/// - Discard → true
/// - Save → awaits the editor's save, then true
Future<bool> handleExitRequest(BuildContext context, WidgetRef ref) async {
  final state = ref.read(editorProvider);
  if (!state.isDirty) return true;

  final decision = await showExitConfirmDialog(context);
  switch (decision) {
    case ExitDecision.discard:
      return true;
    case ExitDecision.save:
      await ref.read(editorProvider.notifier).save();
      return true;
    case ExitDecision.cancel:
    case null:
      return false;
  }
}

// coverage:ignore-start
// Window-manager glue. The OS-level close event is delivered through a
// platform method channel that isn't exercised by `flutter test`; this
// widget is exercised only by smoke tests on a real desktop build. The
// testable logic is in [handleExitRequest] above.

/// Wraps [child] and intercepts OS window-close attempts (red X, Cmd+W,
/// Cmd+Q). On close, calls [handleExitRequest] and either destroys the
/// window or stays.
class WindowCloseGuard extends ConsumerStatefulWidget {
  const WindowCloseGuard({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WindowCloseGuard> createState() => _WindowCloseGuardState();
}

class _WindowCloseGuardState extends ConsumerState<WindowCloseGuard>
    with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Future<void> onWindowClose() async {
    if (!mounted) return;
    final shouldExit = await handleExitRequest(context, ref);
    if (shouldExit) {
      await windowManager.destroy();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
// coverage:ignore-end
```

### Step 5: Run tests, verify pass

Run: `flutter test test/presentation/exit_confirmation_test.dart`
Expected: 5 tests pass.

Run: `flutter test`
Expected: all tests pass (existing + 5 new).

### Step 6: Run analyzer

Run: `flutter analyze`
Expected: `No issues found!`

### Step 7: Commit

```bash
git add lib/presentation/exit_confirmation.dart test/presentation/exit_confirmation_test.dart pubspec.yaml pubspec.lock
git commit --no-gpg-sign -m "Add exit-confirmation dialog with save-before-exit"
```

---

## Task 2: Wire `WindowCloseGuard` into `main.dart`

**Files:**
- Modify: `lib/main.dart`

### Step 1: Update `main()` to initialize window_manager and wrap the app

Open `lib/main.dart`. Replace the existing `main()` function with:

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

Add the imports at the top of the file:

```dart
import 'package:window_manager/window_manager.dart';

import 'presentation/exit_confirmation.dart';
```

### Step 2: Verify the build works on macOS

Run:

```bash
flutter build macos --debug
```

Expected: build succeeds. The `window_manager` package's macOS plugin auto-registers via `GeneratedPluginRegistrant.swift`. If a manual Podfile or Package.swift adjustment is needed (unlikely for a 2026-era release), the build error will name it explicitly; resolve and retry.

### Step 3: Verify tests still pass

Run: `flutter test`
Expected: all tests pass.

Run: `flutter analyze`
Expected: clean.

Run: `dart run tool/coverage_summary.dart` (after `flutter test --coverage`)
Expected: filtered coverage stays around 98–99%. The new file's `coverage:ignore-start`/`-end` block on `WindowCloseGuard` keeps that thin wrapper out of the denominator.

### Step 4: Commit

```bash
git add lib/main.dart
git commit --no-gpg-sign -m "Wrap app in WindowCloseGuard to prompt on dirty exit"
```

---

## Final verification

- [ ] `flutter test` — all tests pass.
- [ ] `flutter analyze` — clean.
- [ ] `dart run tool/coverage_summary.dart` — filtered coverage at or near the prior baseline.
- [ ] macOS smoke test:
  - Open the fixture m4b. Edit the title. Click the red X (or `⌘W`).
  - Dialog appears. Cancel keeps the window open.
  - Click X again, choose Discard. App quits without writing.
  - Reopen, edit, click X, choose Save. App writes the file and quits. Reopen and confirm the title is the edited value.
  - Open a fresh book, make no changes, click X. App quits with no dialog.
