import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/data/ffmetadata_codec.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';

void main() {
  final goldenText = File('test/fixtures/ffmetadata_sample.txt')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  final book = Audiobook.validated(
    title: 'A Test Book',
    author: 'Test Author',
    narrator: 'Test Narrator',
    album: 'Test Series',
    genre: 'Audiobook',
    description: 'A short test description',
    year: 2026,
    chapters: const [
      Chapter(title: 'One', start: Duration.zero),
      Chapter(title: 'Two', start: Duration(seconds: 10)),
      Chapter(title: 'Three', start: Duration(seconds: 20)),
    ],
    totalDuration: const Duration(seconds: 30),
  );

  group('FfmetadataCodec.encode', () {
    test('encodes an Audiobook to ffmetadata text matching the golden file',
        () {
      const codec = FfmetadataCodec();
      expect(codec.encode(book), goldenText);
    });

    test('omits unset metadata fields', () {
      const codec = FfmetadataCodec();
      final stripped = Audiobook.validated(
        chapters: const [Chapter(title: 'Only', start: Duration.zero)],
        totalDuration: const Duration(seconds: 5),
      );
      final encoded = codec.encode(stripped);
      expect(encoded, contains(';FFMETADATA1'));
      expect(encoded, startsWith(';FFMETADATA1\n[CHAPTER]'));
      expect(encoded, isNot(contains('artist=')));
      expect(encoded, contains('[CHAPTER]'));
    });

    test('escapes the four ffmetadata special characters', () {
      const codec = FfmetadataCodec();
      final book = Audiobook.validated(
        title: r'a=b;c#d\e\nf',
        chapters: const [Chapter(title: 'C1', start: Duration.zero)],
        totalDuration: const Duration(seconds: 1),
      );
      final encoded = codec.encode(book);
      expect(encoded, contains(r'title=a\=b\;c\#d\\e\\nf'));
    });
  });

  group('FfmetadataCodec.decode', () {
    test('round-trips an Audiobook through encode and decode', () {
      const codec = FfmetadataCodec();
      final book = Audiobook.validated(
        title: 'A Test Book',
        author: 'Test Author',
        narrator: 'Test Narrator',
        album: 'Test Series',
        genre: 'Audiobook',
        description: 'A short test description',
        year: 2026,
        chapters: const [
          Chapter(title: 'One', start: Duration.zero),
          Chapter(title: 'Two', start: Duration(seconds: 10)),
          Chapter(title: 'Three', start: Duration(seconds: 20)),
        ],
        totalDuration: const Duration(seconds: 30),
      );

      final encoded = codec.encode(book);
      final decoded = codec.decode(encoded);

      expect(decoded.title, book.title);
      expect(decoded.author, book.author);
      expect(decoded.narrator, book.narrator);
      expect(decoded.album, book.album);
      expect(decoded.genre, book.genre);
      expect(decoded.description, book.description);
      expect(decoded.year, book.year);
      expect(decoded.chapters, book.chapters);
      expect(decoded.totalDuration, book.totalDuration);
    });

    test('decodes the golden file', () {
      const codec = FfmetadataCodec();
      final goldenText = File('test/fixtures/ffmetadata_sample.txt')
          .readAsStringSync();
      final decoded = codec.decode(goldenText);
      expect(decoded.title, 'A Test Book');
      expect(decoded.chapters.length, 3);
      expect(decoded.chapters[0].title, 'One');
      expect(decoded.totalDuration, const Duration(seconds: 30));
    });

    test('round-trips escape sequences', () {
      const codec = FfmetadataCodec();
      final book = Audiobook.validated(
        title: r'a=b;c#d\e',
        chapters: const [Chapter(title: 'C1', start: Duration.zero)],
        totalDuration: const Duration(seconds: 1),
      );
      final decoded = codec.decode(codec.encode(book));
      expect(decoded.title, r'a=b;c#d\e');
    });

    test('rejects input without the FFMETADATA1 header', () {
      const codec = FfmetadataCodec();
      expect(() => codec.decode('title=Foo'), throwsFormatException);
    });
  });
}
