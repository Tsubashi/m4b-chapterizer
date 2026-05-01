import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/bookbinder.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
import 'package:m4b_chapterizer/presentation/providers/editor_state.dart';
import 'package:m4b_chapterizer/presentation/providers/playback.dart';
import 'package:m4b_chapterizer/presentation/widgets/chapter_list.dart';
import 'package:m4b_chapterizer/presentation/widgets/playback_controls.dart';

class _StubBookbinder implements Bookbinder {
  @override
  Future<Audiobook> read(String sourcePath) async => Audiobook.validated(
        chapters: const [
          Chapter(title: 'A', start: Duration.zero),
          Chapter(title: 'B', start: Duration(seconds: 10)),
        ],
        totalDuration: const Duration(seconds: 30),
      );
  @override
  Future<void> write({required String sourcePath, required String destinationPath, required Audiobook audiobook}) async {}
}

class _FakePlayback implements PlaybackController {
  Duration _pos = const Duration(seconds: 7);
  bool _playing = false;
  @override
  Future<void> setSource(String path) async {}
  @override
  Future<void> play() async => _playing = true;
  @override
  Future<void> pause() async => _playing = false;
  @override
  Future<void> seek(Duration position) async => _pos = position;
  @override
  Duration get position => _pos;
  @override
  bool get playing => _playing;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Future<void> dispose() async {}
}

void main() {
  testWidgets('Set start to playhead snaps the selected chapter to position',
      (tester) async {
    final fake = _StubBookbinder();
    final fakePlayback = _FakePlayback();
    final container = ProviderContainer(
      overrides: [
        bookbinderProvider.overrideWithValue(fake),
        playbackControllerProvider.overrideWithValue(fakePlayback),
      ],
    );
    await container.read(editorProvider.notifier).open('/tmp/x.m4b');
    container.read(selectedChapterProvider.notifier).state = 1;

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: PlaybackControls())),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('playback.snap')));
    await tester.pump();

    expect(
      container.read(editorProvider).audiobook?.chapters[1].start,
      const Duration(seconds: 7),
    );
  });
}
