# Chapter Navigation Seeks Playhead — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the user clicks a chapter row, presses `↑`/`↓` to move chapter selection, or successfully edits a chapter's start time, the playback playhead seeks to the relevant timestamp.

**Architecture:** Three one-line additions at the user-action callsites — `_ChapterRow.onTap` in `ChapterList`, the `MoveChapterSelectionIntent` action in `EditorShortcuts`, and the success path of `EditorNotifier.setChapterStart`. Tests gain a `_NullPlayback` and a `_RecordingPlayback` fake; `editor_state_test.dart`'s `makeContainer` helper now also overrides `playbackControllerProvider`.

**Tech Stack:** No new packages.

**Reference design:** `docs/superpowers/specs/2026-05-02-chapter-click-seeks-design.md`

**Conventions:**
- `--no-gpg-sign` REQUIRED on every `git commit`.
- Run `flutter test` and `flutter analyze` before each commit.

---

## Task 1: All three navigation paths seek

**Files:**
- Modify: `lib/presentation/widgets/chapter_list.dart`
- Modify: `lib/presentation/keyboard/shortcuts.dart`
- Modify: `lib/presentation/providers/editor_state.dart`
- Modify: `test/presentation/editor_state_test.dart`
- Modify: `test/presentation/chapter_list_test.dart`
- Modify: `test/presentation/keyboard_shortcuts_test.dart`

### Step 1: Add a no-op `_NullPlayback` and a recording `_RecordingPlayback` to `editor_state_test.dart`

At the top of `test/presentation/editor_state_test.dart`, add the import and the two fake classes after the existing `_FakeBookbinder`:

```dart
import 'package:m4b_chapterizer/presentation/providers/playback.dart';
```

```dart
class _NullPlayback implements PlaybackController {
  @override
  Future<void> setSource(String path) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Duration get position => Duration.zero;
  @override
  bool get playing => false;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<bool> get playingStream => const Stream.empty();
  @override
  Future<void> dispose() async {}
}

class _RecordingPlayback implements PlaybackController {
  final List<Duration> seeks = [];
  @override
  Future<void> setSource(String path) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
  }
  @override
  Duration get position => Duration.zero;
  @override
  bool get playing => false;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<bool> get playingStream => const Stream.empty();
  @override
  Future<void> dispose() async {}
}
```

### Step 2: Update `makeContainer` to override `playbackControllerProvider`

Replace the existing `makeContainer` helper:

```dart
ProviderContainer makeContainer(
  _FakeBookbinder fake, {
  PlaybackController? playback,
}) =>
    ProviderContainer(
      overrides: [
        bookbinderProvider.overrideWithValue(fake),
        playbackControllerProvider.overrideWithValue(playback ?? _NullPlayback()),
      ],
    );
```

Existing call sites continue to work; they just get a `_NullPlayback` by default.

### Step 3: Add the two new editor-state tests

Append at the end of the existing `setChapterStart reorder & clamp` group in `editor_state_test.dart`:

```dart
    test('successful setChapterStart seeks to the new start', () async {
      final fake = _FakeBookbinder(threeChapterBook());
      final playback = _RecordingPlayback();
      final container = makeContainer(fake, playback: playback);
      addTearDown(container.dispose);
      await container.read(editorProvider.notifier).open('/tmp/x.m4b');

      final error = container
          .read(editorProvider.notifier)
          .setChapterStart(1, const Duration(seconds: 25));

      expect(error, isNull);
      expect(playback.seeks, [const Duration(seconds: 25)]);
    });

    test('rejected setChapterStart does not seek', () async {
      final fake = _FakeBookbinder(threeChapterBook());
      final playback = _RecordingPlayback();
      final container = makeContainer(fake, playback: playback);
      addTearDown(container.dispose);
      await container.read(editorProvider.notifier).open('/tmp/x.m4b');

      final error = container
          .read(editorProvider.notifier)
          .setChapterStart(1, Duration.zero);

      expect(error, SetChapterStartError.duplicate);
      expect(playback.seeks, isEmpty);
    });

    test('beyond-total clamp seeks to the clamped value', () async {
      final fake = _FakeBookbinder(threeChapterBook());
      final playback = _RecordingPlayback();
      final container = makeContainer(fake, playback: playback);
      addTearDown(container.dispose);
      await container.read(editorProvider.notifier).open('/tmp/x.m4b');

      final error = container
          .read(editorProvider.notifier)
          .setChapterStart(1, const Duration(seconds: 9999));

      expect(error, isNull);
      expect(playback.seeks, [const Duration(milliseconds: 29999)]);
    });
```

### Step 4: Run, see failures

Run: `flutter test test/presentation/editor_state_test.dart`
Expected: 3 new failures — `setChapterStart` doesn't seek yet.

### Step 5: Wire seek into `EditorNotifier.setChapterStart`

In `lib/presentation/providers/editor_state.dart`, find the success path of `setChapterStart` (after the `state = state.copyWith(...)` commit, around the selection-update logic). Add the seek as the very last step before `return null`:

```dart
    // 5. Commit.
    final newBook = Audiobook.validated(...);
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

    // 7. Seek the playhead to the new start so the user can hear it.
    ref.read(playbackControllerProvider).seek(clamped);

    return null;
```

The import for `playbackControllerProvider` is at the top of `editor_state.dart`. If it's not already imported (it lives in `lib/presentation/providers/playback.dart`), add:

```dart
import 'playback.dart';
```

### Step 6: Run editor_state tests

Run: `flutter test test/presentation/editor_state_test.dart`
Expected: all tests pass (existing + 3 new).

### Step 7: Add the chapter-list click test

In `test/presentation/chapter_list_test.dart`, the existing `_StubBookbinder` provides the bookbinder side. Add a `_RecordingPlayback` class (same shape as the one in editor_state_test) and the import for `PlaybackController`:

```dart
import 'package:m4b_chapterizer/presentation/providers/playback.dart';
```

```dart
class _RecordingPlayback implements PlaybackController {
  final List<Duration> seeks = [];
  @override
  Future<void> setSource(String path) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
  }
  @override
  Duration get position => Duration.zero;
  @override
  bool get playing => false;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<bool> get playingStream => const Stream.empty();
  @override
  Future<void> dispose() async {}
}
```

Now find the existing `_setUp` helper and modify it so callers can supply a playback fake. Replace `_setUp` with:

```dart
Future<({ProviderContainer container, _RecordingPlayback playback})>
    _setUp(WidgetTester tester) async {
  final fake = _StubBookbinder(Audiobook.validated(
    chapters: const [
      Chapter(title: 'Alpha', start: Duration.zero),
      Chapter(title: 'Beta', start: Duration(seconds: 10)),
    ],
    totalDuration: const Duration(seconds: 30),
  ));
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
  return (container: container, playback: playback);
}
```

Existing tests use `final container = await _setUp(tester);`. Update each call site to read from the record:

```dart
final (:container, :playback) = await _setUp(tester);
```

Wherever existing tests just use `container`, change to that destructuring pattern, and the `playback` variable becomes available. For tests that don't assert on playback, they can prefix with `_` to ignore.

(Note: the destructuring pattern is supported by Dart 3 records.)

Append the new test at the end of `main()` in `chapter_list_test.dart`:

```dart
  testWidgets('tap on a chapter row seeks to that chapter\'s start',
      (tester) async {
    final (:container, :playback) = await _setUp(tester);
    // Tap chapter 1 (Beta @ 10s).
    await tester.tap(find.byKey(const ValueKey('chapters.row.1')));
    await tester.pump();

    expect(playback.seeks, [const Duration(seconds: 10)]);
    // Selection moved as well.
    expect(container.read(selectedChapterProvider), 1);
  });
```

### Step 8: Wire seek into the chapter-list `onTap`

In `lib/presentation/widgets/chapter_list.dart`, find the `_ChapterRow` construction inside `ChapterList.build`. Replace the `onTap` line:

```dart
                onTap: () {
                  ref.read(selectedChapterProvider.notifier).state = i;
                  ref.read(playbackControllerProvider).seek(chapter.start);
                },
```

Also add the import at the top of the file (if not already there):

```dart
import '../providers/playback.dart';
```

### Step 9: Run chapter-list tests

Run: `flutter test test/presentation/chapter_list_test.dart`
Expected: all tests pass.

### Step 10: Add the keyboard-shortcuts seek tests

In `test/presentation/keyboard_shortcuts_test.dart`, the existing `_FakePlayback` already records seeks via its `seeks` field. Add the new tests inside `_registerWidgetTests`'s group (after the `ArrowDown does NOT change selection while a TextField is focused` test):

```dart
    testWidgets('ArrowDown seeks to the next chapter\'s start',
        (tester) async {
      final h = await _pumpEditor(tester);
      h.container.read(selectedChapterProvider.notifier).state = 0;
      // Establish a baseline by clearing prior seek records.
      h.playback.seeks.clear();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      expect(h.container.read(selectedChapterProvider), 1);
      expect(h.playback.seeks, [const Duration(seconds: 10)]);
    });

    testWidgets('ArrowUp at index 0 does not move selection or seek',
        (tester) async {
      final h = await _pumpEditor(tester);
      h.container.read(selectedChapterProvider.notifier).state = 0;
      h.playback.seeks.clear();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();

      expect(h.container.read(selectedChapterProvider), 0);
      expect(h.playback.seeks, isEmpty);
    });
```

### Step 11: Wire seek into `MoveChapterSelectionIntent`

In `lib/presentation/keyboard/shortcuts.dart`, find the `MoveChapterSelectionIntent` action body. Replace it with one that also seeks AND skips when the index doesn't change:

```dart
          MoveChapterSelectionIntent:
              _BareKeyAction<MoveChapterSelectionIntent>((intent) {
            final book = ref.read(editorProvider).audiobook;
            if (book == null) return null;
            final cur = ref.read(selectedChapterProvider);
            final next = (cur + intent.delta)
                .clamp(0, book.chapters.length - 1);
            if (next == cur) return null;
            ref.read(selectedChapterProvider.notifier).state = next;
            ref.read(playbackControllerProvider).seek(book.chapters[next].start);
            return null;
          }),
```

The `if (next == cur) return null;` is the new no-op guard for "ArrowUp at index 0 does not seek".

### Step 12: Run keyboard-shortcuts tests

Run: `flutter test test/presentation/keyboard_shortcuts_test.dart`
Expected: all tests pass (existing + 2 new).

### Step 13: Run full suite

Run: `flutter test`
Expected: all tests pass.

### Step 14: Run analyzer

Run: `flutter analyze`
Expected: `No issues found!`

### Step 15: Commit

```bash
git add lib/presentation/widgets/chapter_list.dart lib/presentation/keyboard/shortcuts.dart lib/presentation/providers/editor_state.dart test/presentation/editor_state_test.dart test/presentation/chapter_list_test.dart test/presentation/keyboard_shortcuts_test.dart
git commit --no-gpg-sign -m "Seek playhead on chapter click, arrow nav, or start-time edit"
```

---

## Final verification

- [ ] `flutter test` — all tests pass.
- [ ] `flutter analyze` — clean.
- [ ] macOS smoke test: open the fixture, click chapters → playhead jumps; arrow up/down → playhead follows; edit a chapter's start time → playhead jumps to the new value.
