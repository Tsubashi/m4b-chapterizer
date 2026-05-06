import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/editor_state.dart';
import '../providers/playback.dart';
import '../providers/waveform_viewport.dart';
import '../providers/zoomed_waveform_peaks.dart';

class WaveformView extends ConsumerStatefulWidget {
  const WaveformView({super.key});

  static const double height = 120;

  @override
  ConsumerState<WaveformView> createState() => _WaveformViewState();
}

class _WaveformViewState extends ConsumerState<WaveformView>
    with SingleTickerProviderStateMixin {
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<double>? _speedSub;
  late final Ticker _ticker;

  Duration _latestTotalDuration = Duration.zero;
  double _latestViewportWidth = 0;

  WaveformTilePeaks? _lastTile;
  bool _isPlaying = false;

  // Extrapolation baseline. _basePosition is the most recent value the
  // playback stream reported; _baseWallClock is the wall-clock time at
  // that moment (read via package:clock so fake_async advances it in
  // tests). The Ticker drives per-frame repaints; the actual delta we
  // extrapolate by is the wall-clock delta, scaled by playback speed.
  Duration _basePosition = Duration.zero;
  DateTime _baseWallClock = DateTime.fromMicrosecondsSinceEpoch(0);

  // What the painter actually consumes for the playhead line.
  Duration _smoothedPlayhead = Duration.zero;

  // The position stream emits at ~5 Hz, so each baseline is only
  // useful for ~200 ms of extrapolation. If we go significantly past
  // that without a fresh emission, stop ticking — there's no
  // meaningful new information to extrapolate to and a runaway
  // Ticker prevents `pumpAndSettle` from terminating in tests. The
  // next position emission re-arms the Ticker via _onPosition.
  static const Duration _extrapolationBudget = Duration(milliseconds: 1000);

  /// Multiplier applied to wall-clock delta when extrapolating between
  /// position-stream emissions. Reads PlaybackController.speed live so
  /// the speed control's setSpeed call is reflected on the next Ticker
  /// tick.
  double _currentPlaybackSpeed() =>
      ref.read(playbackControllerProvider).speed;

  @override
  void initState() {
    super.initState();
    final controller = ref.read(playbackControllerProvider);
    _isPlaying = controller.playing;
    _basePosition = controller.position;
    _baseWallClock = clock.now();
    _smoothedPlayhead = controller.position;

    _positionSub = controller.positionStream.listen(_onPosition);
    _playingSub = controller.playingStream.listen(_onPlayingChange);
    _speedSub = controller.speedStream.listen(_onSpeedChange);

    _ticker = createTicker(_onTick);
    if (_isPlaying) _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _positionSub?.cancel();
    _playingSub?.cancel();
    _speedSub?.cancel();
    super.dispose();
  }

  void _onPosition(Duration playhead) {
    // Always reset the extrapolation baseline.
    _basePosition = playhead;
    _baseWallClock = clock.now();

    if (_isPlaying) {
      // Re-arm the Ticker: it may have stopped itself if too much
      // time passed without a stream emission (see _onTick).
      if (!_ticker.isActive) _ticker.start();
      return;
    }

    // Paused: drive the painter directly from the stream value, and
    // run the existing ensure-visible logic.
    if (_latestTotalDuration <= Duration.zero ||
        _latestViewportWidth <= 0) {
      setState(() => _smoothedPlayhead = playhead);
      return;
    }
    final viewport = ref.read(waveformViewportProvider);
    final windowMicros =
        (_latestViewportWidth / viewport.pixelsPerSecond * 1e6).round();
    final windowEnd =
        viewport.windowStart + Duration(microseconds: windowMicros);
    if (playhead < viewport.windowStart || playhead > windowEnd) {
      ref.read(waveformViewportProvider.notifier).followPlayhead(
            playhead,
            _latestTotalDuration,
            _latestViewportWidth,
          );
    }
    setState(() => _smoothedPlayhead = playhead);
  }

  void _onPlayingChange(bool playing) {
    if (!mounted || _isPlaying == playing) return;
    final controller = ref.read(playbackControllerProvider);
    _basePosition = controller.position;
    // Reset the wall-clock baseline so the first post-resume delta
    // is 0, not whatever wall time elapsed while paused.
    _baseWallClock = clock.now();
    setState(() {
      _isPlaying = playing;
      _smoothedPlayhead = _basePosition;
    });
    if (playing) {
      _ticker.start();
    } else {
      _ticker.stop();
    }
  }

  void _onSpeedChange(double newSpeed) {
    if (!mounted) return;
    // The new speed only applies to wall-clock time strictly after the
    // change. Re-read controller.position and restamp the wall-clock
    // baseline so the next Ticker tick computes a small delta scaled
    // by the new speed, not the entire pre-change interval scaled by it.
    final controller = ref.read(playbackControllerProvider);
    _basePosition = controller.position;
    _baseWallClock = clock.now();
  }

  void _onTick(Duration tickerElapsed) {
    if (!mounted) return;

    final wallDelta = clock.now().difference(_baseWallClock);

    // If we've been extrapolating without a fresh stream emission for
    // longer than the budget, stop the Ticker. The next emission will
    // restart it. This bounds drift and lets `pumpAndSettle` settle
    // when nothing else is keeping the frame loop alive.
    if (wallDelta >= _extrapolationBudget) {
      _ticker.stop();
      return;
    }

    final speedScaledMicros =
        (wallDelta.inMicroseconds * _currentPlaybackSpeed()).round();
    final interpolated =
        _basePosition + Duration(microseconds: speedScaledMicros);
    final clampedMicros = interpolated.inMicroseconds
        .clamp(0, _latestTotalDuration.inMicroseconds);
    final clamped = Duration(microseconds: clampedMicros);

    if (_latestTotalDuration <= Duration.zero ||
        _latestViewportWidth <= 0) {
      setState(() => _smoothedPlayhead = clamped);
      return;
    }

    ref.read(waveformViewportProvider.notifier).followPlayhead(
          clamped,
          _latestTotalDuration,
          _latestViewportWidth,
        );
    setState(() => _smoothedPlayhead = clamped);
  }

  /// True if `tile`'s `[tileStart, tileStart + tileDuration)` intersects
  /// the visible viewport `[windowStart, windowStart + windowDurationMicros)`.
  bool _tileOverlapsViewport(
    WaveformTilePeaks tile,
    Duration windowStart,
    int windowDurationMicros,
  ) {
    final tileStartMicros = tile.tileStart.inMicroseconds;
    final tileEndMicros = tileStartMicros + tile.tileDuration.inMicroseconds;
    final windowStartMicros = windowStart.inMicroseconds;
    final windowEndMicros = windowStartMicros + windowDurationMicros;
    return tileStartMicros < windowEndMicros &&
        tileEndMicros > windowStartMicros;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(
      editorProvider.select((s) => s.path),
      (previous, next) {
        if (next != null && next != previous) {
          // Drop the previous file's tile so it can't bleed into the
          // first frame of the new file.
          _lastTile = null;
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

    final viewport = ref.watch(waveformViewportProvider);
    final controller = ref.watch(playbackControllerProvider);
    final viewportNotifier = ref.read(waveformViewportProvider.notifier);

    return SizedBox(
      height: WaveformView.height,
      child: LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        _latestViewportWidth = width;

        final viewportDurationMicros =
            (width / viewport.pixelsPerSecond * 1e6).round();
        final tileIndex = viewportDurationMicros == 0
            ? 0
            : viewport.windowStart.inMicroseconds ~/ viewportDurationMicros;
        final tileKey = WaveformTileKey(
          path: path,
          tileIndex: tileIndex,
          viewportDurationMicros: viewportDurationMicros,
          pixelsPerSecond: viewport.pixelsPerSecond,
        );
        final tileAsync = ref.watch(zoomedWaveformPeaksProvider(tileKey));

        if (tileAsync.hasValue) {
          final resolved = tileAsync.value!;
          if (resolved.tileDuration > Duration.zero) {
            _lastTile = resolved;
          }
        }

        if (_isPlaying) {
          final nextTileKey = WaveformTileKey(
            path: path,
            tileIndex: tileIndex + 1,
            viewportDurationMicros: viewportDurationMicros,
            pixelsPerSecond: viewport.pixelsPerSecond,
          );
          ref.watch(zoomedWaveformPeaksProvider(nextTileKey));
        }

        final liveTile = tileAsync.maybeWhen(
          data: (t) => t,
          orElse: () => null,
        );
        final effectiveTile = liveTile ??
            _lastTile ??
            const WaveformTilePeaks(
              tileStart: Duration.zero,
              tileDuration: Duration.zero,
              peaks: [],
            );

        final fallbackOverlaps = liveTile == null &&
            _lastTile != null &&
            _tileOverlapsViewport(
              _lastTile!,
              viewport.windowStart,
              viewportDurationMicros,
            );
        final showLoading = tileAsync.isLoading && !fallbackOverlaps;

        return Stack(
          children: [
            Positioned.fill(
              child: Listener(
                // coverage:ignore-start
                onPointerSignal: (event) {
                  if (event is! PointerScrollEvent) return;
                  if (!_isZoomModifierHeld()) return;
                  final factor = -event.scrollDelta.dy * 0.005;
                  final newPxPerSec = viewport.pixelsPerSecond *
                      (factor.isFinite ? math.exp(factor) : 1.0);
                  final cursorTime = _timeAt(
                    event.localPosition.dx,
                    width,
                    viewport,
                  );
                  viewportNotifier.zoomTo(
                    newPxPerSec,
                    cursorTime,
                    book.totalDuration,
                    width,
                  );
                },
                onPointerPanZoomStart: (event) {},
                onPointerPanZoomUpdate: (event) {
                  if (!_isZoomModifierHeld()) return;
                  if (event.scale == 1.0) return;
                  final newPxPerSec =
                      viewport.pixelsPerSecond * event.scale;
                  final cursorTime = _timeAt(
                    event.localPosition.dx,
                    width,
                    viewport,
                  );
                  viewportNotifier.zoomTo(
                    newPxPerSec,
                    cursorTime,
                    book.totalDuration,
                    width,
                  );
                },
                // coverage:ignore-end
                child: GestureDetector(
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
                      tile: effectiveTile,
                      windowStart: viewport.windowStart,
                      pixelsPerSecond: viewport.pixelsPerSecond,
                      playhead: _smoothedPlayhead,
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
                ),
              ),
            ),
            if (showLoading)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Generating waveform…',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
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
    final tMicros = viewport.windowStart.inMicroseconds +
        (fraction * windowMicros).round();
    final clamped = tMicros.clamp(0, totalDuration.inMicroseconds);
    controller.seek(Duration(microseconds: clamped));
  }

  // coverage:ignore-start
  bool _isZoomModifierHeld() {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight) ||
        keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);
  }

  Duration _timeAt(double localX, double width, WaveformViewport viewport) {
    if (width <= 0 || viewport.pixelsPerSecond <= 0) {
      return viewport.windowStart;
    }
    final fraction = (localX / width).clamp(0.0, 1.0);
    final windowMicros =
        (width / viewport.pixelsPerSecond * 1e6).round();
    return viewport.windowStart +
        Duration(microseconds: (fraction * windowMicros).round());
  }
  // coverage:ignore-end
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
    required this.tile,
    required this.windowStart,
    required this.pixelsPerSecond,
    required this.playhead,
    required this.chapterStarts,
    required this.playedColor,
    required this.unplayedColor,
    required this.tickColor,
    required this.playheadColor,
  });

  final WaveformTilePeaks tile;
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

    // Zero-amplitude axis: a thin horizontal line through the middle,
    // drawn before the bars so taller peaks overlay it. Standard
    // audio-editor reference line; also visible when peaks are empty
    // (loading / no audio) so the body never looks blank.
    _paintCenterLine(canvas, size, centerY);

    if (tile.peaks.isNotEmpty && tile.tileDuration > Duration.zero) {
      _paintWaveform(canvas, size, centerY, windowMicros);
    }
    _paintTicks(canvas, size, windowMicros);
    _paintPlayhead(canvas, size, windowMicros);
  }

  void _paintCenterLine(Canvas canvas, Size size, double centerY) {
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      Paint()
        ..color = unplayedColor
        ..strokeWidth = 1,
    );
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
    final tileStartMicros = tile.tileStart.inMicroseconds;
    final tileDurationMicros = tile.tileDuration.inMicroseconds;
    final peaksLen = tile.peaks.length;
    for (var px = 0; px < pixelCount; px++) {
      final fractionInWindow = px / size.width;
      final tMicros = windowStart.inMicroseconds +
          (fractionInWindow * windowMicros).round();
      final relMicros = tMicros - tileStartMicros;
      if (relMicros < 0 || relMicros >= tileDurationMicros) continue;
      var binIndex =
          (relMicros / tileDurationMicros * peaksLen).floor();
      if (binIndex >= peaksLen) binIndex = peaksLen - 1;
      final peak = tile.peaks[binIndex];
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
      old.tile != tile ||
      old.windowStart != windowStart ||
      old.pixelsPerSecond != pixelsPerSecond ||
      old.playhead != playhead ||
      old.chapterStarts != chapterStarts ||
      old.playedColor != playedColor ||
      old.unplayedColor != unplayedColor ||
      old.tickColor != tickColor ||
      old.playheadColor != playheadColor;
}
