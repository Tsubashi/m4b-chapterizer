import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
import 'package:m4b_chapterizer/domain/models/cover.dart';

void main() {
  group('Audiobook', () {
    const totalDuration = Duration(minutes: 30);
    const chapter1 = Chapter(title: 'One', start: Duration.zero);
    const chapter2 = Chapter(title: 'Two', start: Duration(minutes: 10));
    const chapter3 = Chapter(title: 'Three', start: Duration(minutes: 20));

    test('exposes its fields', () {
      const book = Audiobook(
        title: 'A Book',
        author: 'Some Author',
        narrator: 'A Narrator',
        chapters: [chapter1, chapter2],
        totalDuration: totalDuration,
      );
      expect(book.title, 'A Book');
      expect(book.author, 'Some Author');
      expect(book.narrator, 'A Narrator');
      expect(book.chapters, [chapter1, chapter2]);
      expect(book.totalDuration, totalDuration);
    });

    test('endOf returns the next chapter start time', () {
      const book = Audiobook(
        chapters: [chapter1, chapter2, chapter3],
        totalDuration: totalDuration,
      );
      expect(book.endOf(0), const Duration(minutes: 10));
      expect(book.endOf(1), const Duration(minutes: 20));
    });

    test('endOf for the last chapter returns the total duration', () {
      const book = Audiobook(
        chapters: [chapter1, chapter2, chapter3],
        totalDuration: totalDuration,
      );
      expect(book.endOf(2), totalDuration);
    });

    test('rejects empty chapter list', () {
      expect(
        () => Audiobook.validated(chapters: const [], totalDuration: totalDuration),
        throwsArgumentError,
      );
    });

    test('rejects non-monotonic chapter starts', () {
      // The first chapter starts at zero (so the chapters.first check passes);
      // the second is BEFORE the first, which trips strictly-increasing.
      expect(
        () => Audiobook.validated(
          chapters: const [
            Chapter(title: 'A', start: Duration.zero),
            Chapter(title: 'B', start: Duration(minutes: 3)),
            Chapter(title: 'C', start: Duration(minutes: 2)),
          ],
          totalDuration: totalDuration,
        ),
        throwsArgumentError,
      );
    });

    test('rejects chapter start past total duration', () {
      expect(
        () => Audiobook.validated(
          chapters: const [
            Chapter(title: 'A', start: Duration.zero),
            Chapter(title: 'B', start: Duration(minutes: 31)),
          ],
          totalDuration: totalDuration,
        ),
        throwsArgumentError,
      );
    });

    test('copyWith updates only the supplied fields', () {
      const original = Audiobook(
        title: 'A',
        chapters: [chapter1],
        totalDuration: totalDuration,
      );
      final updated = original.copyWith(title: 'B');
      expect(updated.title, 'B');
      expect(updated.chapters, [chapter1]);
      expect(updated.totalDuration, totalDuration);
    });

    test('endOf throws RangeError for a negative or out-of-range index', () {
      const book = Audiobook(
        chapters: [chapter1, chapter2],
        totalDuration: totalDuration,
      );
      expect(() => book.endOf(-1), throwsRangeError);
      expect(() => book.endOf(2), throwsRangeError);
    });

    test('rejects a first chapter that does not start at zero', () {
      expect(
        () => Audiobook.validated(
          chapters: const [
            Chapter(title: 'A', start: Duration(seconds: 1)),
            Chapter(title: 'B', start: Duration(minutes: 5)),
          ],
          totalDuration: totalDuration,
        ),
        throwsArgumentError,
      );
    });

    test('value equality across all fields', () {
      final cover1 = Cover(bytes: Uint8List.fromList([1, 2, 3]), mimeType: 'image/png');
      final cover2 = Cover(bytes: Uint8List.fromList([1, 2, 3]), mimeType: 'image/png');
      final a = Audiobook(
        title: 'T',
        author: 'Au',
        narrator: 'N',
        album: 'Al',
        genre: 'G',
        description: 'D',
        year: 2024,
        cover: cover1,
        chapters: const [chapter1, chapter2],
        totalDuration: totalDuration,
      );
      final b = Audiobook(
        title: 'T',
        author: 'Au',
        narrator: 'N',
        album: 'Al',
        genre: 'G',
        description: 'D',
        year: 2024,
        cover: cover2,
        chapters: const [chapter1, chapter2],
        totalDuration: totalDuration,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      // Identity short-circuit also works.
      // ignore: unrelated_type_equality_checks
      expect(a == a, isTrue);
      // A field difference breaks equality.
      expect(a == a.copyWith(title: 'Other'), isFalse);
      // Different runtime type breaks equality.
      // ignore: unrelated_type_equality_checks
      expect(a == 'not an audiobook', isFalse);
    });
  });

  group('AudiobookDiff.firstDifferingChapterIndex', () {
    Audiobook book(List<Chapter> chapters) => Audiobook.validated(
          chapters: chapters,
          totalDuration: const Duration(seconds: 100),
        );

    test('returns null when chapters are equal', () {
      final a = book(const [
        Chapter(title: 'A', start: Duration.zero),
        Chapter(title: 'B', start: Duration(seconds: 5)),
      ]);
      final b = book(const [
        Chapter(title: 'A', start: Duration.zero),
        Chapter(title: 'B', start: Duration(seconds: 5)),
      ]);
      expect(a.firstDifferingChapterIndex(b), isNull);
    });

    test('returns the index of the first differing chapter', () {
      final a = book(const [
        Chapter(title: 'A', start: Duration.zero),
        Chapter(title: 'B', start: Duration(seconds: 5)),
        Chapter(title: 'C', start: Duration(seconds: 10)),
      ]);
      final b = book(const [
        Chapter(title: 'A', start: Duration.zero),
        Chapter(title: 'BB', start: Duration(seconds: 5)),
        Chapter(title: 'C', start: Duration(seconds: 10)),
      ]);
      expect(a.firstDifferingChapterIndex(b), 1);
    });

    test('handles a longer right side (insertion at end)', () {
      final a = book(const [
        Chapter(title: 'A', start: Duration.zero),
        Chapter(title: 'B', start: Duration(seconds: 5)),
        Chapter(title: 'C', start: Duration(seconds: 10)),
      ]);
      final b = book(const [
        Chapter(title: 'A', start: Duration.zero),
        Chapter(title: 'B', start: Duration(seconds: 5)),
        Chapter(title: 'C', start: Duration(seconds: 10)),
        Chapter(title: 'D', start: Duration(seconds: 15)),
      ]);
      expect(a.firstDifferingChapterIndex(b), 3);
    });

    test('handles a shorter right side (deletion at index)', () {
      final a = book(const [
        Chapter(title: 'A', start: Duration.zero),
        Chapter(title: 'B', start: Duration(seconds: 5)),
        Chapter(title: 'C', start: Duration(seconds: 10)),
        Chapter(title: 'D', start: Duration(seconds: 15)),
      ]);
      final b = book(const [
        Chapter(title: 'A', start: Duration.zero),
        Chapter(title: 'C', start: Duration(seconds: 10)),
        Chapter(title: 'D', start: Duration(seconds: 15)),
      ]);
      expect(a.firstDifferingChapterIndex(b), 1);
    });
  });
}
