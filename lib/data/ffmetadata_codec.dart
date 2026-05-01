import 'dart:convert';

import '../domain/models/audiobook.dart';
import '../domain/models/chapter.dart';

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

  /// Parses ffmetadata text and reconstructs an [Audiobook].
  ///
  /// The input must start with [_header]. The total duration is derived from
  /// the END timestamp of the last chapter.
  Audiobook decode(String text) {
    final lines = const LineSplitter().convert(text);
    if (lines.isEmpty || lines.first.trim() != _header) {
      throw const FormatException('Input is not ffmetadata: missing header');
    }

    final globalFields = <String, String>{};
    final chapterBlocks = <Map<String, String>>[];
    Map<String, String>? currentChapter;

    for (var i = 1; i < lines.length; i++) {
      final raw = lines[i];
      if (raw.isEmpty || raw.startsWith(';')) continue;
      if (raw.trim() == '[CHAPTER]') {
        currentChapter = <String, String>{};
        chapterBlocks.add(currentChapter);
        continue;
      }
      final pair = _parseKeyValue(raw);
      if (pair == null) continue;
      if (currentChapter != null) {
        currentChapter[pair.$1] = pair.$2;
      } else {
        globalFields[pair.$1] = pair.$2;
      }
    }

    if (chapterBlocks.isEmpty) {
      throw const FormatException('ffmetadata contains no chapters');
    }

    final chapters = <_ParsedChapter>[];
    for (final block in chapterBlocks) {
      final timebase = block['TIMEBASE'] ?? '1/1000';
      final divisor = _parseTimebaseDivisor(timebase);
      final startUnits = int.parse(block['START'] ?? '0');
      final endUnits = int.parse(block['END'] ?? '0');
      chapters.add(_ParsedChapter(
        title: block['title'] ?? '',
        start: Duration(milliseconds: startUnits * 1000 ~/ divisor),
        end: Duration(milliseconds: endUnits * 1000 ~/ divisor),
      ));
    }

    final totalDuration = chapters.last.end;

    return Audiobook.validated(
      title: globalFields['title'],
      author: globalFields['artist'],
      narrator: globalFields['composer'],
      album: globalFields['album'],
      genre: globalFields['genre'],
      description: globalFields['comment'],
      year: int.tryParse(globalFields['date'] ?? ''),
      chapters: [
        for (final c in chapters) Chapter(title: c.title, start: c.start),
      ],
      totalDuration: totalDuration,
    );
  }

  static (String, String)? _parseKeyValue(String line) {
    final buffer = StringBuffer();
    var i = 0;
    String? key;
    while (i < line.length) {
      final ch = line[i];
      if (ch == r'\' && i + 1 < line.length) {
        final next = line[i + 1];
        buffer.write(next == 'n' ? '\n' : next);
        i += 2;
        continue;
      }
      if (ch == '=' && key == null) {
        key = buffer.toString();
        buffer.clear();
        i++;
        continue;
      }
      buffer.write(ch);
      i++;
    }
    if (key == null) return null;
    return (key, buffer.toString());
  }

  static int _parseTimebaseDivisor(String timebase) {
    final parts = timebase.split('/');
    if (parts.length != 2) {
      throw FormatException('Invalid TIMEBASE: $timebase');
    }
    return int.parse(parts[1]);
  }
}

class _ParsedChapter {
  _ParsedChapter({required this.title, required this.start, required this.end});
  final String title;
  final Duration start;
  final Duration end;
}
