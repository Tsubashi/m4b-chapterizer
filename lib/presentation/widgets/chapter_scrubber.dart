import 'package:flutter/material.dart';

class ChapterScrubber extends StatefulWidget {
  const ChapterScrubber({
    super.key,
    required this.position,
    required this.totalDuration,
    required this.chapterStarts,
    required this.onSeek,
  });

  final Duration position;
  final Duration totalDuration;
  final List<Duration> chapterStarts;
  final ValueChanged<Duration> onSeek;

  @override
  State<ChapterScrubber> createState() => _ChapterScrubberState();
}

class _ChapterScrubberState extends State<ChapterScrubber> {
  static const double _hitAreaHeight = 24;
  static const double _trackHeight = 4;
  static const double _tickHeight = 12;
  static const double _playheadDiameter = 12;
  static const double _horizontalPadding = 12;
  static const double _snapPx = 6;

  Duration? _dragPosition;

  Duration _displayedPosition() {
    final p = _dragPosition ?? widget.position;
    final total = widget.totalDuration;
    if (total <= Duration.zero) return Duration.zero;
    if (p < Duration.zero) return Duration.zero;
    if (p > total) return total;
    return p;
  }

  Duration _positionForX(double x, double width) {
    final usable = width - 2 * _horizontalPadding;
    if (usable <= 0 || widget.totalDuration <= Duration.zero) {
      return Duration.zero;
    }
    final fraction = ((x - _horizontalPadding) / usable).clamp(0.0, 1.0);
    final micros = (widget.totalDuration.inMicroseconds * fraction).round();
    return Duration(microseconds: micros);
  }

  Duration _maybeSnap(double tapX, double width) {
    if (widget.chapterStarts.isEmpty) {
      return _positionForX(tapX, width);
    }
    final usable = width - 2 * _horizontalPadding;
    if (usable <= 0 || widget.totalDuration <= Duration.zero) {
      return Duration.zero;
    }
    Duration? closest;
    double closestDx = double.infinity;
    for (final start in widget.chapterStarts) {
      final fraction =
          start.inMicroseconds / widget.totalDuration.inMicroseconds;
      final tickX = _horizontalPadding + fraction * usable;
      final dx = (tickX - tapX).abs();
      if (dx < closestDx) {
        closestDx = dx;
        closest = start;
      }
    }
    if (closest != null && closestDx <= _snapPx) return closest;
    return _positionForX(tapX, width);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: _hitAreaHeight,
      child: LayoutBuilder(builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            widget.onSeek(_maybeSnap(
              details.localPosition.dx,
              constraints.maxWidth,
            ));
          },
          onHorizontalDragStart: (details) {
            setState(() {
              _dragPosition = _positionForX(
                details.localPosition.dx,
                constraints.maxWidth,
              );
            });
          },
          onHorizontalDragUpdate: (details) {
            setState(() {
              _dragPosition = _positionForX(
                details.localPosition.dx,
                constraints.maxWidth,
              );
            });
          },
          onHorizontalDragEnd: (_) {
            final settled = _dragPosition;
            setState(() => _dragPosition = null);
            if (settled != null) widget.onSeek(settled);
          },
          onHorizontalDragCancel: () {
            setState(() => _dragPosition = null);
          },
          child: CustomPaint(
            painter: _ScrubberPainter(
              position: _displayedPosition(),
              totalDuration: widget.totalDuration,
              chapterStarts: widget.chapterStarts,
              trackColor: scheme.surfaceContainerHighest,
              fillColor: scheme.primary,
              tickColor: scheme.outline,
              playheadColor: scheme.primary,
              trackHeight: _trackHeight,
              tickHeight: _tickHeight,
              playheadDiameter: _playheadDiameter,
              horizontalPadding: _horizontalPadding,
            ),
            size: Size.infinite,
          ),
        );
      }),
    );
  }
}

class _ScrubberPainter extends CustomPainter {
  _ScrubberPainter({
    required this.position,
    required this.totalDuration,
    required this.chapterStarts,
    required this.trackColor,
    required this.fillColor,
    required this.tickColor,
    required this.playheadColor,
    required this.trackHeight,
    required this.tickHeight,
    required this.playheadDiameter,
    required this.horizontalPadding,
  });

  final Duration position;
  final Duration totalDuration;
  final List<Duration> chapterStarts;
  final Color trackColor;
  final Color fillColor;
  final Color tickColor;
  final Color playheadColor;
  final double trackHeight;
  final double tickHeight;
  final double playheadDiameter;
  final double horizontalPadding;

  double _xFor(Duration d, double width) {
    final usable = width - 2 * horizontalPadding;
    if (usable <= 0 || totalDuration <= Duration.zero) {
      return horizontalPadding;
    }
    final fraction =
        d.inMicroseconds / totalDuration.inMicroseconds;
    return horizontalPadding + fraction.clamp(0.0, 1.0) * usable;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final playheadX = _xFor(position, size.width);

    final trackTop = centerY - trackHeight / 2;
    final trackRect = RRect.fromLTRBR(
      horizontalPadding,
      trackTop,
      size.width - horizontalPadding,
      trackTop + trackHeight,
      Radius.circular(trackHeight / 2),
    );
    canvas.drawRRect(trackRect, Paint()..color = trackColor);

    final fillRect = RRect.fromLTRBR(
      horizontalPadding,
      trackTop,
      playheadX,
      trackTop + trackHeight,
      Radius.circular(trackHeight / 2),
    );
    canvas.drawRRect(fillRect, Paint()..color = fillColor);

    final tickPaint = Paint()
      ..color = tickColor
      ..strokeWidth = 2;
    for (final start in chapterStarts) {
      final x = _xFor(start, size.width);
      canvas.drawLine(
        Offset(x, centerY - tickHeight / 2),
        Offset(x, centerY + tickHeight / 2),
        tickPaint,
      );
    }

    canvas.drawCircle(
      Offset(playheadX, centerY),
      playheadDiameter / 2,
      Paint()..color = playheadColor,
    );
  }

  @override
  bool shouldRepaint(covariant _ScrubberPainter old) =>
      old.position != position ||
      old.totalDuration != totalDuration ||
      old.chapterStarts != chapterStarts ||
      old.trackColor != trackColor ||
      old.fillColor != fillColor ||
      old.tickColor != tickColor ||
      old.playheadColor != playheadColor;
}
