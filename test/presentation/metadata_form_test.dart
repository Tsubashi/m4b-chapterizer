import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/bookbinder.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
import 'package:m4b_chapterizer/presentation/providers/editor_state.dart';
import 'package:m4b_chapterizer/presentation/widgets/metadata_form.dart';

class _StubBookbinder implements Bookbinder {
  _StubBookbinder(this.book);
  Audiobook book;
  @override
  Future<Audiobook> read(String sourcePath) async => book;
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

  testWidgets('re-hydrates controllers when a different file is opened',
      (tester) async {
    final fake = _StubBookbinder(Audiobook.validated(
      title: 'A Title',
      author: 'An Author',
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

    expect(find.widgetWithText(TextField, 'A Title'), findsOneWidget);

    // Swap out the stub's audiobook and open a different path.
    fake.book = Audiobook.validated(
      title: 'Another Title',
      author: 'Other Author',
      chapters: const [Chapter(title: 'C2', start: Duration.zero)],
      totalDuration: const Duration(seconds: 7),
    );
    await container.read(editorProvider.notifier).open('/tmp/y.m4b');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Another Title'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'A Title'), findsNothing);
  });

  testWidgets('focus → mutate → blur on title field pushes one undo step',
      (tester) async {
    final fake = _StubBookbinder(Audiobook.validated(
      title: 'Old',
      chapters: const [Chapter(title: 'C', start: Duration.zero)],
      totalDuration: const Duration(seconds: 5),
    ));
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/tmp/x.m4b');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: MetadataForm())),
    ));
    await tester.pumpAndSettle();

    expect(container.read(editorProvider).canUndo, isFalse);

    final titleKey = const ValueKey('metadata.title');
    await tester.tap(find.byKey(titleKey));
    await tester.pump();
    await tester.enterText(find.byKey(titleKey), 'Brand New');
    await tester.pump();

    // No push yet — still in session.
    expect(container.read(editorProvider).canUndo, isFalse);

    // Defocus the field.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    expect(container.read(editorProvider).canUndo, isTrue);
    container.read(editorProvider.notifier).undo();
    expect(container.read(editorProvider).audiobook!.title, 'Old');
  });

  testWidgets(
      'editing three different fields produces three independent undo steps',
      (tester) async {
    final fake = _StubBookbinder(Audiobook.validated(
      title: 'OldTitle',
      author: 'OldAuthor',
      narrator: 'OldNarrator',
      chapters: const [Chapter(title: 'C', start: Duration.zero)],
      totalDuration: const Duration(seconds: 5),
    ));
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/tmp/x.m4b');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: MetadataForm())),
    ));
    await tester.pumpAndSettle();

    final titleKey = const ValueKey('metadata.title');
    final authorKey = const ValueKey('metadata.author');
    final narratorKey = const ValueKey('metadata.narrator');

    // 1. Tap the Title field; type 'NewTitle'.
    await tester.tap(find.byKey(titleKey));
    await tester.pump();
    await tester.enterText(find.byKey(titleKey), 'NewTitle');
    await tester.pump();

    // 2. Tap the Author field (this blurs Title); type 'NewAuthor'.
    await tester.tap(find.byKey(authorKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(authorKey), 'NewAuthor');
    await tester.pump();

    // 3. Tap the Narrator field (blurs Author); type 'NewNarrator'.
    await tester.tap(find.byKey(narratorKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(narratorKey), 'NewNarrator');
    await tester.pump();

    // 4. Defocus.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    // 5. Three undo steps recorded — one per field session.
    expect(container.read(editorProvider).undoStack.length, 3);

    final notifier = container.read(editorProvider.notifier);

    // 6. Undo once: narrator reverts; title/author still new.
    notifier.undo();
    await tester.pumpAndSettle();
    {
      final book = container.read(editorProvider).audiobook!;
      expect(book.narrator, 'OldNarrator');
      expect(book.author, 'NewAuthor');
      expect(book.title, 'NewTitle');
    }

    // 7. Undo again: author reverts.
    notifier.undo();
    await tester.pumpAndSettle();
    {
      final book = container.read(editorProvider).audiobook!;
      expect(book.author, 'OldAuthor');
      expect(book.title, 'NewTitle');
      expect(book.narrator, 'OldNarrator');
    }

    // 8. Undo again: title reverts.
    notifier.undo();
    await tester.pumpAndSettle();
    {
      final book = container.read(editorProvider).audiobook!;
      expect(book.title, 'OldTitle');
      expect(book.author, 'OldAuthor');
      expect(book.narrator, 'OldNarrator');
    }
  });

  testWidgets('undo after a metadata edit also reverts the visible field text',
      (tester) async {
    final fake = _StubBookbinder(Audiobook.validated(
      title: 'Old',
      chapters: const [Chapter(title: 'C', start: Duration.zero)],
      totalDuration: const Duration(seconds: 5),
    ));
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/tmp/x.m4b');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: MetadataForm())),
    ));
    await tester.pumpAndSettle();

    // Edit + commit by defocusing.
    final titleKey = const ValueKey('metadata.title');
    await tester.tap(find.byKey(titleKey));
    await tester.pump();
    await tester.enterText(find.byKey(titleKey), 'New');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    // Undo.
    container.read(editorProvider.notifier).undo();
    await tester.pumpAndSettle();

    expect(container.read(editorProvider).audiobook!.title, 'Old');
    final controller =
        tester.widget<TextField>(find.byKey(titleKey)).controller!;
    expect(controller.text, 'Old',
        reason: 'controller text must follow the audiobook value after undo');
  });
}
