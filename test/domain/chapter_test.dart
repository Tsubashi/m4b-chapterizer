import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';

void main() {
  group('Chapter', () {
    test('exposes its title and start time', () {
      const chapter = Chapter(title: 'Prologue', start: Duration.zero);
      expect(chapter.title, 'Prologue');
      expect(chapter.start, Duration.zero);
    });

    test('is value-equal when fields match', () {
      const a = Chapter(title: 'C1', start: Duration(seconds: 5));
      const b = Chapter(title: 'C1', start: Duration(seconds: 5));
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('copyWith overrides only the supplied fields', () {
      const original = Chapter(title: 'A', start: Duration(seconds: 10));
      final renamed = original.copyWith(title: 'B');
      expect(renamed.title, 'B');
      expect(renamed.start, const Duration(seconds: 10));
    });

    test('toString includes both fields for diagnostic output', () {
      const chapter = Chapter(title: 'Intro', start: Duration(seconds: 5));
      final str = chapter.toString();
      expect(str, contains('Intro'));
      expect(str, contains('Chapter('));
    });
  });
}
