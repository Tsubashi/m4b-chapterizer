import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/bookbinder.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
import 'package:m4b_chapterizer/presentation/drag_drop/drag_drop_channel.dart';
import 'package:m4b_chapterizer/presentation/keyboard/shortcuts.dart';
import 'package:m4b_chapterizer/presentation/providers/editor_state.dart';
import 'package:m4b_chapterizer/presentation/providers/playback.dart';
import 'package:m4b_chapterizer/presentation/screens/editor_screen.dart';
import 'package:m4b_chapterizer/presentation/widgets/chapter_list.dart'
    show
        chapterScrollRequestProvider,
        chapterStartFocusNodesProvider,
        chapterTitleFocusNodesProvider,
        selectedChapterProvider;

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
        UndoIntent,
        RedoIntent,
      ]));
    });
  });

  _registerWidgetTests();
}

// ---- Widget integration helpers ----

class _StubBookbinder implements Bookbinder {
  // ignore: unused_element_parameter
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

class _StubChannel implements DragDropChannel {
  @override
  Stream<DragEvent> get events => const Stream.empty();
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
    dragDropChannelProvider.overrideWithValue(_StubChannel()),
  ]);
  await container.read(editorProvider.notifier).open('/tmp/x.m4b');
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: EditorScreen()),
  ));
  await tester.pumpAndSettle();
  return (container: container, playback: playback, book: bookbinder);
}

Future<({ProviderContainer container, _FakePlayback playback, _StubBookbinder book})>
    _pumpEditorWith4Chapters(WidgetTester tester) async {
  final audiobook = Audiobook.validated(
    title: 'KB Test 4',
    chapters: const [
      Chapter(title: 'A', start: Duration.zero),
      Chapter(title: 'B', start: Duration(seconds: 10)),
      Chapter(title: 'C', start: Duration(seconds: 30)),
      Chapter(title: 'D', start: Duration(seconds: 40)),
    ],
    totalDuration: const Duration(seconds: 60),
  );
  final bookbinder = _StubBookbinder(audiobook);
  final playback = _FakePlayback();
  final container = ProviderContainer(overrides: [
    bookbinderProvider.overrideWithValue(bookbinder),
    playbackControllerProvider.overrideWithValue(playback),
    dragDropChannelProvider.overrideWithValue(_StubChannel()),
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

    testWidgets(
        'Backspace does NOT delete a chapter while a TextField is focused',
        (tester) async {
      final h = await _pumpEditor(tester);
      h.container.read(selectedChapterProvider.notifier).state = 1;
      final beforeCount =
          h.container.read(editorProvider).audiobook!.chapters.length;

      // Focus the title field of chapter 1 — real focus, not test text input.
      await tester.tap(find.byKey(const ValueKey('chapters.title.1')));
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus
            ?.context?.findAncestorWidgetOfExactType<EditableText>(),
        isNotNull,
        reason: 'precondition: an EditableText must be focused',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      final afterCount =
          h.container.read(editorProvider).audiobook!.chapters.length;
      expect(afterCount, beforeCount,
          reason: 'Backspace should be consumed by the focused field');
    });

    testWidgets(
        'Space does NOT toggle play while a TextField is focused',
        (tester) async {
      final h = await _pumpEditor(tester);
      await tester.tap(find.byKey(const ValueKey('chapters.title.0')));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(h.playback.playing, isFalse);
    });

    testWidgets(
        'ArrowDown in a chapter title field commits and jumps to the next row',
        (tester) async {
      final h = await _pumpEditor(tester);
      h.container.read(selectedChapterProvider.notifier).state = 0;
      await tester.tap(find.byKey(const ValueKey('chapters.title.0')));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      // New behavior: Up/Down inside chapter fields jump rows. Detailed
      // expectations live in the "Chapter-list keyboard: Up / Down" group.
      expect(h.container.read(selectedChapterProvider), 1);
    });

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

    testWidgets('ArrowDown bumps the scroll request counter',
        (tester) async {
      final h = await _pumpEditor(tester);
      h.container.read(selectedChapterProvider.notifier).state = 0;
      final before = h.container.read(chapterScrollRequestProvider);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      expect(
        h.container.read(chapterScrollRequestProvider),
        greaterThan(before),
        reason: 'arrow nav should request a scroll-into-view',
      );
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

    testWidgets(
        'Backspace deletes a character when a TextField is focused',
        (tester) async {
      await _pumpEditor(tester);
      final fieldFinder = find.byKey(const ValueKey('chapters.title.0'));
      await tester.tap(fieldFinder);
      await tester.pump();

      final state = tester.state<EditableTextState>(
        find.descendant(
            of: fieldFinder, matching: find.byType(EditableText)),
      );
      final controller = state.widget.controller;
      // Place cursor at end of "Alpha".
      controller.selection =
          TextSelection.collapsed(offset: controller.text.length);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      expect(controller.text, 'Alph',
          reason: 'Backspace should delete a character in the focused field');
    });

    // Note: there is no widget test verifying that pressing Space inserts a
    // space character into a focused TextField. Printable characters in
    // Flutter desktop apps reach the field via the OS's IME / text-input
    // channel, not via the hardware key-event path that `sendKeyEvent`
    // simulates, so the Space-inserts behavior must be verified by smoke
    // test on the real macOS build. The "Space does NOT toggle play while a
    // TextField is focused" test above proves our shortcut returns
    // KeyEventResult.ignored, which is what the OS needs to route the event
    // to text input.

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

    testWidgets('Cmd+Z undoes when no field is focused', (tester) async {
      final h = await _pumpEditor(tester);
      final beforeCount =
          h.container.read(editorProvider).audiobook!.chapters.length;

      // Programmatically add a chapter; this records an undo step.
      h.container.read(editorProvider.notifier).addChapter();
      expect(
        h.container.read(editorProvider).audiobook!.chapters.length,
        beforeCount + 1,
      );

      await _sendCmdKey(tester, LogicalKeyboardKey.keyZ);
      expect(
        h.container.read(editorProvider).audiobook!.chapters.length,
        beforeCount,
      );
    });

    testWidgets(
        'Cmd+Z while a TextField is focused cancels the in-flight edit',
        (tester) async {
      final h = await _pumpEditor(tester);
      final originalTitle =
          h.container.read(editorProvider).audiobook!.chapters.first.title;

      // Focus the chapter 0 title field; type into it.
      await tester.tap(find.byKey(const ValueKey('chapters.title.0')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('chapters.title.0')),
        'Modified',
      );
      await tester.pump();
      expect(
        h.container.read(editorProvider).audiobook!.chapters.first.title,
        'Modified',
      );

      await _sendCmdKey(tester, LogicalKeyboardKey.keyZ);
      await tester.pumpAndSettle();

      // Title reverted; primary focus no longer in EditableText; no undo step.
      expect(
        h.container.read(editorProvider).audiobook!.chapters.first.title,
        originalTitle,
      );
      expect(
        FocusManager.instance.primaryFocus
            ?.context?.findAncestorWidgetOfExactType<EditableText>(),
        isNull,
      );
      expect(h.container.read(editorProvider).canUndo, isFalse);
    });

    testWidgets('Cmd+Shift+Z redoes when no field is focused',
        (tester) async {
      final h = await _pumpEditor(tester);
      final beforeCount =
          h.container.read(editorProvider).audiobook!.chapters.length;
      h.container.read(editorProvider.notifier).addChapter();
      h.container.read(editorProvider.notifier).undo();
      expect(
        h.container.read(editorProvider).audiobook!.chapters.length,
        beforeCount,
      );

      await _sendCmdKey(tester, LogicalKeyboardKey.keyZ, shift: true);
      expect(
        h.container.read(editorProvider).audiobook!.chapters.length,
        beforeCount + 1,
      );
    });

    testWidgets('Cmd+Shift+Z while a TextField is focused is a no-op',
        (tester) async {
      final h = await _pumpEditor(tester);
      // Build a redo step, then focus a field and try Cmd+Shift+Z.
      h.container.read(editorProvider.notifier).addChapter();
      h.container.read(editorProvider.notifier).undo();

      await tester.tap(find.byKey(const ValueKey('chapters.title.0')));
      await tester.pump();

      final beforeRedoCanRedo =
          h.container.read(editorProvider).canRedo;
      await _sendCmdKey(tester, LogicalKeyboardKey.keyZ, shift: true);
      // Redo did NOT fire — canRedo unchanged.
      expect(h.container.read(editorProvider).canRedo, beforeRedoCanRedo);
    });

    group('Chapter-list keyboard: Up / Down', () {
      testWidgets('ArrowDown in title commits and focuses next title',
          (tester) async {
        final h = await _pumpEditor(tester);
        await tester.tap(find.byKey(const ValueKey('chapters.title.0')));
        await tester.pumpAndSettle();
        await tester.enterText(
            find.byKey(const ValueKey('chapters.title.0')),
            'New Title');
        await tester.pump();

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();

        final book = h.container.read(editorProvider).audiobook!;
        expect(book.chapters[0].title, 'New Title');
        expect(h.container.read(selectedChapterProvider), 1);
        final titleNodes =
            h.container.read(chapterTitleFocusNodesProvider);
        expect(FocusManager.instance.primaryFocus, titleNodes[1]);
      });

      testWidgets('ArrowUp in start focuses previous start',
          (tester) async {
        final h = await _pumpEditor(tester);
        await tester.tap(find.byKey(const ValueKey('chapters.start.1')));
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();

        final startNodes =
            h.container.read(chapterStartFocusNodesProvider);
        expect(FocusManager.instance.primaryFocus, startNodes[0]);
        expect(h.container.read(selectedChapterProvider), 0);
      });

      testWidgets(
          'ArrowUp in start with valid new time uses pre-commit position',
          (tester) async {
        // 4 chapters: A=0, B=10s, C=30s, D=40s.
        final h = await _pumpEditorWith4Chapters(tester);
        await tester.tap(find.byKey(const ValueKey('chapters.start.2')));
        await tester.pumpAndSettle();
        await tester.enterText(
            find.byKey(const ValueKey('chapters.start.2')),
            '00:00:00.005');
        await tester.pump();

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();

        // Commit reorders to [A, C, B, D]. Pre-commit target was B
        // (idx 1). B's new idx is 2. Selection lands at 2.
        final book = h.container.read(editorProvider).audiobook!;
        expect(book.chapters[1].title, 'C');
        expect(book.chapters[2].title, 'B');
        expect(h.container.read(selectedChapterProvider), 2);
        final startNodes =
            h.container.read(chapterStartFocusNodesProvider);
        expect(FocusManager.instance.primaryFocus, startNodes[2]);
      });

      testWidgets('ArrowUp at first chapter is a no-op', (tester) async {
        final h = await _pumpEditor(tester);
        await tester.tap(find.byKey(const ValueKey('chapters.title.0')));
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();

        final titleNodes =
            h.container.read(chapterTitleFocusNodesProvider);
        expect(FocusManager.instance.primaryFocus, titleNodes[0]);
        expect(h.container.read(selectedChapterProvider), 0);
      });

      testWidgets('ArrowDown at last chapter is a no-op', (tester) async {
        final h = await _pumpEditor(tester);
        await tester.tap(find.byKey(const ValueKey('chapters.start.2')));
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();

        final startNodes =
            h.container.read(chapterStartFocusNodesProvider);
        expect(FocusManager.instance.primaryFocus, startNodes[2]);
        expect(h.container.read(selectedChapterProvider), 2);
      });

      testWidgets('ArrowDown in metadata field does not move chapter selection',
          (tester) async {
        final h = await _pumpEditor(tester);
        final initial = h.container.read(selectedChapterProvider);
        await tester.tap(find.byKey(const ValueKey('metadata.title')));
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();

        expect(h.container.read(selectedChapterProvider), initial);
      });

      testWidgets(
          'ArrowDown in start with unparseable text reverts and moves',
          (tester) async {
        final h = await _pumpEditor(tester);
        final originalStart = h.container
            .read(editorProvider)
            .audiobook!
            .chapters[0]
            .start;
        await tester.tap(find.byKey(const ValueKey('chapters.start.0')));
        await tester.pumpAndSettle();
        await tester.enterText(
            find.byKey(const ValueKey('chapters.start.0')), 'garbage');
        await tester.pump();

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();

        final book = h.container.read(editorProvider).audiobook!;
        expect(book.chapters[0].start, originalStart);
        expect(h.container.read(selectedChapterProvider), 1);
        final startNodes =
            h.container.read(chapterStartFocusNodesProvider);
        expect(FocusManager.instance.primaryFocus, startNodes[1]);
      });
    });
  });
}
