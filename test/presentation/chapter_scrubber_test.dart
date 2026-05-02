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

  group('ChapterScrubber tap-to-seek', () {
    testWidgets('tap at 25% of width seeks to ~25% of duration',
        (tester) async {
      Duration? seeked;
      const total = Duration(seconds: 100);
      await tester.pumpWidget(_harness(
        totalDuration: total,
        onSeek: (d) => seeked = d,
        width: 400,
      ));

      final scrubber = find.byType(ChapterScrubber);
      final topLeft = tester.getTopLeft(scrubber);
      final size = tester.getSize(scrubber);
      // Tap at the 25% horizontal position within the scrubber.
      final tapAt = topLeft + Offset(size.width * 0.25, size.height / 2);
      await tester.tapAt(tapAt);
      await tester.pump();

      expect(seeked, isNotNull);
      // 25% of width minus 12px padding on each side. Allow ±2 seconds tolerance.
      final expected = total * (((400 * 0.25) - 12) / (400 - 24));
      expect(
        (seeked! - expected).abs() <= const Duration(seconds: 2),
        isTrue,
        reason: 'expected ~$expected, got $seeked',
      );
    });

    testWidgets('tap at the very left clamps to 0',
        (tester) async {
      Duration? seeked;
      await tester.pumpWidget(_harness(
        totalDuration: const Duration(seconds: 100),
        onSeek: (d) => seeked = d,
        width: 400,
      ));
      final scrubber = find.byType(ChapterScrubber);
      final topLeft = tester.getTopLeft(scrubber);
      await tester.tapAt(topLeft + const Offset(0, 12));
      await tester.pump();
      expect(seeked, Duration.zero);
    });

    testWidgets('tap at the very right clamps to totalDuration',
        (tester) async {
      Duration? seeked;
      const total = Duration(seconds: 100);
      await tester.pumpWidget(_harness(
        totalDuration: total,
        onSeek: (d) => seeked = d,
        width: 400,
      ));
      final scrubber = find.byType(ChapterScrubber);
      final topRight = tester.getTopRight(scrubber);
      await tester.tapAt(topRight + const Offset(-1, 12));
      await tester.pump();
      expect(seeked, total);
    });
  });

  group('ChapterScrubber snap-to-tick', () {
    testWidgets('tap within 6px of a chapter tick snaps to that start',
        (tester) async {
      Duration? seeked;
      const total = Duration(seconds: 100);
      const chapter2Start = Duration(seconds: 30);
      await tester.pumpWidget(_harness(
        totalDuration: total,
        chapterStarts: const [
          Duration.zero,
          chapter2Start,
          Duration(seconds: 60),
        ],
        onSeek: (d) => seeked = d,
        width: 400,
      ));

      final scrubber = find.byType(ChapterScrubber);
      final topLeft = tester.getTopLeft(scrubber);
      final size = tester.getSize(scrubber);
      // Compute pixel x of chapter2: 12 + (30/100) * (400 - 24) = 12 + 112.8 = 124.8
      const usable = 400 - 24;
      const padding = 12;
      const expectedX = padding + (30 / 100) * usable;
      // Tap 4px to the right of the tick → within snap radius.
      final tapAt =
          topLeft + Offset(expectedX + 4, size.height / 2);
      await tester.tapAt(tapAt);
      await tester.pump();
      expect(seeked, chapter2Start);
    });

    testWidgets('tap further than 6px from a tick does not snap',
        (tester) async {
      Duration? seeked;
      const total = Duration(seconds: 100);
      await tester.pumpWidget(_harness(
        totalDuration: total,
        chapterStarts: const [
          Duration.zero,
          Duration(seconds: 30),
        ],
        onSeek: (d) => seeked = d,
        width: 400,
      ));
      final scrubber = find.byType(ChapterScrubber);
      final topLeft = tester.getTopLeft(scrubber);
      const usable = 400 - 24;
      const padding = 12;
      const expectedX = padding + (30 / 100) * usable;
      // Tap 10px right of the tick → outside snap radius.
      await tester.tapAt(
        topLeft + const Offset(expectedX + 10, 12),
      );
      await tester.pump();
      expect(seeked, isNot(const Duration(seconds: 30)));
    });
  });
}
