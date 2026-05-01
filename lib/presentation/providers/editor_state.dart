import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../../domain/bookbinder.dart';
import '../../domain/models/audiobook.dart';
import '../../domain/models/chapter.dart';

@immutable
class EditorState {
  const EditorState({this.audiobook, this.path, this.isDirty = false});

  final Audiobook? audiobook;
  final String? path;
  final bool isDirty;

  EditorState copyWith({
    Audiobook? audiobook,
    String? path,
    bool? isDirty,
  }) =>
      EditorState(
        audiobook: audiobook ?? this.audiobook,
        path: path ?? this.path,
        isDirty: isDirty ?? this.isDirty,
      );
}

/// Provided at app startup with `bookbinderProvider.overrideWithValue(...)`.
/// Tests override it with a fake.
final bookbinderProvider = Provider<Bookbinder>((ref) {
  throw StateError(
    'bookbinderProvider must be overridden at the app or test scope',
  );
});

final editorProvider =
    NotifierProvider<EditorNotifier, EditorState>(EditorNotifier.new);

class EditorNotifier extends Notifier<EditorState> {
  @override
  EditorState build() => const EditorState();

  Bookbinder get _bookbinder => ref.read(bookbinderProvider);

  Future<void> open(String path) async {
    final book = await _bookbinder.read(path);
    state = EditorState(audiobook: book, path: path);
  }

  Future<void> save() async {
    final book = state.audiobook;
    final path = state.path;
    if (book == null || path == null) return;
    await _bookbinder.write(
      sourcePath: path,
      destinationPath: path,
      audiobook: book,
    );
    state = state.copyWith(isDirty: false);
  }

  Future<void> saveAs(String newPath) async {
    final book = state.audiobook;
    final path = state.path;
    if (book == null || path == null) return;
    await _bookbinder.write(
      sourcePath: path,
      destinationPath: newPath,
      audiobook: book,
    );
    state = state.copyWith(path: newPath, isDirty: false);
  }

  void setTitle(String value) =>
      _updateBook((b) => b.copyWith(title: value));
  void setAuthor(String value) =>
      _updateBook((b) => b.copyWith(author: value));
  void setNarrator(String value) =>
      _updateBook((b) => b.copyWith(narrator: value));
  void setAlbum(String value) => _updateBook((b) => b.copyWith(album: value));
  void setGenre(String value) => _updateBook((b) => b.copyWith(genre: value));
  void setDescription(String value) =>
      _updateBook((b) => b.copyWith(description: value));
  void setYear(int? value) => _updateBook((b) => b.copyWith(year: value));

  void addChapter() {
    _updateBook((book) {
      final last = book.chapters.last;
      final lastEnd = book.totalDuration;
      final newStart = Duration(
        microseconds: (last.start.inMicroseconds + lastEnd.inMicroseconds) ~/ 2,
      );
      return book.copyWith(
        chapters: [
          ...book.chapters,
          Chapter(title: 'New chapter', start: newStart),
        ],
      );
    });
  }

  void deleteChapter(int index) {
    _updateBook((book) {
      if (book.chapters.length <= 1) return book; // never delete the last chapter
      final updated = [...book.chapters]..removeAt(index);
      // After deletion, ensure first chapter starts at zero (Audiobook invariant).
      if (index == 0) {
        updated[0] = updated[0].copyWith(start: Duration.zero);
      }
      return Audiobook.validated(
        title: book.title,
        author: book.author,
        narrator: book.narrator,
        album: book.album,
        genre: book.genre,
        description: book.description,
        year: book.year,
        cover: book.cover,
        chapters: updated,
        totalDuration: book.totalDuration,
      );
    });
  }

  void renameChapter(int index, String title) {
    _updateBook((book) {
      final updated = [...book.chapters];
      updated[index] = updated[index].copyWith(title: title);
      return book.copyWith(chapters: updated);
    });
  }

  void setChapterStart(int index, Duration start) {
    _updateBook((book) {
      final updated = [...book.chapters];
      updated[index] = updated[index].copyWith(start: start);
      return Audiobook.validated(
        title: book.title,
        author: book.author,
        narrator: book.narrator,
        album: book.album,
        genre: book.genre,
        description: book.description,
        year: book.year,
        cover: book.cover,
        chapters: updated,
        totalDuration: book.totalDuration,
      );
    });
  }

  void _updateBook(Audiobook Function(Audiobook book) f) {
    final book = state.audiobook;
    if (book == null) return;
    state = state.copyWith(audiobook: f(book), isDirty: true);
  }
}
