# Audio Waveform Display — Design

**Date:** 2026-05-01
**Status:** Approved (brainstorming phase)

## Overview

Replace the `ChapterScrubber`'s plain horizontal track with an amplitude waveform of the audio. Compute happens in the background after file open; the scrubber shows the plain track until peaks are ready, then swaps in the waveform. No caching — the user accepted re-computing on each open.

This change also removes the `_ffmpegOnPath()` skip gate from the existing `FfmpegBookbinder` integration test and the new waveform integration test, since we now bundle ffmpeg.

## Goals

- Visualize the entire audiobook's amplitude on the existing `ChapterScrubber`
- Compute peaks asynchronously in the background; UI is never blocked
- Cancel an in-progress compute when the user opens a different file
- Same gestures, ticks, and playhead behavior as the plain scrubber
- Tests cover the binning math, real-ffmpeg extraction, and rendering

## Non-goals

- Caching peaks to disk (sidecar files, content-hashed cache)
- Zoom or pan within the waveform
- Stereo channel rendering (mono peaks only)
- Animated transition from plain track to waveform
- Showing playback amplitude in real time (the displayed waveform is a static overview of the whole file)

## Data extraction

A new `WaveformExtractor` in `lib/data/waveform_extractor.dart`:

```dart
class WaveformExtractor {
  WaveformExtractor({required this.binaries, required this.processStarter});

  final BinaryResolver binaries;
  final Future<Process> Function(String exe, List<String> args) processStarter;

  /// Spawns ffmpeg, streams its PCM output, and returns one normalized peak
  /// per output bin. Each peak is `max(abs(sample)) / 32768` over its bin.
  Future<List<double>> extract({
    required String path,
    required Duration totalDuration,
    int targetPeaks = 4096,
  });

  /// Kills any in-flight ffmpeg process. Causes a pending [extract] future
  /// to throw [WaveformCancelled].
  void cancel();
}

class WaveformCancelled implements Exception {
  const WaveformCancelled();
}
```

The ffmpeg invocation:

```
<ffmpeg> -loglevel error -i <path> -map 0:a -f s16le -ac 1 -ar 8000 -
```

This produces 16-bit signed little-endian mono PCM at 8 kHz on stdout. The extractor:

1. Computes `samplesPerBin = (totalDuration.inMicroseconds * 8000 / 1_000_000) ~/ targetPeaks`. For very short files this could round to 0; clamp to 1.
2. Subscribes to `process.stdout`, reading byte chunks.
3. Maintains a small carry-over buffer (1 byte) to handle int16 boundaries that don't align with chunk boundaries.
4. For each int16 sample (little-endian, two-byte read), updates the running max for the current bin. When `samplesPerBin` samples have been seen, emits the bin's normalized max into the result list and resets.
5. After ffmpeg's stdout closes, emits the partial final bin (if any) and returns the result list. The list length is `targetPeaks` or `targetPeaks - 1` depending on whether the final bin had any samples.

`processStarter` is injected so unit tests pass a fake that emits canned bytes — no real ffmpeg needed.

`cancel()` keeps a reference to the active `Process` and calls `process.kill()`. The streaming subscription's error handler throws `WaveformCancelled` from the `extract` future.

## Lifecycle and Riverpod wiring

A new top-level `binaryResolverProvider` in `lib/presentation/providers/editor_state.dart` (or a new `binary_resolver_provider.dart`) hoists the `BinaryResolver` so multiple consumers can read it:

```dart
final binaryResolverProvider = Provider<BinaryResolver>((ref) {
  throw StateError('binaryResolverProvider must be overridden at app or test scope');
});
```

`main.dart` overrides it to a `BundledBinaryResolver()`. The existing `bookbinderProvider` override consumes `ref.read(binaryResolverProvider)` for its `FfmpegBookbinder`. Tests that wire `bookbinderProvider` already inject their own `Bookbinder`; for tests of the waveform path, we override `binaryResolverProvider` directly with `bundledTestResolver()`.

A new `lib/presentation/providers/waveform.dart`:

```dart
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

The family is keyed on `path`. When the user opens a different file, the new `path` value yields a new family entry; the old entry is auto-disposed by Riverpod, calling `extractor.cancel()` on it, which kills the in-flight ffmpeg.

## Rendering

`ChapterScrubber` gains an optional `peaks` parameter:

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

  final List<double>? peaks;
}
```

In the painter:

- **`peaks == null` or empty** → render exactly as today (4 px solid track, fill, ticks, playhead).
- **`peaks` non-empty** → for each output pixel `x` in `[padding, width - padding]`, compute `binIndex = ((x - padding) / usableWidth) * peaks.length`. Linear-sample the peaks array at that index (clamp to bounds). Draw a vertical bar from `(x, centerY - peak * 10)` to `(x, centerY + peak * 10)`. Bars left of the playhead use `colorScheme.primary`; bars right of the playhead use `colorScheme.outlineVariant`. Track ticks and playhead overlay unchanged.

The visual height of the waveform extends ±10 px from center (total 20 px), fitting within the existing 24 px hit area. Loading peaks visibly expands the bar — natural feedback that the compute finished.

## Integration with `PlaybackControls`

`PlaybackControls` watches the waveform provider keyed on the current file path:

```dart
final state = ref.watch(editorProvider);
final book = state.audiobook;
final peaksAsync = state.path == null
    ? const AsyncValue.data(<double>[])
    : ref.watch(waveformPeaksProvider(state.path!));
final peaks = peaksAsync.maybeWhen(data: (p) => p, orElse: () => const <double>[]);
```

The (possibly empty) `peaks` list is passed to `ChapterScrubber`. Loading and error states both render the plain track — there is no spinner, no error UI. Errors are logged but not surfaced (an MVP simplification; we can add a small "couldn't render waveform" tooltip later if it becomes a problem).

## Removing the ffmpeg-on-path skip

A new `test/helpers/bundled_test_resolver.dart`:

```dart
import 'dart:io';
import 'package:m4b_chapterizer/data/binary_resolver.dart';

BinaryResolver bundledTestResolver() {
  final key = _platformKey();
  final exe = Platform.isWindows ? '.exe' : '';
  final ffmpeg = 'assets/bin/$key/ffmpeg$exe';
  final ffprobe = 'assets/bin/$key/ffprobe$exe';
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

Update `test/data/ffmpeg_bookbinder_integration_test.dart`:

- Delete the `_ffmpegOnPath()` function and the early-return guard
- Replace `SystemBinaryResolver()` with `bundledTestResolver()`

If the bundled binaries are missing (developer hasn't run `dart run tool/fetch_ffmpeg.dart`), tests fail at setup with an explicit message naming the fix command. This is preferred over silent skips.

## Tests

### `test/data/waveform_extractor_test.dart` (new)

A fake `processStarter` for unit tests:

```dart
Future<Process> _fakeStarter(List<int> bytesToEmit, {int exitCode = 0}) {
  // Returns a Process with stdout that emits the bytes and an exitCode future.
  // Implementation uses a custom `MockProcess` class that satisfies the
  // Process interface; constructed in the helper section of the test file.
}
```

1. **Bins synthetic PCM into the requested number of peaks.** Build 32,000 little-endian int16 samples, each set to `0x4000` (16384). Inject `_fakeStarter(thoseBytes)`. Call `extract(path: '/x', totalDuration: 4 s, targetPeaks: 10)` — `samplesPerBin = 4 * 8000 / 10 = 3200`. Expect a list of length 10, each element `0.5 ± 0.001` (16384 / 32768 = 0.5 exactly).

2. **Reports max-abs per bin.** Construct one bin's worth of samples (`samplesPerBin` of them) where most are 0 but one is `0x3FFF` and one is `-0x3FFF`. Verify the bin's emitted peak is `(16383 / 32768) ≈ 0.4999`.

3. **Cancellation kills the process and throws `WaveformCancelled`.** Use a `_fakeStarter` whose stdout emits a few bytes then awaits indefinitely. Start the extract; pump the event loop; call `extract.cancel()` on the extractor. Expect the future to throw `WaveformCancelled`.

4. **Real ffmpeg extracts near-zero peaks from the silent fixture m4b.** Use `bundledTestResolver()` and the real `Process.start`. Call `extract(path: 'test/fixtures/sample.m4b', totalDuration: 30 s, targetPeaks: 4096)`. Assert:
   - `peaks.length` is between 4090 and 4096 (allows for partial-final-bin edge cases)
   - `peaks.every((p) => p < 0.05)` — silent AAC source produces tiny quantization noise but well under 5 % of full scale

### `test/presentation/chapter_scrubber_test.dart` (extend)

5. **Renders waveform without exception when peaks are provided.** Pump with `peaks: const [0.0, 0.5, 1.0, 0.5, 0.0]` and a 400 px wide harness. Verify `tester.takeException()` is null.

6. **Snap-to-tick still works when peaks are present.** Repeat the existing snap test (tap within 6 px of a chapter tick) with `peaks: [...non-empty...]`. Verify `onSeek` was called with the chapter's exact start.

### `test/presentation/playback_controls_test.dart` (extend)

7. **Scrubber receives peaks from the provider.** Override `waveformPeaksProvider(...)` with `AsyncValue.data(const [0.0, 1.0, 0.0])`. Pump `PlaybackControls`, find the `ChapterScrubber`, assert its `peaks` field equals that list.

8. **Plain track shown while peaks are loading.** Override the waveform provider with `AsyncValue.loading()`. Verify `ChapterScrubber.peaks` is empty (not null is fine; the spec is "empty list renders plain track").

### `test/data/ffmpeg_bookbinder_integration_test.dart` (modify)

9. **Existing round-trip test runs without the on-path skip.** Update to use `bundledTestResolver()`. The test contents are otherwise unchanged. Add a setUp that throws clearly if the bundled binaries are missing — already handled by the helper.

## Files

- Create: `lib/data/waveform_extractor.dart`
- Create: `lib/presentation/providers/waveform.dart`
- Create: `test/data/waveform_extractor_test.dart`
- Create: `test/helpers/bundled_test_resolver.dart`
- Modify: `lib/presentation/widgets/chapter_scrubber.dart` (add `peaks` parameter, render waveform)
- Modify: `test/presentation/chapter_scrubber_test.dart` (waveform render + snap-with-peaks tests)
- Modify: `lib/presentation/widgets/playback_controls.dart` (consume waveform provider, pass peaks to scrubber)
- Modify: `test/presentation/playback_controls_test.dart` (peaks-flow-through test)
- Modify: `lib/main.dart` (add `binaryResolverProvider` override; the existing `bookbinderProvider` override now reads through it)
- Modify: `lib/presentation/providers/editor_state.dart` or new `binary_resolver_provider.dart` (declare `binaryResolverProvider`)
- Modify: `test/data/ffmpeg_bookbinder_integration_test.dart` (deskip + use `bundledTestResolver()`)

## Open items for the implementation plan

- Exact `MockProcess` shape to use as the fake `processStarter` return — the implementation plan will define a small class implementing the `Process` interface with controllable `stdout`/`stdin`/`exitCode`/`kill`.
- Where `binaryResolverProvider` lives — pick the cleanest location that doesn't create a circular import. Likely a new `lib/presentation/providers/binary_resolver_provider.dart`.
