import 'models/audiobook.dart';

/// Reads and writes m4b audiobooks. The data layer provides an implementation
/// (`FfmpegBookbinder`); tests substitute a fake.
abstract class Bookbinder {
  /// Reads the m4b at [sourcePath] and returns a populated [Audiobook].
  Future<Audiobook> read(String sourcePath);

  /// Writes [audiobook] to [destinationPath], using [sourcePath] as the audio
  /// source. The audio stream is copied; only metadata and chapters change.
  /// Writes are atomic: if the operation fails, [destinationPath] is untouched.
  Future<void> write({
    required String sourcePath,
    required String destinationPath,
    required Audiobook audiobook,
  });
}
