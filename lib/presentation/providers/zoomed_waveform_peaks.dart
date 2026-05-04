import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../../data/waveform_extractor.dart';
import '../../domain/models/audiobook.dart';
import 'editor_state.dart';

@immutable
class WaveformTileKey {
  const WaveformTileKey({
    required this.path,
    required this.tileIndex,
    required this.viewportDurationMicros,
    required this.pixelsPerSecond,
  });

  final String path;
  final int tileIndex;
  final int viewportDurationMicros;
  final double pixelsPerSecond;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WaveformTileKey &&
          other.path == path &&
          other.tileIndex == tileIndex &&
          other.viewportDurationMicros == viewportDurationMicros &&
          other.pixelsPerSecond == pixelsPerSecond;

  @override
  int get hashCode =>
      Object.hash(path, tileIndex, viewportDurationMicros, pixelsPerSecond);
}

@immutable
class WaveformTilePeaks {
  const WaveformTilePeaks({
    required this.tileStart,
    required this.tileDuration,
    required this.peaks,
  });

  final Duration tileStart;
  final Duration tileDuration;
  final List<double> peaks;
}

@immutable
class TileBounds {
  const TileBounds({
    required this.start,
    required this.duration,
    required this.targetPeaks,
  });

  final Duration start;
  final Duration duration;
  final int targetPeaks;
}

/// Computes the actual tile range and per-pixel peak count for the
/// given key, clamped to the file's `[0, totalDuration]`.
TileBounds computeTileBounds(Audiobook book, WaveformTileKey key) {
  final viewportMicros = key.viewportDurationMicros;
  final unclampedStartMicros =
      key.tileIndex * viewportMicros - viewportMicros;
  final unclampedEndMicros = unclampedStartMicros + 3 * viewportMicros;
  final totalMicros = book.totalDuration.inMicroseconds;

  final startMicros =
      unclampedStartMicros < 0 ? 0 : unclampedStartMicros;
  final endMicros =
      unclampedEndMicros > totalMicros ? totalMicros : unclampedEndMicros;
  final durationMicros = endMicros - startMicros;
  if (durationMicros <= 0) {
    return TileBounds(
      start: Duration(microseconds: startMicros),
      duration: Duration.zero,
      targetPeaks: 0,
    );
  }
  final targetPeaks = (durationMicros /
          Duration.microsecondsPerSecond *
          key.pixelsPerSecond)
      .ceil();
  return TileBounds(
    start: Duration(microseconds: startMicros),
    duration: Duration(microseconds: durationMicros),
    targetPeaks: targetPeaks,
  );
}

/// Per-tile peaks for the zoomable waveform view. Tests override this
/// family to return canned `WaveformTilePeaks` instances; production
/// reads `binaryResolverProvider` and spawns ffmpeg.
final zoomedWaveformPeaksProvider =
    FutureProvider.family<WaveformTilePeaks, WaveformTileKey>(
  (ref, key) async {
    final book = ref.read(editorProvider).audiobook;
    if (book == null) {
      return const WaveformTilePeaks(
        tileStart: Duration.zero,
        tileDuration: Duration.zero,
        peaks: [],
      );
    }
    final bounds = computeTileBounds(book, key);
    if (bounds.targetPeaks <= 0) {
      return WaveformTilePeaks(
        tileStart: bounds.start,
        tileDuration: bounds.duration,
        peaks: const [],
      );
    }
    // coverage:ignore-start
    // Production wiring: a fresh extractor per tile so concurrent
    // tiles can't share cancel state. Tests override this whole
    // provider with `overrideWith((ref, key) async => ...)`.
    final extractor = WaveformExtractor(
      binaries: ref.read(binaryResolverProvider),
      processStarter: Process.start,
    );
    ref.onDispose(extractor.cancel);
    final peaks = await extractor.extractRange(
      path: key.path,
      start: bounds.start,
      duration: bounds.duration,
      targetPeaks: bounds.targetPeaks,
    );
    return WaveformTilePeaks(
      tileStart: bounds.start,
      tileDuration: bounds.duration,
      peaks: peaks,
    );
    // coverage:ignore-end
  },
);
