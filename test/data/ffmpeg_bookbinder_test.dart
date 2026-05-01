import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:m4b_chapterizer/data/binary_resolver.dart';
import 'package:m4b_chapterizer/data/ffmpeg_bookbinder.dart';
import 'package:m4b_chapterizer/data/process_runner.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';

class _MockProcessRunner extends Mock implements ProcessRunner {}

void main() {
  setUpAll(() {
    registerFallbackValue(const <String>[]);
  });

  late _MockProcessRunner runner;
  late FfmpegBookbinder bookbinder;

  setUp(() {
    runner = _MockProcessRunner();
    bookbinder = FfmpegBookbinder(
      runner: runner,
      binaries: const FixedBinaryResolver(
        ffmpeg: '/usr/bin/ffmpeg',
        ffprobe: '/usr/bin/ffprobe',
      ),
    );
  });

  group('FfmpegBookbinder.read', () {
    test('invokes ffprobe with the expected arguments', () async {
      final goldenJson =
          File('test/fixtures/ffprobe_sample.json').readAsStringSync();
      when(() => runner.run(
            executable: '/usr/bin/ffprobe',
            arguments: any(named: 'arguments'),
          )).thenAnswer((_) async => ProcessOutput(
            exitCode: 0,
            stdout: goldenJson,
            stderr: '',
            stdoutBytes: Uint8List.fromList(utf8.encode(goldenJson)),
          ));
      // No attached cover in this stub.
      when(() => runner.run(
            executable: '/usr/bin/ffmpeg',
            arguments: any(named: 'arguments'),
          )).thenAnswer((_) async => ProcessOutput(
            exitCode: 1,
            stdout: '',
            stderr: 'no cover',
            stdoutBytes: Uint8List(0),
          ));

      final book = await bookbinder.read('/tmp/book.m4b');
      expect(book.title, 'A Test Book');
      expect(book.chapters.length, 3);

      verify(() => runner.run(
            executable: '/usr/bin/ffprobe',
            arguments: const [
              '-show_format',
              '-show_chapters',
              '-show_streams',
              '-of',
              'json',
              '-i',
              '/tmp/book.m4b',
            ],
          )).called(1);
    });

    test('extracts cover bytes when ffprobe reports an attached_pic stream',
        () async {
      final goldenJson =
          File('test/fixtures/ffprobe_sample.json').readAsStringSync();
      when(() => runner.run(
            executable: '/usr/bin/ffprobe',
            arguments: any(named: 'arguments'),
          )).thenAnswer((_) async => ProcessOutput(
            exitCode: 0,
            stdout: goldenJson,
            stderr: '',
            stdoutBytes: Uint8List.fromList(utf8.encode(goldenJson)),
          ));
      final fakeJpegBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);
      when(() => runner.run(
            executable: '/usr/bin/ffmpeg',
            arguments: any(named: 'arguments'),
          )).thenAnswer((_) async => ProcessOutput(
            exitCode: 0,
            stdout: '',
            stderr: '',
            stdoutBytes: fakeJpegBytes,
          ));

      final book = await bookbinder.read('/tmp/book.m4b');
      expect(book.cover, isNotNull);
      expect(book.cover!.bytes, fakeJpegBytes);
      expect(book.cover!.mimeType, 'image/jpeg');
    });

    test('throws BookbinderException when ffprobe returns a nonzero exit code',
        () async {
      when(() => runner.run(
            executable: any(named: 'executable'),
            arguments: any(named: 'arguments'),
          )).thenAnswer((_) async => ProcessOutput(
            exitCode: 1,
            stdout: '',
            stderr: 'No such file',
            stdoutBytes: Uint8List(0),
          ));

      await expectLater(
        bookbinder.read('/tmp/missing.m4b'),
        throwsA(isA<BookbinderException>()),
      );
    });
  });

  group('FfmpegBookbinder.write', () {
    final book = Audiobook.validated(
      title: 'New Title',
      author: 'New Author',
      chapters: const [
        Chapter(title: 'A', start: Duration.zero),
        Chapter(title: 'B', start: Duration(seconds: 5)),
      ],
      totalDuration: const Duration(seconds: 10),
    );

    test('invokes ffmpeg with -map_metadata, -map_chapters, and -c copy',
        () async {
      when(() => runner.run(
            executable: '/usr/bin/ffmpeg',
            arguments: any(named: 'arguments'),
          )).thenAnswer((_) async => ProcessOutput(
            exitCode: 0,
            stdout: '',
            stderr: '',
            stdoutBytes: Uint8List(0),
          ));

      try {
        await bookbinder.write(
          sourcePath: '/tmp/in.m4b',
          destinationPath: '${Directory.systemTemp.path}/out.m4b',
          audiobook: book,
        );
      } catch (_) {
        // Mocked runner reports ffmpeg success without producing the temp
        // output file, so the rename step throws. We only care about the
        // arguments captured below.
      }

      final captured = verify(() => runner.run(
            executable: '/usr/bin/ffmpeg',
            arguments: captureAny(named: 'arguments'),
          )).captured;
      final args = captured.single as List<String>;
      expect(args, contains('-map_metadata'));
      expect(args, contains('-map_chapters'));
      expect(args, contains('-c'));
      expect(args, contains('copy'));
    });

    test('atomic write: leaves destination untouched when ffmpeg fails',
        () async {
      final destPath = '${Directory.systemTemp.path}/out.m4b';
      // Pre-existing file we should NOT overwrite or clobber.
      File(destPath).writeAsStringSync('original-bytes');

      when(() => runner.run(
            executable: '/usr/bin/ffmpeg',
            arguments: any(named: 'arguments'),
          )).thenAnswer((_) async => ProcessOutput(
            exitCode: 1,
            stdout: '',
            stderr: 'simulated failure',
            stdoutBytes: Uint8List(0),
          ));

      await expectLater(
        bookbinder.write(
          sourcePath: '/tmp/in.m4b',
          destinationPath: destPath,
          audiobook: book,
        ),
        throwsA(isA<BookbinderException>()),
      );
      expect(File(destPath).readAsStringSync(), 'original-bytes');
      File(destPath).deleteSync();
    });
  });
}
