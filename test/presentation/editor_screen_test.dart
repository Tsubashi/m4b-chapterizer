import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/bookbinder.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
import 'package:m4b_chapterizer/presentation/drag_drop/drag_drop_channel.dart';
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
  Future<void> setSpeed(double speed) async {}
  @override
  Duration get position => Duration.zero;
  @override
  bool get playing => false;
  @override
  double get speed => 1.0;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<bool> get playingStream => const Stream.empty();
  @override
  Stream<double> get speedStream => const Stream.empty();
  @override
  Future<void> dispose() async {}
}

class _RecordingPlayback implements PlaybackController {
  final List<String> setSourceCalls = [];
  @override
  Future<void> setSource(String path) async {
    setSourceCalls.add(path);
  }

  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Duration get position => Duration.zero;
  @override
  bool get playing => false;
  @override
  double get speed => 1.0;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<bool> get playingStream => const Stream.empty();
  @override
  Stream<double> get speedStream => const Stream.empty();
  @override
  Future<void> dispose() async {}
}

class _StubChannel implements DragDropChannel {
  @override
  Stream<DragEvent> get events => const Stream.empty();
}

void main() {
  testWidgets('shows the dirty marker after editing', (tester) async {
    final container = ProviderContainer(overrides: [
      bookbinderProvider.overrideWithValue(_Stub()),
      playbackControllerProvider.overrideWithValue(_NoopPlayback()),
      dragDropChannelProvider.overrideWithValue(_StubChannel()),
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

  testWidgets('setSource is invoked once per path, not per rebuild',
      (tester) async {
    final playback = _RecordingPlayback();
    final container = ProviderContainer(overrides: [
      bookbinderProvider.overrideWithValue(_Stub()),
      playbackControllerProvider.overrideWithValue(playback),
      dragDropChannelProvider.overrideWithValue(_StubChannel()),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: EditorScreen()),
    ));
    await tester.pumpAndSettle();

    // No path yet, so no setSource calls.
    expect(playback.setSourceCalls, isEmpty);

    // Open a file: setSource should be called exactly once.
    await container.read(editorProvider.notifier).open('/tmp/x.m4b');
    await tester.pumpAndSettle();
    expect(playback.setSourceCalls, ['/tmp/x.m4b']);

    // Trigger a rebuild without changing the path: setSource must not be
    // called again.
    container.read(editorProvider.notifier).setTitle('Edited');
    await tester.pump();
    expect(playback.setSourceCalls, ['/tmp/x.m4b']);
  });
}
