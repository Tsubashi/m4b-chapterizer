import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/bookbinder.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
import 'package:m4b_chapterizer/presentation/providers/editor_state.dart';
import 'package:m4b_chapterizer/presentation/widgets/chapter_list.dart';

class _StubBookbinder implements Bookbinder {
  _StubBookbinder(this._book);
  final Audiobook _book;
  @override
  Future<Audiobook> read(String sourcePath) async => _book;
  @override
  Future<void> write({required String sourcePath, required String destinationPath, required Audiobook audiobook}) async {}
}

Future<ProviderContainer> _setUp(WidgetTester tester) async {
  final fake = _StubBookbinder(Audiobook.validated(
    chapters: const [
      Chapter(title: 'Alpha', start: Duration.zero),
      Chapter(title: 'Beta', start: Duration(seconds: 10)),
    ],
    totalDuration: const Duration(seconds: 30),
  ));
  final container = ProviderContainer(
    overrides: [bookbinderProvider.overrideWithValue(fake)],
  );
  await container.read(editorProvider.notifier).open('/tmp/x.m4b');
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: Scaffold(body: ChapterList())),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('renders one row per chapter', (tester) async {
    await _setUp(tester);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
  });

  testWidgets('Add button appends a chapter', (tester) async {
    final container = await _setUp(tester);
    await tester.tap(find.byKey(const ValueKey('chapters.add')));
    await tester.pump();
    expect(container.read(editorProvider).audiobook?.chapters.length, 3);
  });

  testWidgets('Delete button removes the selected chapter', (tester) async {
    final container = await _setUp(tester);
    await tester.tap(find.byKey(const ValueKey('chapters.row.1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chapters.delete')));
    await tester.pump();
    expect(container.read(editorProvider).audiobook?.chapters.length, 1);
    expect(container.read(editorProvider).audiobook?.chapters.first.title,
        'Alpha');
  });

  testWidgets('editing a title updates state', (tester) async {
    final container = await _setUp(tester);
    await tester.enterText(
      find.byKey(const ValueKey('chapters.title.0')),
      'Renamed',
    );
    await tester.pump();
    expect(container.read(editorProvider).audiobook?.chapters.first.title,
        'Renamed');
  });
}
