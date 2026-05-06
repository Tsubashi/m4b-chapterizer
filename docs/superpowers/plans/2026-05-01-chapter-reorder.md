# Chapter Reorder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the user changes a chapter's start time, automatically reorder the chapter list by start; clamp out-of-bounds values; surface duplicate / first-must-be-zero violations as snackbars.

**Architecture:** `EditorNotifier.setChapterStart` becomes a function returning `SetChapterStartError?`. It clamps, sorts, validates, commits — and updates the selection if the originally-edited chapter moved. The chapter row widget surfaces a snackbar on rejection and reverts the field text. `Audiobook` invariants are unchanged.

**Tech Stack:** No new packages.

**Reference design:** `docs/superpowers/specs/2026-05-01-chapter-reorder-design.md`

**Conventions:**
- `--no-gpg-sign` REQUIRED on every `git commit`.
- Run `flutter test` and `flutter analyze` before each commit.

---

## Task 1: New `setChapterStart` semantics in `EditorNotifier`

Rewrites the method to clamp, sort, validate, and return an error code on rejection. All five domain-level behaviors covered by unit tests.

**Files:**
- Modify: `lib/presentation/providers/editor_state.dart`
- Modify: `test/presentation/editor_state_test.dart`

- [ ] **Step 1: Append failing tests**

Append to the end of `test/presentation/editor_state_test.dart`'s `main()` (after the existing tests):

```dart
  group('setChapterStart reorder & clamp', () {
    Audiobook threeChapterBook() => Audiobook.validated(
          chapters: const [
            Chapter(title: 'First', start: Duration.zero),
            Chapter(title: 'Second', start: Duration(seconds: 10)),
            Chapter(title: 'Third', start: Duration(seconds: 20)),
          ],
          totalDuration: const Duration(seconds: 30),
        );

    test('reorders the list when a new start breaks order; selection follows',
        () async {
      final fake = _FakeBookbinder(threeChapterBook());
      final container = makeContainer(fake);
      addTearDown(container.dispose);
      await container.read(editorProvider.notifier).open('/tmp/x.m4b');
      container.read(selectedChapterProvider.notifier).state = 1;

      final error = container
          .read(editorProvider.notifier)
          .setChapterStart(1, const Duration(seconds: 25));

      expect(error, isNull);
      final book = container.read(editorProvider).audiobook!;
      expect(book.chapters.map((c) => c.title).toList(),
          ['First', 'Third', 'Second']);
      expect(book.chapters[2].start, const Duration(seconds: 25));
      expect(container.read(selectedChapterProvider), 2);
    });

    test('clamps a negative start to zero (which then triggers duplicate)',
        () async {
      final fake = _FakeBookbinder(threeChapterBook());
      final container = makeContainer(fake);
      addTearDown(container.dispose);
      await container.read(editorProvider.notifier).open('/tmp/x.m4b');
      final stateBefore = container.read(editorProvider).audiobook;

      final error = container
          .read(editorProvider.notifier)
          .setChapterStart(1, const Duration(seconds: -5));

      expect(error, SetChapterStartError.duplicate);
      expect(identical(stateBefore, container.read(editorProvider).audiobook),
          isTrue);
    });

    test('clamps a beyond-total start to totalDuration - 1ms', () async {
      final fake = _FakeBookbinder(threeChapterBook());
      final container = makeContainer(fake);
      addTearDown(container.dispose);
      await container.read(editorProvider.notifier).open('/tmp/x.m4b');

      final error = container
          .read(editorProvider.notifier)
          .setChapterStart(1, const Duration(seconds: 9999));

      expect(error, isNull);
      final book = container.read(editorProvider).audiobook!;
      // Chapter "Second" is now at the end, clamped to 30s - 1ms.
      final movedChapter =
          book.chapters.firstWhere((c) => c.title == 'Second');
      expect(movedChapter.start, const Duration(milliseconds: 29999));
    });

    test('rejects with duplicate error and leaves state unchanged',
        () async {
      final fake = _FakeBookbinder(threeChapterBook());
      final container = makeContainer(fake);
      addTearDown(container.dispose);
      await container.read(editorProvider.notifier).open('/tmp/x.m4b');
      final stateBefore = container.read(editorProvider).audiobook;

      final error = container
          .read(editorProvider.notifier)
          .setChapterStart(1, Duration.zero);

      expect(error, SetChapterStartError.duplicate);
      expect(identical(stateBefore, container.read(editorProvider).audiobook),
          isTrue);
    });

    test('rejects with firstNotZero error when chapter 0 is moved off zero',
        () async {
      final fake = _FakeBookbinder(threeChapterBook());
      final container = makeContainer(fake);
      addTearDown(container.dispose);
      await container.read(editorProvider.notifier).open('/tmp/x.m4b');
      final stateBefore = container.read(editorProvider).audiobook;

      final error = container
          .read(editorProvider.notifier)
          .setChapterStart(0, const Duration(seconds: 5));

      expect(error, SetChapterStartError.firstNotZero);
      expect(identical(stateBefore, container.read(editorProvider).audiobook),
          isTrue);
    });

    test('selection follows only the moved chapter, not the original index',
        () async {
      final fake = _FakeBookbinder(threeChapterBook());
      final container = makeContainer(fake);
      addTearDown(container.dispose);
      await container.read(editorProvider.notifier).open('/tmp/x.m4b');
      container.read(selectedChapterProvider.notifier).state = 0;

      // Move chapter 1 (not the selected one) past chapter 2.
      final error = container
          .read(editorProvider.notifier)
          .setChapterStart(1, const Duration(seconds: 25));

      expect(error, isNull);
      // Selection stays at 0 because we did not edit the selected chapter.
      expect(container.read(selectedChapterProvider), 0);
    });
  });
```

This block uses helpers (`makeContainer`, `_FakeBookbinder`) that already exist in the file. Verify they do; if `makeContainer` is named differently, use the existing equivalent.

- [ ] **Step 2: Run, see failures**

Run: `flutter test test/presentation/editor_state_test.dart`
Expected: 6 new failures — `SetChapterStartError` is undefined; existing `setChapterStart` returns `void`.

- [ ] **Step 3: Replace `setChapterStart` and add the error enum**

Open `lib/presentation/providers/editor_state.dart`. Add this enum (above the `EditorNotifier` class, below the imports):

```dart
enum SetChapterStartError { duplicate, firstNotZero }
```

Replace the existing `setChapterStart` method body with:

```dart
  SetChapterStartError? setChapterStart(int index, Duration start) {
    final book = state.audiobook;
    if (book == null) return null;

    // 1. Clamp into [0, totalDuration - 1ms].
    final maxAllowed = book.totalDuration - const Duration(milliseconds: 1);
    Duration clamped = start;
    if (clamped < Duration.zero) clamped = Duration.zero;
    if (clamped > maxAllowed) clamped = maxAllowed;

    // 2. Build candidate, capturing the new chapter instance for identity tracking.
    final movedChapter = book.chapters[index].copyWith(start: clamped);
    final candidate = [...book.chapters];
    candidate[index] = movedChapter;

    // 3. Sort by start.
    candidate.sort((a, b) => a.start.compareTo(b.start));

    // 4. Validate invariants.
    for (var i = 1; i < candidate.length; i++) {
      if (candidate[i].start == candidate[i - 1].start) {
        return SetChapterStartError.duplicate;
      }
    }
    if (candidate.first.start != Duration.zero) {
      return SetChapterStartError.firstNotZero;
    }

    // 5. Commit.
    final newBook = Audiobook.validated(
      title: book.title,
      author: book.author,
      narrator: book.narrator,
      album: book.album,
      genre: book.genre,
      description: book.description,
      year: book.year,
      cover: book.cover,
      chapters: candidate,
      totalDuration: book.totalDuration,
    );
    state = state.copyWith(audiobook: newBook, isDirty: true);

    // 6. Update selection if the moved chapter is the selected one and its
    //    index changed.
    final currentlySelected = ref.read(selectedChapterProvider);
    if (currentlySelected == index) {
      final newIndex =
          candidate.indexWhere((c) => identical(c, movedChapter));
      if (newIndex >= 0 && newIndex != index) {
        ref.read(selectedChapterProvider.notifier).state = newIndex;
      }
    }
    return null;
  }
```

Notes for the implementer:
- `selectedChapterProvider` is defined in `lib/presentation/widgets/chapter_list.dart`. Add the import at the top of `editor_state.dart`:
  ```dart
  import '../widgets/chapter_list.dart' show selectedChapterProvider;
  ```
- The previous implementation called `Audiobook.validated(...)` and let `ArgumentError` propagate. Removing that path is intentional — all rejection now flows through the `SetChapterStartError` return value.

- [ ] **Step 4: Run tests**

Run: `flutter test test/presentation/editor_state_test.dart`
Expected: all tests pass (existing + 6 new).

- [ ] **Step 5: Run analyzer**

Run: `flutter analyze`
Expected: `No issues found!`. If a circular-import warning appears (provider <-> widgets), move `selectedChapterProvider` definition into `lib/presentation/providers/playback.dart` or create `lib/presentation/providers/chapter_selection.dart` and update imports in `chapter_list.dart` accordingly. Adjust this task's import line if you make that move.

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/providers/editor_state.dart test/presentation/editor_state_test.dart
git commit --no-gpg-sign -m "Reorder chapters in setChapterStart; surface invariant violations as enum"
```

---

## Task 2: Snackbar feedback in chapter row

Wire the new `SetChapterStartError?` return into `_ChapterRow`'s start-time submit handler. Show a snackbar and revert the field on rejection.

**Files:**
- Modify: `lib/presentation/widgets/chapter_list.dart`
- Modify: `test/presentation/chapter_list_test.dart`

- [ ] **Step 1: Append failing tests**

Append to `test/presentation/chapter_list_test.dart`'s `main()`:

```dart
  testWidgets('shows snackbar and reverts field on duplicate start', (tester) async {
    final container = await _setUp(tester);

    // Chapter 0 is at 00:00.000. Try to set chapter 1's start to the same.
    final startField = find.byKey(const ValueKey('chapters.start.1'));
    await tester.tap(startField);
    await tester.pump();
    await tester.enterText(startField, '00:00:00.000');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    // Snackbar visible with the duplicate message.
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('unique'), findsOneWidget);

    // The field's text reverted to the original "00:00:10.000".
    final controller =
        tester.widget<TextField>(startField).controller!;
    expect(controller.text, '00:00:10.000');

    // Audiobook state unchanged: chapter 1 still at 10s.
    expect(
      container.read(editorProvider).audiobook!.chapters[1].start,
      const Duration(seconds: 10),
    );
  });

  testWidgets('reorders rendered rows when start time moves a chapter',
      (tester) async {
    final container = await _setUp(tester);

    // Move chapter 1 ('Beta' @ 10s) to 25s, past chapter 2 (which doesn't
    // exist in this 2-chapter setup — extend to 3).
    // _setUp uses a 2-chapter book; for this test, override with a 3-chapter
    // book by re-opening with a different fake.
    // Simpler: just verify the 2-chapter case where Beta moves to 25s
    // (totalDuration 30s) which keeps it at index 1 — so we need a 3-chapter
    // setup. Override in a fresh container:
    final fake = _StubBookbinder(Audiobook.validated(
      chapters: const [
        Chapter(title: 'Alpha', start: Duration.zero),
        Chapter(title: 'Beta', start: Duration(seconds: 10)),
        Chapter(title: 'Gamma', start: Duration(seconds: 20)),
      ],
      totalDuration: const Duration(seconds: 30),
    ));
    final c = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    addTearDown(c.dispose);
    await c.read(editorProvider.notifier).open('/tmp/y.m4b');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: ChapterList())),
    ));
    await tester.pumpAndSettle();

    // Move 'Beta' (index 1) to 00:00:25.000.
    final startField = find.byKey(const ValueKey('chapters.start.1'));
    await tester.tap(startField);
    await tester.pump();
    await tester.enterText(startField, '00:00:25.000');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // Audiobook chapter order is now [Alpha, Gamma, Beta].
    expect(
      c.read(editorProvider).audiobook!.chapters.map((x) => x.title).toList(),
      ['Alpha', 'Gamma', 'Beta'],
    );

    // Suppress unused container warning.
    expect(container, isNotNull);
  });
```

Add the import for `package:flutter/services.dart` at the top of the test file if not already present (for `TextInputAction`).

- [ ] **Step 2: Run, see failures**

Run: `flutter test test/presentation/chapter_list_test.dart`
Expected: 2 new failures — current behavior throws or silently no-ops; no snackbar appears.

- [ ] **Step 3: Update the `_ChapterRow` callback signature**

In `lib/presentation/widgets/chapter_list.dart`, change `_ChapterRow`'s `onStartChanged` field type:

```dart
  final SetChapterStartError? Function(Duration) onStartChanged;
```

Add the import for the enum at the top of the file:

```dart
import '../providers/editor_state.dart' show SetChapterStartError, editorProvider;
```

(Replace the existing `import '../providers/editor_state.dart';` if present — keep both `editorProvider` and `SetChapterStartError` available.)

Replace the `onSubmitted` handler in `_ChapterRow`'s build method (the start-time `TextField`) with:

```dart
                onSubmitted: (v) {
                  Duration parsed;
                  try {
                    parsed = parseDuration(v);
                  } on FormatException {
                    _startController.text = formatDuration(widget.chapter.start);
                    return;
                  }
                  final error = widget.onStartChanged(parsed);
                  if (error != null) {
                    _startController.text = formatDuration(widget.chapter.start);
                    final messenger = ScaffoldMessenger.of(context);
                    messenger.showSnackBar(SnackBar(
                      content: Text(switch (error) {
                        SetChapterStartError.duplicate =>
                            'Chapter start times must be unique',
                        SetChapterStartError.firstNotZero =>
                            'First chapter must start at 00:00:00.000',
                      }),
                    ));
                  }
                },
```

In the parent `ChapterList`, update the call site that constructs `_ChapterRow`:

```dart
              onStartChanged: (d) => notifier.setChapterStart(i, d),
```

(The signature now matches `SetChapterStartError? Function(Duration)` automatically because `notifier.setChapterStart` now returns that.)

- [ ] **Step 4: Run tests**

Run: `flutter test test/presentation/chapter_list_test.dart`
Expected: all tests pass (existing + 2 new).

- [ ] **Step 5: Run full suite + analyzer**

Run: `flutter test`
Expected: every test passes.

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Smoke-test on macOS**

```bash
flutter run -d macos
```

Open `test/fixtures/sample.m4b`. Verify:
- Editing a chapter's start to a value past the next chapter reorders rows.
- Editing chapter 1 to `00:00:00.000` shows a snackbar and reverts the field.
- Editing chapter 0 to a non-zero time shows a snackbar and reverts.
- Editing to a negative value silently clamps; if it would dup chapter 0, snackbar.

- [ ] **Step 7: Commit**

```bash
git add lib/presentation/widgets/chapter_list.dart test/presentation/chapter_list_test.dart
git commit --no-gpg-sign -m "Show snackbar on chapter-start invariant rejections; revert field"
```

---

## Final verification

- [ ] `flutter test` — all green.
- [ ] `flutter analyze` — clean.
- [ ] macOS smoke test (above) confirms the visible behaviors.
