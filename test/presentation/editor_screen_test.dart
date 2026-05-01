import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/bookbinder.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
import 'package:m4b_chapterizer/presentation/providers/editor_state.dart';
import 'package:m4b_chapterizer/presentation/providers/playback.dart';
import 'package:m4b_chapterizer/presentation/screens/editor_screen.dart';

class _Stub implements Bookbinder {
  @override
  Future<Audiobook> read(String sourcePath) async => Audiobook.validated(
        title: 'Loaded',
        chapters: const [Chapter(title: 'C', start: Duration.zero)],
        totalDuration: const Duration(seconds: 5),
      );
  @override
  Future<void> write({required String sourcePath, required String destinationPath, required Audiobook audiobook}) async {}
}

class _NoopPlayback implements PlaybackController {
  @override
  Future<void> setSource(String path) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Duration get position => Duration.zero;
  @override
  bool get playing => false;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Future<void> dispose() async {}
}

void main() {
  testWidgets('shows the dirty marker after editing', (tester) async {
    final container = ProviderContainer(overrides: [
      bookbinderProvider.overrideWithValue(_Stub()),
      playbackControllerProvider.overrideWithValue(_NoopPlayback()),
    ]);
    await container.read(editorProvider.notifier).open('/tmp/x.m4b');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: EditorScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('•'), findsNothing);

    container.read(editorProvider.notifier).setTitle('Edited');
    await tester.pump();
    expect(find.text('•'), findsOneWidget);
  });
}
