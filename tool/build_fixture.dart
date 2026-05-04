// Generates test/fixtures/sample.m4b and test/fixtures/sample_cover.png.
// Run by hand once when the fixture needs to be (re)created:
//   dart run tool/build_fixture.dart
//
// Requires `ffmpeg` on PATH.

import 'dart:io';

const _metadata = '''
;FFMETADATA1
title=A Test Book
artist=Test Author
composer=Test Narrator
album=Test Series
genre=Audiobook
date=2026
comment=A short test description
[CHAPTER]
TIMEBASE=1/1000
START=0
END=10000
title=One
[CHAPTER]
TIMEBASE=1/1000
START=10000
END=20000
title=Two
[CHAPTER]
TIMEBASE=1/1000
START=20000
END=30000
title=Three
''';

Future<void> _runOrThrow(String exe, List<String> args) async {
  final result = await Process.run(exe, args);
  if (result.exitCode != 0) {
    throw StateError('$exe ${args.join(' ')} failed:\n${result.stderr}');
  }
}

Future<void> main() async {
  final tempDir = await Directory.systemTemp.createTemp('m4b-fixture-');
  try {
    final metadataPath = '${tempDir.path}/metadata.txt';
    final silentWavPath = '${tempDir.path}/silent.wav';
    final coverPath = 'test/fixtures/sample_cover.png';
    final outPath = 'test/fixtures/sample.m4b';

    await File(metadataPath).writeAsString(_metadata);

    // 30s of silence at 22050 Hz mono.
    await _runOrThrow('ffmpeg', [
      '-y',
      '-f', 'lavfi',
      '-i', 'anullsrc=channel_layout=mono:sample_rate=22050',
      '-t', '30',
      silentWavPath,
    ]);

    // 16x16 solid-colour PNG.
    await _runOrThrow('ffmpeg', [
      '-y',
      '-f', 'lavfi',
      '-i', 'color=c=red:s=16x16',
      '-frames:v', '1',
      coverPath,
    ]);

    // Encode to AAC + attach cover + apply chapter metadata.
    await _runOrThrow('ffmpeg', [
      '-y',
      '-i', silentWavPath,
      '-i', coverPath,
      '-i', metadataPath,
      '-map', '0:a',
      '-map', '1:v',
      '-map_metadata', '2',
      '-map_chapters', '2',
      '-c:a', 'aac',
      '-b:a', '32k',
      '-c:v', 'png',
      '-disposition:v:0', 'attached_pic',
      '-f', 'mp4',
      outPath,
    ]);

    stdout.writeln('Wrote $outPath');
  } finally {
    await tempDir.delete(recursive: true);
  }
}
