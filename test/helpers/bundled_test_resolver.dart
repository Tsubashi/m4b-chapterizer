import 'dart:io';

import 'package:m4b_chapterizer/data/binary_resolver.dart';

/// Returns a [BinaryResolver] pointing to `assets/bin/<platform>/`.
/// Used by integration tests so they exercise the same ffmpeg version that
/// ships in the production .app bundle.
///
/// Throws [StateError] with a clear remediation message if the bundled
/// binaries don't exist (developer hasn't run `dart run tool/fetch_ffmpeg.dart`).
BinaryResolver bundledTestResolver() {
  final key = _platformKey();
  final exeSuffix = Platform.isWindows ? '.exe' : '';
  final ffmpeg = 'assets/bin/$key/ffmpeg$exeSuffix';
  final ffprobe = 'assets/bin/$key/ffprobe$exeSuffix';
  for (final p in [ffmpeg, ffprobe]) {
    if (!File(p).existsSync()) {
      throw StateError(
        '$p not found. Run: dart run tool/fetch_ffmpeg.dart',
      );
    }
  }
  return FixedBinaryResolver(ffmpeg: ffmpeg, ffprobe: ffprobe);
}

String _platformKey() {
  if (Platform.isMacOS) {
    return Platform.version.contains('arm64') ? 'macos-arm64' : 'macos-x64';
  }
  if (Platform.isWindows) return 'windows-x64';
  if (Platform.isLinux) return 'linux-x64';
  throw UnsupportedError('Unsupported: ${Platform.operatingSystem}');
}
