# Stop Waveform Recompute on Chapter Edits — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the waveform disappearing when the user adds, deletes, or edits a chapter. Replace `ref.watch(editorProvider)` with `ref.read(editorProvider)` in `waveformPeaksProvider`, and extract the `WaveformExtractor` into its own provider so the regression test can spy on `extract()` calls.

**Architecture:** One file change + one test file. Production behavior unchanged except for the bug fix; the new `waveformExtractorProvider` is purely for testability.

**Tech Stack:** No new packages.

**Reference design:** `docs/superpowers/specs/2026-05-02-waveform-no-recompute-on-edit-design.md`

**Conventions:**
- `--no-gpg-sign` REQUIRED on every `git commit`.

---

## Task 1: Fix the bug, refactor for testability, add regression test

**Files:**
- Modify: `lib/presentation/providers/waveform.dart`
- Create: `test/presentation/providers/waveform_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/presentation/providers/waveform_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/data/binary_resolver.dart';
import 'package:m4b_chapterizer/data/waveform_extractor.dart';
import 'package:m4b_chapterizer/domain/bookbinder.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
import 'package:m4b_chapterizer/presentation/providers/editor_state.dart';
import 'package:m4b_chapterizer/presentation/providers/waveform.dart';

class _StubBookbinder implements Bookbinder {
  _StubBookbinder(this._book);
  Audiobook _book;
  Audiobook? swapTo;

  @override
  Future<Audiobook> read(String sourcePath) async {
    if (sourcePath == '/tmp/y.m4b' && swapTo != null) {
      return swapTo!;
    }
    return _book;
  }

  @override
  Future<void> write({
    required String sourcePath,
    required String destinationPath,
    required Audiobook audiobook,
  }) async {}
}

class _RecordingExtractor implements WaveformExtractor {
  int extractCallCount = 0;

  @override
  BinaryResolver get binaries =>
      const FixedBinaryResolver(ffmpeg: '/x', ffprobe: '/x');

  @override
  Future<Process> Function(String, List<String>) get processStarter =>
      (_, __) => throw UnimplementedError();

  @override
  Future<List<double>> extract({
    required String path,
    required Duration totalDuration,
    int targetPeaks = 4096,
  }) async {
    extractCallCount++;
    return const [0.5, 0.5, 0.5];
  }

  @override
  void cancel() {}
}

Audiobook _book(String title) => Audiobook.validated(
      title: title,
      chapters: const [
        Chapter(title: 'A', start: Duration.zero),
        Chapter(title: 'B', start: Duration(seconds: 5)),
      ],
      totalDuration: const Duration(seconds: 10),
    );

void main() {
  test('chapter mutations do not trigger a re-extract', () async {
    final spy = _RecordingExtractor();
    final container = ProviderContainer(overrides: [
      bookbinderProvider.overrideWithValue(_StubBookbinder(_book('First'))),
      waveformExtractorProvider.overrideWithValue(spy),
    ]);
    addTearDown(container.dispose);

    await container.read(editorProvider.notifier).open('/tmp/x.m4b');
    await container.read(waveformPeaksProvider('/tmp/x.m4b').future);
    expect(spy.extractCallCount, 1);

    container.read(editorProvider.notifier).addChapter();
    container.read(editorProvider.notifier).deleteChapter(0);
    container.read(editorProvider.notifier).setTitle('Edited');
    await Future<void>.delayed(Duration.zero);

    final after = container.read(waveformPeaksProvider('/tmp/x.m4b'));
    expect(after, isA<AsyncData<List<double>>>());
    expect(spy.extractCallCount, 1,
        reason: 'chapter mutations must not cause a re-extract');
  });

  test('opening a different file triggers a new extract', () async {
    final spy = _RecordingExtractor();
    final stub = _StubBookbinder(_book('First'))..swapTo = _book('Second');
    final container = ProviderContainer(overrides: [
      bookbinderProvider.overrideWithValue(stub),
      waveformExtractorProvider.overrideWithValue(spy),
    ]);
    addTearDown(container.dispose);

    await container.read(editorProvider.notifier).open('/tmp/x.m4b');
    await container.read(waveformPeaksProvider('/tmp/x.m4b').future);
    expect(spy.extractCallCount, 1);

    await container.read(editorProvider.notifier).open('/tmp/y.m4b');
    await container.read(waveformPeaksProvider('/tmp/y.m4b').future);
    expect(spy.extractCallCount, 2);
  });
}
```

- [ ] **Step 2: Run, see failures**

Run: `flutter test test/presentation/providers/waveform_test.dart`
Expected: FAIL — `waveformExtractorProvider` doesn't exist.

- [ ] **Step 3: Apply the fix and refactor**

Open `lib/presentation/providers/waveform.dart`. Replace its entire body with:

```dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/waveform_extractor.dart';
import 'editor_state.dart';

/// Provided here so tests can override with a spy. Production wires the
/// real ffmpeg-driven extractor.
final waveformExtractorProvider = Provider<WaveformExtractor>((ref) {
  return WaveformExtractor(
    binaries: ref.read(binaryResolverProvider),
    processStarter: Process.start,
  );
});

/// Computes amplitude peaks for the audio at [path] in the background.
/// Errors and "still loading" both render as an empty peak list at the UI.
final waveformPeaksProvider =
    FutureProvider.family<List<double>, String>((ref, path) async {
  final book = ref.read(editorProvider).audiobook;
  if (book == null) return <double>[];

  final extractor = ref.read(waveformExtractorProvider);
  ref.onDispose(extractor.cancel);

  return extractor.extract(path: path, totalDuration: book.totalDuration);
});
```

The two changes from the previous version:

1. `ref.watch(editorProvider)` → `ref.read(editorProvider)` (the bug fix).
2. The `WaveformExtractor` construction is hoisted into `waveformExtractorProvider` so tests can override it.

- [ ] **Step 4: Run tests**

Run: `flutter test test/presentation/providers/waveform_test.dart`
Expected: both tests pass.

- [ ] **Step 5: Run full suite + analyzer**

Run: `flutter test`
Expected: all tests pass.

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Smoke-test on macOS**

```bash
flutter run -d macos
```

Open `test/fixtures/sample.m4b`. Wait for the waveform to render. Add and delete a chapter. Verify the waveform stays visible the entire time.

- [ ] **Step 7: Commit**

```bash
git add lib/presentation/providers/waveform.dart test/presentation/providers/waveform_test.dart
git commit --no-gpg-sign -m "Stop waveform recompute on chapter edits"
```

---

## Final verification

- [ ] `flutter test` — all green.
- [ ] `flutter analyze` — clean.
- [ ] macOS smoke test confirms the waveform persists through chapter mutations.
