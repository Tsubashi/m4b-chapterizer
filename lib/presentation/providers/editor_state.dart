import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../../data/binary_resolver.dart';
import '../../domain/bookbinder.dart';
import '../../domain/models/audiobook.dart';
import '../../domain/models/chapter.dart';
import '../../domain/models/cover.dart';
import '../widgets/chapter_list.dart'
    show selectedChapterProvider, chapterScrollRequestProvider;
import 'playback.dart';

enum SetChapterStartError { duplicate, firstNotZero }

@immutable
class EditorState {
  const EditorState({
    this.audiobook,
    this.path,
    this.isDirty = false,
    this.undoStack = const [],
    this.redoStack = const [],
  });

  final Audiobook? audiobook;
  final String? path;
  final bool isDirty;
  final List<Audiobook> undoStack;
  final List<Audiobook> redoStack;

  bool get canUndo => undoStack.isNotEmpty;
  bool get canRedo => redoStack.isNotEmpty;

  EditorState copyWith({
    Audiobook? audiobook,
    String? path,
    bool? isDirty,
    List<Audiobook>? undoStack,
    List<Audiobook>? redoStack,
  }) =>
      EditorState(
        audiobook: audiobook ?? this.audiobook,
        path: path ?? this.path,
        isDirty: isDirty ?? this.isDirty,
        undoStack: undoStack ?? this.undoStack,
        redoStack: redoStack ?? this.redoStack,
      );
}

/// Provided at app startup with `bookbinderProvider.overrideWithValue(...)`.
/// Tests override it with a fake.
final bookbinderProvider = Provider<Bookbinder>((ref) {
  // coverage:ignore-start
  // Defensive fallback: production wires the override in main(); tests
  // always override before reading. The error path exists only as a
  // signal during integration / smoke runs.
  throw StateError(
    'bookbinderProvider must be overridden at the app or test scope',
  );
  // coverage:ignore-end
});

final binaryResolverProvider = Provider<BinaryResolver>((ref) {
  // coverage:ignore-start
  // Same defensive fallback as bookbinderProvider above.
  throw StateError(
    'binaryResolverProvider must be overridden at the app or test scope',
  );
  // coverage:ignore-end
});

final editorProvider =
    NotifierProvider<EditorNotifier, EditorState>(EditorNotifier.new);

class EditorNotifier extends Notifier<EditorState> {
  Audiobook? _editSnapshot;

  @override
  EditorState build() => const EditorState();

  Bookbinder get _bookbinder => ref.read(bookbinderProvider);

  Future<void> open(String path) async {
    final book = await _bookbinder.read(path);
    _editSnapshot = null;
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

  // ===== Continuous ops (no push; rely on session) =====

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

  void renameChapter(int index, String title) {
    _updateBook((book) {
      final updated = [...book.chapters];
      updated[index] = updated[index].copyWith(title: title);
      return book.copyWith(chapters: updated);
    });
  }

  // ===== Discrete ops (push immediately; close any open session first) =====

  void addChapter() {
    final book = state.audiobook;
    if (book == null) return;

    // Insert at the current playhead, clamped to (0, totalDuration). Bump in
    // 1ms steps to find a free slot if the playhead exactly matches an
    // existing chapter start (e.g., user is parked at chapter 0 = 0:00).
    Duration newStart =
        ref.read(playbackControllerProvider).position;
    final maxStart = book.totalDuration - const Duration(milliseconds: 1);
    if (newStart < Duration.zero) newStart = Duration.zero;
    if (newStart > maxStart) newStart = maxStart;
    final taken = {for (final c in book.chapters) c.start};
    while (taken.contains(newStart) && newStart <= maxStart) {
      newStart = newStart + const Duration(milliseconds: 1);
    }
    if (newStart > maxStart) return; // no room near the playhead

    _pushUndo();
    _updateBook((book) {
      final updated = [
        ...book.chapters,
        Chapter(title: 'New chapter', start: newStart),
      ]..sort((a, b) => a.start.compareTo(b.start));
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
    // Select the newly-inserted chapter so the UI scrolls to it.
    final book2 = state.audiobook;
    if (book2 != null) {
      final idx =
          book2.chapters.indexWhere((c) => c.start == newStart);
      if (idx >= 0) {
        ref.read(selectedChapterProvider.notifier).state = idx;
      }
    }
  }

  void deleteChapter(int index) {
    final book = state.audiobook;
    if (book == null || book.chapters.length <= 1) return;
    _pushUndo();
    _updateBook((book) {
      final updated = [...book.chapters]..removeAt(index);
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
    final book2 = state.audiobook;
    if (book2 != null) {
      final cur = ref.read(selectedChapterProvider);
      final clamped = cur > book2.chapters.length - 1
          ? book2.chapters.length - 1
          : cur;
      if (clamped != cur) {
        ref.read(selectedChapterProvider.notifier).state = clamped;
      }
    }
  }

  SetChapterStartError? setChapterStart(int index, Duration start) {
    final book = state.audiobook;
    if (book == null) return null;

    final maxAllowed = book.totalDuration - const Duration(milliseconds: 1);
    Duration clamped = start;
    if (clamped < Duration.zero) clamped = Duration.zero;
    if (clamped > maxAllowed) clamped = maxAllowed;

    final movedChapter = book.chapters[index].copyWith(start: clamped);
    final candidate = [...book.chapters];
    candidate[index] = movedChapter;
    candidate.sort((a, b) => a.start.compareTo(b.start));

    for (var i = 1; i < candidate.length; i++) {
      if (candidate[i].start == candidate[i - 1].start) {
        return SetChapterStartError.duplicate;
      }
    }
    if (candidate.first.start != Duration.zero) {
      return SetChapterStartError.firstNotZero;
    }

    _pushUndo();

    final newBook = Audiobook.validated(
      title: book.title,
      author: book.author,
      narrator: book.narrator,
      album: book.album,
      genre: book.genre,
      description: book.description,
      year: book.year,
      cover: book.cover,
      chapters: candidate,
      totalDuration: book.totalDuration,
    );
    state = state.copyWith(audiobook: newBook, isDirty: true);

    final newIndex =
        candidate.indexWhere((c) => identical(c, movedChapter));
    if (newIndex >= 0) {
      ref.read(selectedChapterProvider.notifier).state = newIndex;
    }

    ref.read(playbackControllerProvider).seek(clamped);
    return null;
  }

  void clearCover() {
    final book = state.audiobook;
    if (book == null || book.cover == null) return;
    _pushUndo();
    state = state.copyWith(
      audiobook: book.copyWith(clearCover: true),
      isDirty: true,
    );
  }

  void replaceCover(Cover cover) {
    _pushUndo();
    _updateBook((b) => b.copyWith(cover: cover));
  }

  // ===== Field-edit session =====

  void beginFieldEdit() {
    if (_editSnapshot != null) return; // re-focusing same field is a no-op
    final book = state.audiobook;
    if (book == null) return;
    _editSnapshot = book;
  }

  void endFieldEdit() {
    final snapshot = _editSnapshot;
    _editSnapshot = null;
    if (snapshot == null) return;
    final book = state.audiobook;
    if (book == null || identical(book, snapshot) || book == snapshot) return;
    state = state.copyWith(
      undoStack: [...state.undoStack, snapshot],
      redoStack: const [],
    );
  }

  void cancelFieldEdit() {
    final snapshot = _editSnapshot;
    _editSnapshot = null;
    if (snapshot == null) return;
    state = state.copyWith(audiobook: snapshot, isDirty: state.isDirty);
  }

  // ===== Undo / redo =====

  void undo() {
    if (state.undoStack.isEmpty) return;
    _editSnapshot = null;
    final book = state.audiobook;
    final undoStack = state.undoStack;
    final newAudiobook = undoStack.last;
    state = state.copyWith(
      audiobook: newAudiobook,
      undoStack: undoStack.sublist(0, undoStack.length - 1),
      redoStack:
          book == null ? state.redoStack : [...state.redoStack, book],
      isDirty: true,
    );
    if (book != null) {
      final diff = newAudiobook.firstDifferingChapterIndex(book);
      if (diff != null) {
        final clamped = diff > newAudiobook.chapters.length - 1
            ? newAudiobook.chapters.length - 1
            : diff;
        ref.read(selectedChapterProvider.notifier).state = clamped;
        // Ask the chapter list to scroll the changed row into view.
        ref.read(chapterScrollRequestProvider.notifier).state++;
      }
    }
  }

  void redo() {
    if (state.redoStack.isEmpty) return;
    _editSnapshot = null;
    final book = state.audiobook;
    final redoStack = state.redoStack;
    final newAudiobook = redoStack.last;
    state = state.copyWith(
      audiobook: newAudiobook,
      undoStack:
          book == null ? state.undoStack : [...state.undoStack, book],
      redoStack: redoStack.sublist(0, redoStack.length - 1),
      isDirty: true,
    );
    if (book != null) {
      final diff = newAudiobook.firstDifferingChapterIndex(book);
      if (diff != null) {
        final clamped = diff > newAudiobook.chapters.length - 1
            ? newAudiobook.chapters.length - 1
            : diff;
        ref.read(selectedChapterProvider.notifier).state = clamped;
        ref.read(chapterScrollRequestProvider.notifier).state++;
      }
    }
  }

  // ===== Internals =====

  /// Records the current audiobook on the undo stack and clears the redo
  /// stack. Discrete ops call this before mutating; closes any open session
  /// to keep undo steps in chronological order.
  void _pushUndo() {
    // Close any open continuous-edit session first; that may itself push.
    endFieldEdit();
    final book = state.audiobook;
    if (book == null) return;
    state = state.copyWith(
      undoStack: [...state.undoStack, book],
      redoStack: const [],
    );
  }

  void _updateBook(Audiobook Function(Audiobook book) f) {
    final book = state.audiobook;
    if (book == null) return;
    state = state.copyWith(audiobook: f(book), isDirty: true);
  }
}
