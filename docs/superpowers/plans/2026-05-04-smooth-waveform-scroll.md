# Smooth Waveform Scroll Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the once-per-position-stream-tick `followPlayhead` call with a frame-rate `Ticker` that interpolates between stream emissions, so the waveform scrolls continuously instead of in ~200 ms jumps.

**Architecture:** Add a `Ticker` (via `SingleTickerProviderStateMixin`) to `_WaveformViewState`. Position stream emissions set a baseline `(_basePosition, _baseTickerElapsed)`; on each Ticker tick, compute `interpolated = basePosition + (tickerElapsed − baseTickerElapsed) × speed` and feed it to both `followPlayhead` and the painter's playhead line. The Ticker only runs while playing.

**Tech Stack:** Flutter 3.41.9, Dart 3.11, `Ticker` from `package:flutter/scheduler.dart` (re-exported via `package:flutter/widgets.dart`).

**Spec:** `docs/superpowers/specs/2026-05-04-smooth-waveform-scroll-design.md`

---

## File Map

**Modified:**
- `lib/presentation/widgets/waveform_view.dart` — add `SingleTickerProviderStateMixin`, `Ticker`, baseline state, `_onTick`, `_currentPlaybackSpeed`. Restructure `_onPosition` and `_onPlayingChange`. Replace the painter's `StreamBuilder<Duration>` wrapper with a direct read of `_smoothedPlayhead`.
- `test/presentation/waveform_view_test.dart` — add 6 new tests asserting via `windowStart` side effects.

---

## Task 1: Smooth scroll via Ticker-driven interpolation

Single TDD task — the changes are interlocked enough that splitting them produces intermediate states with broken tests.

**Files:**
- Modify: `test/presentation/waveform_view_test.dart`
- Modify: `lib/presentation/widgets/waveform_view.dart`

- [ ] **Step 1: Append failing tests**

Append the following inside `void main() { ... }` in `test/presentation/waveform_view_test.dart`, after the existing tests (alongside the "Tile flicker elimination" group):

```dart
  group('Smooth playback scroll', () {
    testWidgets('paused: in-window position emission does not move viewport',
        (tester) async {
      final playback = _FakePlayback();
      addTearDown(playback.dispose);
      final container = await _pump(tester, playback: playback);

      // Default: paused, viewport [0, 8 s]. 5 s is inside.
      expect(playback.playing, isFalse);
      playback.emitPosition(const Duration(seconds: 5));
      await tester.pump();

      expect(
        container.read(waveformViewportProvider).windowStart,
        Duration.zero,
      );
    });

    testWidgets(
        'paused: out-of-window position emission re-anchors immediately',
        (tester) async {
      final playback = _FakePlayback();
      addTearDown(playback.dispose);
      final container = await _pump(tester, playback: playback);

      playback.emitPosition(const Duration(seconds: 30));
      await tester.pump();

      // followPlayhead at 25% of 8 s window: windowStart = 30 − 2 = 28 s.
      expect(
        container
            .read(waveformViewportProvider)
            .windowStart
            .inMilliseconds,
        closeTo(28000, 50),
      );
    });

    testWidgets('windowStart advances continuously while playing',
        (tester) async {
      final playback = _FakePlayback();
      addTearDown(playback.dispose);
      final container = await _pump(tester, playback: playback);

      // Set baseline at 5 s, then start playback.
      playback.emitPosition(const Duration(seconds: 5));
      playback.emitPlaying(true);
      await tester.pump();

      // Advance Flutter's scheduler by 500 ms. The Ticker callback
      // sees its elapsed advance accordingly and interpolates.
      await tester.pump(const Duration(milliseconds: 500));

      // Expected: interpolated playhead = 5 s + 500 ms = 5.5 s.
      // followPlayhead anchors at 25% of 8 s window:
      // windowStart = 5500 − 2000 = 3500 ms.
      expect(
        container
            .read(waveformViewportProvider)
            .windowStart
            .inMilliseconds,
        closeTo(3500, 50),
      );
    });

    testWidgets('pausing stops extrapolation', (tester) async {
      final playback = _FakePlayback();
      addTearDown(playback.dispose);
      final container = await _pump(tester, playback: playback);

      playback.emitPosition(const Duration(seconds: 5));
      playback.emitPlaying(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Note where the viewport is right before pausing.
      final stoppedAt =
          container.read(waveformViewportProvider).windowStart;

      playback.emitPlaying(false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // No further extrapolation after pause.
      expect(
        container.read(waveformViewportProvider).windowStart,
        stoppedAt,
      );
    });

    testWidgets('seek mid-playback resets the extrapolation baseline',
        (tester) async {
      final playback = _FakePlayback();
      addTearDown(playback.dispose);
      final container = await _pump(tester, playback: playback);

      playback.emitPosition(Duration.zero);
      playback.emitPlaying(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Seek to 30 s mid-playback. The next Ticker pump should base
      // its extrapolation on the new emission, not continue from
      // the old baseline.
      playback.emitPosition(const Duration(seconds: 30));
      await tester.pump();

      // followPlayhead anchors the new playhead at 25% from left:
      // windowStart ≈ 30 − 2 = 28 s. Allow a frame of extrapolation
      // beyond the seek (a few ms at most).
      expect(
        container
            .read(waveformViewportProvider)
            .windowStart
            .inMilliseconds,
        closeTo(28000, 100),
      );
    });

    testWidgets('resuming play after pause resyncs to controller.position',
        (tester) async {
      final playback = _FakePlayback();
      addTearDown(playback.dispose);
      final container = await _pump(tester, playback: playback);

      // Play from 5 s briefly, pause; viewport advances during the
      // play interval.
      playback.emitPosition(const Duration(seconds: 5));
      playback.emitPlaying(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      playback.emitPlaying(false);
      await tester.pump();

      // The fake's `_pos` was last set when emitPosition fired (5 s).
      // controller.position therefore returns 5 s. After resuming,
      // the new baseline is 5 s, and 100 ms later the viewport
      // should be windowStart ≈ 5100 − 2000 = 3100 ms.
      playback.emitPlaying(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        container
            .read(waveformViewportProvider)
            .windowStart
            .inMilliseconds,
        closeTo(3100, 100),
      );
    });
  });
```

The existing test "viewport follows playhead while playing" remains; the new "windowStart advances continuously while playing" test is its smoother companion (the existing one verifies a single-shot follow on a discrete position event, the new one verifies the per-frame extrapolation in between events).

- [ ] **Step 2: Run tests; verify failure**

Run: `flutter test test/presentation/waveform_view_test.dart`
Expected: all "Smooth playback scroll" tests fail. Today's `_onPosition` only updates the viewport when a stream event fires, so `tester.pump(500ms)` doesn't move `windowStart` — the "advances continuously while playing" assertion fails first. Some other tests in the new group may pass coincidentally (those that rely on stream events alone) but the smooth-scroll-related ones fail.

- [ ] **Step 3: Add the implementation**

In `lib/presentation/widgets/waveform_view.dart`, add `import 'package:flutter/scheduler.dart';` near the existing `flutter/widgets.dart` import (the Ticker types live there). Replace the entire `_WaveformViewState` class with the version below. The `WaveformView` class, `_ZoomButtons`, `_WaveformPainter`, and the file's other imports stay byte-for-byte the same.

```dart
class _WaveformViewState extends ConsumerState<WaveformView>
    with SingleTickerProviderStateMixin {
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _playingSub;
  late final Ticker _ticker;

  Duration _latestTotalDuration = Duration.zero;
  double _latestViewportWidth = 0;

  WaveformTilePeaks? _lastTile;
  bool _isPlaying = false;

  // Extrapolation baseline. _basePosition is the most recent value the
  // playback stream reported; _baseTickerElapsed is the Ticker.elapsed
  // value at that moment (captured from _lastTickerElapsed below). The
  // Ticker advances Ticker.elapsed at the display refresh rate; we
  // extrapolate from the baseline by the delta in Ticker.elapsed,
  // scaled by the current playback speed.
  Duration _basePosition = Duration.zero;
  Duration _baseTickerElapsed = Duration.zero;
  Duration _lastTickerElapsed = Duration.zero;

  // What the painter actually consumes for the playhead line.
  Duration _smoothedPlayhead = Duration.zero;

  /// Multiplier applied to wall-clock delta when extrapolating between
  /// position-stream emissions. Today the player runs at fixed 1.0×;
  /// when a rate UI lands, replace this with a read from
  /// PlaybackController.speed (and consider subscribing to a
  /// speedStream to reset the baseline on rate changes — without that,
  /// drift after a rate change is bounded to one stream interval).
  double _currentPlaybackSpeed() => 1.0;

  @override
  void initState() {
    super.initState();
    final controller = ref.read(playbackControllerProvider);
    _isPlaying = controller.playing;
    _basePosition = controller.position;
    _smoothedPlayhead = controller.position;

    _positionSub = controller.positionStream.listen(_onPosition);
    _playingSub = controller.playingStream.listen(_onPlayingChange);

    _ticker = createTicker(_onTick);
    if (_isPlaying) _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _positionSub?.cancel();
    _playingSub?.cancel();
    super.dispose();
  }

  void _onPosition(Duration playhead) {
    // Always reset the extrapolation baseline.
    _basePosition = playhead;
    _baseTickerElapsed = _lastTickerElapsed;

    if (_isPlaying) {
      // Ticker is running and will pick up the new baseline on its
      // next tick.
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
    // Ticker.start() resets the ticker's internal elapsed to 0 on the
    // next frame; match our baseline so the first post-resume delta
    // is 0, not whatever _lastTickerElapsed was at pause time.
    _baseTickerElapsed = Duration.zero;
    _lastTickerElapsed = Duration.zero;
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

  void _onTick(Duration tickerElapsed) {
    if (!mounted) return;
    _lastTickerElapsed = tickerElapsed;

    final delta = tickerElapsed - _baseTickerElapsed;
    final speedScaledMicros =
        (delta.inMicroseconds * _currentPlaybackSpeed()).round();
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
```

Notable changes vs. the previous `_WaveformViewState`:

- New mixin: `with SingleTickerProviderStateMixin`.
- New fields: `_ticker`, `_basePosition`, `_baseTickerElapsed`, `_lastTickerElapsed`, `_smoothedPlayhead`, `_currentPlaybackSpeed()`.
- `_onPlayingChange` is now a named method (was an inline closure) so it can resync the baseline and start/stop the Ticker.
- `_onPosition` no longer calls `followPlayhead` while playing — the Ticker does. While paused, it still runs the ensure-visible check.
- `_onTick` is new.
- `dispose` now disposes the Ticker.
- The painter wrapper is now just `Listener > GestureDetector > CustomPaint` (no `StreamBuilder<Duration>`); the painter's `playhead` argument reads `_smoothedPlayhead` directly from State.

- [ ] **Step 4: Run tests; verify pass**

Run: `flutter test test/presentation/waveform_view_test.dart`
Expected: the new "Smooth playback scroll" group passes (6 tests), plus all prior tests in this file (24 → 30 total).

- [ ] **Step 5: Run full suite + analyzer**

Run: `flutter test`
Run: `flutter analyze`
Expected: 247 prior + 6 new = 253 tests passing; analyzer clean.

- [ ] **Step 6: Build macOS to confirm runtime is happy**

Run: `flutter build macos --debug`
Expected: clean build.

- [ ] **Step 7: Commit**

```bash
git add lib/presentation/widgets/waveform_view.dart test/presentation/waveform_view_test.dart
git commit --no-gpg-sign -m "$(cat <<'EOF'
Smooth waveform scroll via Ticker-driven interpolation

just_audio.positionStream emits at ~5 Hz, so the previous
once-per-stream-tick followPlayhead call advanced windowStart in
~200 ms steps — visibly jumpy. Add a Ticker (via
SingleTickerProviderStateMixin) that fires every frame while playing.
Position-stream emissions set a baseline (basePosition,
baseTickerElapsed); each tick computes
  interpolated = basePosition + (tickerElapsed − baseTickerElapsed)
                                  × _currentPlaybackSpeed()
and feeds that to followPlayhead and the painter's playhead line.

Drift between extrapolation and the player's reality is bounded to
one stream interval since each emission resets the baseline. The
Ticker only runs while playing — pausing stops it; a seek mid-play
just resets the baseline.

The single-line _currentPlaybackSpeed() returns 1.0 today; when a
rate UI lands, that's the only call site to update.

Drives extrapolation from Ticker.elapsed (not Stopwatch) so
tester.pump(Duration) advances the same clock the production code
reads — tests assert via windowStart side effects.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Verification

After the task lands:

- [ ] **Final test run**

Run: `flutter test`
Expected: 253 tests passing.

- [ ] **Final analyzer**

Run: `flutter analyze`
Expected: no issues.

- [ ] **Coverage**

Run: `flutter test --coverage`
Run: `dart tool/coverage_summary.dart coverage/lcov.info`
Expected: total stays at or above the previous baseline (~98 %).

- [ ] **macOS smoke test**

`flutter run -d macos`. Open an `.m4b`. Press play. The waveform should now scroll continuously at the display's refresh rate — no 20 px jumps. Pause; the waveform freezes. Click the thin scrubber to seek to a different time; the zoomed view re-anchors immediately. Resume play; smooth scrolling continues from the new position.
