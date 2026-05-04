# Zoomable Waveform — Refinements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a loading state, switch the zoomed waveform to tile-based extraction (so peaks resolve at viewport-pixel resolution without flickering during continuous follow), and re-anchor the zoomed viewport on seek-to-outside-window while paused.

**Architecture:** A new `WaveformExtractor.extractRange` method invokes ffmpeg with `-ss` / `-t` for windowed extraction. A new `zoomedWaveformPeaksProvider` family is keyed on quantized `WaveformTileKey` (path + tileIndex + viewportDuration + pxPerSec), with each tile covering 3× the viewport width — so continuous follow only crosses a tile boundary every viewport-width of audio, not every frame. `WaveformView` switches from the whole-file `waveformPeaksProvider` to the new tile provider, displays a "Generating waveform…" indicator while the active tile is loading, and changes its position-stream listener to `followPlayhead` whenever the playhead is outside the current viewport (regardless of play/pause state).

**Tech Stack:** Flutter 3.41.9, Dart 3.11, flutter_riverpod 3.x, ffmpeg `-ss` / `-t`.

**Spec:** `docs/superpowers/specs/2026-05-03-zoomable-waveform-refinements-design.md`

---

## File Map

**New:**
- `lib/presentation/providers/zoomed_waveform_peaks.dart` — `WaveformTileKey`, `WaveformTilePeaks`, `computeTileBounds`, `TileBounds`, `zoomedWaveformPeaksProvider`
- `test/presentation/providers/zoomed_waveform_peaks_test.dart`

**Modified:**
- `lib/data/waveform_extractor.dart` — add `extractRange`; refactor binning into `_binStream`
- `test/data/waveform_extractor_test.dart` — add `extractRange` tests
- `lib/presentation/widgets/waveform_view.dart` — switch peak source, add loading state, change ensure-visible rule
- `test/presentation/waveform_view_test.dart` — re-point overrides at new provider, add loading + ensure-visible tests

---

## Task 1: `WaveformExtractor.extractRange` with windowed ffmpeg

Add windowed extraction. Refactor the binning loop into a private helper shared with `extract()`.

**Files:**
- Modify: `lib/data/waveform_extractor.dart`
- Modify: `test/data/waveform_extractor_test.dart`

- [ ] **Step 1: Append failing tests**

Add the following inside `void main() { ... }` in `test/data/waveform_extractor_test.dart`, after the existing `group('WaveformExtractor.extract', ...) { ... }`:

```dart
  group('WaveformExtractor.extractRange', () {
    test('invokes ffmpeg with -ss before -i and -t after', () async {
      List<String>? capturedArgs;
      final extractor = WaveformExtractor(
        binaries: binaries,
        processStarter: (exe, args) async {
          capturedArgs = args;
          return _MockProcess(
            stdout: const Stream.empty(),
            exitCode: Future.value(0),
          );
        },
      );

      await extractor.extractRange(
        path: '/x.m4b',
        start: const Duration(seconds: 10),
        duration: const Duration(seconds: 30),
        targetPeaks: 100,
      );

      expect(capturedArgs, isNotNull);
      final args = capturedArgs!;
      // -ss must precede -i (input seek for fast container indexing).
      final ssIdx = args.indexOf('-ss');
      final iIdx = args.indexOf('-i');
      final tIdx = args.indexOf('-t');
      expect(ssIdx, greaterThanOrEqualTo(0));
      expect(iIdx, greaterThan(ssIdx));
      expect(tIdx, greaterThan(iIdx));
      // -ss value is the start in seconds.
      expect(double.parse(args[ssIdx + 1]), closeTo(10.0, 1e-9));
      // -t value is the duration in seconds.
      expect(double.parse(args[tIdx + 1]), closeTo(30.0, 1e-9));
      expect(args[iIdx + 1], '/x.m4b');
    });

    test('bins windowed PCM into the requested number of peaks', () async {
      // 240,000 samples at constant amplitude 16384. With 30 s duration and
      // targetPeaks=10: samplesPerBin = 30 * 8000 / 10 = 24000.
      final samples = List.filled(240000, 16384);
      final bytes = _samples(samples);

      final extractor = WaveformExtractor(
        binaries: binaries,
        processStarter: (exe, args) async => _MockProcess(
          stdout: Stream.value(bytes),
          exitCode: Future.value(0),
        ),
      );

      final peaks = await extractor.extractRange(
        path: '/x.m4b',
        start: const Duration(seconds: 5),
        duration: const Duration(seconds: 30),
        targetPeaks: 10,
      );

      expect(peaks.length, 10);
      for (final p in peaks) {
        expect(p, closeTo(0.5, 1e-6));
      }
    });

    test('cancellation kills the process and throws WaveformCancelled',
        () async {
      final stdoutController = StreamController<List<int>>();
      addTearDown(stdoutController.close);
      final exitCompleter = Completer<int>();
      final extractor = WaveformExtractor(
        binaries: binaries,
        processStarter: (exe, args) async => _MockProcess(
          stdout: stdoutController.stream,
          exitCode: exitCompleter.future,
          onKill: () {
            if (!exitCompleter.isCompleted) exitCompleter.complete(137);
          },
        ),
      );

      final future = extractor.extractRange(
        path: '/x.m4b',
        start: Duration.zero,
        duration: const Duration(seconds: 5),
        targetPeaks: 10,
      );
      // Pump a small amount of data, then cancel.
      stdoutController.add(_samples(List.filled(100, 16384)));
      await Future<void>.delayed(Duration.zero);
      extractor.cancel();
      await stdoutController.close();

      expect(future, throwsA(isA<WaveformCancelled>()));
    });
  });
```

- [ ] **Step 2: Run tests; verify failure**

Run: `flutter test test/data/waveform_extractor_test.dart`
Expected: compile error — `extractRange` doesn't exist.

- [ ] **Step 3: Refactor `WaveformExtractor` and add `extractRange`**

Replace `lib/data/waveform_extractor.dart` with:

```dart
import 'dart:async';
import 'dart:io';

import 'binary_resolver.dart';

class WaveformCancelled implements Exception {
  const WaveformCancelled();

  @override
  String toString() => 'WaveformCancelled';
}

class WaveformExtractor {
  WaveformExtractor({required this.binaries, required this.processStarter});

  final BinaryResolver binaries;
  final Future<Process> Function(String exe, List<String> args) processStarter;

  Process? _activeProcess;
  bool _cancelled = false;

  /// Extracts [targetPeaks] amplitude bins covering the full file.
  Future<List<double>> extract({
    required String path,
    required Duration totalDuration,
    int targetPeaks = 4096,
  }) async {
    final totalSamples =
        (totalDuration.inMicroseconds * 8000) ~/ Duration.microsecondsPerSecond;
    final process = await processStarter(binaries.ffmpeg, [
      '-loglevel', 'error',
      '-i', path,
      '-map', '0:a',
      '-f', 's16le',
      '-ac', '1',
      '-ar', '8000',
      '-',
    ]);
    return _binStream(
      process: process,
      totalSamples: totalSamples,
      targetPeaks: targetPeaks,
    );
  }

  /// Like [extract], but only for the half-open audio window
  /// `[start, start + duration)`. Uses ffmpeg's `-ss` (input seek)
  /// before `-i` for fast container-indexed seek and `-t` after `-i`
  /// to limit the output duration.
  Future<List<double>> extractRange({
    required String path,
    required Duration start,
    required Duration duration,
    required int targetPeaks,
  }) async {
    final totalSamples =
        (duration.inMicroseconds * 8000) ~/ Duration.microsecondsPerSecond;
    final startSeconds =
        start.inMicroseconds / Duration.microsecondsPerSecond;
    final durationSeconds =
        duration.inMicroseconds / Duration.microsecondsPerSecond;
    final process = await processStarter(binaries.ffmpeg, [
      '-loglevel', 'error',
      '-ss', startSeconds.toString(),
      '-i', path,
      '-t', durationSeconds.toString(),
      '-map', '0:a',
      '-f', 's16le',
      '-ac', '1',
      '-ar', '8000',
      '-',
    ]);
    return _binStream(
      process: process,
      totalSamples: totalSamples,
      targetPeaks: targetPeaks,
    );
  }

  Future<List<double>> _binStream({
    required Process process,
    required int totalSamples,
    required int targetPeaks,
  }) async {
    var samplesPerBin = totalSamples ~/ targetPeaks;
    if (samplesPerBin < 1) samplesPerBin = 1;
    _activeProcess = process;

    final peaks = <double>[];
    int currentBinSampleCount = 0;
    int currentBinMax = 0;
    int? carryByte;

    try {
      await for (final chunk in process.stdout) {
        if (_cancelled) throw const WaveformCancelled();
        final List<int> bytes;
        if (carryByte != null) {
          bytes = [carryByte, ...chunk];
          carryByte = null;
        } else {
          bytes = chunk;
        }
        final usableLength = bytes.length & ~1;
        if (bytes.length > usableLength) {
          carryByte = bytes[usableLength];
        }
        for (var i = 0; i < usableLength; i += 2) {
          var sample = bytes[i] | (bytes[i + 1] << 8);
          if (sample >= 0x8000) sample -= 0x10000;
          final absSample = sample < 0 ? -sample : sample;
          if (absSample > currentBinMax) currentBinMax = absSample;
          currentBinSampleCount++;
          if (currentBinSampleCount >= samplesPerBin) {
            peaks.add(currentBinMax / 32768);
            currentBinSampleCount = 0;
            currentBinMax = 0;
          }
        }
      }

      if (_cancelled) throw const WaveformCancelled();

      final exitCode = await process.exitCode;
      if (exitCode != 0) {
        throw StateError('ffmpeg exited with code $exitCode');
      }

      if (currentBinSampleCount > 0) {
        peaks.add(currentBinMax / 32768);
      }
      return peaks;
    } catch (e) {
      if (_cancelled) throw const WaveformCancelled();
      rethrow;
    } finally {
      _activeProcess = null;
    }
  }

  void cancel() {
    _cancelled = true;
    _activeProcess?.kill();
  }
}
```

- [ ] **Step 4: Run tests; verify pass**

Run: `flutter test test/data/waveform_extractor_test.dart`
Expected: existing extract tests + 3 new extractRange tests pass.

- [ ] **Step 5: Run full suite + analyzer**

Run: `flutter test`
Run: `flutter analyze`
Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add lib/data/waveform_extractor.dart test/data/waveform_extractor_test.dart
git commit --no-gpg-sign -m "$(cat <<'EOF'
Add WaveformExtractor.extractRange for windowed extraction

ffmpeg invocation uses -ss before -i (fast container-indexed seek)
and -t after -i (output duration limit). Refactors the existing
binning loop into a private _binStream helper shared with extract().

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: `WaveformTileKey`, `WaveformTilePeaks`, `computeTileBounds`, and the family provider

Create the tile types and a pure-logic tile-bounds function. Add the family provider that wraps `WaveformExtractor.extractRange` (production wiring is `coverage:ignore`-marked).

**Files:**
- Create: `lib/presentation/providers/zoomed_waveform_peaks.dart`
- Create: `test/presentation/providers/zoomed_waveform_peaks_test.dart`

- [ ] **Step 1: Write failing tests for `computeTileBounds`**

Create `test/presentation/providers/zoomed_waveform_peaks_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
import 'package:m4b_chapterizer/presentation/providers/zoomed_waveform_peaks.dart';

Audiobook _book(Duration totalDuration) => Audiobook.validated(
      chapters: const [Chapter(title: 'A', start: Duration.zero)],
      totalDuration: totalDuration,
    );

void main() {
  test('tile in the middle of the file', () {
    final book = _book(const Duration(seconds: 60));
    final key = WaveformTileKey(
      path: '/x.m4b',
      tileIndex: 2,
      viewportDurationMicros: 8 * 1000 * 1000,
      pixelsPerSecond: 100,
    );
    final b = computeTileBounds(book, key);
    // Unclamped: start = (2 - 1) * 8s = 8s; end = 8s + 24s = 32s.
    expect(b.start, const Duration(seconds: 8));
    expect(b.duration, const Duration(seconds: 24));
    expect(b.targetPeaks, 24 * 100);
  });

  test('tile clamped at the file start (tileIndex 0)', () {
    final book = _book(const Duration(seconds: 60));
    final key = WaveformTileKey(
      path: '/x.m4b',
      tileIndex: 0,
      viewportDurationMicros: 8 * 1000 * 1000,
      pixelsPerSecond: 100,
    );
    final b = computeTileBounds(book, key);
    // Unclamped start = -8s; clamped to 0s.
    // Unclamped end = 16s.
    expect(b.start, Duration.zero);
    expect(b.duration, const Duration(seconds: 16));
    expect(b.targetPeaks, 16 * 100);
  });

  test('tile clamped at the file end', () {
    final book = _book(const Duration(seconds: 30));
    final key = WaveformTileKey(
      path: '/x.m4b',
      tileIndex: 2,
      viewportDurationMicros: 8 * 1000 * 1000,
      pixelsPerSecond: 100,
    );
    final b = computeTileBounds(book, key);
    // Unclamped: start = 8s, end = 32s. End clamped to 30s.
    expect(b.start, const Duration(seconds: 8));
    expect(b.duration, const Duration(seconds: 22));
    expect(b.targetPeaks, 22 * 100);
  });

  test('tile entirely past the file end produces zero duration', () {
    final book = _book(const Duration(seconds: 5));
    final key = WaveformTileKey(
      path: '/x.m4b',
      tileIndex: 10,
      viewportDurationMicros: 8 * 1000 * 1000,
      pixelsPerSecond: 100,
    );
    final b = computeTileBounds(book, key);
    expect(b.duration, Duration.zero);
    expect(b.targetPeaks, 0);
  });

  test('WaveformTileKey equality and hashCode', () {
    final a = WaveformTileKey(
      path: '/x.m4b',
      tileIndex: 1,
      viewportDurationMicros: 8000000,
      pixelsPerSecond: 100,
    );
    final b = WaveformTileKey(
      path: '/x.m4b',
      tileIndex: 1,
      viewportDurationMicros: 8000000,
      pixelsPerSecond: 100,
    );
    final c = WaveformTileKey(
      path: '/x.m4b',
      tileIndex: 2,
      viewportDurationMicros: 8000000,
      pixelsPerSecond: 100,
    );
    expect(a, equals(b));
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(equals(c)));
  });
}
```

- [ ] **Step 2: Run tests; verify failure**

Run: `flutter test test/presentation/providers/zoomed_waveform_peaks_test.dart`
Expected: compile error — `zoomed_waveform_peaks.dart` doesn't exist.

- [ ] **Step 3: Implement the tile types, `computeTileBounds`, and the family provider**

Create `lib/presentation/providers/zoomed_waveform_peaks.dart`:

```dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../../data/waveform_extractor.dart';
import '../../domain/models/audiobook.dart';
import 'editor_state.dart';

@immutable
class WaveformTileKey {
  const WaveformTileKey({
    required this.path,
    required this.tileIndex,
    required this.viewportDurationMicros,
    required this.pixelsPerSecond,
  });

  final String path;
  final int tileIndex;
  final int viewportDurationMicros;
  final double pixelsPerSecond;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WaveformTileKey &&
          other.path == path &&
          other.tileIndex == tileIndex &&
          other.viewportDurationMicros == viewportDurationMicros &&
          other.pixelsPerSecond == pixelsPerSecond;

  @override
  int get hashCode =>
      Object.hash(path, tileIndex, viewportDurationMicros, pixelsPerSecond);
}

@immutable
class WaveformTilePeaks {
  const WaveformTilePeaks({
    required this.tileStart,
    required this.tileDuration,
    required this.peaks,
  });

  final Duration tileStart;
  final Duration tileDuration;
  final List<double> peaks;
}

@immutable
class TileBounds {
  const TileBounds({
    required this.start,
    required this.duration,
    required this.targetPeaks,
  });

  final Duration start;
  final Duration duration;
  final int targetPeaks;
}

/// Computes the actual tile range and per-pixel peak count for the
/// given key, clamped to the file's `[0, totalDuration]`.
TileBounds computeTileBounds(Audiobook book, WaveformTileKey key) {
  final viewportMicros = key.viewportDurationMicros;
  final unclampedStartMicros =
      key.tileIndex * viewportMicros - viewportMicros;
  final unclampedEndMicros = unclampedStartMicros + 3 * viewportMicros;
  final totalMicros = book.totalDuration.inMicroseconds;

  final startMicros =
      unclampedStartMicros < 0 ? 0 : unclampedStartMicros;
  final endMicros =
      unclampedEndMicros > totalMicros ? totalMicros : unclampedEndMicros;
  final durationMicros = endMicros - startMicros;
  if (durationMicros <= 0) {
    return TileBounds(
      start: Duration(microseconds: startMicros),
      duration: Duration.zero,
      targetPeaks: 0,
    );
  }
  final targetPeaks = (durationMicros /
          Duration.microsecondsPerSecond *
          key.pixelsPerSecond)
      .ceil();
  return TileBounds(
    start: Duration(microseconds: startMicros),
    duration: Duration(microseconds: durationMicros),
    targetPeaks: targetPeaks,
  );
}

/// Per-tile peaks for the zoomable waveform view. Tests override this
/// family to return canned `WaveformTilePeaks` instances; production
/// reads `binaryResolverProvider` and spawns ffmpeg.
final zoomedWaveformPeaksProvider =
    FutureProvider.family<WaveformTilePeaks, WaveformTileKey>(
  (ref, key) async {
    final book = ref.read(editorProvider).audiobook;
    if (book == null) {
      return const WaveformTilePeaks(
        tileStart: Duration.zero,
        tileDuration: Duration.zero,
        peaks: [],
      );
    }
    final bounds = computeTileBounds(book, key);
    if (bounds.targetPeaks <= 0) {
      return WaveformTilePeaks(
        tileStart: bounds.start,
        tileDuration: bounds.duration,
        peaks: const [],
      );
    }
    // coverage:ignore-start
    // Production wiring: a fresh extractor per tile so concurrent
    // tiles can't share cancel state. Tests override this whole
    // provider with `overrideWith((ref, key) async => ...)`.
    final extractor = WaveformExtractor(
      binaries: ref.read(binaryResolverProvider),
      processStarter: Process.start,
    );
    ref.onDispose(extractor.cancel);
    final peaks = await extractor.extractRange(
      path: key.path,
      start: bounds.start,
      duration: bounds.duration,
      targetPeaks: bounds.targetPeaks,
    );
    return WaveformTilePeaks(
      tileStart: bounds.start,
      tileDuration: bounds.duration,
      peaks: peaks,
    );
    // coverage:ignore-end
  },
);
```

- [ ] **Step 4: Run tests; verify pass**

Run: `flutter test test/presentation/providers/zoomed_waveform_peaks_test.dart`
Expected: 5 passing tests.

- [ ] **Step 5: Run full suite + analyzer**

Run: `flutter test`
Run: `flutter analyze`
Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/providers/zoomed_waveform_peaks.dart test/presentation/providers/zoomed_waveform_peaks_test.dart
git commit --no-gpg-sign -m "$(cat <<'EOF'
Add tile-based zoomedWaveformPeaksProvider

Family keyed on WaveformTileKey (path + tileIndex + viewportDuration +
pxPerSec). Each tile covers 3x the viewport width, aligned to
tileIndex * viewportDuration. computeTileBounds is a pure function
exported for unit-testing the clamping math; the provider's ffmpeg
spawning is coverage-ignored production wiring.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Switch `WaveformView` to the tile provider; add loading state

Replace the whole-file `waveformPeaksProvider` watch with `zoomedWaveformPeaksProvider`. Pass `WaveformTilePeaks` to the painter. Add the centered loading indicator. Update all 10 existing `waveform_view_test.dart` tests to override the new family provider, and add 2 new tests for the loading state.

**Files:**
- Modify: `lib/presentation/widgets/waveform_view.dart`
- Modify: `test/presentation/waveform_view_test.dart`

- [ ] **Step 1: Update existing test overrides + add 2 new loading tests**

Replace the existing `_pump` helper in `test/presentation/waveform_view_test.dart` with one that overrides the new family. The new helper takes a `tilePeaks` parameter (default empty) and an optional `loading` flag:

```dart
import 'package:m4b_chapterizer/presentation/providers/zoomed_waveform_peaks.dart';
// ... existing imports ...

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required _FakePlayback playback,
  WaveformTilePeaks? tilePeaks,
  bool loading = false,
}) async {
  // Default canned tile peaks: empty list, but with a real
  // tileStart/duration so the painter has valid coordinates.
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
      zoomedWaveformPeaksProvider.overrideWith(
        (ref, key) => loading
            ? Completer<WaveformTilePeaks>().future
            : Future.value(canned),
      ),
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
  await tester.pumpAndSettle();
  return container;
}
```

The override `(ref, key) => ...` is the family-wide form; any tile key resolves to the canned value (or the never-completing future for the loading case).

Remove the old `waveformPeaksProvider('/tmp/x.m4b')` and `'/tmp/y.m4b'` overrides from the helper (they're no longer needed — `WaveformView` doesn't read that provider after this task).

Add these two new tests inside `void main() { ... }`:

```dart
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
    // Default loading=false, default canned tilePeaks resolves immediately.

    expect(find.text('Generating waveform…'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
```

The existing `viewport resets when file path changes` test changes `path` to `/tmp/y.m4b`; the family override above resolves any tile key for any path, so it still works. No further changes needed in that test.

The existing `tap seeks the playhead to that time` test uses a tap at `(200, 60)` to assert seek to ~2s. That assumes the default zoom (100 px/s) and viewport (800 px) — both unchanged by this task. The test should still pass.

- [ ] **Step 2: Run tests; verify failure**

Run: `flutter test test/presentation/waveform_view_test.dart`
Expected: 12 tests; existing 10 fail because `WaveformView` still reads `waveformPeaksProvider` (which the helper no longer overrides), and the 2 new loading tests fail because the loading UI doesn't exist.

- [ ] **Step 3: Update `WaveformView` to read the tile provider and render loading UI**

Replace `_WaveformViewState`'s `build` body so it reads `zoomedWaveformPeaksProvider` instead of `waveformPeaksProvider`, computes the tile key from current viewport state, and renders a loading overlay when the tile's `AsyncValue` is in the loading state.

The full `lib/presentation/widgets/waveform_view.dart` becomes:

```dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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

class _WaveformViewState extends ConsumerState<WaveformView> {
  StreamSubscription<Duration>? _positionSub;
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

  @override
  Widget build(BuildContext context) {
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

    final viewport = ref.watch(waveformViewportProvider);
    final controller = ref.watch(playbackControllerProvider);
    final viewportNotifier = ref.read(waveformViewportProvider.notifier);

    return SizedBox(
      height: WaveformView.height,
      child: LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        _latestViewportWidth = width;

        // Compute the tile key from the current viewport.
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
        final tile = tileAsync.maybeWhen(
          data: (t) => t,
          orElse: () => const WaveformTilePeaks(
            tileStart: Duration.zero,
            tileDuration: Duration.zero,
            peaks: [],
          ),
        );

        return Stack(
          children: [
            Positioned.fill(
              child: StreamBuilder<Duration>(
                stream: controller.positionStream,
                initialData: controller.position,
                builder: (context, snapshot) {
                  final playhead = snapshot.data ?? controller.position;
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
                          tile: tile,
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
            if (tileAsync.isLoading)
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

    if (tile.peaks.isNotEmpty && tile.tileDuration > Duration.zero) {
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
```

Note: the painter compares `old.tile != tile`. `WaveformTilePeaks` doesn't override `==` — that's intentional. Identity comparison is sufficient because Riverpod hands a stable instance per tile-key resolution. (If a future change starts producing new instances with the same data on every rebuild, add `==`/`hashCode` then.)

- [ ] **Step 4: Run tests; verify pass**

Run: `flutter test test/presentation/waveform_view_test.dart`
Expected: 12 passing tests.

- [ ] **Step 5: Run full suite + analyzer**

Run: `flutter test`
Run: `flutter analyze`
Expected: all green.

- [ ] **Step 6: Build macOS**

Run: `flutter build macos --debug`
Expected: clean build.

- [ ] **Step 7: Commit**

```bash
git add lib/presentation/widgets/waveform_view.dart test/presentation/waveform_view_test.dart
git commit --no-gpg-sign -m "$(cat <<'EOF'
Switch WaveformView to tile-based peaks; add loading state

WaveformView now reads zoomedWaveformPeaksProvider keyed on the tile
containing the current viewport (3x viewport width, aligned to
viewportDuration boundaries). Painter takes WaveformTilePeaks and
maps viewport pixels to tile bin indices. While the active tile is
loading, a centered "Generating waveform…" indicator overlays the
empty body.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Ensure-visible on seek while paused

The `_onPosition` listener already accepts a paused-state branch from Task 3. Add tests proving it re-anchors the viewport when the new playhead is outside the window, and stays put when the new playhead is inside.

**Files:**
- Modify: `test/presentation/waveform_view_test.dart`

(No production-code change required — Task 3's `_onPosition` already implements ensure-visible. This task adds the test coverage that verifies it.)

- [ ] **Step 1: Append failing tests**

Add inside `void main() { ... }`:

```dart
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
```

- [ ] **Step 2: Run tests**

Run: `flutter test test/presentation/waveform_view_test.dart`
Expected: 15 passing tests (the 3 new ones pass because Task 3 already implemented the ensure-visible behavior).

- [ ] **Step 3: Run full suite + analyzer**

Run: `flutter test`
Run: `flutter analyze`
Expected: all green.

- [ ] **Step 4: Commit**

```bash
git add test/presentation/waveform_view_test.dart
git commit --no-gpg-sign -m "$(cat <<'EOF'
Test ensure-visible on seek while paused

Verifies that an external seek (e.g. clicking the thin overview
scrubber) re-anchors the zoomed viewport when the new playhead is
outside the current window, and leaves the viewport untouched when
the new playhead is already visible.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Verification

After all tasks land:

- [ ] **Final test run**

Run: `flutter test`
Expected: 229 prior tests + 3 new extractRange + 5 new tile-bounds + 2 loading + 3 ensure-visible = 242 tests passing.

- [ ] **Final analyzer**

Run: `flutter analyze`
Expected: no issues.

- [ ] **Coverage**

Run: `flutter test --coverage`
Run: `dart tool/coverage_summary.dart coverage/lcov.info`
Expected: total stays at or above the previous baseline (~98 %).

- [ ] **macOS smoke test** — walk through the 7 cases in the spec's "Smoke-test plan" section.
