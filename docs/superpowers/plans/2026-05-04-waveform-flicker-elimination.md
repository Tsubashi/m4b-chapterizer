# Waveform Flicker Elimination Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the waveform-blanking flash when the viewport crosses a tile boundary during playback by (a) prefetching the next tile while playing and (b) falling back to the last successfully loaded tile while the active tile is still loading.

**Architecture:** Two cooperating changes inside `_WaveformViewState`. A `_lastTile` field captures the most recently resolved `WaveformTilePeaks` so the painter can keep drawing during a tile-key transition; a second `ref.watch` on `nextTileKey`, gated on a play/pause state subscription, primes the family cache for the upcoming tile. The painter and the loading overlay are unchanged; only what gets passed to them and the gate on the overlay changes.

**Tech Stack:** Flutter 3.41.9, Dart 3.11, flutter_riverpod 3.x.

**Spec:** `docs/superpowers/specs/2026-05-04-waveform-flicker-elimination-design.md`

---

## File Map

**Modified:**
- `lib/presentation/widgets/waveform_view.dart` — `_lastTile` field, `_isPlaying` field + `playingStream` subscription, prefetch watch, fallback wiring, `_tileOverlapsViewport` helper, loading-overlay gate, `_lastTile` reset on path change.
- `test/presentation/waveform_view_test.dart` — extend `_pump` to accept a per-key resolver; add 6 new tests.

---

## Task 1: Implement fallback + prefetch with TDD

A single task because the two pieces share state (`_isPlaying` for prefetch, `_lastTile` for fallback) and the loading-gate logic depends on both. Six tests cover the spec; implementation follows.

**Files:**
- Modify: `test/presentation/waveform_view_test.dart`
- Modify: `lib/presentation/widgets/waveform_view.dart`

- [ ] **Step 1: Extend the `_pump` helper to support per-key resolution**

In `test/presentation/waveform_view_test.dart`, replace the existing `_pump` signature and body. The new shape adds an optional `keyResolver` parameter; existing callers using only `tilePeaks` / `loading` keep working unchanged.

```dart
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required _FakePlayback playback,
  WaveformTilePeaks? tilePeaks,
  bool loading = false,
  Future<WaveformTilePeaks> Function(WaveformTileKey key)? keyResolver,
}) async {
  final canned = tilePeaks ??
      const WaveformTilePeaks(
        tileStart: Duration.zero,
        tileDuration: Duration(seconds: 24),
        peaks: [],
      );
  final container = ProviderContainer(
    overrides: [
      bookbinderProvider.overrideWithValue(_StubBookbinder()),
      playbackControllerProvider.overrideWithValue(playback),
      zoomedWaveformPeaksProvider.overrideWith((ref, key) {
        if (keyResolver != null) return keyResolver(key);
        return loading
            ? Completer<WaveformTilePeaks>().future
            : Future.value(canned);
      }),
    ],
  );
  addTearDown(container.dispose);
  await container.read(editorProvider.notifier).open('/tmp/x.m4b');

  await tester.binding.setSurfaceSize(const Size(800, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: Scaffold(body: SizedBox(width: 800, child: WaveformView())),
    ),
  ));
  if (loading) {
    await tester.pump();
  } else {
    await tester.pumpAndSettle();
  }
  return container;
}
```

- [ ] **Step 2: Append the six new tests**

Add the following inside `void main() { ... }` in `test/presentation/waveform_view_test.dart`, after the existing tests:

```dart
  group('Tile flicker elimination', () {
    testWidgets(
        'falls back to last loaded tile while current tile is loading',
        (tester) async {
      final playback = _FakePlayback();
      addTearDown(playback.dispose);

      // First lookup resolves with a 24 s wide tile starting at 0.
      // Subsequent lookups (after pan triggers a new tileKey) never
      // resolve. _lastTile should keep the painter drawing and hide
      // the loading indicator because the old tile still overlaps.
      var loadCount = 0;
      final container = await _pump(
        tester,
        playback: playback,
        keyResolver: (key) {
          loadCount++;
          if (loadCount == 1) {
            return Future.value(const WaveformTilePeaks(
              tileStart: Duration.zero,
              tileDuration: Duration(seconds: 24),
              peaks: [0.5, 0.5, 0.5],
            ));
          }
          return Completer<WaveformTilePeaks>().future;
        },
      );

      // Pan to windowStart = 8 s (800 px / 100 pxPerSec). Default
      // viewportDuration = 8 s, so tileIndex flips 0 → 1, triggering
      // a fresh family lookup that never resolves.
      container.read(waveformViewportProvider.notifier).panBy(
            800,
            const Duration(seconds: 60),
            800,
          );
      await tester.pump();

      expect(find.text('Generating waveform…'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows loading when last tile no longer overlaps viewport',
        (tester) async {
      final playback = _FakePlayback();
      addTearDown(playback.dispose);

      var loadCount = 0;
      final container = await _pump(
        tester,
        playback: playback,
        keyResolver: (key) {
          loadCount++;
          if (loadCount == 1) {
            return Future.value(const WaveformTilePeaks(
              tileStart: Duration.zero,
              tileDuration: Duration(seconds: 24),
              peaks: [0.5, 0.5, 0.5],
            ));
          }
          return Completer<WaveformTilePeaks>().future;
        },
      );

      // Pan windowStart well past the old tile's end (24 s). 30 s is
      // outside [0, 24), so _lastTile no longer covers the viewport.
      // Loading indicator should appear.
      container.read(waveformViewportProvider.notifier).panBy(
            3000,
            const Duration(seconds: 60),
            800,
          );
      await tester.pump();

      expect(find.text('Generating waveform…'), findsOneWidget);
    });

    testWidgets('_lastTile resets when path changes (no bleed-through)',
        (tester) async {
      final playback = _FakePlayback();
      addTearDown(playback.dispose);

      final container = await _pump(
        tester,
        playback: playback,
        keyResolver: (key) {
          if (key.path == '/tmp/x.m4b') {
            return Future.value(const WaveformTilePeaks(
              tileStart: Duration.zero,
              tileDuration: Duration(seconds: 24),
              peaks: [0.5, 0.5, 0.5],
            ));
          }
          return Completer<WaveformTilePeaks>().future;
        },
      );

      // Open a different path. The _StubBookbinder returns the same
      // audiobook regardless of path, but the path-change listener in
      // WaveformView should null out _lastTile, and the new path's
      // tile lookup never resolves — so the loading indicator must
      // reappear.
      await container.read(editorProvider.notifier).open('/tmp/y.m4b');
      await tester.pump();
      await tester.pump();

      expect(find.text('Generating waveform…'), findsOneWidget);
    });

    testWidgets('prefetches the next tile while playing', (tester) async {
      final playback = _FakePlayback();
      addTearDown(playback.dispose);

      final queriedKeys = <WaveformTileKey>[];
      final container = await _pump(
        tester,
        playback: playback,
        keyResolver: (key) {
          queriedKeys.add(key);
          return Future.value(const WaveformTilePeaks(
            tileStart: Duration.zero,
            tileDuration: Duration(seconds: 24),
            peaks: [0.5, 0.5, 0.5],
          ));
        },
      );
      // Initial mount, paused: only the current tile (tileIndex 0)
      // should be queried so far.
      expect(queriedKeys.map((k) => k.tileIndex).toSet(), equals({0}));

      // Start playing. The widget should rebuild and add a watch on
      // tileIndex + 1 = 1.
      playback.emitPlaying(true);
      await tester.pump();
      await tester.pump();

      expect(
        queriedKeys.map((k) => k.tileIndex).toSet(),
        equals({0, 1}),
      );
      // Sanity: container still alive so the watches are real.
      expect(container.read(editorProvider).path, '/tmp/x.m4b');
    });

    testWidgets('does not prefetch while paused', (tester) async {
      final playback = _FakePlayback();
      addTearDown(playback.dispose);

      final queriedKeys = <WaveformTileKey>[];
      await _pump(
        tester,
        playback: playback,
        keyResolver: (key) {
          queriedKeys.add(key);
          return Future.value(const WaveformTilePeaks(
            tileStart: Duration.zero,
            tileDuration: Duration(seconds: 24),
            peaks: [0.5, 0.5, 0.5],
          ));
        },
      );

      expect(queriedKeys.map((k) => k.tileIndex).toSet(), equals({0}));
    });
  });

  // Spec test #2 ("Painter shows loading when current tile is loading
  // and `_lastTile` is null") is already covered by the existing
  // "shows loading indicator while the active tile is loading" test
  // earlier in this file: it pumps with no prior successful load, so
  // _lastTile starts null and the gate `isLoading && !fallbackOverlaps`
  // collapses to `isLoading`.
```

- [ ] **Step 3: Run tests; verify failure**

Run: `flutter test test/presentation/waveform_view_test.dart`
Expected: the new "Tile flicker elimination" group fails. The fallback / loading-gate tests fail because `_lastTile` doesn't exist; the prefetch tests fail because only one tile is queried regardless of playback state.

- [ ] **Step 4: Add the implementation**

Replace `_WaveformViewState` in `lib/presentation/widgets/waveform_view.dart` with the version below. The class structure, painter, gestures, and zoom buttons stay; the only changes are:

1. New `_lastTile` field (and its reset in the path-change listener).
2. New `_isPlaying` field plus `playingStream` subscription so the build re-runs when playback state changes.
3. New `_tileOverlapsViewport` helper.
4. New `nextTileKey` computation and conditional `ref.watch` for prefetch.
5. New `effectiveTile` chosen between live data and `_lastTile`.
6. Loading overlay now gated on `tileAsync.isLoading && !overlap`.

```dart
class _WaveformViewState extends ConsumerState<WaveformView> {
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _playingSub;
  Duration _latestTotalDuration = Duration.zero;
  double _latestViewportWidth = 0;
  WaveformTilePeaks? _lastTile;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    final controller = ref.read(playbackControllerProvider);
    _isPlaying = controller.playing;
    _positionSub = controller.positionStream.listen(_onPosition);
    _playingSub = controller.playingStream.listen((playing) {
      if (!mounted) return;
      if (_isPlaying != playing) {
        setState(() => _isPlaying = playing);
      }
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _playingSub?.cancel();
    super.dispose();
  }

  void _onPosition(Duration playhead) {
    if (_latestTotalDuration <= Duration.zero ||
        _latestViewportWidth <= 0) {
      return;
    }
    final controller = ref.read(playbackControllerProvider);
    final notifier = ref.read(waveformViewportProvider.notifier);
    if (controller.playing) {
      notifier.followPlayhead(
        playhead,
        _latestTotalDuration,
        _latestViewportWidth,
      );
      return;
    }
    final viewport = ref.read(waveformViewportProvider);
    final windowMicros =
        (_latestViewportWidth / viewport.pixelsPerSecond * 1e6).round();
    final windowEnd =
        viewport.windowStart + Duration(microseconds: windowMicros);
    if (playhead < viewport.windowStart || playhead > windowEnd) {
      notifier.followPlayhead(
        playhead,
        _latestTotalDuration,
        _latestViewportWidth,
      );
    }
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

        // Capture the freshly-resolved tile so we can keep painting
        // through subsequent loads.
        if (tileAsync.hasValue) {
          final resolved = tileAsync.value!;
          if (resolved.tileDuration > Duration.zero) {
            _lastTile = resolved;
          }
        }

        // Prefetch the next tile only while playing — pan/zoom while
        // paused is user-driven and we can't predict direction.
        if (_isPlaying) {
          final nextTileKey = WaveformTileKey(
            path: path,
            tileIndex: tileIndex + 1,
            viewportDurationMicros: viewportDurationMicros,
            pixelsPerSecond: viewport.pixelsPerSecond,
          );
          ref.watch(zoomedWaveformPeaksProvider(nextTileKey));
        }

        // What the painter actually draws from: live tile if loaded,
        // otherwise the last good tile, otherwise empty.
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
              child: StreamBuilder<Duration>(
                stream: controller.positionStream,
                initialData: controller.position,
                builder: (context, snapshot) {
                  final playhead =
                      snapshot.data ?? controller.position;
                  return Listener(
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
                    ),
                  );
                },
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

The rest of `waveform_view.dart` (top-level imports, `WaveformView` widget, `_ZoomButtons`, `_WaveformPainter`) is unchanged.

- [ ] **Step 5: Run tests; verify pass**

Run: `flutter test test/presentation/waveform_view_test.dart`
Expected: all "Tile flicker elimination" tests pass plus the prior 18 tests in this file.

- [ ] **Step 6: Run full suite + analyzer**

Run: `flutter test`
Run: `flutter analyze`
Expected: all green.

- [ ] **Step 7: Build macOS to confirm runtime is happy**

Run: `flutter build macos --debug`
Expected: clean build.

- [ ] **Step 8: Commit**

```bash
git add lib/presentation/widgets/waveform_view.dart test/presentation/waveform_view_test.dart
git commit --no-gpg-sign -m "$(cat <<'EOF'
Eliminate waveform flicker at tile boundaries during playback

Two cooperating changes inside _WaveformViewState:

1. Fall back to the last successfully loaded tile while the active
   one is loading. _lastTile captures every resolved WaveformTilePeaks;
   the painter consumes liveTile ?? _lastTile, and the loading
   overlay only shows when the painter has nothing to draw (live
   tile loading AND last tile doesn't overlap the viewport, or
   _lastTile is null altogether). _lastTile resets on path change
   so the previous file's data can't bleed into the new file.

2. Prefetch the next tile while playing. A subscription to
   playingStream re-builds the widget when play/pause toggles; when
   playing, the build adds a second ref.watch on tileIndex + 1's
   family entry. By the time the viewport crosses the boundary, the
   next tile is already cached, so the watch on the new key returns
   data immediately — no flicker.

Together these turn typical playback transitions seamless and, on
slow extractions, replace the flicker with a gradual right-edge
thinning.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Verification

After the task lands:

- [ ] **Final test run**

Run: `flutter test`
Expected: 242 prior tests + 5 new = 247 tests passing.

- [ ] **Final analyzer**

Run: `flutter analyze`
Expected: no issues.

- [ ] **Coverage**

Run: `flutter test --coverage`
Run: `dart tool/coverage_summary.dart coverage/lcov.info`
Expected: total stays at or above the previous baseline (~98 %).

- [ ] **macOS smoke test**

`flutter run -d macos`. Open an `.m4b`, press play, watch the waveform scroll. There should be no visible loading flash or blank frame as the viewport crosses tile boundaries every viewport-duration of follow time. Pause, pan around — small loading flashes when crossing into never-visited regions are expected. Zoom in or out — one loading flash at the new resolution, then smooth.
