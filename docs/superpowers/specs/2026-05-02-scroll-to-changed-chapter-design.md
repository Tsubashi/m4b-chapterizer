# Focus and Scroll to Changed Chapter — Design

**Date:** 2026-05-02
**Status:** Approved (brainstorming phase)

## Overview

After every chapter-changing editor operation (add, delete, start-time edit, undo, redo), the affected chapter becomes the selected chapter and the chapter list scrolls it into view. Today, an undo that re-inserts a chapter off-screen is invisible to the user; this fix makes the change obvious.

## Goals

- Adding a chapter selects and scrolls to the new chapter.
- Deleting a chapter keeps the selection on the row that took the deleted one's place (or the new last row).
- Editing a chapter's start time selects the moved chapter — even when it wasn't previously selected.
- Undo / redo whose diff includes a chapter change selects and scrolls to the first differing chapter.
- Undo / redo of a metadata-only change does not change selection or scroll.
- Existing flows (clicking a row, arrow-key navigation) continue to work; their selection updates trigger the same auto-scroll.

## Non-goals

- Metadata-field focus on metadata undo.
- Animated highlighting beyond what the existing selected-chapter badge provides.
- Variable-row-height precision via `scrollable_positioned_list` or similar package.
- Changing how the chapter list itself is rendered (still `ListView.builder` with uniform `ListTile` rows).

## Architecture

### Chapter-diff helper

A new extension in `lib/domain/models/audiobook.dart`:

```dart
extension AudiobookDiff on Audiobook {
  /// Returns the index of the first chapter that differs between this and
  /// [other], using `Chapter`'s value equality. If lengths differ, the
  /// index is the shorter list's length (the first divergent slot).
  /// Returns null when every shared chapter is equal AND lengths match.
  int? firstDifferingChapterIndex(Audiobook other);
}
```

Pure Dart, fully unit-testable.

### `EditorNotifier` selection updates

Each chapter-changing op now also updates `selectedChapterProvider`:

| Method | Selection update |
|---|---|
| `addChapter` | After insertion + sort, set selection to `chapters.indexWhere((c) => identical(c, newChapter))`. |
| `deleteChapter(i)` | After deletion, set selection to `min(i, newLength - 1)`. (Already partially clamps via the chapter row's `onTap` selection logic; we make it explicit and unconditional.) |
| `setChapterStart` | The existing block updates selection only when the moved chapter was already selected. Drop that conditional — always update selection to the moved chapter's new index. |
| `undo` / `redo` | After restoring state, call `firstDifferingChapterIndex(otherBook)`. If non-null, set selection. |

### `ChapterList` auto-scroll

`ChapterList` becomes a `ConsumerStatefulWidget`. State adds:

```dart
final _scrollController = ScrollController();
static const _kRowHeight = 64.0; // estimated; ListTile defaults are uniform
```

The build method registers a `ref.listen<int>(selectedChapterProvider, _onSelectionChanged)`. The handler:

```dart
void _onSelectionChanged(int? prev, int next) {
  if (!_scrollController.hasClients) return;
  final target = (next * _kRowHeight).clamp(
    _scrollController.position.minScrollExtent,
    _scrollController.position.maxScrollExtent,
  );
  _scrollController.animateTo(
    target,
    duration: const Duration(milliseconds: 200),
    curve: Curves.easeOut,
  );
}
```

The `ListView.builder` gets `controller: _scrollController`.

For lists shorter than the viewport (the common case in the fixture), `maxScrollExtent` is 0, so the animateTo is a no-op — fine.

## Tests

### `test/domain/audiobook_test.dart` (extend)

1. **Diff returns null when chapters are equal.** Two audiobooks with identical chapter lists → null.
2. **Diff returns the index of the first differing chapter.** Three-chapter book vs same with chapter 1 retitled → 1.
3. **Diff handles longer right side (insertion at end).** Three-chapter vs four-chapter where the first three match → 3.
4. **Diff handles shorter right side (deletion at index).** Four-chapter vs three-chapter where left's chapter at index 1 is gone → 1.

### `test/presentation/editor_state_test.dart` (extend)

5. **`addChapter` selects the new chapter.** Set playhead to 7s in a 3-chapter book starting at 0/10/20. Add. Verify selection equals the new chapter's index (1, after sort).
6. **`deleteChapter` clamps selection to the new last row.** Selection = 2; delete index 2 in a 3-chapter book → selection becomes 1.
7. **`setChapterStart` always selects the moved chapter.** Selected = 0; move chapter 1 to a position past chapter 2 → selection becomes 2.
8. **`undo` of an add selects the spot the now-removed chapter occupied.** Add a chapter at index 1, then undo → selection becomes 1.
9. **`undo` of a metadata-only change leaves selection alone.** Set selection to 1, do a focus → setTitle → blur cycle, undo → selection still 1.

### `test/presentation/chapter_list_test.dart` (extend)

10. **`ChapterList` scrolls to the selected chapter when selection changes.** Set up a 12-chapter book in a 200-pixel-tall surface; `selectedChapterProvider = 8`; pump and settle; verify `_scrollController.offset > 0`. Lower-bound assertion (≈ 384 for 6 rows past viewport at 64px each) is more robust than equality, so use `greaterThan(200)`.

## Files

- Modify: `lib/domain/models/audiobook.dart` — `AudiobookDiff` extension.
- Modify: `lib/presentation/providers/editor_state.dart` — selection updates in `addChapter`, `deleteChapter`, `setChapterStart`, `undo`, `redo`.
- Modify: `lib/presentation/widgets/chapter_list.dart` — `ConsumerStatefulWidget` + `ScrollController` + `ref.listen` auto-scroll.
- Modify: `test/domain/audiobook_test.dart`
- Modify: `test/presentation/editor_state_test.dart`
- Modify: `test/presentation/chapter_list_test.dart`
