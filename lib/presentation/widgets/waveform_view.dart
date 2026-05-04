import 'dart:async';

import 'package:flutter/gestures.dart';
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
  StreamSubscription<Duration>? _positionSub;

  // Captured at the latest build so the position-stream listener has
  // fresh totalDuration and viewportWidth without re-reading providers
  // outside a build cycle.
  Duration _latestTotalDuration = Duration.zero;
  double _latestViewportWidth = 0;

  @override
  void initState() {
    super.initState();
    final controller = ref.read(playbackControllerProvider);
    _positionSub = controller.positionStream.listen(_onPosition);
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  void _onPosition(Duration playhead) {
    final controller = ref.read(playbackControllerProvider);
    if (!controller.playing) return;
    if (_latestTotalDuration <= Duration.zero ||
        _latestViewportWidth <= 0) {
      return;
    }
    ref.read(waveformViewportProvider.notifier).followPlayhead(
          playhead,
          _latestTotalDuration,
          _latestViewportWidth,
        );
  }

  @override
  Widget build(BuildContext context) {
    // Reset the viewport whenever the file path changes. Deferred to a
    // post-frame callback so LayoutBuilder has had a chance to capture
    // the (possibly new) viewport width into _latestViewportWidth.
    ref.listen<String?>(
      editorProvider.select((s) => s.path),
      (previous, next) {
        if (next != null && next != previous) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final book = ref.read(editorProvider).audiobook;
            if (book == null || _latestViewportWidth <= 0) return;
            ref
                .read(waveformViewportProvider.notifier)
                .reset(book.totalDuration, _latestViewportWidth);
          });
        }
      },
    );

    final book = ref.watch(editorProvider).audiobook;
    final path = ref.watch(editorProvider.select((s) => s.path));
    if (book == null || path == null) {
      return const SizedBox(height: WaveformView.height);
    }

    _latestTotalDuration = book.totalDuration;

    final peaksAsync = ref.watch(waveformPeaksProvider(path));
    final peaks = peaksAsync.maybeWhen(
      data: (p) => p,
      orElse: () => const <double>[],
    );

    final viewport = ref.watch(waveformViewportProvider);
    final controller = ref.watch(playbackControllerProvider);
    final viewportNotifier = ref.read(waveformViewportProvider.notifier);

    return SizedBox(
      height: WaveformView.height,
      child: LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        _latestViewportWidth = width;
        return Stack(
          children: [
            Positioned.fill(
              child: StreamBuilder<Duration>(
                stream: controller.positionStream,
                initialData: controller.position,
                builder: (context, snapshot) {
                  final playhead = snapshot.data ?? controller.position;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    dragStartBehavior: DragStartBehavior.down,
                    onTapUp: (details) => _onTap(
                      details.localPosition.dx,
                      width,
                      book.totalDuration,
                      controller,
                    ),
                    onHorizontalDragUpdate: (details) {
                      if (controller.playing) return;
                      viewportNotifier.panBy(
                        -details.delta.dx,
                        book.totalDuration,
                        width,
                      );
                    },
                    child: CustomPaint(
                      size: Size(width, WaveformView.height),
                      painter: _WaveformPainter(
                        peaks: peaks,
                        totalDuration: book.totalDuration,
                        windowStart: viewport.windowStart,
                        pixelsPerSecond: viewport.pixelsPerSecond,
                        playhead: playhead,
                        chapterStarts: [
                          for (final c in book.chapters) c.start
                        ],
                        playedColor:
                            Theme.of(context).colorScheme.primary,
                        unplayedColor: Theme.of(context)
                            .colorScheme
                            .outlineVariant,
                        tickColor:
                            Theme.of(context).colorScheme.outline,
                        playheadColor:
                            Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: _ZoomButtons(
                onZoomIn: () => viewportNotifier.zoomIn(
                  controller.position,
                  book.totalDuration,
                  width,
                ),
                onZoomOut: () => viewportNotifier.zoomOut(
                  controller.position,
                  book.totalDuration,
                  width,
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  void _onTap(
    double localX,
    double width,
    Duration totalDuration,
    PlaybackController controller,
  ) {
    final viewport = ref.read(waveformViewportProvider);
    if (width <= 0 || viewport.pixelsPerSecond <= 0) return;
    final fraction = (localX / width).clamp(0.0, 1.0);
    final windowMicros =
        (width / viewport.pixelsPerSecond * 1e6).round();
    final tMicros =
        viewport.windowStart.inMicroseconds + (fraction * windowMicros).round();
    final clamped = tMicros.clamp(0, totalDuration.inMicroseconds);
    controller.seek(Duration(microseconds: clamped));
  }
}

class _ZoomButtons extends StatelessWidget {
  const _ZoomButtons({required this.onZoomIn, required this.onZoomOut});

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const ValueKey('waveform.zoomOut'),
          icon: const Icon(Icons.remove),
          tooltip: 'Zoom out',
          onPressed: onZoomOut,
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          key: const ValueKey('waveform.zoomIn'),
          icon: const Icon(Icons.add),
          tooltip: 'Zoom in',
          onPressed: onZoomIn,
          visualDensity: VisualDensity.compact,
        ),
      ],
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

  static const double _halfHeight = 50;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || pixelsPerSecond <= 0) return;
    final centerY = size.height / 2;
    final windowMicros = (size.width / pixelsPerSecond * 1e6).round();

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
      final relMicros = start.inMicroseconds - windowStart.inMicroseconds;
      if (relMicros < 0 || relMicros > windowMicros) continue;
      final x = relMicros / windowMicros * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  void _paintPlayhead(Canvas canvas, Size size, int windowMicros) {
    final relMicros = playhead.inMicroseconds - windowStart.inMicroseconds;
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
