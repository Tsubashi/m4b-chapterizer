import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/data/bundled_binary_resolver.dart';
import 'package:path/path.dart' as p;

void main() {
  test('on macOS, resolves to <App>.app/Contents/Resources/ffmpeg', () {
    if (!Platform.isMacOS) return; // path layout only applies on macOS
    final fakeExecutable =
        '/tmp/Pretend.app/Contents/MacOS/Pretend';
    final resolver =
        BundledBinaryResolver(executablePathOverride: fakeExecutable);
    expect(
      resolver.ffmpeg,
      p.join('/tmp/Pretend.app/Contents/Resources', 'ffmpeg'),
    );
    expect(
      resolver.ffprobe,
      p.join('/tmp/Pretend.app/Contents/Resources', 'ffprobe'),
    );
  });
}
