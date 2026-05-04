import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/models/cover.dart';

void main() {
  group('Cover', () {
    test('exposes bytes and mime type', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final cover = Cover(bytes: bytes, mimeType: 'image/png');
      expect(cover.bytes, bytes);
      expect(cover.mimeType, 'image/png');
    });

    test('is value-equal when bytes and mime type match', () {
      final a = Cover(bytes: Uint8List.fromList([1, 2]), mimeType: 'image/jpeg');
      final b = Cover(bytes: Uint8List.fromList([1, 2]), mimeType: 'image/jpeg');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('rejects unsupported mime types', () {
      expect(
        () => Cover(
          bytes: Uint8List.fromList([0]),
          mimeType: 'image/gif',
        ),
        throwsArgumentError,
      );
    });
  });
}
