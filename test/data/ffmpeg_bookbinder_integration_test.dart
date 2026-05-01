import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/data/binary_resolver.dart';
import 'package:m4b_chapterizer/data/ffmpeg_bookbinder.dart';
import 'package:m4b_chapterizer/data/process_runner.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';

bool _ffmpegOnPath() {
  try {
    final result = Process.runSync('ffmpeg', ['-version']);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  if (!_ffmpegOnPath()) {
    test('skipped: ffmpeg not on PATH', () {}, skip: true);
    return;
  }

  test('read → mutate → write → read round-trip preserves chapters and metadata',
      () async {
    final bookbinder = FfmpegBookbinder(
      runner: const SystemProcessRunner(),
      binaries: const SystemBinaryResolver(),
    );

    final tempDir = await Directory.systemTemp.createTemp('m4b-rt-');
    addTearDown(() => tempDir.delete(recursive: true));
    final workCopy = '${tempDir.path}/work.m4b';
    await File('test/fixtures/sample.m4b').copy(workCopy);

    final original = await bookbinder.read(workCopy);
    expect(original.title, 'A Test Book');
    expect(original.chapters.length, 3);
    expect(original.cover, isNotNull);

    final mutated = original.copyWith(
      title: 'Mutated Title',
      chapters: [
        const Chapter(title: 'Renamed', start: Duration.zero),
        original.chapters[1],
        original.chapters[2],
      ],
    );

    await bookbinder.write(
      sourcePath: workCopy,
      destinationPath: workCopy,
      audiobook: mutated,
    );

    final reread = await bookbinder.read(workCopy);
    expect(reread.title, 'Mutated Title');
    expect(reread.chapters[0].title, 'Renamed');
    expect(reread.chapters.length, 3);
    expect(reread.cover, isNotNull);
    expect(reread.totalDuration, original.totalDuration);
  });
}
