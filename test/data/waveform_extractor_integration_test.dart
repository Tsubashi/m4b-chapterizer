import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/data/waveform_extractor.dart';

import '../helpers/bundled_test_resolver.dart';

void main() {
  test('extracts near-zero peaks from the silent fixture m4b', () async {
    final extractor = WaveformExtractor(
      binaries: bundledTestResolver(),
      processStarter: Process.start,
    );

    final peaks = await extractor.extract(
      path: 'test/fixtures/sample.m4b',
      totalDuration: const Duration(seconds: 30),
      targetPeaks: 4096,
    );

    // Bin alignment may leave a partial final bin, and the fixture's actual
    // duration may be slightly longer than the nominal 30 s, producing a few
    // extra bins. Allow a generous upper bound.
    expect(peaks.length, inInclusiveRange(4090, 4200));
    final maxPeak = peaks.fold<double>(0, (a, b) => a > b ? a : b);
    expect(
      maxPeak,
      lessThan(0.05),
      reason:
          'silent fixture should produce near-zero peaks; max peak was $maxPeak',
    );
  });
}
