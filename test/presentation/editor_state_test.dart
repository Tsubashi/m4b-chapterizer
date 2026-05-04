import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/bookbinder.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
import 'package:m4b_chapterizer/domain/models/cover.dart';
import 'package:m4b_chapterizer/presentation/providers/editor_state.dart';
import 'package:m4b_chapterizer/presentation/providers/playback.dart';
import 'package:m4b_chapterizer/presentation/widgets/chapter_list.dart';

class _FakeBookbinder implements Bookbinder {
  _FakeBookbinder(this._book);
  final Audiobook _book;
  String? lastWritten;
  Audiobook? lastWrittenAudiobook;

  @override
  Future<Audiobook> read(String sourcePath) async => _book;

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
  Duration currentPosition = Duration.zero;
  @override
  Future<void> setSource(String path) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    currentPosition = position;
  }
  @override
  Duration get position => currentPosition;
  @override
  bool get playing => false;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<bool> get playingStream => const Stream.empty();
  @override
  Future<void> dispose() async {}
}

void main() {
  final book = Audiobook.validated(
    title: 'Original',
    chapters: const [
      Chapter(title: 'C1', start: Duration.zero),
      Chapter(title: 'C2', start: Duration(seconds: 5)),
    ],
    totalDuration: const Duration(seconds: 10),
  );

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

  test('initial state has no audiobook and is not dirty', () {
    final fake = _FakeBookbinder(book);
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    final state = container.read(editorProvider);
    expect(state.audiobook, isNull);
    expect(state.isDirty, isFalse);
    expect(state.path, isNull);
  });

  test('open loads an audiobook and resets dirty', () async {
    final fake = _FakeBookbinder(book);
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/tmp/foo.m4b');
    final state = container.read(editorProvider);
    expect(state.audiobook?.title, 'Original');
    expect(state.path, '/tmp/foo.m4b');
    expect(state.isDirty, isFalse);
  });

  test('setTitle marks dirty and updates the title', () async {
    final fake = _FakeBookbinder(book);
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/tmp/foo.m4b');
    container.read(editorProvider.notifier).setTitle('Edited');
    final state = container.read(editorProvider);
    expect(state.audiobook?.title, 'Edited');
    expect(state.isDirty, isTrue);
  });

  test('the rest of the metadata setters update the matching field', () async {
    final fake = _FakeBookbinder(book);
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/tmp/foo.m4b');
    final n = container.read(editorProvider.notifier);
    n.setAuthor('AU');
    n.setNarrator('NA');
    n.setAlbum('AL');
    n.setGenre('GE');
    n.setDescription('DE');
    n.setYear(1999);
    final book2 = container.read(editorProvider).audiobook!;
    expect(book2.author, 'AU');
    expect(book2.narrator, 'NA');
    expect(book2.album, 'AL');
    expect(book2.genre, 'GE');
    expect(book2.description, 'DE');
    expect(book2.year, 1999);
    expect(container.read(editorProvider).isDirty, isTrue);
  });

  test('replaceCover sets the cover and pushes one undo step', () async {
    final fake = _FakeBookbinder(book);
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/tmp/foo.m4b');
    final cover = Cover(
      bytes: Uint8List.fromList([1, 2, 3]),
      mimeType: 'image/png',
    );
    container.read(editorProvider.notifier).replaceCover(cover);
    expect(container.read(editorProvider).audiobook?.cover, cover);
    expect(container.read(editorProvider).canUndo, isTrue);
    container.read(editorProvider.notifier).undo();
    expect(container.read(editorProvider).audiobook?.cover, isNull);
  });

  test('setter on a notifier with no audiobook is a no-op', () {
    final fake = _FakeBookbinder(book);
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    // Note: no `open` — audiobook stays null.
    final n = container.read(editorProvider.notifier);
    n.setTitle('whatever');
    n.addChapter();
    n.deleteChapter(0);
    n.setChapterStart(0, const Duration(seconds: 1));
    n.clearCover();
    expect(container.read(editorProvider).audiobook, isNull);
    expect(container.read(editorProvider).isDirty, isFalse);
  });

  test('save writes back to the loaded path and clears dirty', () async {
    final fake = _FakeBookbinder(book);
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/tmp/foo.m4b');
    container.read(editorProvider.notifier).setTitle('Edited');
    await container.read(editorProvider.notifier).save();
    expect(fake.lastWritten, '/tmp/foo.m4b');
    expect(fake.lastWrittenAudiobook?.title, 'Edited');
    expect(container.read(editorProvider).isDirty, isFalse);
  });

  test('saveAs writes to a new path and updates the loaded path', () async {
    final fake = _FakeBookbinder(book);
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/tmp/foo.m4b');
    await container.read(editorProvider.notifier).saveAs('/tmp/bar.m4b');
    final state = container.read(editorProvider);
    expect(fake.lastWritten, '/tmp/bar.m4b');
    expect(state.path, '/tmp/bar.m4b');
    expect(state.isDirty, isFalse);
  });

  test('addChapter inserts at the end and marks dirty', () async {
    final fake = _FakeBookbinder(book);
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/tmp/foo.m4b');
    container.read(editorProvider.notifier).addChapter();
    final state = container.read(editorProvider);
    expect(state.audiobook?.chapters.length, 3);
    expect(state.isDirty, isTrue);
  });

  test('deleteChapter removes the indexed chapter', () async {
    final fake = _FakeBookbinder(book);
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/tmp/foo.m4b');
    container.read(editorProvider.notifier).deleteChapter(0);
    final state = container.read(editorProvider);
    expect(state.audiobook?.chapters.length, 1);
    expect(state.audiobook?.chapters.first.title, 'C2');
    // The first chapter was removed; the new first chapter must start at zero.
    expect(state.audiobook?.chapters.first.start, Duration.zero);
  });

  test('setChapterStart updates the chapter at index', () async {
    final fake = _FakeBookbinder(book);
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/tmp/foo.m4b');
    container
        .read(editorProvider.notifier)
        .setChapterStart(1, const Duration(seconds: 7));
    final state = container.read(editorProvider);
    expect(state.audiobook?.chapters[1].start, const Duration(seconds: 7));
  });

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
  });

  group('undo/redo', () {
    Audiobook book3() => Audiobook.validated(
          title: 'Original',
          chapters: const [
            Chapter(title: 'A', start: Duration.zero),
            Chapter(title: 'B', start: Duration(seconds: 5)),
            Chapter(title: 'C', start: Duration(seconds: 10)),
          ],
          totalDuration: const Duration(seconds: 30),
        );

    test('discrete op pushes one undo step; undo reverts', () async {
      final fake = _FakeBookbinder(book3());
      final container = makeContainer(fake);
      addTearDown(container.dispose);
      await container.read(editorProvider.notifier).open('/tmp/x.m4b');

      container.read(editorProvider.notifier).addChapter();
      expect(
        container.read(editorProvider).audiobook!.chapters.length,
        4,
      );
      expect(container.read(editorProvider).canUndo, isTrue);

      container.read(editorProvider.notifier).undo();
      expect(
        container.read(editorProvider).audiobook!.chapters.length,
        3,
      );
      expect(container.read(editorProvider).canUndo, isFalse);
      expect(container.read(editorProvider).canRedo, isTrue);
    });

    test('continuous op without session does not push', () async {
      final fake = _FakeBookbinder(book3());
      final container = makeContainer(fake);
      addTearDown(container.dispose);
      await container.read(editorProvider.notifier).open('/tmp/x.m4b');

      container.read(editorProvider.notifier).setTitle('Foo');
      expect(container.read(editorProvider).canUndo, isFalse);
    });

    test('begin then end with no change pushes nothing', () async {
      final fake = _FakeBookbinder(book3());
      final container = makeContainer(fake);
      addTearDown(container.dispose);
      await container.read(editorProvider.notifier).open('/tmp/x.m4b');

      final n = container.read(editorProvider.notifier);
      n.beginFieldEdit();
      n.endFieldEdit();
      expect(container.read(editorProvider).canUndo, isFalse);
    });

    test('session with continuous mutations pushes one step', () async {
      final fake = _FakeBookbinder(book3());
      final container = makeContainer(fake);
      addTearDown(container.dispose);
      await container.read(editorProvider.notifier).open('/tmp/x.m4b');

      final n = container.read(editorProvider.notifier);
      n.beginFieldEdit();
      n.setTitle('Foo');
      n.setTitle('FooBar');
      n.endFieldEdit();

      expect(container.read(editorProvider).audiobook!.title, 'FooBar');
      expect(container.read(editorProvider).canUndo, isTrue);

      n.undo();
      expect(container.read(editorProvider).audiobook!.title, 'Original');
    });

    test('cancelFieldEdit reverts state and pushes nothing', () async {
      final fake = _FakeBookbinder(book3());
      final container = makeContainer(fake);
      addTearDown(container.dispose);
      await container.read(editorProvider.notifier).open('/tmp/x.m4b');

      final n = container.read(editorProvider.notifier);
      n.beginFieldEdit();
      n.setTitle('Foo');
      n.cancelFieldEdit();

      expect(container.read(editorProvider).audiobook!.title, 'Original');
      expect(container.read(editorProvider).canUndo, isFalse);
    });

    test('discrete op during session closes the session first', () async {
      final fake = _FakeBookbinder(book3());
      final container = makeContainer(fake);
      addTearDown(container.dispose);
      await container.read(editorProvider.notifier).open('/tmp/x.m4b');

      final n = container.read(editorProvider.notifier);
      n.beginFieldEdit();
      n.setTitle('Foo');
      n.addChapter();

      // Two undo steps recorded: one for the title edit (closed by addChapter),
      // one for addChapter itself.
      n.undo();
      // Most recent op is addChapter — undo it.
      expect(container.read(editorProvider).audiobook!.chapters.length, 3);
      expect(container.read(editorProvider).audiobook!.title, 'Foo');

      n.undo();
      expect(container.read(editorProvider).audiobook!.title, 'Original');
      expect(container.read(editorProvider).canUndo, isFalse);
    });

    test('redo reverses an undo', () async {
      final fake = _FakeBookbinder(book3());
      final container = makeContainer(fake);
      addTearDown(container.dispose);
      await container.read(editorProvider.notifier).open('/tmp/x.m4b');

      final n = container.read(editorProvider.notifier);
      n.beginFieldEdit();
      n.setTitle('Foo');
      n.endFieldEdit();
      n.undo();
      expect(container.read(editorProvider).audiobook!.title, 'Original');

      n.redo();
      expect(container.read(editorProvider).audiobook!.title, 'Foo');
    });

    test('any new mutation after undo clears redo stack', () async {
      final fake = _FakeBookbinder(book3());
      final container = makeContainer(fake);
      addTearDown(container.dispose);
      await container.read(editorProvider.notifier).open('/tmp/x.m4b');

      final n = container.read(editorProvider.notifier);
      n.addChapter();
      n.undo();
      expect(container.read(editorProvider).canRedo, isTrue);

      n.addChapter();
      expect(container.read(editorProvider).canRedo, isFalse);
    });

    test('open clears both stacks', () async {
      final fake = _FakeBookbinder(book3());
      final container = makeContainer(fake);
      addTearDown(container.dispose);
      await container.read(editorProvider.notifier).open('/tmp/x.m4b');

      final n = container.read(editorProvider.notifier);
      n.addChapter();
      n.undo();
      expect(container.read(editorProvider).canUndo, isFalse);
      expect(container.read(editorProvider).canRedo, isTrue);

      await n.open('/tmp/x.m4b');
      expect(container.read(editorProvider).canUndo, isFalse);
      expect(container.read(editorProvider).canRedo, isFalse);
    });

    test('save leaves stacks alone', () async {
      final fake = _FakeBookbinder(book3());
      final container = makeContainer(fake);
      addTearDown(container.dispose);
      await container.read(editorProvider.notifier).open('/tmp/x.m4b');

      final n = container.read(editorProvider.notifier);
      n.addChapter();
      await n.save();
      expect(container.read(editorProvider).canUndo, isTrue);
    });
  });

  group('addChapter inserts at the playhead', () {
    Audiobook threeChapterBook() => Audiobook.validated(
          chapters: const [
            Chapter(title: 'A', start: Duration.zero),
            Chapter(title: 'B', start: Duration(seconds: 10)),
            Chapter(title: 'C', start: Duration(seconds: 20)),
          ],
          totalDuration: const Duration(seconds: 30),
        );

    test('uses the current playback position as the new start', () async {
      final fake = _FakeBookbinder(threeChapterBook());
      final playback = _RecordingPlayback()
        ..currentPosition = const Duration(seconds: 7);
      final container = makeContainer(fake, playback: playback);
      addTearDown(container.dispose);
      await container.read(editorProvider.notifier).open('/tmp/x.m4b');

      container.read(editorProvider.notifier).addChapter();

      final book = container.read(editorProvider).audiobook!;
      expect(book.chapters.length, 4);
      // After sort: 0, 7, 10, 20.
      expect(book.chapters[1].start, const Duration(seconds: 7));
      expect(book.chapters[1].title, 'New chapter');
    });

    test('clamps a position past totalDuration', () async {
      final fake = _FakeBookbinder(threeChapterBook());
      final playback = _RecordingPlayback()
        ..currentPosition = const Duration(seconds: 60); // past 30s total
      final container = makeContainer(fake, playback: playback);
      addTearDown(container.dispose);
      await container.read(editorProvider.notifier).open('/tmp/x.m4b');

      container.read(editorProvider.notifier).addChapter();

      final book = container.read(editorProvider).audiobook!;
      expect(book.chapters.length, 4);
      expect(book.chapters.last.start,
          const Duration(milliseconds: 29999));
    });

    test('bumps by 1ms when the playhead is exactly on an existing chapter',
        () async {
      final fake = _FakeBookbinder(threeChapterBook());
      // Park the playhead exactly on chapter B's start.
      final playback = _RecordingPlayback()
        ..currentPosition = const Duration(seconds: 10);
      final container = makeContainer(fake, playback: playback);
      addTearDown(container.dispose);
      await container.read(editorProvider.notifier).open('/tmp/x.m4b');

      container.read(editorProvider.notifier).addChapter();

      final book = container.read(editorProvider).audiobook!;
      expect(book.chapters.length, 4);
      // After sort: 0, 10 (B), 10.001 (new), 20.
      expect(book.chapters[2].start,
          const Duration(seconds: 10, milliseconds: 1));
    });
  });

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

    test('undo clamps selection when undo shrinks the chapter list', () async {
      // Place the playhead near the end so addChapter inserts at the tail.
      final fake = _FakeBookbinder(threeChapterBook());
      final playback = _RecordingPlayback()
        ..currentPosition = const Duration(seconds: 25);
      final container = makeContainer(fake, playback: playback);
      addTearDown(container.dispose);
      await container.read(editorProvider.notifier).open('/tmp/x.m4b');

      container.read(editorProvider.notifier).addChapter();
      // After add: chapters = [A, B, C, NEW@25] — selection moved to 3.
      expect(container.read(selectedChapterProvider), 3);
      expect(
        container.read(editorProvider).audiobook!.chapters.length,
        4,
      );

      container.read(editorProvider.notifier).undo();
      // After undo: chapters = [A, B, C]. The first differing index between
      // [A, B, C, NEW] (length 4) and [A, B, C] (length 3) is 3 — past the
      // new last index. Selection must be clamped to 2.
      expect(container.read(editorProvider).audiobook!.chapters.length, 3);
      expect(container.read(selectedChapterProvider), 2);
    });

    test('redo clamps selection when redo shrinks the chapter list', () async {
      // Set up a deletion: selection on the final chapter, deleteChapter,
      // then undo (restores 3 chapters), then redo (returns to 2). The redo
      // path enters its own clamp branch when the diff index lands past the
      // new last index.
      final fake = _FakeBookbinder(threeChapterBook());
      final container = makeContainer(fake);
      addTearDown(container.dispose);
      await container.read(editorProvider.notifier).open('/tmp/x.m4b');
      container.read(selectedChapterProvider.notifier).state = 2;

      container.read(editorProvider.notifier).deleteChapter(2);
      // After delete: 2 chapters; selection clamped to 1 already.
      container.read(editorProvider.notifier).undo();
      // Restored to 3 chapters.
      expect(
        container.read(editorProvider).audiobook!.chapters.length,
        3,
      );
      // Park the selection on the to-be-removed last chapter again.
      container.read(selectedChapterProvider.notifier).state = 2;

      container.read(editorProvider.notifier).redo();
      // After redo: 2 chapters; selection clamped to 1.
      expect(
        container.read(editorProvider).audiobook!.chapters.length,
        2,
      );
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
}
