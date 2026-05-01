import 'dart:convert';

import '../domain/models/audiobook.dart';
import '../domain/models/chapter.dart';

class FfprobeResult {
  const FfprobeResult({required this.audiobook, required this.hasAttachedCover});

  final Audiobook audiobook;
  final bool hasAttachedCover;
}

class FfprobeCodec {
  const FfprobeCodec();

  FfprobeResult decode(String json) {
    final root = jsonDecode(json) as Map<String, dynamic>;
    final streams = (root['streams'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final chaptersJson =
        (root['chapters'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final format = (root['format'] as Map<String, dynamic>?) ?? const {};
    final formatTags =
        (format['tags'] as Map<String, dynamic>?)?.cast<String, dynamic>() ??
            const {};

    if (chaptersJson.isEmpty) {
      throw const FormatException(
        'ffprobe output contains no chapters; m4b without chapters is not '
        'supported in MVP',
      );
    }

    final chapters = <Chapter>[];
    Duration lastEnd = Duration.zero;
    for (final block in chaptersJson) {
      final timebase = block['time_base'] as String? ?? '1/1000';
      final divisor = _parseTimebaseDivisor(timebase);
      final startUnits = (block['start'] as num).toInt();
      final endUnits = (block['end'] as num).toInt();
      final tags = (block['tags'] as Map<String, dynamic>?) ?? const {};
      chapters.add(Chapter(
        title: tags['title'] as String? ?? '',
        start: Duration(milliseconds: startUnits * 1000 ~/ divisor),
      ));
      lastEnd = Duration(milliseconds: endUnits * 1000 ~/ divisor);
    }

    final hasAttachedCover = streams.any((s) {
      if (s['codec_type'] != 'video') return false;
      final disposition =
          (s['disposition'] as Map<String, dynamic>?) ?? const {};
      return (disposition['attached_pic'] as num?)?.toInt() == 1;
    });

    return FfprobeResult(
      audiobook: Audiobook.validated(
        title: formatTags['title'] as String?,
        author: formatTags['artist'] as String?,
        narrator: formatTags['composer'] as String?,
        album: formatTags['album'] as String?,
        genre: formatTags['genre'] as String?,
        description: formatTags['comment'] as String?,
        year: int.tryParse(formatTags['date'] as String? ?? ''),
        chapters: chapters,
        totalDuration: lastEnd,
      ),
      hasAttachedCover: hasAttachedCover,
    );
  }

  static int _parseTimebaseDivisor(String timebase) {
    final parts = timebase.split('/');
    if (parts.length != 2) {
      throw FormatException('Invalid time_base: $timebase');
    }
    return int.parse(parts[1]);
  }
}
