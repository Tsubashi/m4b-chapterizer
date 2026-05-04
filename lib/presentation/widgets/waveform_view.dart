import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/editor_state.dart';
import '../providers/playback.dart';
import '../providers/waveform.dart';
import '../providers/waveform_viewport.dart';

class WaveformView extends ConsumerStatefulWidget {
  const WaveformView({super.key});

  static const double height = 120;

  @override
  ConsumerState<WaveformView> createState() => _WaveformViewState();
}

class _WaveformViewState extends ConsumerState<WaveformView> {
  @override
  Widget build(BuildContext context) {
    final book = ref.watch(editorProvider).audiobook;
    final path = ref.watch(editorProvider.select((s) => s.path));
    if (book == null || path == null) {
      return const SizedBox(height: WaveformView.height);
    }

    final peaksAsync = ref.watch(waveformPeaksProvider(path));
    final peaks = peaksAsync.maybeWhen(
      data: (p) => p,
      orElse: () => const <double>[],
    );

    final viewport = ref.watch(waveformViewportProvider);
    final controller = ref.watch(playbackControllerProvider);

    return SizedBox(
      height: WaveformView.height,
      child: LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        return StreamBuilder<Duration>(
          stream: controller.positionStream,
          initialData: controller.position,
          builder: (context, snapshot) {
            final playhead = snapshot.data ?? controller.position;
            return CustomPaint(
              size: Size(width, WaveformView.height),
              painter: _WaveformPainter(
                peaks: peaks,
                totalDuration: book.totalDuration,
                windowStart: viewport.windowStart,
                pixelsPerSecond: viewport.pixelsPerSecond,
                playhead: playhead,
                chapterStarts: [for (final c in book.chapters) c.start],
                playedColor: Theme.of(context).colorScheme.primary,
                unplayedColor:
                    Theme.of(context).colorScheme.outlineVariant,
                tickColor: Theme.of(context).colorScheme.outline,
                playheadColor: Theme.of(context).colorScheme.primary,
              ),
            );
          },
        );
      }),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.peaks,
    required this.totalDuration,
    required this.windowStart,
    required this.pixelsPerSecond,
    required this.playhead,
    required this.chapterStarts,
    required this.playedColor,
    required this.unplayedColor,
    required this.tickColor,
    required this.playheadColor,
  });

  final List<double> peaks;
  final Duration totalDuration;
  final Duration windowStart;
  final double pixelsPerSecond;
  final Duration playhead;
  final List<Duration> chapterStarts;
  final Color playedColor;
  final Color unplayedColor;
  final Color tickColor;
  final Color playheadColor;

  static const double _halfHeight = 50; // wave fills 100 of 120 px

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || pixelsPerSecond <= 0) return;
    final centerY = size.height / 2;
    final windowMicros =
        (size.width / pixelsPerSecond * 1e6).round();

    if (peaks.isNotEmpty) {
      _paintWaveform(canvas, size, centerY, windowMicros);
    }
    _paintTicks(canvas, size, windowMicros);
    _paintPlayhead(canvas, size, windowMicros);
  }

  void _paintWaveform(
    Canvas canvas,
    Size size,
    double centerY,
    int windowMicros,
  ) {
    final played = Paint()
      ..color = playedColor
      ..strokeWidth = 1;
    final unplayed = Paint()
      ..color = unplayedColor
      ..strokeWidth = 1;
    final pixelCount = size.width.ceil();
    final totalMicros = totalDuration.inMicroseconds;
    if (totalMicros <= 0) return;
    for (var px = 0; px < pixelCount; px++) {
      final fractionInWindow = px / size.width;
      final tMicros = windowStart.inMicroseconds +
          (fractionInWindow * windowMicros).round();
      if (tMicros < 0 || tMicros >= totalMicros) continue;
      final binFraction = tMicros / totalMicros;
      var binIndex = (binFraction * peaks.length).floor();
      if (binIndex >= peaks.length) binIndex = peaks.length - 1;
      final peak = peaks[binIndex];
      final h = peak * _halfHeight;
      final paint = tMicros <= playhead.inMicroseconds ? played : unplayed;
      canvas.drawLine(
        Offset(px.toDouble(), centerY - h),
        Offset(px.toDouble(), centerY + h),
        paint,
      );
    }
  }

  void _paintTicks(Canvas canvas, Size size, int windowMicros) {
    final paint = Paint()
      ..color = tickColor
      ..strokeWidth = 2;
    for (final start in chapterStarts) {
      final relMicros =
          start.inMicroseconds - windowStart.inMicroseconds;
      if (relMicros < 0 || relMicros > windowMicros) continue;
      final x = relMicros / windowMicros * size.width;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );
    }
  }

  void _paintPlayhead(Canvas canvas, Size size, int windowMicros) {
    final relMicros =
        playhead.inMicroseconds - windowStart.inMicroseconds;
    if (relMicros < 0 || relMicros > windowMicros) return;
    final x = relMicros / windowMicros * size.width;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = playheadColor
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.peaks != peaks ||
      old.totalDuration != totalDuration ||
      old.windowStart != windowStart ||
      old.pixelsPerSecond != pixelsPerSecond ||
      old.playhead != playhead ||
      old.chapterStarts != chapterStarts ||
      old.playedColor != playedColor ||
      old.unplayedColor != unplayedColor ||
      old.tickColor != tickColor ||
      old.playheadColor != playheadColor;
}
