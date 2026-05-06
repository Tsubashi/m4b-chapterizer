import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/data/ffprobe_codec.dart';

void main() {
  group('FfprobeCodec.decode', () {
    final goldenJson =
        File('test/fixtures/ffprobe_sample.json').readAsStringSync();

    test('decodes the golden ffprobe output into a populated Audiobook', () {
      const codec = FfprobeCodec();
      final result = codec.decode(goldenJson);
      expect(result.audiobook.title, 'A Test Book');
      expect(result.audiobook.author, 'Test Author');
      expect(result.audiobook.narrator, 'Test Narrator');
      expect(result.audiobook.album, 'Test Series');
      expect(result.audiobook.genre, 'Audiobook');
      expect(result.audiobook.year, 2026);
      expect(result.audiobook.description, 'A short test description');
      expect(result.audiobook.chapters.length, 3);
      expect(result.audiobook.chapters[0].title, 'One');
      expect(result.audiobook.chapters[0].start, Duration.zero);
      expect(result.audiobook.chapters[1].start, const Duration(seconds: 10));
      expect(result.audiobook.totalDuration, const Duration(seconds: 30));
      expect(result.hasAttachedCover, isTrue);
    });

    test('reports no attached cover when no video stream is present', () {
      const codec = FfprobeCodec();
      final result = codec.decode('''
{
  "streams": [{"index": 0, "codec_type": "audio"}],
  "chapters": [
    {"time_base": "1/1000", "start": 0, "end": 1000, "tags": {"title": "C"}}
  ],
  "format": {"duration": "1.000000", "tags": {}}
}''');
      expect(result.hasAttachedCover, isFalse);
    });

    test('falls back to format.duration when chapters are missing', () {
      const codec = FfprobeCodec();
      expect(
        () => codec.decode('''
{
  "streams": [{"index": 0, "codec_type": "audio"}],
  "chapters": [],
  "format": {"duration": "10.000000", "tags": {}}
}'''),
        throwsFormatException,
      );
    });
  });
}
