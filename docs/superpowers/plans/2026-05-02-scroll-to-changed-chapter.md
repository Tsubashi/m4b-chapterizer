# Focus and Scroll to Changed Chapter — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After any chapter-changing operation (add, delete, start edit, undo, redo), select the affected chapter and scroll it into view.

**Architecture:** Add a chapter-diff helper to `Audiobook`. `EditorNotifier` calls it from `undo`/`redo` and otherwise updates selection in `addChapter`/`deleteChapter`/`setChapterStart`. `ChapterList` becomes stateful with a `ScrollController` and a `ref.listen` on `selectedChapterProvider` that animates the list.

**Tech Stack:** No new packages.

**Reference design:** `docs/superpowers/specs/2026-05-02-scroll-to-changed-chapter-design.md`

**Conventions:** `--no-gpg-sign` REQUIRED on every commit. Run `flutter test` and `flutter analyze` before each commit.

---

## Task 1: `AudiobookDiff` extension

**Files:**
- Modify: `lib/domain/models/audiobook.dart`
- Modify: `test/domain/audiobook_test.dart`

### Step 1: Append failing tests

Append at the end of `test/domain/audiobook_test.dart`'s `main()`:

```dart
  group('AudiobookDiff.firstDifferingChapterIndex', () {
    Audiobook book(List<Chapter> chapters) => Audiobook.validated(
          chapters: chapters,
          totalDuration: const Duration(seconds: 100),
        );

    test('returns null when chapters are equal', () {
      final a = book(const [
        Chapter(title: 'A', start: Duration.zero),
        Chapter(title: 'B', start: Duration(seconds: 5)),
      ]);
      final b = book(const [
        Chapter(title: 'A', start: Duration.zero),
        Chapter(title: 'B', start: Duration(seconds: 5)),
      ]);
      expect(a.firstDifferingChapterIndex(b), isNull);
    });

    test('returns the index of the first differing chapter', () {
      final a = book(const [
        Chapter(title: 'A', start: Duration.zero),
        Chapter(title: 'B', start: Duration(seconds: 5)),
        Chapter(title: 'C', start: Duration(seconds: 10)),
      ]);
      final b = book(const [
        Chapter(title: 'A', start: Duration.zero),
        Chapter(title: 'BB', start: Duration(seconds: 5)),
        Chapter(title: 'C', start: Duration(seconds: 10)),
      ]);
      expect(a.firstDifferingChapterIndex(b), 1);
    });

    test('handles a longer right side (insertion at end)', () {
      final a = book(const [
        Chapter(title: 'A', start: Duration.zero),
        Chapter(title: 'B', start: Duration(seconds: 5)),
        Chapter(title: 'C', start: Duration(seconds: 10)),
      ]);
      final b = book(const [
        Chapter(title: 'A', start: Duration.zero),
        Chapter(title: 'B', start: Duration(seconds: 5)),
        Chapter(title: 'C', start: Duration(seconds: 10)),
        Chapter(title: 'D', start: Duration(seconds: 15)),
      ]);
      expect(a.firstDifferingChapterIndex(b), 3);
    });

    test('handles a shorter right side (deletion at index)', () {
      final a = book(const [
        Chapter(title: 'A', start: Duration.zero),
        Chapter(title: 'B', start: Duration(seconds: 5)),
        Chapter(title: 'C', start: Duration(seconds: 10)),
        Chapter(title: 'D', start: Duration(seconds: 15)),
      ]);
      final b = book(const [
        Chapter(title: 'A', start: Duration.zero),
        Chapter(title: 'C', start: Duration(seconds: 10)),
        Chapter(title: 'D', start: Duration(seconds: 15)),
      ]);
      expect(a.firstDifferingChapterIndex(b), 1);
    });
  });
```

### Step 2: Run, see failures

Run: `flutter test test/domain/audiobook_test.dart`
Expected: FAIL — `firstDifferingChapterIndex` undefined.

### Step 3: Implement extension

Append to `lib/domain/models/audiobook.dart`:

```dart
extension AudiobookDiff on Audiobook {
  /// Returns the index of the first chapter that differs between this and
  /// [other], using `Chapter`'s value equality. If lengths differ, the
  /// index is the shorter list's length (the first divergent slot).
  /// Returns null when every shared chapter is equal AND lengths match.
  int? firstDifferingChapterIndex(Audiobook other) {
    final n =
        chapters.length < other.chapters.length ? chapters.length : other.chapters.length;
    for (var i = 0; i < n; i++) {
      if (chapters[i] != other.chapters[i]) return i;
    }
    if (chapters.length != other.chapters.length) return n;
    return null;
  }
}
```

### Step 4: Run, verify, commit

```bash
flutter test test/domain/audiobook_test.dart
flutter analyze
git add lib/domain/models/audiobook.dart test/domain/audiobook_test.dart
git commit --no-gpg-sign -m "Add AudiobookDiff.firstDifferingChapterIndex"
```

---

## Task 2: `EditorNotifier` selection updates

**Files:**
- Modify: `lib/presentation/providers/editor_state.dart`
- Modify: `test/presentation/editor_state_test.dart`

### Step 1: Append failing tests

Append at the end of `test/presentation/editor_state_test.dart`'s `main()`:

```dart
  group('selection follows chapter changes', () {
    Audiobook threeChapterBook() => Audiobook.validated(
          chapters: const [
            Chapter(title: 'A', start: Duration.zero),
            Chapter(title: 'B', start: Duration(seconds: 10)),
            Chapter(title: 'C', start: Duration(seconds: 20)),
          ],
          totalDuration: const Duration(seconds: 30),
        );

    test('addChapter selects the newly-inserted chapter', () async {
      final fake = _FakeBookbinder(threeChapterBook());
      final playback = _RecordingPlayback()
        ..currentPosition = const Duration(seconds: 7);
      final container = makeContainer(fake, playback: playback);
      addTearDown(container.dispose);
      await container.read(editorProvider.notifier).open('/tmp/x.m4b');

      container.read(editorProvider.notifier).addChapter();
      // Sorted chapters: 0, 7, 10, 20 — new is at index 1.
      expect(container.read(selectedChapterProvider), 1);
    });

    test('deleteChapter clamps selection to the new last row', () async {
      final fake = _FakeBookbinder(threeChapterBook());
      final container = makeContainer(fake);
      addTearDown(container.dispose);
      await container.read(editorProvider.notifier).open('/tmp/x.m4b');
      container.read(selectedChapterProvider.notifier).state = 2;

      container.read(editorProvider.notifier).deleteChapter(2);
      expect(container.read(selectedChapterProvider), 1);
    });

    test('setChapterStart always selects the moved chapter', () async {
      final fake = _FakeBookbinder(threeChapterBook());
      final container = makeContainer(fake);
      addTearDown(container.dispose);
      await container.read(editorProvider.notifier).open('/tmp/x.m4b');
      container.read(selectedChapterProvider.notifier).state = 0;

      container
          .read(editorProvider.notifier)
          .setChapterStart(1, const Duration(seconds: 25));
      // Sorted: A@0, C@20, B@25 — moved chapter B is at index 2.
      expect(container.read(selectedChapterProvider), 2);
    });

    test('undo of an add selects the formerly-new chapter\'s spot',
        () async {
      final fake = _FakeBookbinder(threeChapterBook());
      final playback = _RecordingPlayback()
        ..currentPosition = const Duration(seconds: 7);
      final container = makeContainer(fake, playback: playback);
      addTearDown(container.dispose);
      await container.read(editorProvider.notifier).open('/tmp/x.m4b');

      container.read(editorProvider.notifier).addChapter();
      // After add, chapter list = [A, NEW, B, C], selection = 1.
      container.read(editorProvider.notifier).undo();
      // After undo, chapter list = [A, B, C]. The first differing index
      // between [A, NEW, B, C] (post-add) and [A, B, C] (post-undo) is 1.
      expect(container.read(selectedChapterProvider), 1);
    });

    test('undo of a metadata-only change does not change selection',
        () async {
      final fake = _FakeBookbinder(threeChapterBook());
      final container = makeContainer(fake);
      addTearDown(container.dispose);
      await container.read(editorProvider.notifier).open('/tmp/x.m4b');
      container.read(selectedChapterProvider.notifier).state = 1;

      final n = container.read(editorProvider.notifier);
      n.beginFieldEdit();
      n.setTitle('Edited');
      n.endFieldEdit();
      n.undo();

      expect(container.read(selectedChapterProvider), 1);
    });
  });
```

### Step 2: Run, see failures

Run: `flutter test test/presentation/editor_state_test.dart`
Expected: 5 failures.

### Step 3: Update `addChapter` to select the new chapter

In `lib/presentation/providers/editor_state.dart`, modify the success path of `addChapter`. After the existing `_updateBook(...)` call, append:

```dart
    // Select the newly-inserted chapter so the UI scrolls to it.
    final book2 = state.audiobook;
    if (book2 != null) {
      final idx =
          book2.chapters.indexWhere((c) => c.start == newStart);
      if (idx >= 0) {
        ref.read(selectedChapterProvider.notifier).state = idx;
      }
    }
```

This needs `newStart` to be in scope after `_updateBook`. Since `newStart` is computed before the `_updateBook` call, it's already in scope. Good.

### Step 4: Update `deleteChapter` to clamp selection

In `deleteChapter`, after the existing `_updateBook(...)` call, append:

```dart
    final book2 = state.audiobook;
    if (book2 != null) {
      final cur = ref.read(selectedChapterProvider);
      final clamped = cur > book2.chapters.length - 1
          ? book2.chapters.length - 1
          : cur;
      if (clamped != cur) {
        ref.read(selectedChapterProvider.notifier).state = clamped;
      }
    }
```

For the deleted-index case where `cur == index == newLength`, `clamped = newLength - 1` and the assignment fires. For `cur < newLength`, no change. Good.

But the test wants: `cur = 2; deleteChapter(2)` → selection = 1. After deletion, length = 2; cur = 2 > 1 → clamp to 1. Correct.

If cur = 0 and we delete index 1 (book has 3 chapters, length goes to 2): cur = 0, length-1 = 1, 0 ≤ 1, no change. Selection stays at 0. Correct.

### Step 5: Update `setChapterStart` to always select the moved chapter

In `setChapterStart`, replace the existing selection-update block:

```dart
    final currentlySelected = ref.read(selectedChapterProvider);
    if (currentlySelected == index) {
      final newIndex =
          candidate.indexWhere((c) => identical(c, movedChapter));
      if (newIndex >= 0 && newIndex != index) {
        ref.read(selectedChapterProvider.notifier).state = newIndex;
      }
    }
```

with:

```dart
    final newIndex =
        candidate.indexWhere((c) => identical(c, movedChapter));
    if (newIndex >= 0) {
      ref.read(selectedChapterProvider.notifier).state = newIndex;
    }
```

### Step 6: Update `undo` and `redo` to set selection from the diff

Replace the existing `undo()` and `redo()` methods with:

```dart
  void undo() {
    if (state.undoStack.isEmpty) return;
    _editSnapshot = null;
    final book = state.audiobook;
    final undoStack = state.undoStack;
    final newAudiobook = undoStack.last;
    state = state.copyWith(
      audiobook: newAudiobook,
      undoStack: undoStack.sublist(0, undoStack.length - 1),
      redoStack:
          book == null ? state.redoStack : [...state.redoStack, book],
      isDirty: true,
    );
    if (book != null) {
      final diff = newAudiobook.firstDifferingChapterIndex(book);
      if (diff != null) {
        final clamped = diff > newAudiobook.chapters.length - 1
            ? newAudiobook.chapters.length - 1
            : diff;
        ref.read(selectedChapterProvider.notifier).state = clamped;
      }
    }
  }

  void redo() {
    if (state.redoStack.isEmpty) return;
    _editSnapshot = null;
    final book = state.audiobook;
    final redoStack = state.redoStack;
    final newAudiobook = redoStack.last;
    state = state.copyWith(
      audiobook: newAudiobook,
      undoStack:
          book == null ? state.undoStack : [...state.undoStack, book],
      redoStack: redoStack.sublist(0, redoStack.length - 1),
      isDirty: true,
    );
    if (book != null) {
      final diff = newAudiobook.firstDifferingChapterIndex(book);
      if (diff != null) {
        final clamped = diff > newAudiobook.chapters.length - 1
            ? newAudiobook.chapters.length - 1
            : diff;
        ref.read(selectedChapterProvider.notifier).state = clamped;
      }
    }
  }
```

The `clamped` step handles undo of an add: post-undo `chapters` is shorter than the index where the add happened, so we clamp.

### Step 7: Run tests, verify, commit

```bash
flutter test test/presentation/editor_state_test.dart
flutter analyze
git add lib/presentation/providers/editor_state.dart test/presentation/editor_state_test.dart
git commit --no-gpg-sign -m "Update selection to follow chapter changes including undo/redo"
```

---

## Task 3: `ChapterList` auto-scroll on selection change

**Files:**
- Modify: `lib/presentation/widgets/chapter_list.dart`
- Modify: `test/presentation/chapter_list_test.dart`

### Step 1: Append failing test

Append at the end of `test/presentation/chapter_list_test.dart`'s `main()`:

```dart
  testWidgets('ChapterList scrolls to the selected chapter on selection change',
      (tester) async {
    // 12 chapters, 200px tall surface — chapter 8 is well below the fold.
    addTearDown(() => tester.view.resetPhysicalSize());
    tester.view.physicalSize = const Size(400, 200);
    tester.view.devicePixelRatio = 1.0;

    final book = Audiobook.validated(
      chapters: List.generate(
        12,
        (i) => Chapter(
          title: 'Ch $i',
          start: Duration(seconds: i * 5),
        ),
      ),
      totalDuration: const Duration(seconds: 200),
    );
    final fake = _StubBookbinder(book);
    final playback = _RecordingPlayback();
    final container = ProviderContainer(
      overrides: [
        bookbinderProvider.overrideWithValue(fake),
        playbackControllerProvider.overrideWithValue(playback),
      ],
    );
    await container.read(editorProvider.notifier).open('/tmp/x.m4b');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: ChapterList())),
    ));
    await tester.pumpAndSettle();

    // Locate the scrollable inside the ChapterList.
    final scrollable = find.descendant(
      of: find.byType(ChapterList),
      matching: find.byType(Scrollable),
    );
    final initialOffset = tester.widget<Scrollable>(scrollable)
        .controller!
        .position
        .pixels;
    expect(initialOffset, 0);

    container.read(selectedChapterProvider.notifier).state = 8;
    await tester.pumpAndSettle();

    final afterOffset = tester.widget<Scrollable>(scrollable)
        .controller!
        .position
        .pixels;
    expect(afterOffset, greaterThan(200),
        reason: 'list should scroll past the initial viewport to row 8');
  });
```

### Step 2: Run, see failure

Run: `flutter test test/presentation/chapter_list_test.dart`
Expected: FAIL — list doesn't scroll on its own.

### Step 3: Convert `ChapterList` to a `ConsumerStatefulWidget` with auto-scroll

Replace the `ChapterList` class in `lib/presentation/widgets/chapter_list.dart` with:

```dart
class ChapterList extends ConsumerStatefulWidget {
  const ChapterList({super.key});

  @override
  ConsumerState<ChapterList> createState() => _ChapterListState();
}

class _ChapterListState extends ConsumerState<ChapterList> {
  static const double _kRowHeight = 64;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onSelectionChanged(int? prev, int next) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final target = (next * _kRowHeight)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(selectedChapterProvider, _onSelectionChanged);

    final book = ref.watch(editorProvider).audiobook;
    final selected = ref.watch(selectedChapterProvider);
    final notifier = ref.read(editorProvider.notifier);
    if (book == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            itemCount: book.chapters.length,
            itemBuilder: (context, i) {
              final chapter = book.chapters[i];
              return _ChapterRow(
                key: ValueKey('chapters.row.$i'),
                index: i,
                chapter: chapter,
                selected: i == selected,
                onTap: () {
                  ref.read(selectedChapterProvider.notifier).state = i;
                  ref.read(playbackControllerProvider).seek(chapter.start);
                },
                onTitleChanged: (v) => notifier.renameChapter(i, v),
                onStartChanged: (d) => notifier.setChapterStart(i, d),
              );
            },
          ),
        ),
        OverflowBar(
          alignment: MainAxisAlignment.spaceEvenly,
          overflowAlignment: OverflowBarAlignment.center,
          spacing: 8,
          children: [
            TextButton(
              key: const ValueKey('chapters.add'),
              onPressed: notifier.addChapter,
              child: const Text('+ Add'),
            ),
            TextButton(
              key: const ValueKey('chapters.delete'),
              onPressed: () => notifier.deleteChapter(
                  ref.read(selectedChapterProvider)),
              child: const Text('− Delete'),
            ),
          ],
        ),
      ],
    );
  }
}
```

The rest of `chapter_list.dart` (`selectedChapterProvider`, `chapterTitleFocusNodesProvider`, `_ChapterRow`, `_ChapterRowState`) is unchanged.

### Step 4: Run tests, verify, commit

```bash
flutter test test/presentation/chapter_list_test.dart
flutter analyze
flutter test
git add lib/presentation/widgets/chapter_list.dart test/presentation/chapter_list_test.dart
git commit --no-gpg-sign -m "Auto-scroll the chapter list to the selected chapter"
```

---

## Final verification

- [ ] `flutter test` — all tests pass.
- [ ] `flutter analyze` — clean.
- [ ] macOS smoke test:
  - Open a book with many chapters.
  - Scroll near the top, then arrow-key down past the visible area → list scrolls.
  - Add a chapter → list scrolls to it; chapter is selected (number badge filled).
  - Delete a chapter → adjacent chapter becomes selected.
  - Edit a chapter's start time to force a reorder → list scrolls to its new position.
  - Add several chapters, then `⌘Z`, `⌘Z`, `⌘Z` → list scrolls to each removal in turn.
