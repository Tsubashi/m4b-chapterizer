import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/presentation/widgets/chapter_scrubber.dart';

Widget _harness({
  Duration position = Duration.zero,
  Duration totalDuration = const Duration(seconds: 100),
  List<Duration> chapterStarts = const [],
  ValueChanged<Duration>? onSeek,
  double width = 400,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: ChapterScrubber(
            position: position,
            totalDuration: totalDuration,
            chapterStarts: chapterStarts,
            onSeek: onSeek ?? (_) {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('ChapterScrubber rendering', () {
    testWidgets('renders without exception at default size', (tester) async {
      await tester.pumpWidget(_harness());
      expect(find.byType(ChapterScrubber), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders at narrow constraints without overflow',
        (tester) async {
      await tester.pumpWidget(_harness(width: 180));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders with chapter ticks without exception',
        (tester) async {
      await tester.pumpWidget(_harness(
        chapterStarts: const [
          Duration.zero,
          Duration(seconds: 30),
          Duration(seconds: 60),
        ],
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('clamps a position outside [0, totalDuration]',
        (tester) async {
      await tester.pumpWidget(_harness(
        position: const Duration(seconds: -10),
        totalDuration: const Duration(seconds: 100),
      ));
      expect(tester.takeException(), isNull);
    });
  });
}
