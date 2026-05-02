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

  testWidgets('selected chapter number has a filled background',
      (tester) async {
    final container = await _setUp(tester);

    // Initially chapter 0 is selected. Its number container should have a
    // primary-colored background; the unselected one should be transparent.
    Container numberContainer(int i) => tester.widget<Container>(
          find.byKey(ValueKey('chapters.number.$i')),
        );

    final selectedColor =
        (numberContainer(0).decoration as BoxDecoration).color;
    final unselectedColor =
        (numberContainer(1).decoration as BoxDecoration).color;
    expect(selectedColor, isNot(Colors.transparent));
    expect(unselectedColor, Colors.transparent);

    // Now switch selection to chapter 1.
    container.read(selectedChapterProvider.notifier).state = 1;
    await tester.pump();

    expect((numberContainer(0).decoration as BoxDecoration).color,
        Colors.transparent);
    expect((numberContainer(1).decoration as BoxDecoration).color,
        isNot(Colors.transparent));
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

  testWidgets('lays out without overflow when surface is narrow',
      (tester) async {
    addTearDown(() => tester.view.resetPhysicalSize());
    tester.view.physicalSize = const Size(180, 600);
    tester.view.devicePixelRatio = 1.0;
    await _setUp(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('typing into a chapter title preserves cursor at end',
      (tester) async {
    await _setUp(tester);
    final fieldFinder = find.byKey(const ValueKey('chapters.title.0'));

    // Tap the field to focus it, then type two characters.
    await tester.tap(fieldFinder);
    await tester.pump();
    final state = tester.state<EditableTextState>(
      find.descendant(of: fieldFinder, matching: find.byType(EditableText)),
    );
    final controller = state.widget.controller;
    // Start from a known empty value to make assertions deterministic.
    controller.text = '';
    await tester.pump();

    await tester.enterText(fieldFinder, 'A');
    await tester.pump();
    await tester.enterText(fieldFinder, 'AB');
    await tester.pump();

    expect(controller.text, 'AB');
    expect(controller.selection.baseOffset, controller.text.length);
  });

  testWidgets('shows snackbar and reverts field on duplicate start', (tester) async {
    final container = await _setUp(tester);

    // Chapter 0 is at 00:00.000. Try to set chapter 1's start to the same.
    final startField = find.byKey(const ValueKey('chapters.start.1'));
    await tester.tap(startField);
    await tester.pump();
    await tester.enterText(startField, '00:00:00.000');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    // Snackbar visible with the duplicate message.
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('unique'), findsOneWidget);

    // The field's text reverted to the original "00:00:10.000".
    final controller =
        tester.widget<TextField>(startField).controller!;
    expect(controller.text, '00:00:10.000');

    // Audiobook state unchanged: chapter 1 still at 10s.
    expect(
      container.read(editorProvider).audiobook!.chapters[1].start,
      const Duration(seconds: 10),
    );
  });

  testWidgets('reorders rendered rows when start time moves a chapter',
      (tester) async {
    final container = await _setUp(tester);

    // Move chapter 1 ('Beta' @ 10s) to 25s, past chapter 2 (which doesn't
    // exist in this 2-chapter setup — extend to 3).
    // _setUp uses a 2-chapter book; for this test, override with a 3-chapter
    // book by re-opening with a different fake.
    // Simpler: just verify the 2-chapter case where Beta moves to 25s
    // (totalDuration 30s) which keeps it at index 1 — so we need a 3-chapter
    // setup. Override in a fresh container:
    final fake = _StubBookbinder(Audiobook.validated(
      chapters: const [
        Chapter(title: 'Alpha', start: Duration.zero),
        Chapter(title: 'Beta', start: Duration(seconds: 10)),
        Chapter(title: 'Gamma', start: Duration(seconds: 20)),
      ],
      totalDuration: const Duration(seconds: 30),
    ));
    final c = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    addTearDown(c.dispose);
    await c.read(editorProvider.notifier).open('/tmp/y.m4b');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: ChapterList())),
    ));
    await tester.pumpAndSettle();

    // Move 'Beta' (index 1) to 00:00:25.000.
    final startField = find.byKey(const ValueKey('chapters.start.1'));
    await tester.tap(startField);
    await tester.pump();
    await tester.enterText(startField, '00:00:25.000');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // Audiobook chapter order is now [Alpha, Gamma, Beta].
    expect(
      c.read(editorProvider).audiobook!.chapters.map((x) => x.title).toList(),
      ['Alpha', 'Gamma', 'Beta'],
    );

    // Suppress unused container warning.
    expect(container, isNotNull);
  });
}
