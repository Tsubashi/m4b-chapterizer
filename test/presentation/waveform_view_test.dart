import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/bookbinder.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
import 'package:m4b_chapterizer/presentation/providers/editor_state.dart';
import 'package:m4b_chapterizer/presentation/providers/playback.dart';
import 'package:m4b_chapterizer/presentation/providers/waveform.dart';
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
  List<double> peaks = const [],
}) async {
  final container = ProviderContainer(
    overrides: [
      bookbinderProvider.overrideWithValue(_StubBookbinder()),
      playbackControllerProvider.overrideWithValue(playback),
      waveformPeaksProvider('/tmp/x.m4b').overrideWith((ref) async => peaks),
    ],
  );
  addTearDown(container.dispose);
  await container.read(editorProvider.notifier).open('/tmp/x.m4b');

  // Force the viewport's tester-side width to a known value (800).
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
      peaks: const [0.0, 0.5, 1.0, 0.5, 0.0],
    );
    expect(tester.takeException(), isNull);
  });
}
