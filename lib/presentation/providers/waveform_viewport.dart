import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

@immutable
class WaveformViewport {
  const WaveformViewport({
    required this.pixelsPerSecond,
    required this.windowStart,
  });

  final double pixelsPerSecond;
  final Duration windowStart;

  WaveformViewport copyWith({
    double? pixelsPerSecond,
    Duration? windowStart,
  }) =>
      WaveformViewport(
        pixelsPerSecond: pixelsPerSecond ?? this.pixelsPerSecond,
        windowStart: windowStart ?? this.windowStart,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WaveformViewport &&
          other.pixelsPerSecond == pixelsPerSecond &&
          other.windowStart == windowStart;

  @override
  int get hashCode => Object.hash(pixelsPerSecond, windowStart);
}

const double _kDefaultPxPerSec = 100;
const double _kMaxPxPerSec = 2000;

/// Pure-logic notifier. All methods take totalDuration and viewportWidth
/// as arguments so the notifier never reads other providers and stays
/// trivial to unit-test.
class WaveformViewportNotifier extends Notifier<WaveformViewport> {
  @override
  WaveformViewport build() => const WaveformViewport(
        pixelsPerSecond: _kDefaultPxPerSec,
        windowStart: Duration.zero,
      );

  /// Resets to default zoom/start. If the file is short enough that the
  /// default 100 px/s would show more than the whole file, picks the
  /// "whole file fits" minimum instead.
  void reset(Duration totalDuration, double viewportWidth) {
    final minPxPerSec = _minPxPerSec(totalDuration, viewportWidth);
    final pxPerSec = _kDefaultPxPerSec < minPxPerSec
        ? minPxPerSec
        : _kDefaultPxPerSec;
    state = WaveformViewport(
      pixelsPerSecond: pxPerSec,
      windowStart: Duration.zero,
    );
  }

  /// Sets pixelsPerSecond and re-anchors so [centerTime] lands at the
  /// same screen fraction as before. Clamps both axes.
  void zoomTo(
    double newPxPerSec,
    Duration centerTime,
    Duration totalDuration,
    double viewportWidth,
  ) {
    final minPxPerSec = _minPxPerSec(totalDuration, viewportWidth);
    final clampedPxPerSec =
        newPxPerSec.clamp(minPxPerSec, _kMaxPxPerSec).toDouble();

    // Anchor centerTime at its current screen fraction.
    final oldWindowDuration = _windowDurationFor(
      state.pixelsPerSecond,
      viewportWidth,
    );
    final newWindowDuration = _windowDurationFor(
      clampedPxPerSec,
      viewportWidth,
    );

    final rawFraction = oldWindowDuration.inMicroseconds == 0
        ? 0.0
        : (centerTime.inMicroseconds - state.windowStart.inMicroseconds) /
            oldWindowDuration.inMicroseconds;
    // If centerTime is currently outside the window, fall back to placing
    // it at the left edge of the new window (fraction 0).
    final fraction = (rawFraction < 0 || rawFraction > 1) ? 0.0 : rawFraction;
    final newStartMicros = centerTime.inMicroseconds -
        (fraction * newWindowDuration.inMicroseconds).round();

    state = WaveformViewport(
      pixelsPerSecond: clampedPxPerSec,
      windowStart: _clampStart(
        Duration(microseconds: newStartMicros),
        newWindowDuration,
        totalDuration,
      ),
    );
  }

  void zoomIn(
    Duration centerTime,
    Duration totalDuration,
    double viewportWidth,
  ) =>
      zoomTo(
        state.pixelsPerSecond * 2,
        centerTime,
        totalDuration,
        viewportWidth,
      );

  void zoomOut(
    Duration centerTime,
    Duration totalDuration,
    double viewportWidth,
  ) =>
      zoomTo(
        state.pixelsPerSecond / 2,
        centerTime,
        totalDuration,
        viewportWidth,
      );

  /// Pans by [deltaPixels] pixels, converting to time using the current
  /// pixelsPerSecond. Positive delta scrolls toward the file end.
  void panBy(
    double deltaPixels,
    Duration totalDuration,
    double viewportWidth,
  ) {
    final deltaMicros =
        (deltaPixels / state.pixelsPerSecond * 1e6).round();
    final newStart = state.windowStart + Duration(microseconds: deltaMicros);
    final windowDuration = _windowDurationFor(
      state.pixelsPerSecond,
      viewportWidth,
    );
    state = state.copyWith(
      windowStart: _clampStart(newStart, windowDuration, totalDuration),
    );
  }

  /// Sets windowStart so the playhead lands at [anchorFraction] from the
  /// left edge of the viewport.
  void followPlayhead(
    Duration playhead,
    Duration totalDuration,
    double viewportWidth, {
    double anchorFraction = 0.25,
  }) {
    final windowDuration = _windowDurationFor(
      state.pixelsPerSecond,
      viewportWidth,
    );
    final offsetMicros =
        (windowDuration.inMicroseconds * anchorFraction).round();
    final newStart =
        playhead - Duration(microseconds: offsetMicros);
    state = state.copyWith(
      windowStart: _clampStart(newStart, windowDuration, totalDuration),
    );
  }

  // ----- internals -----

  double _minPxPerSec(Duration totalDuration, double viewportWidth) {
    final seconds = totalDuration.inMicroseconds / 1e6;
    if (seconds <= 0 || viewportWidth <= 0) return _kDefaultPxPerSec;
    return viewportWidth / seconds;
  }

  Duration _windowDurationFor(double pxPerSec, double viewportWidth) {
    if (pxPerSec <= 0) return Duration.zero;
    final micros = (viewportWidth / pxPerSec * 1e6).round();
    return Duration(microseconds: micros);
  }

  Duration _clampStart(
    Duration start,
    Duration windowDuration,
    Duration totalDuration,
  ) {
    if (start < Duration.zero) return Duration.zero;
    final maxStart = totalDuration - windowDuration;
    if (maxStart <= Duration.zero) return Duration.zero;
    if (start > maxStart) return maxStart;
    return start;
  }
}

final waveformViewportProvider =
    NotifierProvider<WaveformViewportNotifier, WaveformViewport>(
  WaveformViewportNotifier.new,
);
