import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/data/binary_resolver.dart';

void main() {
  group('SystemBinaryResolver', () {
    test('resolves to the named binary on PATH', () {
      const resolver = SystemBinaryResolver();
      expect(resolver.ffmpeg, 'ffmpeg');
      expect(resolver.ffprobe, 'ffprobe');
    });
  });

  group('FixedBinaryResolver', () {
    test('returns the explicit paths it was constructed with', () {
      const resolver = FixedBinaryResolver(
        ffmpeg: '/opt/ffmpeg/bin/ffmpeg',
        ffprobe: '/opt/ffmpeg/bin/ffprobe',
      );
      expect(resolver.ffmpeg, '/opt/ffmpeg/bin/ffmpeg');
      expect(resolver.ffprobe, '/opt/ffmpeg/bin/ffprobe');
    });
  });
}
