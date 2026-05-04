# Zoomable Waveform View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 120-px-tall zoomable waveform widget above the existing `ChapterScrubber` inside `PlaybackControls`. Zoom with Cmd+scroll/pinch (cursor-centered) or `−`/`+` buttons (playhead-centered); pan by drag/scroll while paused; continuous follow during playback at 25 % from the left edge.

**Architecture:** New `WaveformViewportNotifier` holds `(pixelsPerSecond, windowStart)` and exposes `zoomTo`/`zoomIn`/`zoomOut`/`panBy`/`followPlayhead`/`reset` methods that take `totalDuration` and `viewportWidth` as arguments (so the notifier is pure logic, easy to unit-test). New `WaveformView` widget reads the viewport, paints peaks + ticks + playhead, and translates gestures into notifier method calls. `WaveformView` mounts above the existing `ChapterScrubber` in `PlaybackControls`. Reuses the existing `waveformPeaksProvider`; no re-extraction on zoom.

**Tech Stack:** Flutter 3.41.9, Dart 3.11, flutter_riverpod 3.x, `CustomPainter`, `Listener` for pointer events, `GestureDetector` for tap/drag, `HardwareKeyboard.instance` for Cmd detection.

**Spec:** `docs/superpowers/specs/2026-05-03-zoomable-waveform-design.md`

---

## File Map

**New:**
- `lib/presentation/providers/waveform_viewport.dart` — `WaveformViewport`, `WaveformViewportNotifier`, `waveformViewportProvider`
- `lib/presentation/widgets/waveform_view.dart` — `WaveformView`, `_WaveformPainter`, `_ZoomButtons`
- `test/presentation/providers/waveform_viewport_test.dart`
- `test/presentation/waveform_view_test.dart`

**Modified:**
- `lib/presentation/widgets/playback_controls.dart` — insert `WaveformView` above `ChapterScrubber`
- `test/presentation/playback_controls_test.dart` — assert `WaveformView` is above `ChapterScrubber`

---

## Task 1: WaveformViewport state and notifier

Pure logic. No UI dependencies. All nine viewport behaviors covered by tests before implementation.

**Files:**
- Create: `lib/presentation/providers/waveform_viewport.dart`
- Create: `test/presentation/providers/waveform_viewport_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/presentation/providers/waveform_viewport_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/presentation/providers/waveform_viewport.dart';

const _total60s = Duration(seconds: 60);
const _viewportWidth = 800.0;

WaveformViewportNotifier _makeNotifier() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  // Read once to instantiate the notifier; we drive it directly from
  // here for the rest of each test.
  container.read(waveformViewportProvider);
  return container.read(waveformViewportProvider.notifier);
}

void main() {
  test('reset returns to default state', () {
    final n = _makeNotifier();
    n.zoomTo(400, const Duration(seconds: 5), _total60s, _viewportWidth);
    n.reset(_total60s, _viewportWidth);
    expect(n.state.pixelsPerSecond, 100);
    expect(n.state.windowStart, Duration.zero);
  });

  test('reset clamps to whole-file fit for short files', () {
    final n = _makeNotifier();
    // totalDuration=4s, viewport=800 → minPxPerSec = 200. Default 100 is
    // below the min, so reset picks the min.
    n.reset(const Duration(seconds: 4), _viewportWidth);
    expect(n.state.pixelsPerSecond, 200);
    expect(n.state.windowStart, Duration.zero);
  });

  test('zoomIn doubles pxPerSec and re-centers on centerTime', () {
    final n = _makeNotifier();
    // Default state: 100 px/s, windowStart 0 ⇒ windowDuration = 8s.
    // Center on time 12s. Old fraction of 12s in window is (12-0)/8 = 1.5
    // — but center time only matters when it's actually inside the
    // window, otherwise it's clamped after. Pick a center inside.
    n.zoomTo(100, Duration.zero, _total60s, _viewportWidth);
    // Now zoomIn centered on 4s (which IS in the [0, 8] window).
    n.zoomIn(const Duration(seconds: 4), _total60s, _viewportWidth);
    expect(n.state.pixelsPerSecond, 200);
    // Window is now 800/200 = 4s wide. 4s should be at the same fraction
    // (0.5) it was before, so windowStart = 4 - 0.5*4 = 2s.
    expect(n.state.windowStart, const Duration(seconds: 2));
  });

  test('zoomOut halves and clamps at min', () {
    final n = _makeNotifier();
    n.reset(_total60s, _viewportWidth); // 100 px/s
    n.zoomOut(const Duration(seconds: 4), _total60s, _viewportWidth);
    expect(n.state.pixelsPerSecond, 50);
    n.zoomOut(const Duration(seconds: 4), _total60s, _viewportWidth);
    expect(n.state.pixelsPerSecond, 25);
    n.zoomOut(const Duration(seconds: 4), _total60s, _viewportWidth);
    // minPxPerSec = 800/60 ≈ 13.333. Halving 25 → 12.5, but clamped to
    // 13.333… (we accept ±0.01 tolerance for float math).
    expect(n.state.pixelsPerSecond, closeTo(800 / 60, 0.01));
  });

  test('zoomIn clamps at max (2000)', () {
    final n = _makeNotifier();
    n.zoomTo(1500, Duration.zero, _total60s, _viewportWidth);
    n.zoomIn(Duration.zero, _total60s, _viewportWidth);
    expect(n.state.pixelsPerSecond, 2000); // 3000 clamped to 2000
  });

  test('panBy shifts windowStart and clamps left', () {
    final n = _makeNotifier();
    n.reset(_total60s, _viewportWidth);
    n.zoomTo(100, const Duration(seconds: 10), _total60s, _viewportWidth);
    expect(n.state.windowStart, const Duration(seconds: 10));
    n.panBy(-2000, _total60s, _viewportWidth); // -20s in time
    expect(n.state.windowStart, Duration.zero);
  });

  test('panBy shifts windowStart and clamps right', () {
    final n = _makeNotifier();
    n.reset(_total60s, _viewportWidth);
    n.panBy(10000, _total60s, _viewportWidth); // +100s in time
    // windowDuration = 8s, so max windowStart = 60 - 8 = 52s.
    expect(n.state.windowStart, const Duration(seconds: 52));
  });

  test('followPlayhead places playhead at 25% from left', () {
    final n = _makeNotifier();
    n.reset(_total60s, _viewportWidth);
    // windowDuration = 8s; 25% of 8 = 2s. So windowStart = 30 - 2 = 28s.
    n.followPlayhead(const Duration(seconds: 30), _total60s, _viewportWidth);
    expect(n.state.windowStart, const Duration(seconds: 28));
  });

  test('followPlayhead clamps near file start', () {
    final n = _makeNotifier();
    n.reset(_total60s, _viewportWidth);
    n.followPlayhead(const Duration(seconds: 1), _total60s, _viewportWidth);
    expect(n.state.windowStart, Duration.zero);
  });

  test('followPlayhead clamps near file end', () {
    final n = _makeNotifier();
    n.reset(_total60s, _viewportWidth);
    n.followPlayhead(const Duration(seconds: 59), _total60s, _viewportWidth);
    // windowDuration = 8s, max start = 52s.
    expect(n.state.windowStart, const Duration(seconds: 52));
  });

  test('zoomTo direct call clamps and re-centers', () {
    final n = _makeNotifier();
    n.reset(_total60s, _viewportWidth);
    n.zoomTo(400, const Duration(seconds: 5), _total60s, _viewportWidth);
    expect(n.state.pixelsPerSecond, 400);
    // windowDuration = 800/400 = 2s. 5s was at fraction 5/8 = 0.625 in
    // the old window. New windowStart = 5 - 0.625*2 = 3.75s.
    expect(
      n.state.windowStart.inMilliseconds,
      closeTo(3750, 1),
    );
  });
}
```

- [ ] **Step 2: Run tests; verify failure**

Run: `flutter test test/presentation/providers/waveform_viewport_test.dart`
Expected: compile error — `waveform_viewport.dart` doesn't exist.

- [ ] **Step 3: Implement the notifier**

Create `lib/presentation/providers/waveform_viewport.dart`:

```dart
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

    final fraction = oldWindowDuration.inMicroseconds == 0
        ? 0.0
        : (centerTime.inMicroseconds - state.windowStart.inMicroseconds) /
            oldWindowDuration.inMicroseconds;
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
```

- [ ] **Step 4: Run tests; verify pass**

Run: `flutter test test/presentation/providers/waveform_viewport_test.dart`
Expected: 11 passing tests.

- [ ] **Step 5: Run full suite + analyzer**

Run: `flutter test`
Run: `flutter analyze`
Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/providers/waveform_viewport.dart test/presentation/providers/waveform_viewport_test.dart
git commit --no-gpg-sign -m "$(cat <<'EOF'
Add WaveformViewport state and notifier

Pure-logic notifier for the upcoming zoomable waveform view. Holds
(pixelsPerSecond, windowStart) and exposes zoomTo / zoomIn / zoomOut /
panBy / followPlayhead / reset. Methods take totalDuration and
viewportWidth as arguments so the notifier never reads other providers
and is trivial to unit-test.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: WaveformView widget — basic rendering

The widget that paints the waveform, ticks, and playhead, driven by the viewport. No gestures yet; no follow yet. The widget owns a `LayoutBuilder` to know its viewport width.

**Files:**
- Create: `lib/presentation/widgets/waveform_view.dart`
- Create: `test/presentation/waveform_view_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/presentation/waveform_view_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/bookbinder.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
import 'package:m4b_chapterizer/presentation/providers/editor_state.dart';
import 'package:m4b_chapterizer/presentation/providers/playback.dart';
import 'package:m4b_chapterizer/presentation/providers/waveform.dart';
import 'package:m4b_chapterizer/presentation/providers/waveform_viewport.dart';
import 'package:m4b_chapterizer/presentation/widgets/waveform_view.dart';

class _StubBookbinder implements Bookbinder {
  @override
  Future<Audiobook> read(String sourcePath) async => Audiobook.validated(
        chapters: const [
          Chapter(title: 'A', start: Duration.zero),
          Chapter(title: 'B', start: Duration(seconds: 10)),
        ],
        totalDuration: const Duration(seconds: 60),
      );
  @override
  Future<void> write({
    required String sourcePath,
    required String destinationPath,
    required Audiobook audiobook,
  }) async {}
}

class _FakePlayback implements PlaybackController {
  _FakePlayback() {
    _positionController = StreamController<Duration>.broadcast();
    _playingController = StreamController<bool>.broadcast();
  }
  late final StreamController<Duration> _positionController;
  late final StreamController<bool> _playingController;
  final List<Duration> seeks = [];
  Duration _pos = Duration.zero;
  bool _playing = false;

  void emitPosition(Duration p) {
    _pos = p;
    _positionController.add(p);
  }

  void emitPlaying(bool playing) {
    _playing = playing;
    _playingController.add(playing);
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

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required _FakePlayback playback,
  List<double> peaks = const [],
}) async {
  final container = ProviderContainer(
    overrides: [
      bookbinderProvider.overrideWithValue(_StubBookbinder()),
      playbackControllerProvider.overrideWithValue(playback),
      waveformPeaksProvider('/tmp/x.m4b').overrideWith((ref) async => peaks),
    ],
  );
  addTearDown(container.dispose);
  await container.read(editorProvider.notifier).open('/tmp/x.m4b');

  // Force the viewport's tester-side width to a known value (800).
  await tester.binding.setSurfaceSize(const Size(800, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: Scaffold(body: SizedBox(width: 800, child: WaveformView())),
    ),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('renders without exception when peaks are empty',
      (tester) async {
    final playback = _FakePlayback();
    addTearDown(playback.dispose);
    await _pump(tester, playback: playback);
    expect(tester.takeException(), isNull);
    expect(find.byType(WaveformView), findsOneWidget);
  });

  testWidgets('renders without exception when peaks are non-empty',
      (tester) async {
    final playback = _FakePlayback();
    addTearDown(playback.dispose);
    await _pump(
      tester,
      playback: playback,
      peaks: const [0.0, 0.5, 1.0, 0.5, 0.0],
    );
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run tests; verify failure**

Run: `flutter test test/presentation/waveform_view_test.dart`
Expected: compile error — `WaveformView` doesn't exist.

- [ ] **Step 3: Implement basic `WaveformView`**

Create `lib/presentation/widgets/waveform_view.dart`:

```dart
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
```

- [ ] **Step 4: Run tests; verify pass**

Run: `flutter test test/presentation/waveform_view_test.dart`
Expected: 2 passing tests.

- [ ] **Step 5: Run full suite + analyzer**

Run: `flutter test`
Run: `flutter analyze`
Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/widgets/waveform_view.dart test/presentation/waveform_view_test.dart
git commit --no-gpg-sign -m "$(cat <<'EOF'
Add WaveformView widget with basic rendering

Paints peaks, chapter ticks, and the playhead from the viewport state.
No gestures, no playhead-follow yet — those come in subsequent tasks.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Tap-to-seek, drag-to-pan, and zoom buttons

Add interactive gestures: click seeks, drag pans (paused only), `−` / `+` buttons zoom centered on the playhead.

**Files:**
- Modify: `lib/presentation/widgets/waveform_view.dart`
- Modify: `test/presentation/waveform_view_test.dart`

- [ ] **Step 1: Append failing tests to `waveform_view_test.dart`**

Append the following tests inside `void main() { ... }` (alongside the two existing tests):

```dart
  testWidgets('tap seeks the playhead to that time', (tester) async {
    final playback = _FakePlayback();
    addTearDown(playback.dispose);
    await _pump(tester, playback: playback);

    // Default zoom: 100 px/s, windowStart 0, viewport 800 →
    // windowDuration = 8 s. Tap at x = 200 → 2 s.
    final box = find.byType(WaveformView);
    final topLeft = tester.getTopLeft(box);
    await tester.tapAt(topLeft + const Offset(200, 60));
    await tester.pump();

    expect(playback.seeks, hasLength(1));
    expect(
      playback.seeks.single.inMilliseconds,
      closeTo(2000, 50),
    );
  });

  testWidgets('+ button doubles the zoom', (tester) async {
    final playback = _FakePlayback();
    addTearDown(playback.dispose);
    final container = await _pump(tester, playback: playback);

    expect(
      container.read(waveformViewportProvider).pixelsPerSecond,
      100,
    );
    await tester.tap(find.byKey(const ValueKey('waveform.zoomIn')));
    await tester.pump();
    expect(
      container.read(waveformViewportProvider).pixelsPerSecond,
      200,
    );
  });

  testWidgets('- button halves the zoom and clamps at min', (tester) async {
    final playback = _FakePlayback();
    addTearDown(playback.dispose);
    final container = await _pump(tester, playback: playback);

    // Zoom out repeatedly. Min for totalDuration=60s, viewport=800 is
    // 800/60 ≈ 13.333. Default 100 → 50 → 25 → ~13.33.
    final zoomOut = find.byKey(const ValueKey('waveform.zoomOut'));
    await tester.tap(zoomOut);
    await tester.pump();
    expect(
      container.read(waveformViewportProvider).pixelsPerSecond,
      50,
    );
    await tester.tap(zoomOut);
    await tester.pump();
    expect(
      container.read(waveformViewportProvider).pixelsPerSecond,
      25,
    );
    await tester.tap(zoomOut);
    await tester.pump();
    expect(
      container.read(waveformViewportProvider).pixelsPerSecond,
      closeTo(800 / 60, 0.01),
    );
  });

  testWidgets('drag pans the viewport while paused', (tester) async {
    final playback = _FakePlayback();
    addTearDown(playback.dispose);
    final container = await _pump(tester, playback: playback);

    // Default state: 100 px/s, windowStart 0. Drag the body to the
    // LEFT by 200 px → viewport advances by 2 s.
    final box = find.byType(WaveformView);
    final topLeft = tester.getTopLeft(box);
    await tester.timedDragFrom(
      topLeft + const Offset(400, 60),
      const Offset(-200, 0),
      const Duration(milliseconds: 100),
    );
    await tester.pumpAndSettle();

    expect(
      container.read(waveformViewportProvider).windowStart.inMilliseconds,
      closeTo(2000, 50),
    );
  });

  testWidgets('drag is a no-op while playing', (tester) async {
    final playback = _FakePlayback();
    addTearDown(playback.dispose);
    final container = await _pump(tester, playback: playback);

    // Start playback. Note the viewport BEFORE we drag.
    playback.emitPlaying(true);
    await tester.pump();
    final beforeStart =
        container.read(waveformViewportProvider).windowStart;

    // Attempt to drag.
    final box = find.byType(WaveformView);
    final topLeft = tester.getTopLeft(box);
    await tester.timedDragFrom(
      topLeft + const Offset(400, 60),
      const Offset(-200, 0),
      const Duration(milliseconds: 100),
    );
    await tester.pumpAndSettle();

    // Drag had no effect because playback is active.
    expect(
      container.read(waveformViewportProvider).windowStart,
      beforeStart,
    );
  });
```

- [ ] **Step 2: Run tests; verify failure**

Run: `flutter test test/presentation/waveform_view_test.dart`
Expected: tap test fails (no gesture handler yet); zoom-button tests fail (no buttons); drag tests fail (no drag handler).

- [ ] **Step 3: Replace `WaveformView` with the gesture-aware version**

Replace `lib/presentation/widgets/waveform_view.dart` build method and add `_ZoomButtons`. The full new file:

```dart
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
    final viewportNotifier = ref.read(waveformViewportProvider.notifier);

    return SizedBox(
      height: WaveformView.height,
      child: LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Stack(
          children: [
            Positioned.fill(
              child: StreamBuilder<Duration>(
                stream: controller.positionStream,
                initialData: controller.position,
                builder: (context, snapshot) {
                  final playhead =
                      snapshot.data ?? controller.position;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
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
```

- [ ] **Step 4: Run tests; verify pass**

Run: `flutter test test/presentation/waveform_view_test.dart`
Expected: 7 passing tests.

- [ ] **Step 5: Run full suite + analyzer**

Run: `flutter test`
Run: `flutter analyze`
Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/widgets/waveform_view.dart test/presentation/waveform_view_test.dart
git commit --no-gpg-sign -m "$(cat <<'EOF'
Wire tap, drag, and zoom buttons into WaveformView

Tap on the body seeks via playbackControllerProvider. Drag pans the
viewport while paused; drag is a no-op while playing (the upcoming
auto-follow would overwrite it anyway). The zoomed-in/zoomed-out
corner buttons call zoomIn/zoomOut centered on the current playhead
position.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Auto-follow during playback

Subscribe to the position stream; while playing, call `followPlayhead` on every tick. While paused, do nothing. Reset on file open.

**Files:**
- Modify: `lib/presentation/widgets/waveform_view.dart`
- Modify: `test/presentation/waveform_view_test.dart`

- [ ] **Step 1: Append failing tests**

Append the following tests inside `void main() { ... }`:

```dart
  testWidgets('viewport follows playhead while playing', (tester) async {
    final playback = _FakePlayback();
    addTearDown(playback.dispose);
    final container = await _pump(tester, playback: playback);

    playback.emitPlaying(true);
    await tester.pump();
    playback.emitPosition(const Duration(seconds: 30));
    await tester.pump();

    // windowDuration = 800/100 = 8s. Anchor at 25% → start = 30 - 2 = 28s.
    expect(
      container
          .read(waveformViewportProvider)
          .windowStart
          .inMilliseconds,
      closeTo(28000, 50),
    );
  });

  testWidgets('viewport does NOT follow while paused', (tester) async {
    final playback = _FakePlayback();
    addTearDown(playback.dispose);
    final container = await _pump(tester, playback: playback);

    // Pan to a known place first.
    container
        .read(waveformViewportProvider.notifier)
        .panBy(500, const Duration(seconds: 60), 800);
    final beforeStart =
        container.read(waveformViewportProvider).windowStart;

    // playing == false (the default). Emit a position update.
    playback.emitPosition(const Duration(seconds: 30));
    await tester.pump();

    expect(
      container.read(waveformViewportProvider).windowStart,
      beforeStart,
    );
  });

  testWidgets('viewport resets when file path changes', (tester) async {
    final playback = _FakePlayback();
    addTearDown(playback.dispose);
    final container = await _pump(tester, playback: playback);

    // Zoom and pan.
    container
        .read(waveformViewportProvider.notifier)
        .zoomTo(400, Duration.zero, const Duration(seconds: 60), 800);
    expect(
      container.read(waveformViewportProvider).pixelsPerSecond,
      400,
    );

    // Override read for the new path BEFORE opening it. The fake bookbinder
    // returns the same audiobook; the path itself is what triggers reset.
    await container.read(editorProvider.notifier).open('/tmp/y.m4b');
    await tester.pumpAndSettle();

    expect(
      container.read(waveformViewportProvider).pixelsPerSecond,
      100,
    );
    expect(
      container.read(waveformViewportProvider).windowStart,
      Duration.zero,
    );
  });
```

Also update `_pump` to install an override for `'/tmp/y.m4b'` so the second test doesn't fail loading peaks. Replace the override list inside `_pump`:

```dart
  final container = ProviderContainer(
    overrides: [
      bookbinderProvider.overrideWithValue(_StubBookbinder()),
      playbackControllerProvider.overrideWithValue(playback),
      waveformPeaksProvider('/tmp/x.m4b').overrideWith((ref) async => peaks),
      waveformPeaksProvider('/tmp/y.m4b').overrideWith((ref) async => peaks),
    ],
  );
```

- [ ] **Step 2: Run tests; verify failure**

Run: `flutter test test/presentation/waveform_view_test.dart`
Expected: follow test fails (no follow yet); paused test passes accidentally; reset test fails (no reset wiring yet).

- [ ] **Step 3: Add follow + reset wiring**

Modify `_WaveformViewState` to add `initState`/`dispose` subscriptions. Update the `build` method's `body` is unchanged from Task 3, but the state class adds:

```dart
import 'dart:async';

// ... existing imports ...

class _WaveformViewState extends ConsumerState<WaveformView> {
  StreamSubscription<Duration>? _positionSub;

  // We capture totalDuration and viewportWidth at the latest build so the
  // stream listener has them available without re-reading providers from
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
    final book = ref.watch(editorProvider).audiobook;
    final path = ref.watch(editorProvider.select((s) => s.path));

    // Reset the viewport whenever the file path changes.
    ref.listen<String?>(
      editorProvider.select((s) => s.path),
      (previous, next) {
        if (next != null && next != previous) {
          // Defer until after this frame so we have a viewport width
          // captured from the LayoutBuilder below.
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
    final tMicros = viewport.windowStart.inMicroseconds +
        (fraction * windowMicros).round();
    final clamped = tMicros.clamp(0, totalDuration.inMicroseconds);
    controller.seek(Duration(microseconds: clamped));
  }
}
```

(Add `import 'dart:async';` at the top of the file if not present.)

- [ ] **Step 4: Run tests; verify pass**

Run: `flutter test test/presentation/waveform_view_test.dart`
Expected: 10 passing tests.

- [ ] **Step 5: Run full suite + analyzer**

Run: `flutter test`
Run: `flutter analyze`
Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/widgets/waveform_view.dart test/presentation/waveform_view_test.dart
git commit --no-gpg-sign -m "$(cat <<'EOF'
Add playhead-follow during playback and reset-on-open

Subscribes to playbackControllerProvider.positionStream; when playing,
each position tick re-anchors the viewport so the playhead lands at
25% from the left edge. While paused, the listener is a no-op. A
ref.listen on editorProvider.path resets the viewport whenever a new
file is opened.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Wire `WaveformView` into `PlaybackControls`

Insert above the existing `ChapterScrubber`. Add a positional test that asserts the layout order.

**Files:**
- Modify: `lib/presentation/widgets/playback_controls.dart`
- Modify: `test/presentation/playback_controls_test.dart`

- [ ] **Step 1: Insert `WaveformView` above `ChapterScrubber`**

Replace `lib/presentation/widgets/playback_controls.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../keyboard/editor_actions.dart';
import '../providers/editor_state.dart';
import '../providers/playback.dart';
import '../providers/waveform.dart';
import '../util/duration_format.dart';
import 'chapter_scrubber.dart';
import 'waveform_view.dart';

class PlaybackControls extends ConsumerWidget {
  const PlaybackControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(playbackControllerProvider);
    final state = ref.watch(editorProvider);
    final book = state.audiobook;

    final peaksAsync = state.path == null
        ? const AsyncValue<List<double>>.data(<double>[])
        : ref.watch(waveformPeaksProvider(state.path!));
    final peaks = peaksAsync.maybeWhen(
      data: (p) => p,
      orElse: () => const <double>[],
    );

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (book != null) const WaveformView(),
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
                  peaks: peaks,
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
                builder: (context, snapshot) {
                  final current = snapshot.data ?? controller.position;
                  final total = book?.totalDuration ?? Duration.zero;
                  return Text(
                    '${formatDuration(current)} / ${formatDuration(total)}',
                  );
                },
              ),
              const Spacer(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(
                    key: const ValueKey('playback.save'),
                    onPressed: book == null
                        ? null
                        : () => EditorActions(context, ref).save(),
                    child: const Text('Save'),
                  ),
                  MenuAnchor(
                    builder: (context, menuController, _) => IconButton(
                      key: const ValueKey('playback.save.menu'),
                      icon: const Icon(Icons.arrow_drop_down),
                      onPressed: book == null
                          ? null
                          : () => menuController.isOpen
                              ? menuController.close()
                              : menuController.open(),
                    ),
                    menuChildren: [
                      MenuItemButton(
                        key: const ValueKey('playback.saveAs'),
                        onPressed: () =>
                            EditorActions(context, ref).saveAs(),
                        child: const Text('Save As…'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Append test to `playback_controls_test.dart`**

Add the import at the top:

```dart
import 'package:m4b_chapterizer/presentation/widgets/waveform_view.dart';
```

Append inside the existing `void main() { ... }`:

```dart
  testWidgets('renders WaveformView above the ChapterScrubber',
      (tester) async {
    final fake = _StubBookbinder();
    final fakePlayback = _FakePlayback();
    addTearDown(fakePlayback.dispose);
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

    final waveformTop = tester.getTopLeft(find.byType(WaveformView)).dy;
    final scrubberTop = tester.getTopLeft(find.byType(ChapterScrubber)).dy;
    expect(waveformTop, lessThan(scrubberTop));
  });
```

- [ ] **Step 3: Run tests; verify pass**

Run: `flutter test`
Expected: all tests pass (existing 207 + new viewport tests + new waveform_view tests + 1 new playback_controls test).

- [ ] **Step 4: Run analyzer**

Run: `flutter analyze`
Expected: no issues.

- [ ] **Step 5: Build macOS to confirm runtime is happy**

Run: `flutter build macos --debug`
Expected: clean build.

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/widgets/playback_controls.dart test/presentation/playback_controls_test.dart
git commit --no-gpg-sign -m "$(cat <<'EOF'
Mount WaveformView above the chapter scrubber

PlaybackControls now shows the tall zoomable waveform directly above
the existing thin overview track. The two visualizations share the
same peak data; the new view adds zoom and follow.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Cmd+scroll and Cmd+pinch zoom (smoke-tested)

Add raw pointer handling to support Cmd+scroll-wheel zoom and trackpad Cmd+pinch zoom centered on the cursor. These gestures aren't reliably driveable in `flutter test` (they require simulated raw pointer streams with synthesized modifier state), so the wiring is verified at the smoke-test level. The handler is small and `coverage:ignore`-marked.

**Files:**
- Modify: `lib/presentation/widgets/waveform_view.dart`

- [ ] **Step 1: Wrap the gesture body in a `Listener`**

In `_WaveformViewState.build`, replace the `GestureDetector(...)` block inside `Positioned.fill(child: StreamBuilder(...))` with a `Listener` that wraps a `GestureDetector`. The full updated `Positioned.fill` becomes:

```dart
Positioned.fill(
  child: StreamBuilder<Duration>(
    stream: controller.positionStream,
    initialData: controller.position,
    builder: (context, snapshot) {
      final playhead = snapshot.data ?? controller.position;
      return Listener(
        // coverage:ignore-start
        // Cmd+scroll and Cmd+pinch zoom are exercised via smoke tests
        // on a real desktop build. flutter test cannot synthesize raw
        // pointer-scroll events with modifier-key state in a portable
        // way; the rest of the widget's behavior is covered by the
        // GestureDetector tests below.
        onPointerSignal: (event) {
          if (event is! PointerScrollEvent) return;
          if (!_isZoomModifierHeld()) return;
          final factor = (-event.scrollDelta.dy * 0.005);
          final newPxPerSec =
              viewport.pixelsPerSecond *
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
          final newPxPerSec = viewport.pixelsPerSecond * event.scale;
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
              chapterStarts: [for (final c in book.chapters) c.start],
              playedColor: Theme.of(context).colorScheme.primary,
              unplayedColor:
                  Theme.of(context).colorScheme.outlineVariant,
              tickColor: Theme.of(context).colorScheme.outline,
              playheadColor: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      );
    },
  ),
),
```

Add the helper methods to `_WaveformViewState`:

```dart
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
```

Add the imports at the top of the file (if not already present):

```dart
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
```

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze`
Expected: no issues.

- [ ] **Step 3: Run tests**

Run: `flutter test`
Expected: all tests still pass (no new tests; the existing tap/drag/zoom-button tests cover the GestureDetector branch unchanged).

- [ ] **Step 4: Build macOS**

Run: `flutter build macos --debug`
Expected: clean build.

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/widgets/waveform_view.dart
git commit --no-gpg-sign -m "$(cat <<'EOF'
Add Cmd+scroll and Cmd+pinch zoom centered on the cursor

Wraps the gesture body in a Listener that handles raw pointer scroll
and trackpad pan-zoom events. Cmd+scroll-wheel zooms continuously
(exp(deltaY * 0.005)); Cmd+pinch zooms by the gesture's scale factor.
Both anchor on the cursor's time position. Coverage-ignored — these
gestures aren't reliably synthesizable in flutter test and are
exercised by smoke testing on a real desktop build.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 6: Smoke test (manual, post-merge)**

Walk through the 12 cases in the spec's "Smoke-test plan" section.

---

## Verification

After all tasks land:

- [ ] **Final test run**

Run: `flutter test`
Expected: 207 prior tests + 11 viewport notifier + 10 waveform widget + 1 playback-controls layout = 229 tests passing.

- [ ] **Final analyzer run**

Run: `flutter analyze`
Expected: no issues.

- [ ] **Coverage check**

Run: `flutter test --coverage`
Run: `dart tool/coverage_summary.dart coverage/lcov.info`
Expected: filtered total stays at or above the previous baseline (~98 %). The Cmd+scroll/pinch handlers are `coverage:ignore`-marked.

- [ ] **macOS smoke test** — walk through the 12 smoke-test cases in the spec.
