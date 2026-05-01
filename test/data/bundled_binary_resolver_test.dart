import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/data/bundled_binary_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('extracts ffmpeg and ffprobe from assets into the support directory',
      () async {
    final tempSupport =
        await Directory.systemTemp.createTemp('m4b-bundled-');
    addTearDown(() => tempSupport.delete(recursive: true));

    // Pretend asset loader: returns canned bytes for the two known assets.
    Future<ByteData> loader(String key) async {
      if (key.endsWith('/ffmpeg') || key.endsWith('/ffmpeg.exe')) {
        return ByteData.view(Uint8List.fromList([0x7F, 0x45, 0x4C, 0x46]).buffer);
      }
      if (key.endsWith('/ffprobe') || key.endsWith('/ffprobe.exe')) {
        return ByteData.view(Uint8List.fromList([0x7F, 0x45, 0x4C, 0x46]).buffer);
      }
      throw FlutterError('asset not found: $key');
    }

    final resolver = BundledBinaryResolver(
      assetLoader: loader,
      supportDirOverride: tempSupport.path,
    );

    final ffmpeg = await resolver.resolveFfmpeg();
    final ffprobe = await resolver.resolveFfprobe();

    expect(File(ffmpeg).existsSync(), isTrue);
    expect(File(ffprobe).existsSync(), isTrue);
    if (!Platform.isWindows) {
      // Should be marked executable.
      final stat = File(ffmpeg).statSync();
      expect(stat.modeString().contains('x'), isTrue);
    }
  });
}
