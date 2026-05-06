import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/bookbinder.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
import 'package:m4b_chapterizer/presentation/providers/editor_state.dart';
import 'package:m4b_chapterizer/presentation/providers/playback.dart';
import 'package:m4b_chapterizer/presentation/providers/waveform_viewport.dart';
import 'package:m4b_chapterizer/presentation/providers/zoomed_waveform_peaks.dart';
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
    // CircularProgressIndicator animates forever, so pumpAndSettle would
    // hang. A single pump is enough to flush the initial build.
    await tester.pump();
  } else {
    await tester.pumpAndSettle();
  }
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
      tilePeaks: const WaveformTilePeaks(
        tileStart: Duration.zero,
        tileDuration: Duration(seconds: 24),
        peaks: [0.0, 0.5, 1.0, 0.5, 0.0],
      ),
    );
    expect(tester.takeException(), isNull);
  });

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

    // Pan to a known place first: panBy 500 px at 100 px/s → start = 5s,
    // window = [5s, 13s].
    container
        .read(waveformViewportProvider.notifier)
        .panBy(500, const Duration(seconds: 60), 800);
    final beforeStart =
        container.read(waveformViewportProvider).windowStart;

    // playing == false (the default). Emit a position update INSIDE the
    // current window so the ensure-visible branch is a no-op.
    playback.emitPosition(const Duration(seconds: 8));
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

    // The fake bookbinder returns the same audiobook regardless of path;
    // the path itself is what triggers the reset.
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

  testWidgets('shows loading indicator while the active tile is loading',
      (tester) async {
    final playback = _FakePlayback();
    addTearDown(playback.dispose);
    await _pump(tester, playback: playback, loading: true);

    expect(find.text('Generating waveform…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('hides loading indicator once the tile resolves',
      (tester) async {
    final playback = _FakePlayback();
    addTearDown(playback.dispose);
    await _pump(tester, playback: playback);

    expect(find.text('Generating waveform…'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('seek to a position outside the viewport re-anchors while paused',
      (tester) async {
    final playback = _FakePlayback();
    addTearDown(playback.dispose);
    final container = await _pump(tester, playback: playback);

    // Default state: paused, viewport [0, 8s] at 100 px/s.
    expect(playback.playing, isFalse);
    playback.emitPosition(const Duration(seconds: 30));
    await tester.pump();

    // 30s is outside [0,8s]. ensure-visible → followPlayhead at 25%
    // → windowStart = 30 - 2 = 28s.
    expect(
      container
          .read(waveformViewportProvider)
          .windowStart
          .inMilliseconds,
      closeTo(28000, 50),
    );
  });

  testWidgets('seek to a position inside the viewport keeps it put while paused',
      (tester) async {
    final playback = _FakePlayback();
    addTearDown(playback.dispose);
    final container = await _pump(tester, playback: playback);

    // Default state: paused, viewport [0, 8s].
    playback.emitPosition(const Duration(seconds: 4));
    await tester.pump();

    expect(
      container.read(waveformViewportProvider).windowStart,
      Duration.zero,
    );
  });

  testWidgets(
      'drag-pan, then seek inside the panned viewport, keeps viewport put',
      (tester) async {
    final playback = _FakePlayback();
    addTearDown(playback.dispose);
    final container = await _pump(tester, playback: playback);

    // Manually set windowStart = 30s.
    container
        .read(waveformViewportProvider.notifier)
        .panBy(3000, const Duration(seconds: 60), 800);
    final pannedStart =
        container.read(waveformViewportProvider).windowStart;
    expect(pannedStart, const Duration(seconds: 30));

    // Seek to 32s, which is inside [30s, 38s].
    playback.emitPosition(const Duration(seconds: 32));
    await tester.pump();

    expect(
      container.read(waveformViewportProvider).windowStart,
      pannedStart,
    );
  });

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
}
