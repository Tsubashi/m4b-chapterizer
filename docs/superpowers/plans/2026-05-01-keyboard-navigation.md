# Keyboard Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add keyboard shortcuts covering media controls, chapter list navigation, file operations, and the "set chapter to playhead" action — with bare keys deferring to focused `TextField`s and modifier shortcuts always active.

**Architecture:** A new `lib/presentation/keyboard/shortcuts.dart` exports `Intent` classes, an `editorShortcuts()` keymap function, and an `EditorShortcuts` `ConsumerWidget`. The widget pairs Flutter's `Shortcuts` (the keymap) with `Actions` (the callback bodies, which read providers via `ref.read`). Bare-key shortcuts (`Space`, arrows, `Enter`, `Backspace`) are consumed by `EditableText` when a field has focus, so they only fire otherwise — no explicit focus check needed.

**Tech Stack:** Flutter `Shortcuts`/`Actions`/`Intent`/`CallbackAction` framework, `dart:io` `Platform` for macOS-vs-other key bindings, no new packages.

**Reference design:** `docs/superpowers/specs/2026-05-01-keyboard-navigation-design.md`

**Conventions:**
- `--no-gpg-sign` REQUIRED on every `git commit`.
- After every task, run `flutter test` and `flutter analyze` before committing.

---

## Task 1: Intent classes and `editorShortcuts()` keymap

Defines the data structures with no behavior. Tests verify the keymap entries map the right activators to the right intent types and use platform-correct modifiers.

**Files:**
- Create: `lib/presentation/keyboard/shortcuts.dart`
- Test: `test/presentation/keyboard_shortcuts_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/presentation/keyboard_shortcuts_test.dart`:

```dart
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/presentation/keyboard/shortcuts.dart';

void main() {
  group('editorShortcuts keymap', () {
    test('maps Space to PlayPauseIntent', () {
      final map = editorShortcuts();
      final entry = map.entries.firstWhere(
        (e) => e.value is PlayPauseIntent,
        orElse: () => throw StateError('no PlayPauseIntent'),
      );
      expect(entry.key,
          const SingleActivator(LogicalKeyboardKey.space));
    });

    test('maps ArrowLeft to ScrubIntent(-5s) and ArrowRight to +5s', () {
      final map = editorShortcuts();
      final left = map[const SingleActivator(LogicalKeyboardKey.arrowLeft)];
      final right = map[const SingleActivator(LogicalKeyboardKey.arrowRight)];
      expect(left, isA<ScrubIntent>());
      expect((left as ScrubIntent).delta, const Duration(seconds: -5));
      expect(right, isA<ScrubIntent>());
      expect((right as ScrubIntent).delta, const Duration(seconds: 5));
    });

    test('maps Shift+ArrowLeft and Shift+ArrowRight to ±30s', () {
      final map = editorShortcuts();
      final shiftLeft =
          map[const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true)];
      final shiftRight = map[
          const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true)];
      expect((shiftLeft as ScrubIntent).delta, const Duration(seconds: -30));
      expect((shiftRight as ScrubIntent).delta, const Duration(seconds: 30));
    });

    test('maps ArrowUp/ArrowDown to MoveChapterSelectionIntent ±1', () {
      final map = editorShortcuts();
      final up = map[const SingleActivator(LogicalKeyboardKey.arrowUp)];
      final down = map[const SingleActivator(LogicalKeyboardKey.arrowDown)];
      expect((up as MoveChapterSelectionIntent).delta, -1);
      expect((down as MoveChapterSelectionIntent).delta, 1);
    });

    test('uses meta modifier on macOS, control elsewhere for Save', () {
      final map = editorShortcuts();
      final saveEntry = map.entries.firstWhere((e) => e.value is SaveIntent);
      final activator = saveEntry.key as SingleActivator;
      expect(activator.trigger, LogicalKeyboardKey.keyS);
      if (Platform.isMacOS) {
        expect(activator.meta, isTrue);
        expect(activator.control, isFalse);
      } else {
        expect(activator.meta, isFalse);
        expect(activator.control, isTrue);
      }
    });

    test('contains entries for the documented intents', () {
      final map = editorShortcuts();
      final intentTypes = map.values.map((v) => v.runtimeType).toSet();
      expect(intentTypes, containsAll(<Type>[
        PlayPauseIntent,
        ScrubIntent,
        MoveChapterSelectionIntent,
        FocusSelectedChapterTitleIntent,
        DeleteSelectedChapterIntent,
        AddChapterIntent,
        SaveIntent,
        SaveAsIntent,
        OpenFileIntent,
        SetChapterToPlayheadIntent,
        DefocusIntent,
      ]));
    });
  });
}
```

- [ ] **Step 2: Run, see failures**

Run: `flutter test test/presentation/keyboard_shortcuts_test.dart`
Expected: FAIL — "Target of URI doesn't exist".

- [ ] **Step 3: Implement intents and keymap**

Create `lib/presentation/keyboard/shortcuts.dart`:

```dart
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class PlayPauseIntent extends Intent {
  const PlayPauseIntent();
}

class ScrubIntent extends Intent {
  const ScrubIntent(this.delta);
  final Duration delta;
}

class MoveChapterSelectionIntent extends Intent {
  const MoveChapterSelectionIntent(this.delta);
  final int delta;
}

class FocusSelectedChapterTitleIntent extends Intent {
  const FocusSelectedChapterTitleIntent();
}

class DeleteSelectedChapterIntent extends Intent {
  const DeleteSelectedChapterIntent();
}

class AddChapterIntent extends Intent {
  const AddChapterIntent();
}

class SaveIntent extends Intent {
  const SaveIntent();
}

class SaveAsIntent extends Intent {
  const SaveAsIntent();
}

class OpenFileIntent extends Intent {
  const OpenFileIntent();
}

class SetChapterToPlayheadIntent extends Intent {
  const SetChapterToPlayheadIntent();
}

class DefocusIntent extends Intent {
  const DefocusIntent();
}

/// Returns the editor's full keyboard shortcut map, with platform-correct
/// modifiers (`⌘` on macOS, `Ctrl` elsewhere).
Map<ShortcutActivator, Intent> editorShortcuts() {
  final isMac = Platform.isMacOS;
  SingleActivator cmd(LogicalKeyboardKey trigger, {bool shift = false}) =>
      SingleActivator(
        trigger,
        meta: isMac,
        control: !isMac,
        shift: shift,
      );

  return <ShortcutActivator, Intent>{
    const SingleActivator(LogicalKeyboardKey.space): const PlayPauseIntent(),
    const SingleActivator(LogicalKeyboardKey.arrowLeft):
        const ScrubIntent(Duration(seconds: -5)),
    const SingleActivator(LogicalKeyboardKey.arrowRight):
        const ScrubIntent(Duration(seconds: 5)),
    const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
        const ScrubIntent(Duration(seconds: -30)),
    const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
        const ScrubIntent(Duration(seconds: 30)),
    const SingleActivator(LogicalKeyboardKey.arrowUp):
        const MoveChapterSelectionIntent(-1),
    const SingleActivator(LogicalKeyboardKey.arrowDown):
        const MoveChapterSelectionIntent(1),
    const SingleActivator(LogicalKeyboardKey.enter):
        const FocusSelectedChapterTitleIntent(),
    const SingleActivator(LogicalKeyboardKey.backspace):
        const DeleteSelectedChapterIntent(),
    const SingleActivator(LogicalKeyboardKey.escape): const DefocusIntent(),
    cmd(LogicalKeyboardKey.keyN): const AddChapterIntent(),
    cmd(LogicalKeyboardKey.keyS): const SaveIntent(),
    cmd(LogicalKeyboardKey.keyS, shift: true): const SaveAsIntent(),
    cmd(LogicalKeyboardKey.keyO): const OpenFileIntent(),
    cmd(LogicalKeyboardKey.keyB): const SetChapterToPlayheadIntent(),
  };
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/presentation/keyboard_shortcuts_test.dart`
Expected: all 6 tests pass.

- [ ] **Step 5: Run analyzer**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/keyboard/shortcuts.dart test/presentation/keyboard_shortcuts_test.dart
git commit --no-gpg-sign -m "Add keyboard shortcut Intents and editorShortcuts keymap"
```

---

## Task 2: `EditorShortcuts` widget with media + Save + Defocus actions

Wire the simple actions: `PlayPauseIntent`, `ScrubIntent`, `DefocusIntent`, `SaveIntent`, `MoveChapterSelectionIntent`, `AddChapterIntent`, `DeleteSelectedChapterIntent`, `SetChapterToPlayheadIntent`. Defer `Open`, `SaveAs`, and `FocusSelectedChapterTitle` to later tasks.

**Files:**
- Modify: `lib/presentation/keyboard/shortcuts.dart`
- Modify: `lib/presentation/screens/editor_screen.dart`
- Modify: `test/presentation/keyboard_shortcuts_test.dart`

- [ ] **Step 1: Append failing tests**

Append the following at the end of `test/presentation/keyboard_shortcuts_test.dart`:

```dart
// ---- Widget integration helpers ----

class _StubBookbinder implements Bookbinder {
  _StubBookbinder([this._book]);
  Audiobook? _book;
  String? lastWritten;
  Audiobook? lastWrittenAudiobook;

  @override
  Future<Audiobook> read(String sourcePath) async =>
      _book ??= Audiobook.validated(
        title: 'KB Test',
        chapters: const [
          Chapter(title: 'Alpha', start: Duration.zero),
          Chapter(title: 'Beta', start: Duration(seconds: 10)),
          Chapter(title: 'Gamma', start: Duration(seconds: 20)),
        ],
        totalDuration: const Duration(seconds: 30),
      );

  @override
  Future<void> write({
    required String sourcePath,
    required String destinationPath,
    required Audiobook audiobook,
  }) async {
    lastWritten = destinationPath;
    lastWrittenAudiobook = audiobook;
  }
}

class _FakePlayback implements PlaybackController {
  final positionController = StreamController<Duration>.broadcast();
  final playingController = StreamController<bool>.broadcast();
  final List<Duration> seeks = [];
  Duration _pos = Duration.zero;
  bool _playing = false;

  @override
  Future<void> setSource(String path) async {}
  @override
  Future<void> play() async {
    _playing = true;
    playingController.add(true);
  }
  @override
  Future<void> pause() async {
    _playing = false;
    playingController.add(false);
  }
  @override
  Future<void> seek(Duration position) async {
    _pos = position;
    seeks.add(position);
  }
  @override
  Duration get position => _pos;
  void setPosition(Duration p) {
    _pos = p;
    positionController.add(p);
  }
  @override
  bool get playing => _playing;
  @override
  Stream<Duration> get positionStream => positionController.stream;
  @override
  Stream<bool> get playingStream => playingController.stream;
  @override
  Future<void> dispose() async {
    await positionController.close();
    await playingController.close();
  }
}

Future<({ProviderContainer container, _FakePlayback playback, _StubBookbinder book})>
    _pumpEditor(WidgetTester tester) async {
  final bookbinder = _StubBookbinder();
  final playback = _FakePlayback();
  final container = ProviderContainer(overrides: [
    bookbinderProvider.overrideWithValue(bookbinder),
    playbackControllerProvider.overrideWithValue(playback),
  ]);
  await container.read(editorProvider.notifier).open('/tmp/x.m4b');
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: EditorScreen()),
  ));
  await tester.pumpAndSettle();
  return (container: container, playback: playback, book: bookbinder);
}

Future<void> _sendCmdKey(WidgetTester tester, LogicalKeyboardKey key,
    {bool shift = false}) async {
  final mod = Platform.isMacOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(mod);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(mod);
  await tester.pump();
}

void _registerWidgetTests() {
  group('EditorShortcuts widget', () {
    testWidgets('Space toggles play when no field is focused',
        (tester) async {
      final h = await _pumpEditor(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(h.playback.playing, isTrue);
    });

    testWidgets('Space is consumed by a focused TextField',
        (tester) async {
      final h = await _pumpEditor(tester);
      // Focus the title field of chapter 0.
      await tester.tap(find.byKey(const ValueKey('chapters.title.0')));
      await tester.pump();
      await tester.enterText(
          find.byKey(const ValueKey('chapters.title.0')), 'Hello World');
      await tester.pump();
      expect(h.playback.playing, isFalse);
      expect(
        h.container.read(editorProvider).audiobook!.chapters.first.title,
        'Hello World',
      );
    });

    testWidgets('ArrowLeft scrubs 5 seconds back', (tester) async {
      final h = await _pumpEditor(tester);
      h.playback.setPosition(const Duration(seconds: 30));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(h.playback.seeks.last, const Duration(seconds: 25));
    });

    testWidgets('Shift+ArrowRight scrubs 30 seconds forward, clamped',
        (tester) async {
      final h = await _pumpEditor(tester);
      h.playback.setPosition(const Duration(seconds: 25));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      // Total = 30s; +30s would be 55s; clamped to 30s.
      expect(h.playback.seeks.last, const Duration(seconds: 30));
    });

    testWidgets('ArrowDown moves selection +1, clamped to length-1',
        (tester) async {
      final h = await _pumpEditor(tester);
      h.container.read(selectedChapterProvider.notifier).state = 1;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(h.container.read(selectedChapterProvider), 2);
      // One more press should not exceed 2.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(h.container.read(selectedChapterProvider), 2);
    });

    testWidgets('ArrowUp moves selection -1, clamped to 0',
        (tester) async {
      final h = await _pumpEditor(tester);
      h.container.read(selectedChapterProvider.notifier).state = 1;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(h.container.read(selectedChapterProvider), 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(h.container.read(selectedChapterProvider), 0);
    });

    testWidgets('Cmd+S triggers save', (tester) async {
      final h = await _pumpEditor(tester);
      // Make state dirty.
      h.container.read(editorProvider.notifier).setTitle('Edited');
      await _sendCmdKey(tester, LogicalKeyboardKey.keyS);
      expect(h.book.lastWritten, '/tmp/x.m4b');
    });

    testWidgets('Cmd+N adds a chapter', (tester) async {
      final h = await _pumpEditor(tester);
      final before = h.container.read(editorProvider).audiobook!.chapters.length;
      await _sendCmdKey(tester, LogicalKeyboardKey.keyN);
      final after = h.container.read(editorProvider).audiobook!.chapters.length;
      expect(after, before + 1);
    });

    testWidgets('Backspace deletes the selected chapter when no field focused',
        (tester) async {
      final h = await _pumpEditor(tester);
      h.container.read(selectedChapterProvider.notifier).state = 1;
      // Click an inert area to ensure the screen has focus, not a TextField.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      final titles = h.container
          .read(editorProvider)
          .audiobook!
          .chapters
          .map((c) => c.title)
          .toList();
      expect(titles, ['Alpha', 'Gamma']);
    });

    testWidgets('Cmd+B sets selected chapter start to playhead position',
        (tester) async {
      final h = await _pumpEditor(tester);
      h.container.read(selectedChapterProvider.notifier).state = 1;
      h.playback.setPosition(const Duration(milliseconds: 14500));
      await _sendCmdKey(tester, LogicalKeyboardKey.keyB);
      await tester.pump();
      // After reorder consideration — chapter "Beta" is still at index 1 since
      // 14500ms is between 10000 and 20000.
      final book = h.container.read(editorProvider).audiobook!;
      final beta = book.chapters.firstWhere((c) => c.title == 'Beta');
      expect(beta.start, const Duration(milliseconds: 14500));
    });

    testWidgets('Esc unfocuses the active field', (tester) async {
      await _pumpEditor(tester);
      await tester.tap(find.byKey(const ValueKey('chapters.title.0')));
      await tester.pump();
      // Verify we're focused inside an EditableText before sending Esc.
      expect(
        FocusManager.instance.primaryFocus
            ?.context?.findAncestorWidgetOfExactType<EditableText>(),
        isNotNull,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      // Primary focus is no longer inside an EditableText.
      final focused = FocusManager.instance.primaryFocus;
      expect(
        focused?.context?.findAncestorWidgetOfExactType<EditableText>(),
        isNull,
      );
    });
  });
}

// Top-level wrapper so the test groups run.
void main_widgets() => _registerWidgetTests();
```

The widget test group is registered via a separate function. Modify the actual `main()` at the top of the file to also call `_registerWidgetTests()`:

Find the existing `void main() { group('editorShortcuts keymap', ...) ... }` and append `_registerWidgetTests();` as the final line of `main()`.

Add the imports needed at the top of the test file (some of these may already be present from earlier additions — keep one of each):

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m4b_chapterizer/domain/bookbinder.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
import 'package:m4b_chapterizer/presentation/providers/editor_state.dart';
import 'package:m4b_chapterizer/presentation/providers/playback.dart';
import 'package:m4b_chapterizer/presentation/screens/editor_screen.dart';
import 'package:m4b_chapterizer/presentation/widgets/chapter_list.dart' show selectedChapterProvider;
```

- [ ] **Step 2: Run, see failures**

Run: `flutter test test/presentation/keyboard_shortcuts_test.dart`
Expected: widget tests fail because `EditorShortcuts` isn't wrapping `EditorScreen` yet.

- [ ] **Step 3: Implement `EditorShortcuts`**

Append to `lib/presentation/keyboard/shortcuts.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/editor_state.dart';
import '../providers/playback.dart';
import '../widgets/chapter_list.dart' show selectedChapterProvider;

class EditorShortcuts extends ConsumerWidget {
  const EditorShortcuts({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Shortcuts(
      shortcuts: editorShortcuts(),
      child: Actions(
        actions: <Type, Action<Intent>>{
          PlayPauseIntent: CallbackAction<PlayPauseIntent>(onInvoke: (_) {
            final c = ref.read(playbackControllerProvider);
            c.playing ? c.pause() : c.play();
            return null;
          }),
          ScrubIntent: CallbackAction<ScrubIntent>(onInvoke: (intent) {
            final c = ref.read(playbackControllerProvider);
            final book = ref.read(editorProvider).audiobook;
            if (book == null) return null;
            final raw = c.position + intent.delta;
            final clamped = raw < Duration.zero
                ? Duration.zero
                : (raw > book.totalDuration ? book.totalDuration : raw);
            c.seek(clamped);
            return null;
          }),
          MoveChapterSelectionIntent:
              CallbackAction<MoveChapterSelectionIntent>(onInvoke: (intent) {
            final book = ref.read(editorProvider).audiobook;
            if (book == null) return null;
            final cur = ref.read(selectedChapterProvider);
            final next = (cur + intent.delta)
                .clamp(0, book.chapters.length - 1);
            ref.read(selectedChapterProvider.notifier).state = next;
            return null;
          }),
          DeleteSelectedChapterIntent:
              CallbackAction<DeleteSelectedChapterIntent>(onInvoke: (_) {
            final book = ref.read(editorProvider).audiobook;
            if (book == null) return null;
            final idx = ref.read(selectedChapterProvider);
            ref.read(editorProvider.notifier).deleteChapter(idx);
            return null;
          }),
          AddChapterIntent: CallbackAction<AddChapterIntent>(onInvoke: (_) {
            ref.read(editorProvider.notifier).addChapter();
            return null;
          }),
          SaveIntent: CallbackAction<SaveIntent>(onInvoke: (_) {
            ref.read(editorProvider.notifier).save();
            return null;
          }),
          SetChapterToPlayheadIntent:
              CallbackAction<SetChapterToPlayheadIntent>(onInvoke: (_) {
            final book = ref.read(editorProvider).audiobook;
            if (book == null) return null;
            final idx = ref.read(selectedChapterProvider);
            final pos = ref.read(playbackControllerProvider).position;
            ref.read(editorProvider.notifier).setChapterStart(idx, pos);
            return null;
          }),
          DefocusIntent: CallbackAction<DefocusIntent>(onInvoke: (_) {
            FocusManager.instance.primaryFocus?.unfocus();
            return null;
          }),
          // SaveAsIntent, OpenFileIntent, FocusSelectedChapterTitleIntent
          // are wired in subsequent tasks.
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}
```

- [ ] **Step 4: Wrap `EditorScreen` body in `EditorShortcuts`**

Edit `lib/presentation/screens/editor_screen.dart`. Find the top of the `build` method's returned `Scaffold`. Wrap the *entire* `Scaffold` in an `EditorShortcuts`:

```dart
    return EditorShortcuts(
      child: Scaffold(
        // ... existing content unchanged
      ),
    );
```

Add the import at the top:

```dart
import '../keyboard/shortcuts.dart';
```

- [ ] **Step 5: Run all tests**

Run: `flutter test`
Expected: keyboard widget tests pass; existing tests continue to pass. (The existing dirty-marker test pumps `EditorScreen` in a `ProviderScope` with `bookbinderProvider` overridden — `EditorShortcuts` reads the same provider, so the wrap is transparent.)

- [ ] **Step 6: Run analyzer**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/presentation/keyboard/shortcuts.dart lib/presentation/screens/editor_screen.dart test/presentation/keyboard_shortcuts_test.dart
git commit --no-gpg-sign -m "Wire keyboard shortcuts for media controls, save, and chapter ops"
```

---

## Task 3: Extract `EditorActions` helper; wire `OpenFileIntent` and `SaveAsIntent`

The current `EditorScreen` defines the Open and Save-As callbacks inline. Extract them into a small helper class so the keyboard shortcuts can call into the same code path.

**Files:**
- Modify: `lib/presentation/screens/editor_screen.dart`
- Create: `lib/presentation/keyboard/editor_actions.dart`
- Modify: `lib/presentation/keyboard/shortcuts.dart`
- Modify: `test/presentation/keyboard_shortcuts_test.dart`

- [ ] **Step 1: Extract `EditorActions`**

Create `lib/presentation/keyboard/editor_actions.dart`:

```dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/editor_state.dart';
import '../util/file_picker_errors.dart';

/// Imperative editor actions shared between the AppBar buttons and
/// the keyboard shortcut bindings.
class EditorActions {
  EditorActions(this.context, this.ref);

  final BuildContext context;
  final WidgetRef ref;

  Future<bool> _confirmDiscard() async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        content:
            const Text('You have unsaved changes. Continue and lose them?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Discard')),
        ],
      ),
    );
    return answer ?? false;
  }

  Future<void> open() async {
    final state = ref.read(editorProvider);
    if (state.isDirty && !await _confirmDiscard()) return;
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

  Future<void> save() async {
    if (ref.read(editorProvider).audiobook == null) return;
    await ref.read(editorProvider.notifier).save();
  }

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
}
```

Add the necessary imports at the top of the new file:

```dart
import 'dart:io' show Platform;
```

- [ ] **Step 2: Replace inline handlers in `EditorScreen` with `EditorActions` calls**

In `lib/presentation/screens/editor_screen.dart`:

1. Add the import:
```dart
import '../keyboard/editor_actions.dart';
```

2. Replace the body of the `Open…` `TextButton`'s `onPressed` with:
```dart
            onPressed: () => EditorActions(context, ref).open(),
```

3. Replace the body of the `Save` `TextButton`'s `onPressed` with:
```dart
            onPressed: state.audiobook == null
                ? null
                : () => EditorActions(context, ref).save(),
```

4. Replace the body of the `Save As…` `TextButton`'s `onPressed` with:
```dart
            onPressed: state.audiobook == null
                ? null
                : () => EditorActions(context, ref).saveAs(),
```

5. Remove the now-unused `_confirmDiscard` method from the file (the helper is duplicated inside `EditorActions`).

- [ ] **Step 3: Wire `OpenFileIntent` and `SaveAsIntent` actions**

In `lib/presentation/keyboard/shortcuts.dart`'s `EditorShortcuts.build`, add to the `actions` map (alongside the existing entries):

```dart
          OpenFileIntent: CallbackAction<OpenFileIntent>(onInvoke: (_) {
            EditorActions(context, ref).open();
            return null;
          }),
          SaveAsIntent: CallbackAction<SaveAsIntent>(onInvoke: (_) {
            EditorActions(context, ref).saveAs();
            return null;
          }),
```

Add the import:
```dart
import 'editor_actions.dart';
```

- [ ] **Step 4: Verify existing tests still pass**

Run: `flutter test`
Expected: all tests pass — the refactor is behavior-preserving (existing dirty-marker test, file picker error test, etc. continue to work).

- [ ] **Step 5: Run analyzer**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/keyboard/editor_actions.dart lib/presentation/screens/editor_screen.dart lib/presentation/keyboard/shortcuts.dart test/presentation/keyboard_shortcuts_test.dart
git commit --no-gpg-sign -m "Extract EditorActions; wire Open and Save-As keyboard shortcuts"
```

---

## Task 4: `FocusSelectedChapterTitleIntent` via per-row `FocusNode`

`Enter` (when no field is focused) should focus the title field of the currently-selected chapter. This requires the chapter list to register `FocusNode`s by index in a Riverpod provider that the action reads.

**Files:**
- Modify: `lib/presentation/widgets/chapter_list.dart`
- Modify: `lib/presentation/keyboard/shortcuts.dart`
- Modify: `test/presentation/keyboard_shortcuts_test.dart`

- [ ] **Step 1: Append failing test**

Append inside `_registerWidgetTests()` in `test/presentation/keyboard_shortcuts_test.dart`:

```dart
    testWidgets('Enter focuses the selected chapter title field',
        (tester) async {
      final h = await _pumpEditor(tester);
      h.container.read(selectedChapterProvider.notifier).state = 1;
      await tester.pump();

      // Ensure no field is currently focused.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      final focused = FocusManager.instance.primaryFocus;
      expect(focused, isNotNull);
      // The focus node should be the one belonging to chapter 1's title.
      final nodes = h.container.read(chapterTitleFocusNodesProvider);
      expect(focused, nodes[1]);
    });
```

- [ ] **Step 2: Run, see failure**

Run: `flutter test test/presentation/keyboard_shortcuts_test.dart`
Expected: the test fails because `chapterTitleFocusNodesProvider` doesn't exist and `FocusSelectedChapterTitleIntent` has no action.

- [ ] **Step 3: Add the provider and register focus nodes per chapter row**

In `lib/presentation/widgets/chapter_list.dart`:

1. Add the provider near the top, alongside `selectedChapterProvider`:
```dart
final chapterTitleFocusNodesProvider =
    Provider<Map<int, FocusNode>>((ref) => <int, FocusNode>{});
```

2. Modify `_ChapterRow` to consume the provider and register/unregister its focus node. Convert the row from `StatefulWidget` to `ConsumerStatefulWidget`:

Replace `class _ChapterRow extends StatefulWidget` with:
```dart
class _ChapterRow extends ConsumerStatefulWidget {
```

Replace `class _ChapterRowState extends State<_ChapterRow>` with:
```dart
class _ChapterRowState extends ConsumerState<_ChapterRow> {
```

3. Add a `FocusNode` field and registration logic. Modify the existing `initState`:
```dart
  late final FocusNode _titleFocusNode;
  late final TextEditingController _titleController;
  late final TextEditingController _startController;

  @override
  void initState() {
    super.initState();
    _titleFocusNode = FocusNode();
    _titleController = TextEditingController(text: widget.chapter.title);
    _startController =
        TextEditingController(text: formatDuration(widget.chapter.start));
    final nodes = ref.read(chapterTitleFocusNodesProvider);
    nodes[widget.index] = _titleFocusNode;
  }
```

4. In `didUpdateWidget`, re-register if the index changed (chapter reorder):
```dart
  @override
  void didUpdateWidget(covariant _ChapterRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      final nodes = ref.read(chapterTitleFocusNodesProvider);
      nodes.remove(oldWidget.index);
      nodes[widget.index] = _titleFocusNode;
    }
    if (widget.chapter.title != _titleController.text) {
      _titleController.text = widget.chapter.title;
    }
    final formatted = formatDuration(widget.chapter.start);
    if (formatted != _startController.text) {
      _startController.text = formatted;
    }
  }
```

5. In `dispose`, unregister:
```dart
  @override
  void dispose() {
    final nodes = ref.read(chapterTitleFocusNodesProvider);
    nodes.remove(widget.index);
    _titleFocusNode.dispose();
    _titleController.dispose();
    _startController.dispose();
    super.dispose();
  }
```

6. Pass the focus node to the title `TextField`:
```dart
            child: TextField(
              key: ValueKey('chapters.title.${widget.index}'),
              focusNode: _titleFocusNode,
              controller: _titleController,
              // ... rest unchanged
            ),
```

- [ ] **Step 4: Wire `FocusSelectedChapterTitleIntent` action**

In `lib/presentation/keyboard/shortcuts.dart`'s `EditorShortcuts.build`, add to the `actions` map:

```dart
          FocusSelectedChapterTitleIntent:
              CallbackAction<FocusSelectedChapterTitleIntent>(
            onInvoke: (_) {
              final idx = ref.read(selectedChapterProvider);
              final nodes = ref.read(chapterTitleFocusNodesProvider);
              nodes[idx]?.requestFocus();
              return null;
            },
          ),
```

Update the existing `chapter_list.dart` import to expose `chapterTitleFocusNodesProvider`:

```dart
import '../widgets/chapter_list.dart' show selectedChapterProvider, chapterTitleFocusNodesProvider;
```

- [ ] **Step 5: Run all tests**

Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 6: Run analyzer**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Smoke-test on macOS**

```bash
flutter run -d macos
```

Open `test/fixtures/sample.m4b`. Verify:
- `Space` plays/pauses; typing in a title field types a space.
- `←` / `→` scrub 5s; `Shift+←` / `→` scrub 30s.
- `↑` / `↓` move chapter selection.
- `Enter` (with no field focused) focuses the selected chapter's title field.
- `Backspace` (with no field focused) deletes the selected chapter.
- `⌘N` adds a chapter; `⌘S` saves; `⌘⇧S` opens save-as dialog; `⌘O` opens open-file dialog (with discard confirm if dirty).
- `⌘B` sets the selected chapter start to the current playhead.
- `Esc` defocuses the active field.

- [ ] **Step 8: Commit**

```bash
git add lib/presentation/widgets/chapter_list.dart lib/presentation/keyboard/shortcuts.dart test/presentation/keyboard_shortcuts_test.dart
git commit --no-gpg-sign -m "Wire Enter to focus selected chapter title via FocusNode provider"
```

---

## Final verification

- [ ] `flutter test` — all tests green.
- [ ] `flutter analyze` — clean.
- [ ] macOS smoke test (Task 4 Step 7) confirms every shortcut.
