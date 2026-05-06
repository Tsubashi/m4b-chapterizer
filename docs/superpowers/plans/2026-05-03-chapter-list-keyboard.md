# Chapter-List Keyboard Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tab cycles `(selected.title) → (selected.start) → (next.title) → …` through the chapter list with wrap; Up/Down commit edits and jump to the corresponding field of the row above/below using the pre-commit position; metadata fields keep default text-cursor behavior.

**Architecture:** Add a sibling `chapterStartFocusNodesProvider` to the existing `chapterTitleFocusNodesProvider`, plus a `chapterStartCommitProvider` registry of per-row commit callbacks. `_ChapterRowState` registers/unregisters its start focus node and commit callback in lock-step with the existing title node registration. New `ChapterFieldTabIntent` bound to Tab/Shift+Tab; the existing `MoveChapterSelectionIntent` action gains a chapter-field-focused branch.

**Tech Stack:** Flutter 3.41.9, Dart 3.11, flutter_riverpod 3.x.

**Spec:** `docs/superpowers/specs/2026-05-03-chapter-list-keyboard-design.md`

---

## File Map

**Modified:**
- `lib/presentation/widgets/chapter_list.dart` — new providers, registrations, factor `_commitStart`
- `lib/presentation/keyboard/shortcuts.dart` — `ChapterFieldTabIntent`, helper, tab + extended move actions
- `test/presentation/keyboard_shortcuts_test.dart` — add chapter-list keyboard nav group

---

## Task 1: Plumbing — start focus node + commit callback registries

Pure refactor. Adds the registries, registers each row's start focus node and commit callback, factors the existing `onSubmitted` body into a private `_commitStart` method. Behavior is unchanged; existing tests stay green.

**Files:**
- Modify: `lib/presentation/widgets/chapter_list.dart`

- [ ] **Step 1: Add the new providers and the commit callback**

In `lib/presentation/widgets/chapter_list.dart`, add the new providers near the existing `chapterTitleFocusNodesProvider` declaration (around line 14):

```dart
final chapterStartFocusNodesProvider =
    Provider<Map<int, FocusNode>>((ref) => <int, FocusNode>{});

final chapterStartCommitProvider =
    Provider<Map<int, void Function()>>((ref) => <int, void Function()>{});
```

- [ ] **Step 2: Register the start focus node and commit callback in `_ChapterRowState`**

The current `_ChapterRowState` registers `_titleFocusNode` in `_focusNodesMap` (which is `chapterTitleFocusNodesProvider`'s map). Add parallel registrations for the start node and commit callback:

Add new fields:

```dart
late final Map<int, FocusNode> _startFocusNodesMap;
late final Map<int, void Function()> _startCommitMap;
```

In `initState`:

```dart
_startFocusNodesMap = ref.read(chapterStartFocusNodesProvider);
_startFocusNodesMap[widget.index] = _startFocusNode;
_startCommitMap = ref.read(chapterStartCommitProvider);
_startCommitMap[widget.index] = _commitStart;
```

In `didUpdateWidget` (extending the existing index-change branch):

```dart
if (oldWidget.index != widget.index) {
  _focusNodesMap.remove(oldWidget.index);
  _focusNodesMap[widget.index] = _titleFocusNode;
  _startFocusNodesMap.remove(oldWidget.index);
  _startFocusNodesMap[widget.index] = _startFocusNode;
  _startCommitMap.remove(oldWidget.index);
  _startCommitMap[widget.index] = _commitStart;
}
```

In `dispose`:

```dart
_focusNodesMap.remove(widget.index);
_startFocusNodesMap.remove(widget.index);
_startCommitMap.remove(widget.index);
_titleFocusNode.dispose();
_startFocusNode.dispose();
_titleController.dispose();
_startController.dispose();
super.dispose();
```

- [ ] **Step 3: Factor the start `onSubmitted` body into `_commitStart`**

Today's start TextField has an inline `onSubmitted` that parses, validates, and reverts. Extract it:

```dart
void _commitStart() {
  final text = _startController.text;
  Duration parsed;
  try {
    parsed = parseDuration(text);
  } on FormatException {
    _startController.text = formatDuration(widget.chapter.start);
    return;
  }
  final error = widget.onStartChanged(parsed);
  if (error != null) {
    _startController.text = formatDuration(widget.chapter.start);
    if (mounted) {
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
  }
}
```

Replace the inline `onSubmitted: (v) { ... }` with `onSubmitted: (_) => _commitStart()`. Drop the local `v` since `_commitStart` reads from the controller directly.

- [ ] **Step 4: Run existing suite + analyzer**

Run: `flutter test`
Run: `flutter analyze`
Expected: all 235 tests pass; analyzer clean.

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/widgets/chapter_list.dart
git commit --no-gpg-sign -m "$(cat <<'EOF'
Register chapter start focus nodes and factor _commitStart

Adds chapterStartFocusNodesProvider and chapterStartCommitProvider
sibling registries to the existing chapterTitleFocusNodesProvider,
populated by _ChapterRowState in initState/didUpdateWidget/dispose.
The onSubmitted body of the start TextField moves into a private
_commitStart so the upcoming Tab/Up/Down shortcuts can share it
with Enter.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Tab and Shift+Tab cycle through chapter fields

Add the `ChapterFieldTabIntent`, bind Tab/Shift+Tab to it, implement the action that walks `(title, start, title, start, …)` with wrap, plus the `_focusedChapterField` helper.

**Files:**
- Modify: `lib/presentation/keyboard/shortcuts.dart`
- Modify: `test/presentation/keyboard_shortcuts_test.dart`

- [ ] **Step 1: Append failing tests**

Add a new group at the end of `void main() { ... }` in `test/presentation/keyboard_shortcuts_test.dart`. The existing test file has helpers for pumping the editor and reading focus state — reuse them. The exact pump helper varies by what's already there; the tests below assume helpers `_pumpEditor`, `_focusTitle(idx)`, `_focusStart(idx)`, and `_pressKey(LogicalKeyboardKey, {bool shift})` exist. **If they don't, add the minimal versions needed at the top of the new group**:

```dart
group('Chapter-list keyboard: Tab', () {
  testWidgets('Tab from chapter title focuses its start field',
      (tester) async {
    final container = await _pumpEditorWith3Chapters(tester);
    await _focusTitle(tester, container, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    final startNodes =
        container.read(chapterStartFocusNodesProvider);
    expect(FocusManager.instance.primaryFocus, startNodes[1]);
  });

  testWidgets('Tab from chapter start focuses next chapter title',
      (tester) async {
    final container = await _pumpEditorWith3Chapters(tester);
    await _focusStart(tester, container, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    final titleNodes =
        container.read(chapterTitleFocusNodesProvider);
    expect(FocusManager.instance.primaryFocus, titleNodes[2]);
    expect(container.read(selectedChapterProvider), 2);
  });

  testWidgets('Tab from last chapter start wraps to first chapter title',
      (tester) async {
    final container = await _pumpEditorWith3Chapters(tester);
    await _focusStart(tester, container, 2);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    final titleNodes =
        container.read(chapterTitleFocusNodesProvider);
    expect(FocusManager.instance.primaryFocus, titleNodes[0]);
    expect(container.read(selectedChapterProvider), 0);
  });

  testWidgets('Shift+Tab from chapter start goes to that chapter title',
      (tester) async {
    final container = await _pumpEditorWith3Chapters(tester);
    await _focusStart(tester, container, 1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    final titleNodes =
        container.read(chapterTitleFocusNodesProvider);
    expect(FocusManager.instance.primaryFocus, titleNodes[1]);
  });

  testWidgets('Shift+Tab from first chapter title wraps to last chapter start',
      (tester) async {
    final container = await _pumpEditorWith3Chapters(tester);
    await _focusTitle(tester, container, 0);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    final startNodes =
        container.read(chapterStartFocusNodesProvider);
    expect(FocusManager.instance.primaryFocus, startNodes[2]);
    expect(container.read(selectedChapterProvider), 2);
  });

  testWidgets('Tab in a metadata field does not enter the chapter cycle',
      (tester) async {
    final container = await _pumpEditorWith3Chapters(tester);
    final initialSelection = container.read(selectedChapterProvider);
    // Focus the metadata Title TextField.
    await tester.tap(find.byKey(const ValueKey('metadata.title')));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(container.read(selectedChapterProvider), initialSelection);
  });
});
```

(If `_pumpEditorWith3Chapters` / `_focusTitle` / `_focusStart` helpers don't exist in the test file, define them at the top of the file based on the patterns already used in `keyboard_shortcuts_test.dart`. The `metadata.title` ValueKey may already exist on the metadata form's title field; if it doesn't, add it in the implementation step or use a different finder like `find.widgetWithText(TextField, ...)` against the visible label.)

- [ ] **Step 2: Run tests; verify failure**

Run: `flutter test test/presentation/keyboard_shortcuts_test.dart`
Expected: 6 new tests fail because `ChapterFieldTabIntent` and the action don't exist yet.

- [ ] **Step 3: Implement `ChapterFieldTabIntent`, the helper, and the action**

In `lib/presentation/keyboard/shortcuts.dart`:

Add new intent near the other intent declarations:

```dart
class ChapterFieldTabIntent extends Intent {
  const ChapterFieldTabIntent(this.delta);
  final int delta; // +1 for Tab, -1 for Shift+Tab
}
```

Add the helper near `_isEditableTextFocused`:

```dart
enum _ChapterFieldType { title, start }

class _FocusedChapterField {
  const _FocusedChapterField(this.index, this.type);
  final int index;
  final _ChapterFieldType type;
}

_FocusedChapterField? _focusedChapterField(WidgetRef ref) {
  final focused = FocusManager.instance.primaryFocus;
  if (focused == null) return null;
  final titles = ref.read(chapterTitleFocusNodesProvider);
  for (final entry in titles.entries) {
    if (entry.value == focused) {
      return _FocusedChapterField(entry.key, _ChapterFieldType.title);
    }
  }
  final starts = ref.read(chapterStartFocusNodesProvider);
  for (final entry in starts.entries) {
    if (entry.value == focused) {
      return _FocusedChapterField(entry.key, _ChapterFieldType.start);
    }
  }
  return null;
}
```

(Add the import for the new provider at the top: change the existing `import '../widgets/chapter_list.dart' show ...` to also include `chapterStartFocusNodesProvider` and `chapterStartCommitProvider`.)

Add the bindings to `editorShortcuts()`:

```dart
const SingleActivator(LogicalKeyboardKey.tab):
    const ChapterFieldTabIntent(1),
const SingleActivator(LogicalKeyboardKey.tab, shift: true):
    const ChapterFieldTabIntent(-1),
```

Add a new action class — like `_BareKeyAction` but enabled only when focused on a chapter field. This is needed so non-chapter-field tabs fall through to default Flutter focus traversal:

```dart
class _ChapterFieldAction<T extends Intent> extends Action<T> {
  _ChapterFieldAction(this._ref, this._onInvoke);

  final WidgetRef _ref;
  final Object? Function(T intent, _FocusedChapterField field) _onInvoke;

  @override
  bool isEnabled(T intent, [BuildContext? context]) =>
      _focusedChapterField(_ref) != null;

  @override
  bool consumesKey(T intent) => _focusedChapterField(_ref) != null;

  @override
  Object? invoke(T intent) {
    final field = _focusedChapterField(_ref);
    if (field == null) return null;
    return _onInvoke(intent, field);
  }
}
```

Wire the action into the `actions:` map of `_EditorShortcutsState.build`:

```dart
ChapterFieldTabIntent: _ChapterFieldAction<ChapterFieldTabIntent>(ref,
    (intent, field) {
  final book = ref.read(editorProvider).audiobook;
  if (book == null) return null;
  final n = book.chapters.length;
  if (n == 0) return null;

  // Compute next (chapterIdx, fieldType).
  late int nextIdx;
  late _ChapterFieldType nextType;
  if (intent.delta > 0) {
    if (field.type == _ChapterFieldType.title) {
      nextIdx = field.index;
      nextType = _ChapterFieldType.start;
    } else {
      nextIdx = (field.index + 1) % n;
      nextType = _ChapterFieldType.title;
    }
  } else {
    if (field.type == _ChapterFieldType.start) {
      nextIdx = field.index;
      nextType = _ChapterFieldType.title;
    } else {
      nextIdx = (field.index - 1 + n) % n;
      nextType = _ChapterFieldType.start;
    }
  }

  // Capture target chapter reference (pre-commit list).
  final targetChapter = book.chapters[nextIdx];

  // Commit current field's pending edit if it's a start field.
  if (field.type == _ChapterFieldType.start) {
    ref.read(chapterStartCommitProvider)[field.index]?.call();
  }

  // Look up target's new index in the (possibly-reordered) list.
  final newBook = ref.read(editorProvider).audiobook;
  if (newBook == null) return null;
  final newIdx = newBook.chapters.indexWhere(
    (c) => identical(c, targetChapter),
  );
  if (newIdx < 0) return null;

  ref.read(selectedChapterProvider.notifier).state = newIdx;

  final node = nextType == _ChapterFieldType.title
      ? ref.read(chapterTitleFocusNodesProvider)[newIdx]
      : ref.read(chapterStartFocusNodesProvider)[newIdx];
  node?.requestFocus();
  return null;
}),
```

- [ ] **Step 4: Run tests; verify pass**

Run: `flutter test test/presentation/keyboard_shortcuts_test.dart`
Expected: 6 new Tab tests pass plus all prior tests in the file.

- [ ] **Step 5: Run full suite + analyzer**

Run: `flutter test`
Run: `flutter analyze`
Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/keyboard/shortcuts.dart test/presentation/keyboard_shortcuts_test.dart
git commit --no-gpg-sign -m "$(cat <<'EOF'
Add Tab / Shift+Tab cycling through chapter fields

Tab walks (selected.title, selected.start, next.title, next.start, ...)
with wrap-around. Shift+Tab reverses. The cycle only fires when focus
is already on a chapter title or start field; from elsewhere
(metadata fields, no focus), default Flutter traversal handles Tab.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Up / Down inside chapter fields commits and jumps rows

Modify `MoveChapterSelectionIntent`'s action to handle the chapter-field-focused case (commit + move + reorder lookup). Metadata-field focus stays default text behavior. No-focus stays existing behavior.

**Files:**
- Modify: `lib/presentation/keyboard/shortcuts.dart`
- Modify: `test/presentation/keyboard_shortcuts_test.dart`

- [ ] **Step 1: Append failing tests**

Add a second group at the end of `void main() { ... }` in `test/presentation/keyboard_shortcuts_test.dart`:

```dart
group('Chapter-list keyboard: Up / Down', () {
  testWidgets('ArrowDown in title commits and focuses next title',
      (tester) async {
    final container = await _pumpEditorWith3Chapters(tester);
    await _focusTitle(tester, container, 0);
    // Type new text into chapter 0's title.
    await tester.enterText(
        find.byKey(const ValueKey('chapters.title.0')), 'New Title');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    final book = container.read(editorProvider).audiobook!;
    expect(book.chapters[0].title, 'New Title');
    expect(container.read(selectedChapterProvider), 1);
    final titleNodes =
        container.read(chapterTitleFocusNodesProvider);
    expect(FocusManager.instance.primaryFocus, titleNodes[1]);
  });

  testWidgets('ArrowUp in start focuses previous start',
      (tester) async {
    final container = await _pumpEditorWith3Chapters(tester);
    await _focusStart(tester, container, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    final startNodes =
        container.read(chapterStartFocusNodesProvider);
    expect(FocusManager.instance.primaryFocus, startNodes[0]);
    expect(container.read(selectedChapterProvider), 0);
  });

  testWidgets(
      'ArrowUp in start with valid new time uses pre-commit position',
      (tester) async {
    // 4 chapters: A=0, B=10s, C=30s, D=40s.
    final container = await _pumpEditorWith4Chapters(tester);
    await _focusStart(tester, container, 2); // C
    await tester.enterText(
        find.byKey(const ValueKey('chapters.start.2')),
        '00:00:00.005');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    // Commit reorders to [A, C, B, D]. Pre-commit target was B
    // (idx 1). B's new idx is 2. Selection lands at 2.
    final book = container.read(editorProvider).audiobook!;
    expect(book.chapters[1].title, 'C');
    expect(book.chapters[2].title, 'B');
    expect(container.read(selectedChapterProvider), 2);
    final startNodes =
        container.read(chapterStartFocusNodesProvider);
    expect(FocusManager.instance.primaryFocus, startNodes[2]);
  });

  testWidgets('ArrowUp at first chapter is a no-op', (tester) async {
    final container = await _pumpEditorWith3Chapters(tester);
    await _focusTitle(tester, container, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    final titleNodes =
        container.read(chapterTitleFocusNodesProvider);
    expect(FocusManager.instance.primaryFocus, titleNodes[0]);
    expect(container.read(selectedChapterProvider), 0);
  });

  testWidgets('ArrowDown at last chapter is a no-op', (tester) async {
    final container = await _pumpEditorWith3Chapters(tester);
    await _focusStart(tester, container, 2);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    final startNodes =
        container.read(chapterStartFocusNodesProvider);
    expect(FocusManager.instance.primaryFocus, startNodes[2]);
    expect(container.read(selectedChapterProvider), 2);
  });

  testWidgets('ArrowDown in metadata field does not move chapter selection',
      (tester) async {
    final container = await _pumpEditorWith3Chapters(tester);
    final initial = container.read(selectedChapterProvider);
    await tester.tap(find.byKey(const ValueKey('metadata.title')));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(container.read(selectedChapterProvider), initial);
  });

  testWidgets('ArrowDown in start with unparseable text reverts and moves',
      (tester) async {
    final container = await _pumpEditorWith3Chapters(tester);
    await _focusStart(tester, container, 0);
    final originalStart = container
        .read(editorProvider)
        .audiobook!
        .chapters[0]
        .start;
    await tester.enterText(
        find.byKey(const ValueKey('chapters.start.0')), 'garbage');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    final book = container.read(editorProvider).audiobook!;
    expect(book.chapters[0].start, originalStart);
    expect(container.read(selectedChapterProvider), 1);
    final startNodes =
        container.read(chapterStartFocusNodesProvider);
    expect(FocusManager.instance.primaryFocus, startNodes[1]);
  });
});
```

(`_pumpEditorWith4Chapters` is a sibling helper that wires 4 chapters with starts 0, 10, 30, 40 seconds. Add it next to `_pumpEditorWith3Chapters`.)

- [ ] **Step 2: Run tests; verify failure**

Run: `flutter test test/presentation/keyboard_shortcuts_test.dart`
Expected: the 7 new Up/Down tests fail because the action still uses the old `_BareKeyAction` semantics (no chapter-field branch).

- [ ] **Step 3: Replace `MoveChapterSelectionIntent`'s action with the new branched version**

In `lib/presentation/keyboard/shortcuts.dart`'s `_EditorShortcutsState.build()`, replace the existing `MoveChapterSelectionIntent: _BareKeyAction<MoveChapterSelectionIntent>((intent) { ... })` entry with this version. It can no longer use `_BareKeyAction` because it must run for chapter-field focus (an editable text) but be ignored for metadata-field focus (also an editable text). Use a custom `Action`:

```dart
MoveChapterSelectionIntent: _MoveChapterSelectionAction(ref),
```

Add the action class below the `_ChapterFieldAction` class:

```dart
class _MoveChapterSelectionAction
    extends Action<MoveChapterSelectionIntent> {
  _MoveChapterSelectionAction(this._ref);

  final WidgetRef _ref;

  bool _isInChapterField() => _focusedChapterField(_ref) != null;

  bool _isInOtherEditableText() {
    final focused = FocusManager.instance.primaryFocus;
    if (focused == null) return false;
    final inEditable =
        focused.context?.findAncestorWidgetOfExactType<EditableText>() !=
            null;
    if (!inEditable) return false;
    return _focusedChapterField(_ref) == null;
  }

  @override
  bool isEnabled(MoveChapterSelectionIntent intent, [BuildContext? c]) {
    // Run when no editable focus, or when in a chapter field. Skip
    // when in any other editable text (metadata) so the field's own
    // arrow handling runs.
    return !_isInOtherEditableText();
  }

  @override
  bool consumesKey(MoveChapterSelectionIntent intent) =>
      !_isInOtherEditableText();

  @override
  Object? invoke(MoveChapterSelectionIntent intent) {
    final field = _focusedChapterField(_ref);
    if (field != null) {
      return _invokeChapterFieldBranch(intent, field);
    }
    return _invokeNoFocusBranch(intent);
  }

  Object? _invokeChapterFieldBranch(
    MoveChapterSelectionIntent intent,
    _FocusedChapterField field,
  ) {
    final book = _ref.read(editorProvider).audiobook;
    if (book == null) return null;
    final n = book.chapters.length;
    final targetIdx = field.index + intent.delta;
    if (targetIdx < 0 || targetIdx >= n) return null;

    final targetChapter = book.chapters[targetIdx];

    if (field.type == _ChapterFieldType.start) {
      _ref.read(chapterStartCommitProvider)[field.index]?.call();
    }

    final newBook = _ref.read(editorProvider).audiobook;
    if (newBook == null) return null;
    final newIdx =
        newBook.chapters.indexWhere((c) => identical(c, targetChapter));
    if (newIdx < 0) return null;

    _ref.read(selectedChapterProvider.notifier).state = newIdx;
    _ref
        .read(playbackControllerProvider)
        .seek(newBook.chapters[newIdx].start);
    _ref.read(chapterScrollRequestProvider.notifier).state++;

    final node = field.type == _ChapterFieldType.title
        ? _ref.read(chapterTitleFocusNodesProvider)[newIdx]
        : _ref.read(chapterStartFocusNodesProvider)[newIdx];
    node?.requestFocus();
    return null;
  }

  Object? _invokeNoFocusBranch(MoveChapterSelectionIntent intent) {
    final book = _ref.read(editorProvider).audiobook;
    if (book == null) return null;
    final cur = _ref.read(selectedChapterProvider);
    final next =
        (cur + intent.delta).clamp(0, book.chapters.length - 1);
    if (next == cur) return null;
    _ref.read(selectedChapterProvider.notifier).state = next;
    _ref
        .read(playbackControllerProvider)
        .seek(book.chapters[next].start);
    _ref.read(chapterScrollRequestProvider.notifier).state++;
    return null;
  }
}
```

(The chapter-field branch consumes the key even on out-of-bounds — returning `null` from `invoke` while keeping `consumesKey` true means the field doesn't see the arrow either, satisfying the "no-op" rule.)

- [ ] **Step 4: Run tests; verify pass**

Run: `flutter test test/presentation/keyboard_shortcuts_test.dart`
Expected: all tests pass — new 7 + Tab's 6 + existing.

- [ ] **Step 5: Run full suite + analyzer**

Run: `flutter test`
Run: `flutter analyze`
Expected: all green.

- [ ] **Step 6: Build macOS to confirm runtime is happy**

Run: `flutter build macos --debug`
Expected: clean build.

- [ ] **Step 7: Commit**

```bash
git add lib/presentation/keyboard/shortcuts.dart test/presentation/keyboard_shortcuts_test.dart
git commit --no-gpg-sign -m "$(cat <<'EOF'
Up/Down inside chapter fields commit and jump rows

When focus is on a chapter title or start field, ArrowUp / ArrowDown
commit any pending edit (start fields parse + apply or revert; title
fields are continuously committed) and move focus to the corresponding
field of the row above or below. The destination is determined from
the pre-commit row index, so commit-induced reorders don't surprise
the user. Up/Down in metadata fields keeps default text behavior;
Up/Down with no field focused keeps the existing chapter-selection
behavior.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Verification

After all tasks land:

- [ ] **Final test run**

Run: `flutter test`
Expected: 235 prior tests + 6 Tab + 7 Up/Down = 248 tests passing.

- [ ] **Final analyzer**

Run: `flutter analyze`
Expected: no issues.

- [ ] **macOS smoke test** — open an `.m4b`, click into the first chapter title, press Tab a few times to walk through fields and rows, edit a chapter start time and press ArrowDown to commit + move, and confirm Up/Down in metadata fields doesn't change chapter selection.
