# Playback Progress Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a horizontal playback progress bar with chapter ticks above the existing playback controls. Tapping seeks; tapping near a tick snaps to that chapter; dragging defers the seek until release.

**Architecture:** A new `ChapterScrubber` stateful widget owns no app state — it takes plain inputs (`position`, `totalDuration`, `chapterStarts`, `onSeek`) and emits a single `onSeek` callback. `PlaybackControls` wraps it in a `StreamBuilder<Duration>` over `PlaybackController.positionStream` and arranges it above today's controls row.

**Tech Stack:** Flutter `CustomPainter` for rendering, `GestureDetector` for tap/drag, no new packages.

**Reference design:** `docs/superpowers/specs/2026-05-01-playback-progress-bar-design.md`

**Conventions:**
- `--no-gpg-sign` REQUIRED on every `git commit` (signing is enabled and blocks).
- After every task, run `flutter test` and `flutter analyze` before committing.
- All Material colors come from `Theme.of(context).colorScheme` — no hard-coded hex.

---

## Task 1: `ChapterScrubber` widget skeleton with `CustomPainter`

Creates the widget and its painter. Renders track, filled portion, playhead, chapter ticks. No interaction yet.

**Files:**
- Create: `lib/presentation/widgets/chapter_scrubber.dart`
- Test: `test/presentation/chapter_scrubber_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/presentation/chapter_scrubber_test.dart`:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/presentation/chapter_scrubber_test.dart`
Expected: FAIL — "Target of URI doesn't exist".

- [ ] **Step 3: Implement `ChapterScrubber` widget and painter**

Create `lib/presentation/widgets/chapter_scrubber.dart`:

```dart
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

  Duration _displayedPosition() {
    final total = widget.totalDuration;
    if (total <= Duration.zero) return Duration.zero;
    if (widget.position < Duration.zero) return Duration.zero;
    if (widget.position > total) return total;
    return widget.position;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: _hitAreaHeight,
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
    final trackTop = centerY - trackHeight / 2;
    final trackRect = RRect.fromLTRBR(
      horizontalPadding,
      trackTop,
      size.width - horizontalPadding,
      trackTop + trackHeight,
      Radius.circular(trackHeight / 2),
    );
    canvas.drawRRect(trackRect, Paint()..color = trackColor);

    final playheadX = _xFor(position, size.width);
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
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/presentation/chapter_scrubber_test.dart`
Expected: `+4: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/widgets/chapter_scrubber.dart test/presentation/chapter_scrubber_test.dart
git commit --no-gpg-sign -m "Add ChapterScrubber widget with custom painter"
```

---

## Task 2: Tap-to-seek

Adds a `GestureDetector` that emits `onSeek(positionForX)` on tap.

**Files:**
- Modify: `lib/presentation/widgets/chapter_scrubber.dart`
- Modify: `test/presentation/chapter_scrubber_test.dart`

- [ ] **Step 1: Append failing tests**

Append to `test/presentation/chapter_scrubber_test.dart`'s `main()`:

```dart
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
```

- [ ] **Step 2: Run tests, see them fail**

Run: `flutter test test/presentation/chapter_scrubber_test.dart`
Expected: 3 new failures — `seeked` is null because there's no gesture handler.

- [ ] **Step 3: Add tap handler**

Modify `lib/presentation/widgets/chapter_scrubber.dart`. Add a helper method to the `_ChapterScrubberState` class:

```dart
  Duration _positionForX(double x, double width) {
    final usable = width - 2 * _horizontalPadding;
    if (usable <= 0 || widget.totalDuration <= Duration.zero) {
      return Duration.zero;
    }
    final fraction = ((x - _horizontalPadding) / usable).clamp(0.0, 1.0);
    final micros = (widget.totalDuration.inMicroseconds * fraction).round();
    return Duration(microseconds: micros);
  }
```

Then wrap the existing `CustomPaint` with a `GestureDetector` and a `LayoutBuilder` (so we know the actual width). Replace the entire `build` method body's return value with:

```dart
    return SizedBox(
      height: _hitAreaHeight,
      child: LayoutBuilder(builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            widget.onSeek(_positionForX(
              details.localPosition.dx,
              constraints.maxWidth,
            ));
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
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/presentation/chapter_scrubber_test.dart`
Expected: `+7: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/widgets/chapter_scrubber.dart test/presentation/chapter_scrubber_test.dart
git commit --no-gpg-sign -m "Add tap-to-seek to ChapterScrubber"
```

---

## Task 3: Tap snap-to-chapter-tick

When the tap is within 6 logical pixels of a chapter tick, snap to that chapter's exact start.

**Files:**
- Modify: `lib/presentation/widgets/chapter_scrubber.dart`
- Modify: `test/presentation/chapter_scrubber_test.dart`

- [ ] **Step 1: Append failing test**

Append to `test/presentation/chapter_scrubber_test.dart`'s `main()`:

```dart
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
```

- [ ] **Step 2: Run, see failure**

Run: `flutter test test/presentation/chapter_scrubber_test.dart`
Expected: the snap test fails (tap returns the linear position, not the chapter start).

- [ ] **Step 3: Implement snap logic**

In `_ChapterScrubberState`, add a constant and a helper:

```dart
  static const double _snapPx = 6;

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
```

Replace the `onTapUp` handler with:

```dart
          onTapUp: (details) {
            widget.onSeek(_maybeSnap(
              details.localPosition.dx,
              constraints.maxWidth,
            ));
          },
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/presentation/chapter_scrubber_test.dart`
Expected: `+9: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/widgets/chapter_scrubber.dart test/presentation/chapter_scrubber_test.dart
git commit --no-gpg-sign -m "Add snap-to-tick on tap in ChapterScrubber"
```

---

## Task 4: Drag-to-seek with deferred onSeek

While dragging, the playhead follows the finger (visual update only). On release, fire a single `onSeek` with the final position.

**Files:**
- Modify: `lib/presentation/widgets/chapter_scrubber.dart`
- Modify: `test/presentation/chapter_scrubber_test.dart`

- [ ] **Step 1: Append failing test**

Append to `test/presentation/chapter_scrubber_test.dart`'s `main()`:

```dart
  group('ChapterScrubber drag-to-seek', () {
    testWidgets('drag fires onSeek exactly once at drag end',
        (tester) async {
      var seekCount = 0;
      Duration? lastSeek;
      const total = Duration(seconds: 100);
      await tester.pumpWidget(_harness(
        totalDuration: total,
        onSeek: (d) {
          seekCount++;
          lastSeek = d;
        },
        width: 400,
      ));

      final scrubber = find.byType(ChapterScrubber);
      final topLeft = tester.getTopLeft(scrubber);
      final size = tester.getSize(scrubber);
      final start = topLeft + Offset(size.width * 0.10, size.height / 2);
      final gesture = await tester.startGesture(start);
      // Move to ~60% in three steps, pump between each.
      await gesture.moveBy(const Offset(80, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(80, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      // No seeks yet.
      expect(seekCount, 0);
      await gesture.up();
      await tester.pump();

      expect(seekCount, 1);
      // 10% start + 200px move at 400 width: x ≈ 240. Fraction ≈ (240-12)/(400-24) ≈ 0.606.
      // ~60.6 seconds. Allow ±3 seconds tolerance.
      final expected = total * 0.606;
      expect(
        (lastSeek! - expected).abs() <= const Duration(seconds: 3),
        isTrue,
        reason: 'expected ~$expected, got $lastSeek',
      );
    });
  });
```

- [ ] **Step 2: Run, see failure**

Run: `flutter test test/presentation/chapter_scrubber_test.dart`
Expected: drag test fails — likely because the existing `onTapUp` doesn't trigger after a drag, so seekCount is 0 but `lastSeek` stays null and the assertions trip.

- [ ] **Step 3: Implement drag handling**

Add a state field to `_ChapterScrubberState`:

```dart
  Duration? _dragPosition;
```

Modify `_displayedPosition()` to prefer the drag value when present:

```dart
  Duration _displayedPosition() {
    final p = _dragPosition ?? widget.position;
    final total = widget.totalDuration;
    if (total <= Duration.zero) return Duration.zero;
    if (p < Duration.zero) return Duration.zero;
    if (p > total) return total;
    return p;
  }
```

Replace the `GestureDetector` with one that handles both tap and pan:

```dart
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
            // ... same as before
          ),
        );
```

(Leave the `CustomPaint` block unchanged from Task 3.)

- [ ] **Step 4: Run tests**

Run: `flutter test test/presentation/chapter_scrubber_test.dart`
Expected: `+10: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/widgets/chapter_scrubber.dart test/presentation/chapter_scrubber_test.dart
git commit --no-gpg-sign -m "Add drag-to-seek with deferred onSeek to ChapterScrubber"
```

---

## Task 5: Wire `ChapterScrubber` into `PlaybackControls`

`PlaybackControls` becomes a `Column` of two rows. The new top row is a `StreamBuilder<Duration>` over `controller.positionStream`. The bottom row is unchanged.

**Files:**
- Modify: `lib/presentation/widgets/playback_controls.dart`
- Modify: `test/presentation/playback_controls_test.dart`

- [ ] **Step 1: Extend `_FakePlayback` and add failing tests**

Open `test/presentation/playback_controls_test.dart`. Find `class _FakePlayback implements PlaybackController`. Replace its body with one that uses controllable stream controllers:

```dart
class _FakePlayback implements PlaybackController {
  _FakePlayback() {
    _positionController = StreamController<Duration>.broadcast();
    _playingController = StreamController<bool>.broadcast();
  }

  late final StreamController<Duration> _positionController;
  late final StreamController<bool> _playingController;
  final List<Duration> seeks = [];
  Duration _pos = const Duration(seconds: 7);
  bool _playing = false;

  void emitPosition(Duration p) {
    _pos = p;
    _positionController.add(p);
  }

  @override
  Future<void> setSource(String path) async {}
  @override
  Future<void> play() async => _playing = true;
  @override
  Future<void> pause() async => _playing = false;
  @override
  Future<void> seek(Duration position) async {
    _pos = position;
    seeks.add(position);
  }

  @override
  Duration get position => _pos;
  @override
  bool get playing => _playing;
  @override
  Stream<Duration> get positionStream => _positionController.stream;
  @override
  Stream<bool> get playingStream => _playingController.stream;
  @override
  Future<void> dispose() async {
    await _positionController.close();
    await _playingController.close();
  }
}
```

Add the import at the top of the file (if not already there):

```dart
import 'dart:async';
```

Now append a new test group at the end of `main()`:

```dart
  group('PlaybackControls scrubber integration', () {
    testWidgets('renders a ChapterScrubber when an audiobook is loaded',
        (tester) async {
      final fake = _StubBookbinder();
      final fakePlayback = _FakePlayback();
      final container = ProviderContainer(
        overrides: [
          bookbinderProvider.overrideWithValue(fake),
          playbackControllerProvider.overrideWithValue(fakePlayback),
        ],
      );
      await container.read(editorProvider.notifier).open('/tmp/x.m4b');
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: PlaybackControls())),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(ChapterScrubber), findsOneWidget);
    });

    testWidgets('tapping the scrubber calls controller.seek',
        (tester) async {
      final fake = _StubBookbinder();
      final fakePlayback = _FakePlayback();
      final container = ProviderContainer(
        overrides: [
          bookbinderProvider.overrideWithValue(fake),
          playbackControllerProvider.overrideWithValue(fakePlayback),
        ],
      );
      await container.read(editorProvider.notifier).open('/tmp/x.m4b');
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: PlaybackControls())),
      ));
      await tester.pumpAndSettle();

      final scrubberFinder = find.byType(ChapterScrubber);
      final topLeft = tester.getTopLeft(scrubberFinder);
      final size = tester.getSize(scrubberFinder);
      await tester.tapAt(
        topLeft + Offset(size.width * 0.5, size.height / 2),
      );
      await tester.pump();

      expect(fakePlayback.seeks.length, 1);
    });
  });
```

Also add the import for `ChapterScrubber`:

```dart
import 'package:m4b_chapterizer/presentation/widgets/chapter_scrubber.dart';
```

- [ ] **Step 2: Run, see failures**

Run: `flutter test test/presentation/playback_controls_test.dart`
Expected: 2 new failures — no `ChapterScrubber` is rendered yet.

- [ ] **Step 3: Modify `PlaybackControls`**

Replace the entire body of `lib/presentation/widgets/playback_controls.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/editor_state.dart';
import '../providers/playback.dart';
import '../util/duration_format.dart';
import 'chapter_list.dart';
import 'chapter_scrubber.dart';

class PlaybackControls extends ConsumerWidget {
  const PlaybackControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(playbackControllerProvider);
    final state = ref.watch(editorProvider);
    final notifier = ref.read(editorProvider.notifier);
    final selectedIndex = ref.watch(selectedChapterProvider);
    final book = state.audiobook;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (book != null)
            StreamBuilder<Duration>(
              stream: controller.positionStream,
              initialData: controller.position,
              builder: (context, snapshot) {
                return ChapterScrubber(
                  position: snapshot.data ?? controller.position,
                  totalDuration: book.totalDuration,
                  chapterStarts: [for (final c in book.chapters) c.start],
                  onSeek: controller.seek,
                );
              },
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              StreamBuilder<bool>(
                stream: controller.playingStream,
                initialData: controller.playing,
                builder: (context, snapshot) {
                  final playing = snapshot.data ?? controller.playing;
                  return IconButton(
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                    onPressed: () =>
                        playing ? controller.pause() : controller.play(),
                  );
                },
              ),
              const SizedBox(width: 12),
              StreamBuilder<Duration>(
                stream: controller.positionStream,
                builder: (context, snapshot) => Text(
                  formatDuration(snapshot.data ?? controller.position),
                ),
              ),
              const Spacer(),
              ElevatedButton(
                key: const ValueKey('playback.snap'),
                onPressed: () => notifier.setChapterStart(
                    selectedIndex, controller.position),
                child: const Text('Set start to playhead'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run all tests**

Run: `flutter test`
Expected: full suite passes (existing 67 tests + new tests from Tasks 1–4 + 2 new integration tests).

- [ ] **Step 5: Run analyzer**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Smoke-test on macOS**

```bash
flutter run -d macos
```

Open `test/fixtures/sample.m4b` and verify:
- Scrubber appears above the play button
- Playhead is at 0:00 initially
- Three chapter ticks are visible
- Tapping the scrubber jumps the playback position
- Tapping near a tick snaps to that chapter
- Dragging shows the playhead moving with the finger but only seeks once on release

- [ ] **Step 7: Commit**

```bash
git add lib/presentation/widgets/playback_controls.dart test/presentation/playback_controls_test.dart
git commit --no-gpg-sign -m "Wire ChapterScrubber into PlaybackControls"
```

---

## Final verification

- [ ] Full test suite green: `flutter test` → all passing.
- [ ] Analyzer clean: `flutter analyze` → no issues.
- [ ] macOS smoke test (above) confirms the visible behaviors.
