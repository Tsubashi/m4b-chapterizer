import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/bookbinder.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
import 'package:m4b_chapterizer/presentation/drag_drop/drag_drop_channel.dart';
import 'package:m4b_chapterizer/presentation/drag_drop/drag_drop_overlay.dart';
import 'package:m4b_chapterizer/presentation/providers/editor_state.dart';

class _FakeChannel implements DragDropChannel {
  final _controller = StreamController<DragEvent>.broadcast();
  @override
  Stream<DragEvent> get events => _controller.stream;
  void send(DragEvent event) => _controller.add(event);
  Future<void> dispose() => _controller.close();
}

class _StubBookbinder implements Bookbinder {
  @override
  Future<Audiobook> read(String sourcePath) async => Audiobook.validated(
        chapters: const [Chapter(title: 'C', start: Duration.zero)],
        totalDuration: const Duration(seconds: 10),
      );
  @override
  Future<void> write({
    required String sourcePath,
    required String destinationPath,
    required Audiobook audiobook,
  }) async {}
}

const _kOverlayText = 'Drop .m4b file here to open';

Future<void> _pump(
  WidgetTester tester,
  _FakeChannel channel,
  ProviderContainer container,
) async {
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: Scaffold(
        body: DragDropOverlay(child: Center(child: Text('body'))),
      ),
    ),
  ));
}

void main() {
  testWidgets('no overlay when not dragging', (tester) async {
    final channel = _FakeChannel();
    final container = ProviderContainer(overrides: [
      dragDropChannelProvider.overrideWithValue(channel),
      bookbinderProvider.overrideWithValue(_StubBookbinder()),
    ]);
    addTearDown(() async {
      await channel.dispose();
      container.dispose();
    });

    await _pump(tester, channel, container);

    expect(find.text(_kOverlayText), findsNothing);
    expect(find.text('body'), findsOneWidget);
  });

  testWidgets('DragEntered shows the overlay', (tester) async {
    final channel = _FakeChannel();
    final container = ProviderContainer(overrides: [
      dragDropChannelProvider.overrideWithValue(channel),
      bookbinderProvider.overrideWithValue(_StubBookbinder()),
    ]);
    addTearDown(() async {
      await channel.dispose();
      container.dispose();
    });

    await _pump(tester, channel, container);
    channel.send(const DragEntered());
    await tester.pumpAndSettle();

    expect(find.text(_kOverlayText), findsOneWidget);
  });

  testWidgets('DragExited hides the overlay', (tester) async {
    final channel = _FakeChannel();
    final container = ProviderContainer(overrides: [
      dragDropChannelProvider.overrideWithValue(channel),
      bookbinderProvider.overrideWithValue(_StubBookbinder()),
    ]);
    addTearDown(() async {
      await channel.dispose();
      container.dispose();
    });

    await _pump(tester, channel, container);
    channel.send(const DragEntered());
    await tester.pumpAndSettle();
    channel.send(const DragExited());
    await tester.pumpAndSettle();

    expect(find.text(_kOverlayText), findsNothing);
  });

  testWidgets('FilesDropped hides overlay and opens the file',
      (tester) async {
    final channel = _FakeChannel();
    final container = ProviderContainer(overrides: [
      dragDropChannelProvider.overrideWithValue(channel),
      bookbinderProvider.overrideWithValue(_StubBookbinder()),
    ]);
    addTearDown(() async {
      await channel.dispose();
      container.dispose();
    });

    await _pump(tester, channel, container);
    channel.send(const DragEntered());
    await tester.pump();
    channel.send(const FilesDropped(['/tmp/book.m4b']));
    await tester.pumpAndSettle();

    expect(find.text(_kOverlayText), findsNothing);
    expect(container.read(editorProvider).path, '/tmp/book.m4b');
  });

  testWidgets('FilesDropped with non-m4b shows snack and does not open',
      (tester) async {
    final channel = _FakeChannel();
    final container = ProviderContainer(overrides: [
      dragDropChannelProvider.overrideWithValue(channel),
      bookbinderProvider.overrideWithValue(_StubBookbinder()),
    ]);
    addTearDown(() async {
      await channel.dispose();
      container.dispose();
    });

    await _pump(tester, channel, container);
    channel.send(const DragEntered());
    await tester.pump();
    channel.send(const FilesDropped(['/tmp/note.txt']));
    await tester.pumpAndSettle();

    expect(find.text('Only .m4b files can be opened'), findsOneWidget);
    expect(container.read(editorProvider).path, isNull);
  });
}
