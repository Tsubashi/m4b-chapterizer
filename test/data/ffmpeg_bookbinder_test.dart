import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:m4b_chapterizer/data/binary_resolver.dart';
import 'package:m4b_chapterizer/data/ffmpeg_bookbinder.dart';
import 'package:m4b_chapterizer/data/process_runner.dart';

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
}
