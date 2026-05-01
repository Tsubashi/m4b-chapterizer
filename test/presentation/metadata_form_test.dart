import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/bookbinder.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
import 'package:m4b_chapterizer/presentation/providers/editor_state.dart';
import 'package:m4b_chapterizer/presentation/widgets/metadata_form.dart';

class _StubBookbinder implements Bookbinder {
  _StubBookbinder(this._book);
  final Audiobook _book;
  @override
  Future<Audiobook> read(String sourcePath) async => _book;
  @override
  Future<void> write({required String sourcePath, required String destinationPath, required Audiobook audiobook}) async {}
}

Future<Widget> _harness(WidgetTester tester, _StubBookbinder fake) async {
  final container = ProviderContainer(
    overrides: [bookbinderProvider.overrideWithValue(fake)],
  );
  await container.read(editorProvider.notifier).open('/tmp/x.m4b');
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: Scaffold(body: MetadataForm())),
  );
}

void main() {
  testWidgets('renders the loaded audiobook fields', (tester) async {
    final fake = _StubBookbinder(Audiobook.validated(
      title: 'A Title',
      author: 'An Author',
      chapters: const [Chapter(title: 'C', start: Duration.zero)],
      totalDuration: const Duration(seconds: 5),
    ));
    await tester.pumpWidget(await _harness(tester, fake));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'A Title'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'An Author'), findsOneWidget);
  });

  testWidgets('typing in the title field updates editor state', (tester) async {
    final fake = _StubBookbinder(Audiobook.validated(
      title: 'Old',
      chapters: const [Chapter(title: 'C', start: Duration.zero)],
      totalDuration: const Duration(seconds: 5),
    ));
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    await container.read(editorProvider.notifier).open('/tmp/x.m4b');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: MetadataForm())),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('metadata.title')),
      'Brand New',
    );
    await tester.pump();

    expect(container.read(editorProvider).audiobook?.title, 'Brand New');
    expect(container.read(editorProvider).isDirty, isTrue);
  });
}
