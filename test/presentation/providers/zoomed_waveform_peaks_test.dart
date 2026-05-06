import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
import 'package:m4b_chapterizer/presentation/providers/zoomed_waveform_peaks.dart';

Audiobook _book(Duration totalDuration) => Audiobook.validated(
      chapters: const [Chapter(title: 'A', start: Duration.zero)],
      totalDuration: totalDuration,
    );

void main() {
  test('tile in the middle of the file', () {
    final book = _book(const Duration(seconds: 60));
    const key = WaveformTileKey(
      path: '/x.m4b',
      tileIndex: 2,
      viewportDurationMicros: 8 * 1000 * 1000,
      pixelsPerSecond: 100,
    );
    final b = computeTileBounds(book, key);
    // Unclamped: start = (2 - 1) * 8s = 8s; end = 8s + 24s = 32s.
    expect(b.start, const Duration(seconds: 8));
    expect(b.duration, const Duration(seconds: 24));
    expect(b.targetPeaks, 24 * 100);
  });

  test('tile clamped at the file start (tileIndex 0)', () {
    final book = _book(const Duration(seconds: 60));
    const key = WaveformTileKey(
      path: '/x.m4b',
      tileIndex: 0,
      viewportDurationMicros: 8 * 1000 * 1000,
      pixelsPerSecond: 100,
    );
    final b = computeTileBounds(book, key);
    // Unclamped start = -8s; clamped to 0s.
    // Unclamped end = 16s.
    expect(b.start, Duration.zero);
    expect(b.duration, const Duration(seconds: 16));
    expect(b.targetPeaks, 16 * 100);
  });

  test('tile clamped at the file end', () {
    final book = _book(const Duration(seconds: 30));
    const key = WaveformTileKey(
      path: '/x.m4b',
      tileIndex: 2,
      viewportDurationMicros: 8 * 1000 * 1000,
      pixelsPerSecond: 100,
    );
    final b = computeTileBounds(book, key);
    // Unclamped: start = 8s, end = 32s. End clamped to 30s.
    expect(b.start, const Duration(seconds: 8));
    expect(b.duration, const Duration(seconds: 22));
    expect(b.targetPeaks, 22 * 100);
  });

  test('tile entirely past the file end produces zero duration', () {
    final book = _book(const Duration(seconds: 5));
    const key = WaveformTileKey(
      path: '/x.m4b',
      tileIndex: 10,
      viewportDurationMicros: 8 * 1000 * 1000,
      pixelsPerSecond: 100,
    );
    final b = computeTileBounds(book, key);
    expect(b.duration, Duration.zero);
    expect(b.targetPeaks, 0);
  });

  test('WaveformTileKey equality and hashCode', () {
    const a = WaveformTileKey(
      path: '/x.m4b',
      tileIndex: 1,
      viewportDurationMicros: 8000000,
      pixelsPerSecond: 100,
    );
    const b = WaveformTileKey(
      path: '/x.m4b',
      tileIndex: 1,
      viewportDurationMicros: 8000000,
      pixelsPerSecond: 100,
    );
    const c = WaveformTileKey(
      path: '/x.m4b',
      tileIndex: 2,
      viewportDurationMicros: 8000000,
      pixelsPerSecond: 100,
    );
    expect(a, equals(b));
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(equals(c)));
  });
}
