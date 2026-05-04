/// Locates the `ffmpeg` and `ffprobe` executables.
abstract class BinaryResolver {
  String get ffmpeg;
  String get ffprobe;
}

/// Relies on the OS to locate `ffmpeg` and `ffprobe` on `PATH`.
/// Used by tests, CI, and developer machines.
class SystemBinaryResolver implements BinaryResolver {
  const SystemBinaryResolver();

  @override
  String get ffmpeg => 'ffmpeg';

  @override
  String get ffprobe => 'ffprobe';
}

/// Returns explicit absolute paths. Used by `BundledBinaryResolver` (Phase 8)
/// and by tests that want full control.
class FixedBinaryResolver implements BinaryResolver {
  const FixedBinaryResolver({required this.ffmpeg, required this.ffprobe});

  @override
  final String ffmpeg;

  @override
  final String ffprobe;
}
