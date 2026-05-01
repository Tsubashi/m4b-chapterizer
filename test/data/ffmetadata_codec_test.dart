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
}
