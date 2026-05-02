# Stop Waveform Recompute on Chapter Edits — Design

**Date:** 2026-05-02
**Status:** Approved (brainstorming phase)

## Overview

When the user adds, deletes, or edits a chapter, the audio waveform briefly disappears and is recomputed. This is wasted work — the waveform depends on audio content, which doesn't change. The fix is a one-line change in the waveform provider, plus a small testability refactor.

## Goals

- Adding, deleting, renaming, or otherwise editing a chapter does not invalidate the cached waveform peaks
- Opening a different file still triggers a fresh compute (correct behavior preserved)
- Regression test demonstrates that chapter mutations leave the peaks future identity unchanged

## Non-goals

- Persistent (sidecar file) caching across app restarts — explicitly out of scope; Option A from the brainstorm
- Smarter cache eviction strategies
- Background pre-fetching

## Root cause

`lib/presentation/providers/waveform.dart` reads the editor's audiobook with `ref.watch(editorProvider)`:

```dart
final waveformPeaksProvider =
    FutureProvider.family<List<double>, String>((ref, path) async {
  final book = ref.watch(editorProvider).audiobook;  // ← any state change rebuilds
  if (book == null) return <double>[];
  final extractor = WaveformExtractor(
    binaries: ref.read(binaryResolverProvider),
    processStarter: Process.start,
  );
  ref.onDispose(extractor.cancel);
  return extractor.extract(path: path, totalDuration: book.totalDuration);
});
```

`FutureProvider.family` already caches per family key (`path`), but `ref.watch` makes the body depend on the entire `editorProvider` state. Any mutation (chapter add/delete/rename, metadata edit, dirty-flag flip) invalidates the future, kills the in-flight ffmpeg process via the `onDispose`, and starts over.

## Fix

Two changes in `lib/presentation/providers/waveform.dart`:

1. **Change `ref.watch` to `ref.read`** for the editor state. We only need `audiobook.totalDuration` once, at the moment the provider runs for a given path.

2. **Extract `WaveformExtractor` construction into its own provider** so tests can override it with a spy. The new provider lives in the same file:

```dart
final waveformExtractorProvider = Provider<WaveformExtractor>((ref) {
  return WaveformExtractor(
    binaries: ref.read(binaryResolverProvider),
    processStarter: Process.start,
  );
});

final waveformPeaksProvider =
    FutureProvider.family<List<double>, String>((ref, path) async {
  final book = ref.read(editorProvider).audiobook;
  if (book == null) return <double>[];
  final extractor = ref.read(waveformExtractorProvider);
  ref.onDispose(extractor.cancel);
  return extractor.extract(path: path, totalDuration: book.totalDuration);
});
```

Production behavior is unchanged — `Process.start` is still the real process starter, `BundledBinaryResolver` is still the binary resolver. The only change is that `WaveformExtractor` is now reachable via a provider override.

## Tests

New file `test/presentation/providers/waveform_test.dart`:

A `_RecordingExtractor` that implements `WaveformExtractor`'s public surface (we can't extend it cleanly because of the `final` fields; in practice the test replaces it via a `Provider.overrideWithValue` and the consuming provider only calls `.extract(...)` and `.cancel()`).

Two tests:

1. **`chapter mutations do not trigger a re-extract`** — open a file via the editor, await first peaks, assert `spy.extractCallCount == 1`. Call `addChapter()` and `deleteChapter(0)`; await microtasks. Assert `spy.extractCallCount` is still `1` and the second `read` returns the same Future identity as the first.

2. **`opening a different file triggers a new extract`** — same setup, then open a different path via the editor. Assert `spy.extractCallCount == 2`.

The spy approach (assertion that the production provider called `extract` exactly once across all chapter mutations) is more robust than just checking Future identity, and it directly tests the behavior the user reported.

## Files

- Modify: `lib/presentation/providers/waveform.dart`
- Create: `test/presentation/providers/waveform_test.dart`
