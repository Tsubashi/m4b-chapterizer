# Audio Waveform Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `ChapterScrubber`'s plain track with an amplitude waveform of the audio, computed in the background after file open and rendered when ready.

**Architecture:** A `WaveformExtractor` streams ffmpeg-decoded mono 8 kHz PCM into ~4096 normalized peaks. A `FutureProvider.family<List<double>, String>` keyed on path computes per-file in the background, with auto-cancel on file change. The existing `ChapterScrubber` gains an optional `peaks` parameter and a waveform-rendering branch.

**Tech Stack:** Bundled ffmpeg (no new packages), Riverpod `FutureProvider.family`, Flutter `CustomPainter`.

**Reference design:** `docs/superpowers/specs/2026-05-01-audio-waveform-design.md`

**Conventions:**
- `--no-gpg-sign` REQUIRED on every `git commit`.
- After every task, run `flutter test` and `flutter analyze` before committing.
- The plan assumes `dart run tool/fetch_ffmpeg.dart` has been run on the developer's machine; tests fail loudly if it hasn't.

---

## Task 1: Bundled-binary test helper + deskip the existing integration test

Establishes the test-side resolver pointing to `assets/bin/<platform>/`, then removes the now-obsolete `_ffmpegOnPath()` skip from `ffmpeg_bookbinder_integration_test.dart`. This is a foundational cleanup that the waveform integration test (Task 3) depends on.

**Files:**
- Create: `test/helpers/bundled_test_resolver.dart`
- Modify: `test/data/ffmpeg_bookbinder_integration_test.dart`

- [ ] **Step 1: Implement the helper**

Create `test/helpers/bundled_test_resolver.dart`:

```dart
import 'dart:io';

import 'package:m4b_chapterizer/data/binary_resolver.dart';

/// Returns a [BinaryResolver] pointing to `assets/bin/<platform>/`.
/// Used by integration tests so they exercise the same ffmpeg version that
/// ships in the production .app bundle.
///
/// Throws [StateError] with a clear remediation message if the bundled
/// binaries don't exist (developer hasn't run `dart run tool/fetch_ffmpeg.dart`).
BinaryResolver bundledTestResolver() {
  final key = _platformKey();
  final exeSuffix = Platform.isWindows ? '.exe' : '';
  final ffmpeg = 'assets/bin/$key/ffmpeg$exeSuffix';
  final ffprobe = 'assets/bin/$key/ffprobe$exeSuffix';
  for (final p in [ffmpeg, ffprobe]) {
    if (!File(p).existsSync()) {
      throw StateError(
        '$p not found. Run: dart run tool/fetch_ffmpeg.dart',
      );
    }
  }
  return FixedBinaryResolver(ffmpeg: ffmpeg, ffprobe: ffprobe);
}

String _platformKey() {
  if (Platform.isMacOS) {
    return Platform.version.contains('arm64') ? 'macos-arm64' : 'macos-x64';
  }
  if (Platform.isWindows) return 'windows-x64';
  if (Platform.isLinux) return 'linux-x64';
  throw UnsupportedError('Unsupported: ${Platform.operatingSystem}');
}
```

- [ ] **Step 2: Update the bookbinder integration test**

Open `test/data/ffmpeg_bookbinder_integration_test.dart` and replace its contents with:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/data/ffmpeg_bookbinder.dart';
import 'package:m4b_chapterizer/data/process_runner.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';

import '../helpers/bundled_test_resolver.dart';

void main() {
  test('read → mutate → write → read round-trip preserves chapters and metadata',
      () async {
    final bookbinder = FfmpegBookbinder(
      runner: const SystemProcessRunner(),
      binaries: bundledTestResolver(),
    );

    final tempDir = await Directory.systemTemp.createTemp('m4b-rt-');
    addTearDown(() => tempDir.delete(recursive: true));
    final workCopy = '${tempDir.path}/work.m4b';
    await File('test/fixtures/sample.m4b').copy(workCopy);

    final original = await bookbinder.read(workCopy);
    expect(original.title, 'A Test Book');
    expect(original.chapters.length, 3);
    expect(original.cover, isNotNull);

    final mutated = original.copyWith(
      title: 'Mutated Title',
      chapters: [
        const Chapter(title: 'Renamed', start: Duration.zero),
        original.chapters[1],
        original.chapters[2],
      ],
    );

    await bookbinder.write(
      sourcePath: workCopy,
      destinationPath: workCopy,
      audiobook: mutated,
    );

    final reread = await bookbinder.read(workCopy);
    expect(reread.title, 'Mutated Title');
    expect(reread.chapters[0].title, 'Renamed');
    expect(reread.chapters.length, 3);
    expect(reread.cover, isNotNull);
    expect(reread.totalDuration, original.totalDuration);
  });
}
```

This deletes the `_ffmpegOnPath()` function and the early-return `skip: true` block. The test now always runs; if the bundled binaries are missing, it fails at setup with the helper's `StateError`.

- [ ] **Step 3: Run the test**

Run: `flutter test test/data/ffmpeg_bookbinder_integration_test.dart`
Expected: pass.

- [ ] **Step 4: Run full suite and analyzer**

Run: `flutter test`
Expected: all tests pass.

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add test/helpers/bundled_test_resolver.dart test/data/ffmpeg_bookbinder_integration_test.dart
git commit --no-gpg-sign -m "Use bundled ffmpeg in integration tests; remove on-PATH skip"
```

---

## Task 2: `WaveformExtractor` with unit tests

Implements the streaming PCM-to-peaks extractor with a fake `processStarter`, no real ffmpeg involved.

**Files:**
- Create: `lib/data/waveform_extractor.dart`
- Create: `test/data/waveform_extractor_test.dart`

- [ ] **Step 1: Write the failing tests with a `_MockProcess` helper**

Create `test/data/waveform_extractor_test.dart`:

```dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/data/binary_resolver.dart';
import 'package:m4b_chapterizer/data/waveform_extractor.dart';

class _MockProcess implements Process {
  _MockProcess({
    required this.stdout,
    required Future<int> exitCode,
    this.onKill,
  }) : _exitCode = exitCode;

  @override
  final Stream<List<int>> stdout;

  final Future<int> _exitCode;
  @override
  Future<int> get exitCode => _exitCode;

  final void Function()? onKill;

  bool killed = false;

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  IOSink get stdin => throw UnimplementedError();

  @override
  int get pid => 0;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    onKill?.call();
    return true;
  }
}

/// Builds a single PCM sample as little-endian int16 bytes.
List<int> _le16(int sample) {
  final clamped = sample & 0xFFFF;
  return [clamped & 0xFF, (clamped >> 8) & 0xFF];
}

List<int> _samples(List<int> values) =>
    [for (final v in values) ..._le16(v)];

void main() {
  const binaries = FixedBinaryResolver(ffmpeg: '/x/ffmpeg', ffprobe: '/x/ffprobe');

  group('WaveformExtractor.extract', () {
    test('bins synthetic PCM into the requested number of peaks', () async {
      // 32_000 samples at constant amplitude 16384. With 4 s totalDuration and
      // targetPeaks=10: samplesPerBin = 4 * 8000 / 10 = 3200. We supply exactly
      // 10 bins worth.
      final samples = List.filled(32000, 16384);
      final bytes = _samples(samples);

      final extractor = WaveformExtractor(
        binaries: binaries,
        processStarter: (exe, args) async => _MockProcess(
          stdout: Stream.value(bytes),
          exitCode: Future.value(0),
        ),
      );

      final peaks = await extractor.extract(
        path: '/x.m4b',
        totalDuration: const Duration(seconds: 4),
        targetPeaks: 10,
      );

      expect(peaks.length, 10);
      for (final p in peaks) {
        expect(p, closeTo(0.5, 1e-6));
      }
    });

    test('reports max-abs per bin', () async {
      // One bin's worth of samples (16, given samplesPerBin=16): 14 zeros, one
      // +16383 and one -16383. The peak should be ~0.5.
      final samples = <int>[
        ...List.filled(7, 0),
        16383,
        -16383,
        ...List.filled(7, 0),
      ];
      final bytes = _samples(samples);

      final extractor = WaveformExtractor(
        binaries: binaries,
        processStarter: (exe, args) async => _MockProcess(
          stdout: Stream.value(bytes),
          exitCode: Future.value(0),
        ),
      );

      final peaks = await extractor.extract(
        path: '/x.m4b',
        totalDuration: const Duration(milliseconds: 2),
        targetPeaks: 1,
      );

      expect(peaks.length, 1);
      expect(peaks.first, closeTo(16383 / 32768, 1e-6));
    });

    test('handles odd-byte chunk boundaries (carry buffer)', () async {
      // Two int16 samples = 4 bytes. Emit them as [byte1], [byte2,byte3,byte4].
      final fullBytes = _samples([16384, 16384]);
      final controller = StreamController<List<int>>();
      controller.add([fullBytes[0]]);
      controller.add([fullBytes[1], fullBytes[2], fullBytes[3]]);
      await controller.close();

      final extractor = WaveformExtractor(
        binaries: binaries,
        processStarter: (exe, args) async => _MockProcess(
          stdout: controller.stream,
          exitCode: Future.value(0),
        ),
      );

      final peaks = await extractor.extract(
        path: '/x.m4b',
        totalDuration: const Duration(microseconds: 250),
        targetPeaks: 1,
      );

      expect(peaks.length, 1);
      expect(peaks.first, closeTo(0.5, 1e-6));
    });

    test('cancellation kills the process and throws WaveformCancelled',
        () async {
      final controller = StreamController<List<int>>();
      final exitCompleter = Completer<int>();
      late _MockProcess mock;
      mock = _MockProcess(
        stdout: controller.stream,
        exitCode: exitCompleter.future,
        onKill: () {
          controller.close();
          if (!exitCompleter.isCompleted) exitCompleter.complete(143);
        },
      );

      final extractor = WaveformExtractor(
        binaries: binaries,
        processStarter: (exe, args) async => mock,
      );

      // Start extracting; emit a few bytes; then cancel.
      final future = extractor.extract(
        path: '/x.m4b',
        totalDuration: const Duration(seconds: 1),
        targetPeaks: 100,
      );
      // Let extract get to its await for loop.
      await Future<void>.delayed(Duration.zero);
      controller.add(_samples([0, 0, 0, 0]));
      await Future<void>.delayed(Duration.zero);
      extractor.cancel();

      expect(future, throwsA(isA<WaveformCancelled>()));
      // Sanity: kill was invoked.
      await Future<void>.delayed(Duration.zero);
      expect(mock.killed, isTrue);
    });

    test('throws StateError if ffmpeg exits with a non-zero code', () async {
      final extractor = WaveformExtractor(
        binaries: binaries,
        processStarter: (exe, args) async => _MockProcess(
          stdout: const Stream.empty(),
          exitCode: Future.value(1),
        ),
      );

      expect(
        extractor.extract(
          path: '/x.m4b',
          totalDuration: const Duration(seconds: 1),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
```

- [ ] **Step 2: Run, see failures**

Run: `flutter test test/data/waveform_extractor_test.dart`
Expected: FAIL — `WaveformExtractor` doesn't exist.

- [ ] **Step 3: Implement `WaveformExtractor`**

Create `lib/data/waveform_extractor.dart`:

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

  Future<List<double>> extract({
    required String path,
    required Duration totalDuration,
    int targetPeaks = 4096,
  }) async {
    final totalSamples =
        (totalDuration.inMicroseconds * 8000) ~/ Duration.microsecondsPerSecond;
    var samplesPerBin = totalSamples ~/ targetPeaks;
    if (samplesPerBin < 1) samplesPerBin = 1;

    final process = await processStarter(binaries.ffmpeg, [
      '-loglevel', 'error',
      '-i', path,
      '-map', '0:a',
      '-f', 's16le',
      '-ac', '1',
      '-ar', '8000',
      '-',
    ]);
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
          bytes = [carryByte!, ...chunk];
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

- [ ] **Step 4: Run tests**

Run: `flutter test test/data/waveform_extractor_test.dart`
Expected: all 5 tests pass.

- [ ] **Step 5: Run analyzer**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/data/waveform_extractor.dart test/data/waveform_extractor_test.dart
git commit --no-gpg-sign -m "Add WaveformExtractor with PCM-to-peaks streaming"
```

---

## Task 3: Real-ffmpeg integration test for `WaveformExtractor`

Verifies the full pipeline against the silent fixture m4b using the bundled ffmpeg.

**Files:**
- Create: `test/data/waveform_extractor_integration_test.dart`

- [ ] **Step 1: Write the test**

Create `test/data/waveform_extractor_integration_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/data/waveform_extractor.dart';

import '../helpers/bundled_test_resolver.dart';

void main() {
  test('extracts near-zero peaks from the silent fixture m4b', () async {
    final extractor = WaveformExtractor(
      binaries: bundledTestResolver(),
      processStarter: Process.start,
    );

    final peaks = await extractor.extract(
      path: 'test/fixtures/sample.m4b',
      totalDuration: const Duration(seconds: 30),
      targetPeaks: 4096,
    );

    // Bin alignment may leave a partial final bin; allow a small range.
    expect(peaks.length, inInclusiveRange(4090, 4096));
    final maxPeak = peaks.fold<double>(0, (a, b) => a > b ? a : b);
    expect(
      maxPeak,
      lessThan(0.05),
      reason:
          'silent fixture should produce near-zero peaks; max peak was $maxPeak',
    );
  });
}
```

- [ ] **Step 2: Run the test**

Run: `flutter test test/data/waveform_extractor_integration_test.dart`
Expected: pass. Confirms the bundled ffmpeg invocation produces the expected PCM stream and the extractor processes it correctly.

- [ ] **Step 3: Run full suite**

Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add test/data/waveform_extractor_integration_test.dart
git commit --no-gpg-sign -m "Add WaveformExtractor real-ffmpeg integration test"
```

---

## Task 4: `binaryResolverProvider` and `waveformPeaksProvider`

Hoists the `BinaryResolver` to a top-level Riverpod provider and adds the family-keyed waveform provider that consumes it.

**Files:**
- Create: `lib/presentation/providers/waveform.dart`
- Modify: `lib/presentation/providers/editor_state.dart` (add `binaryResolverProvider`)
- Modify: `lib/main.dart`

- [ ] **Step 1: Add `binaryResolverProvider`**

In `lib/presentation/providers/editor_state.dart`, alongside `bookbinderProvider`, add:

```dart
final binaryResolverProvider = Provider<BinaryResolver>((ref) {
  throw StateError(
    'binaryResolverProvider must be overridden at the app or test scope',
  );
});
```

Add the import at the top of the file:

```dart
import '../../data/binary_resolver.dart';
```

- [ ] **Step 2: Implement the waveform provider**

Create `lib/presentation/providers/waveform.dart`:

```dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/waveform_extractor.dart';
import 'editor_state.dart';

/// Computes amplitude peaks for the audio at [path] in the background.
/// Errors and "still loading" both render as an empty peak list at the UI.
final waveformPeaksProvider =
    FutureProvider.family<List<double>, String>((ref, path) async {
  final book = ref.watch(editorProvider).audiobook;
  if (book == null) return <double>[];

  final extractor = WaveformExtractor(
    binaries: ref.read(binaryResolverProvider),
    processStarter: Process.start,
  );
  ref.onDispose(extractor.cancel);

  return extractor.extract(path: path, totalDuration: book.totalDuration);
});
```

- [ ] **Step 3: Wire `binaryResolverProvider` in `main.dart`**

Open `lib/main.dart`. Replace the `runApp` call so the resolver is overridden once and the bookbinder reads it:

```dart
void main() {
  final resolver = BundledBinaryResolver();
  runApp(
    ProviderScope(
      overrides: [
        binaryResolverProvider.overrideWithValue(resolver),
        bookbinderProvider.overrideWithValue(
          FfmpegBookbinder(
            runner: const SystemProcessRunner(),
            binaries: resolver,
          ),
        ),
      ],
      child: const M4bChapterizerApp(),
    ),
  );
}
```

(The original was constructing the resolver inline; now it's hoisted into a local variable and registered as a provider override too.)

- [ ] **Step 4: Run all tests**

Run: `flutter test`
Expected: all existing tests pass. (No new test in this task; the provider is exercised in Task 6.)

- [ ] **Step 5: Run analyzer**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/providers/waveform.dart lib/presentation/providers/editor_state.dart lib/main.dart
git commit --no-gpg-sign -m "Add binaryResolverProvider and waveformPeaksProvider"
```

---

## Task 5: `ChapterScrubber` waveform rendering

Adds the `peaks` parameter and the painter branch that renders the waveform when peaks are non-empty.

**Files:**
- Modify: `lib/presentation/widgets/chapter_scrubber.dart`
- Modify: `test/presentation/chapter_scrubber_test.dart`

- [ ] **Step 1: Append failing tests**

Append to the end of `test/presentation/chapter_scrubber_test.dart`'s `main()`:

```dart
  group('ChapterScrubber waveform rendering', () {
    testWidgets('renders without exception when peaks are provided',
        (tester) async {
      await tester.pumpWidget(_harness(
        peaks: const [0.0, 0.5, 1.0, 0.5, 0.0],
      ));
      expect(find.byType(ChapterScrubber), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('snap-to-tick still works when peaks are present',
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
        peaks: const [0.0, 0.5, 1.0, 0.5, 0.0, 0.5, 0.0],
        onSeek: (d) => seeked = d,
        width: 400,
      ));

      final scrubber = find.byType(ChapterScrubber);
      final topLeft = tester.getTopLeft(scrubber);
      final size = tester.getSize(scrubber);
      const usable = 400 - 24;
      const padding = 12;
      const expectedX = padding + (30 / 100) * usable;
      // Tap 4px right of the chapter-2 tick → within snap radius.
      await tester.tapAt(
        topLeft + Offset(expectedX + 4, size.height / 2),
      );
      await tester.pump();
      expect(seeked, chapter2Start);
    });
  });
```

The `_harness` helper at the top of the file accepts `peaks` already? It doesn't — extend it. Find the existing helper and add the parameter:

```dart
Widget _harness({
  Duration position = Duration.zero,
  Duration totalDuration = const Duration(seconds: 100),
  List<Duration> chapterStarts = const [],
  ValueChanged<Duration>? onSeek,
  double width = 400,
  List<double>? peaks,
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
            peaks: peaks,
          ),
        ),
      ),
    ),
  );
}
```

- [ ] **Step 2: Run, see failures**

Run: `flutter test test/presentation/chapter_scrubber_test.dart`
Expected: 2 new failures — the `peaks` parameter doesn't exist on `ChapterScrubber`.

- [ ] **Step 3: Add `peaks` to the widget and painter**

In `lib/presentation/widgets/chapter_scrubber.dart`, modify `ChapterScrubber`:

```dart
class ChapterScrubber extends StatefulWidget {
  const ChapterScrubber({
    super.key,
    required this.position,
    required this.totalDuration,
    required this.chapterStarts,
    required this.onSeek,
    this.peaks,
  });

  final Duration position;
  final Duration totalDuration;
  final List<Duration> chapterStarts;
  final ValueChanged<Duration> onSeek;
  final List<double>? peaks;

  @override
  State<ChapterScrubber> createState() => _ChapterScrubberState();
}
```

In `_ChapterScrubberState.build`, pass `peaks` to the painter:

```dart
            painter: _ScrubberPainter(
              position: _displayedPosition(),
              totalDuration: widget.totalDuration,
              chapterStarts: widget.chapterStarts,
              peaks: widget.peaks ?? const [],
              trackColor: scheme.surfaceContainerHighest,
              fillColor: scheme.primary,
              tickColor: scheme.outline,
              playheadColor: scheme.primary,
              waveformPlayedColor: scheme.primary,
              waveformUnplayedColor: scheme.outlineVariant,
              trackHeight: _trackHeight,
              tickHeight: _tickHeight,
              playheadDiameter: _playheadDiameter,
              horizontalPadding: _horizontalPadding,
            ),
```

In `_ScrubberPainter`, add fields and modify the `paint` method:

```dart
class _ScrubberPainter extends CustomPainter {
  _ScrubberPainter({
    required this.position,
    required this.totalDuration,
    required this.chapterStarts,
    required this.peaks,
    required this.trackColor,
    required this.fillColor,
    required this.tickColor,
    required this.playheadColor,
    required this.waveformPlayedColor,
    required this.waveformUnplayedColor,
    required this.trackHeight,
    required this.tickHeight,
    required this.playheadDiameter,
    required this.horizontalPadding,
  });

  final Duration position;
  final Duration totalDuration;
  final List<Duration> chapterStarts;
  final List<double> peaks;
  final Color trackColor;
  final Color fillColor;
  final Color tickColor;
  final Color playheadColor;
  final Color waveformPlayedColor;
  final Color waveformUnplayedColor;
  final double trackHeight;
  final double tickHeight;
  final double playheadDiameter;
  final double horizontalPadding;

  static const double _waveformHalfHeight = 10;

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

    if (peaks.isEmpty) {
      _paintPlainTrack(canvas, size, centerY, playheadX);
    } else {
      _paintWaveform(canvas, size, centerY, playheadX);
    }

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

  void _paintPlainTrack(
      Canvas canvas, Size size, double centerY, double playheadX) {
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
  }

  void _paintWaveform(
      Canvas canvas, Size size, double centerY, double playheadX) {
    final usableLeft = horizontalPadding;
    final usableRight = size.width - horizontalPadding;
    final usableWidth = usableRight - usableLeft;
    if (usableWidth <= 0) return;

    final played = Paint()
      ..color = waveformPlayedColor
      ..strokeWidth = 1;
    final unplayed = Paint()
      ..color = waveformUnplayedColor
      ..strokeWidth = 1;

    final pixelCount = usableWidth.ceil();
    for (var px = 0; px < pixelCount; px++) {
      final x = usableLeft + px.toDouble();
      final fraction = px / usableWidth;
      var binIndex = (fraction * peaks.length).floor();
      if (binIndex >= peaks.length) binIndex = peaks.length - 1;
      final peak = peaks[binIndex];
      final h = peak * _waveformHalfHeight;
      canvas.drawLine(
        Offset(x, centerY - h),
        Offset(x, centerY + h),
        x <= playheadX ? played : unplayed,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScrubberPainter old) =>
      old.position != position ||
      old.totalDuration != totalDuration ||
      old.chapterStarts != chapterStarts ||
      old.peaks != peaks ||
      old.trackColor != trackColor ||
      old.fillColor != fillColor ||
      old.tickColor != tickColor ||
      old.playheadColor != playheadColor ||
      old.waveformPlayedColor != waveformPlayedColor ||
      old.waveformUnplayedColor != waveformUnplayedColor;
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/presentation/chapter_scrubber_test.dart`
Expected: all tests pass (existing + 2 new).

- [ ] **Step 5: Run analyzer**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/widgets/chapter_scrubber.dart test/presentation/chapter_scrubber_test.dart
git commit --no-gpg-sign -m "Add waveform rendering branch to ChapterScrubber"
```

---

## Task 6: `PlaybackControls` consumes the waveform provider

Wires the waveform provider into `PlaybackControls` so the scrubber receives peaks when ready.

**Files:**
- Modify: `lib/presentation/widgets/playback_controls.dart`
- Modify: `test/presentation/playback_controls_test.dart`

- [ ] **Step 1: Append failing tests**

Append to the end of `test/presentation/playback_controls_test.dart`'s `main()`:

```dart
  testWidgets('ChapterScrubber receives peaks from waveformPeaksProvider',
      (tester) async {
    final fake = _StubBookbinder();
    final fakePlayback = _FakePlayback();
    const peaks = [0.0, 1.0, 0.0];
    final container = ProviderContainer(
      overrides: [
        bookbinderProvider.overrideWithValue(fake),
        playbackControllerProvider.overrideWithValue(fakePlayback),
        waveformPeaksProvider('/tmp/x.m4b')
            .overrideWith((ref) async => peaks),
      ],
    );
    await container.read(editorProvider.notifier).open('/tmp/x.m4b');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: PlaybackControls())),
    ));
    await tester.pumpAndSettle();

    final scrubber =
        tester.widget<ChapterScrubber>(find.byType(ChapterScrubber));
    expect(scrubber.peaks, peaks);
  });

  testWidgets('ChapterScrubber receives empty peaks while loading',
      (tester) async {
    final fake = _StubBookbinder();
    final fakePlayback = _FakePlayback();
    final container = ProviderContainer(
      overrides: [
        bookbinderProvider.overrideWithValue(fake),
        playbackControllerProvider.overrideWithValue(fakePlayback),
        waveformPeaksProvider('/tmp/x.m4b').overrideWith(
          (ref) => Completer<List<double>>().future, // never completes
        ),
      ],
    );
    await container.read(editorProvider.notifier).open('/tmp/x.m4b');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: PlaybackControls())),
    ));
    await tester.pump();

    final scrubber =
        tester.widget<ChapterScrubber>(find.byType(ChapterScrubber));
    expect(scrubber.peaks, isEmpty);
  });
```

Add the imports if not already present in this test file:

```dart
import 'dart:async';

import 'package:m4b_chapterizer/presentation/providers/waveform.dart';
```

- [ ] **Step 2: Run, see failures**

Run: `flutter test test/presentation/playback_controls_test.dart`
Expected: 2 new failures — `PlaybackControls` doesn't read the waveform provider.

- [ ] **Step 3: Wire the waveform provider in `PlaybackControls`**

Modify `lib/presentation/widgets/playback_controls.dart`. Add the import at the top:

```dart
import '../providers/waveform.dart';
```

In the `build` method, between reading `editorProvider` and the existing `if (book != null)` `StreamBuilder`, compute the peaks list:

```dart
    final state = ref.watch(editorProvider);
    final notifier = ref.read(editorProvider.notifier);
    final selectedIndex = ref.watch(selectedChapterProvider);
    final book = state.audiobook;

    final peaksAsync = state.path == null
        ? const AsyncValue<List<double>>.data(<double>[])
        : ref.watch(waveformPeaksProvider(state.path!));
    final peaks = peaksAsync.maybeWhen(
      data: (p) => p,
      orElse: () => const <double>[],
    );
```

Then update the `ChapterScrubber` construction inside the `StreamBuilder` to pass `peaks`:

```dart
                return ChapterScrubber(
                  position: snapshot.data ?? controller.position,
                  totalDuration: book.totalDuration,
                  chapterStarts: [for (final c in book.chapters) c.start],
                  onSeek: controller.seek,
                  peaks: peaks,
                );
```

- [ ] **Step 4: Run all tests**

Run: `flutter test`
Expected: every test passes.

- [ ] **Step 5: Run analyzer**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Smoke-test on macOS**

```bash
flutter run -d macos
```

Open `test/fixtures/sample.m4b`. Verify:
- The plain track appears immediately on file open.
- Within ~1 second the waveform renders (peaks should be near-flat for the silent fixture, but the visual height expands from 4px to ~20px — confirming the swap happened).
- Tap and drag continue to work.
- Chapter ticks remain visible on top of the waveform.

For a richer visual check, point the app at a real audiobook file with non-silent audio.

- [ ] **Step 7: Commit**

```bash
git add lib/presentation/widgets/playback_controls.dart test/presentation/playback_controls_test.dart
git commit --no-gpg-sign -m "Wire waveformPeaksProvider into PlaybackControls"
```

---

## Final verification

- [ ] `flutter test` — all tests green.
- [ ] `flutter analyze` — clean.
- [ ] macOS smoke test (Task 6 Step 6) confirms the plain-then-waveform behavior.
