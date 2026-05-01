import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/bookbinder.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
import 'package:m4b_chapterizer/domain/models/cover.dart';
import 'package:m4b_chapterizer/presentation/providers/editor_state.dart';
import 'package:m4b_chapterizer/presentation/widgets/cover_panel.dart';

class _StubBookbinder implements Bookbinder {
  _StubBookbinder(this._book);
  final Audiobook _book;
  @override
  Future<Audiobook> read(String sourcePath) async => _book;
  @override
  Future<void> write({required String sourcePath, required String destinationPath, required Audiobook audiobook}) async {}
}

void main() {
  // 1x1 transparent PNG.
  final tinyPng = Uint8List.fromList(const [
    0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,
    0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
    0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,
    0x08,0x06,0x00,0x00,0x00,0x1F,0x15,0xC4,0x89,
    0x00,0x00,0x00,0x0D,0x49,0x44,0x41,0x54,
    0x78,0x9C,0x63,0x00,0x01,0x00,0x00,0x05,
    0x00,0x01,0x0D,0x0A,0x2D,0xB4,
    0x00,0x00,0x00,0x00,0x49,0x45,0x4E,0x44,
    0xAE,0x42,0x60,0x82,
  ]);

  testWidgets('shows placeholder when book has no cover', (tester) async {
    final fake = _StubBookbinder(Audiobook.validated(
      chapters: const [Chapter(title: 'C', start: Duration.zero)],
      totalDuration: const Duration(seconds: 1),
    ));
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    await container.read(editorProvider.notifier).open('/tmp/x.m4b');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: CoverPanel())),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cover.placeholder')), findsOneWidget);
  });

  testWidgets('shows the image when book has a cover', (tester) async {
    final fake = _StubBookbinder(Audiobook.validated(
      chapters: const [Chapter(title: 'C', start: Duration.zero)],
      totalDuration: const Duration(seconds: 1),
      cover: Cover(bytes: tinyPng, mimeType: 'image/png'),
    ));
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    await container.read(editorProvider.notifier).open('/tmp/x.m4b');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: CoverPanel())),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cover.image')), findsOneWidget);
  });

  testWidgets('Remove button clears the cover', (tester) async {
    final fake = _StubBookbinder(Audiobook.validated(
      chapters: const [Chapter(title: 'C', start: Duration.zero)],
      totalDuration: const Duration(seconds: 1),
      cover: Cover(bytes: tinyPng, mimeType: 'image/png'),
    ));
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    await container.read(editorProvider.notifier).open('/tmp/x.m4b');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: CoverPanel())),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('cover.remove')));
    await tester.pump();

    expect(container.read(editorProvider).audiobook?.cover, isNull);
    expect(container.read(editorProvider).isDirty, isTrue);
  });
}
