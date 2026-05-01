import '../domain/models/audiobook.dart';

/// Encodes/decodes the ffmpeg `ffmetadata` text format.
///
/// Spec: https://ffmpeg.org/ffmpeg-formats.html#Metadata-2
class FfmetadataCodec {
  const FfmetadataCodec();

  static const _header = ';FFMETADATA1';

  /// ffmetadata reserves these four characters; they must be backslash-escaped
  /// in keys and values: `=`, `;`, `#`, `\`. Newlines are also escaped.
  static String _escape(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('=', r'\=')
      .replaceAll(';', r'\;')
      .replaceAll('#', r'\#')
      .replaceAll('\n', r'\n');

  String encode(Audiobook book) {
    final buffer = StringBuffer()..writeln(_header);
    void writeIfPresent(String key, String? value) {
      if (value == null || value.isEmpty) return;
      buffer.writeln('$key=${_escape(value)}');
    }

    writeIfPresent('title', book.title);
    writeIfPresent('artist', book.author);
    writeIfPresent('composer', book.narrator);
    writeIfPresent('album', book.album);
    writeIfPresent('genre', book.genre);
    if (book.year != null) buffer.writeln('date=${book.year}');
    writeIfPresent('comment', book.description);

    for (var i = 0; i < book.chapters.length; i++) {
      final chapter = book.chapters[i];
      final endMs = book.endOf(i).inMilliseconds;
      buffer
        ..writeln('[CHAPTER]')
        ..writeln('TIMEBASE=1/1000')
        ..writeln('START=${chapter.start.inMilliseconds}')
        ..writeln('END=$endMs')
        ..writeln('title=${_escape(chapter.title)}');
    }

    return buffer.toString();
  }
}
