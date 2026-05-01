import 'dart:typed_data';

import '../domain/bookbinder.dart';
import '../domain/models/audiobook.dart';
import '../domain/models/cover.dart';
import 'binary_resolver.dart';
import 'ffmpeg_invocation.dart' as inv;
import 'ffprobe_codec.dart';
import 'process_runner.dart';

class BookbinderException implements Exception {
  BookbinderException(this.message, {this.stderr});

  final String message;
  final String? stderr;

  @override
  String toString() =>
      'BookbinderException: $message${stderr == null ? '' : '\n$stderr'}';
}

class FfmpegBookbinder implements Bookbinder {
  FfmpegBookbinder({
    required ProcessRunner runner,
    required BinaryResolver binaries,
    FfprobeCodec ffprobeCodec = const FfprobeCodec(),
  })  : _runner = runner,
        _binaries = binaries,
        _ffprobe = ffprobeCodec;

  final ProcessRunner _runner;
  final BinaryResolver _binaries;
  final FfprobeCodec _ffprobe;

  @override
  Future<Audiobook> read(String sourcePath) async {
    final probeOutput = await _runner.run(
      executable: _binaries.ffprobe,
      arguments: inv.probeArguments(sourcePath),
    );
    if (probeOutput.exitCode != 0) {
      throw BookbinderException(
        'ffprobe failed for $sourcePath',
        stderr: probeOutput.stderr,
      );
    }
    final probe = _ffprobe.decode(probeOutput.stdout);
    if (!probe.hasAttachedCover) return probe.audiobook;
    final coverBytes = await _extractCover(sourcePath);
    if (coverBytes == null) return probe.audiobook;
    return probe.audiobook.copyWith(
      cover: Cover(bytes: coverBytes, mimeType: 'image/jpeg'),
    );
  }

  Future<Uint8List?> _extractCover(String sourcePath) async {
    final out = await _runner.run(
      executable: _binaries.ffmpeg,
      arguments: inv.extractCoverArguments(sourcePath),
    );
    if (out.exitCode != 0 || out.stdoutBytes.isEmpty) return null;
    return out.stdoutBytes;
  }

  @override
  Future<void> write({
    required String sourcePath,
    required String destinationPath,
    required Audiobook audiobook,
  }) {
    throw UnimplementedError('FfmpegBookbinder.write — Task 13');
  }
}
