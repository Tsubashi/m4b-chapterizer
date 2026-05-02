import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/bookbinder.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
import 'package:m4b_chapterizer/presentation/keyboard/shortcuts.dart';
import 'package:m4b_chapterizer/presentation/providers/editor_state.dart';
import 'package:m4b_chapterizer/presentation/providers/playback.dart';
import 'package:m4b_chapterizer/presentation/screens/editor_screen.dart';
import 'package:m4b_chapterizer/presentation/widgets/chapter_list.dart'
    show selectedChapterProvider;

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
