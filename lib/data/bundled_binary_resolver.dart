import 'dart:io';

import 'package:path/path.dart' as p;

import 'binary_resolver.dart';

/// Resolves to the ffmpeg/ffprobe executables bundled inside the desktop
/// application's `Contents/Resources/` (macOS) directory at build time.
///
/// On macOS, `Platform.resolvedExecutable` is at
/// `<App>.app/Contents/MacOS/<App>`, so the binaries are at
/// `<App>.app/Contents/Resources/{ffmpeg,ffprobe}`.
class BundledBinaryResolver implements BinaryResolver {
  BundledBinaryResolver({String? executablePathOverride})
      : _executablePath = executablePathOverride ?? Platform.resolvedExecutable; // coverage:ignore-line

  final String _executablePath;

  String _resolve(String name) {
    if (Platform.isMacOS) {
      // .../<App>.app/Contents/MacOS/<App>  ->  .../<App>.app/Contents/Resources/<name>
      final macOSDir = p.dirname(_executablePath);
      final contentsDir = p.dirname(macOSDir);
      return p.join(contentsDir, 'Resources', name);
    }
    // coverage:ignore-start
    // The Windows/Linux branch can't be reached when the test suite runs
    // on macOS CI. The macOS branch above is covered by
    // `bundled_binary_resolver_test.dart`.
    final dir = p.dirname(_executablePath);
    final exeSuffix = Platform.isWindows ? '.exe' : '';
    return p.join(dir, '$name$exeSuffix');
    // coverage:ignore-end
  }

  @override
  String get ffmpeg => _resolve('ffmpeg');

  @override
  String get ffprobe => _resolve('ffprobe');
}
