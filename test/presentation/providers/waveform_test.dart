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
  final Audiobook _book;
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
      (_, _) => throw UnimplementedError();

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
