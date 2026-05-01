import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/bookbinder.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
import 'package:m4b_chapterizer/presentation/providers/editor_state.dart';

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

void main() {
  final book = Audiobook.validated(
    title: 'Original',
    chapters: const [
      Chapter(title: 'C1', start: Duration.zero),
      Chapter(title: 'C2', start: Duration(seconds: 5)),
    ],
    totalDuration: const Duration(seconds: 10),
  );

  ProviderContainer makeContainer(_FakeBookbinder fake) => ProviderContainer(
        overrides: [bookbinderProvider.overrideWithValue(fake)],
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
}
