import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/bookbinder.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
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
}
