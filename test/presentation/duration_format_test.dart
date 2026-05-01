import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/presentation/util/duration_format.dart';

void main() {
  group('formatDuration', () {
    test('formats zero', () {
      expect(formatDuration(Duration.zero), '00:00:00.000');
    });
    test('formats one hour two minutes three seconds and 45 ms', () {
      expect(
        formatDuration(const Duration(
            hours: 1, minutes: 2, seconds: 3, milliseconds: 45)),
        '01:02:03.045',
      );
    });
  });

  group('parseDuration', () {
    test('parses HH:MM:SS.mmm', () {
      expect(parseDuration('01:02:03.045'),
          const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 45));
    });
    test('parses MM:SS.mmm (no hours)', () {
      expect(parseDuration('02:03.045'),
          const Duration(minutes: 2, seconds: 3, milliseconds: 45));
    });
    test('parses SS (seconds only)', () {
      expect(parseDuration('15'), const Duration(seconds: 15));
    });
    test('rejects garbage', () {
      expect(() => parseDuration('not a time'), throwsFormatException);
    });
    test('rejects negative components', () {
      expect(() => parseDuration('-01:00:00'), throwsFormatException);
    });
  });
}
