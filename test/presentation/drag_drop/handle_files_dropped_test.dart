import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/bookbinder.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
import 'package:m4b_chapterizer/presentation/drag_drop/handle_files_dropped.dart';
import 'package:m4b_chapterizer/presentation/providers/editor_state.dart';

class _RecordingBookbinder implements Bookbinder {
  _RecordingBookbinder(this._book);
  final Audiobook _book;
  int writeCount = 0;
  final List<String> readPaths = [];

  @override
  Future<Audiobook> read(String sourcePath) async {
    readPaths.add(sourcePath);
    return _book;
  }

  @override
  Future<void> write({
    required String sourcePath,
    required String destinationPath,
    required Audiobook audiobook,
  }) async {
    writeCount++;
  }
}

Audiobook _book() => Audiobook.validated(
      title: 'Original',
      chapters: const [Chapter(title: 'C', start: Duration.zero)],
      totalDuration: const Duration(seconds: 10),
    );

/// Pumps a Consumer that exposes its `BuildContext` and `WidgetRef`
/// through a callback so the test can drive `handleFilesDropped`.
Future<void> _pumpHarness(
  WidgetTester tester,
  ProviderContainer container,
  void Function(BuildContext, WidgetRef) onReady,
) async {
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(builder: (context, ref, _) {
          onReady(context, ref);
          return const SizedBox();
        }),
      ),
    ),
  ));
}

void main() {
  testWidgets('empty list shows multi-file snack and skips open',
      (tester) async {
    final fake = _RecordingBookbinder(_book());
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    late BuildContext ctx;
    late WidgetRef ref0;
    await _pumpHarness(tester, container, (c, r) {
      ctx = c;
      ref0 = r;
    });

    await handleFilesDropped(ctx, ref0, const []);
    await tester.pump();

    expect(find.text('Drop only one .m4b file at a time'), findsOneWidget);
    expect(fake.readPaths, isEmpty);
  });

  testWidgets('two paths show multi-file snack', (tester) async {
    final fake = _RecordingBookbinder(_book());
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    late BuildContext ctx;
    late WidgetRef ref0;
    await _pumpHarness(tester, container, (c, r) {
      ctx = c;
      ref0 = r;
    });

    await handleFilesDropped(ctx, ref0, const ['/a.m4b', '/b.m4b']);
    await tester.pump();

    expect(find.text('Drop only one .m4b file at a time'), findsOneWidget);
    expect(fake.readPaths, isEmpty);
  });

  testWidgets('single non-m4b file shows wrong-extension snack',
      (tester) async {
    final fake = _RecordingBookbinder(_book());
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    late BuildContext ctx;
    late WidgetRef ref0;
    await _pumpHarness(tester, container, (c, r) {
      ctx = c;
      ref0 = r;
    });

    await handleFilesDropped(ctx, ref0, const ['/file.txt']);
    await tester.pump();

    expect(find.text('Only .m4b files can be opened'), findsOneWidget);
    expect(fake.readPaths, isEmpty);
  });

  testWidgets('uppercase .M4B extension is accepted', (tester) async {
    final fake = _RecordingBookbinder(_book());
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    late BuildContext ctx;
    late WidgetRef ref0;
    await _pumpHarness(tester, container, (c, r) {
      ctx = c;
      ref0 = r;
    });

    await handleFilesDropped(ctx, ref0, const ['/Book.M4B']);
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
    expect(fake.readPaths, ['/Book.M4B']);
    expect(container.read(editorProvider).path, '/Book.M4B');
  });

  testWidgets('clean state opens immediately without dialog',
      (tester) async {
    final fake = _RecordingBookbinder(_book());
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    late BuildContext ctx;
    late WidgetRef ref0;
    await _pumpHarness(tester, container, (c, r) {
      ctx = c;
      ref0 = r;
    });

    await handleFilesDropped(ctx, ref0, const ['/new.m4b']);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(fake.readPaths, ['/new.m4b']);
    expect(container.read(editorProvider).path, '/new.m4b');
  });

  testWidgets('dirty + Discard opens new file without saving',
      (tester) async {
    final fake = _RecordingBookbinder(_book());
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/old.m4b');
    container.read(editorProvider.notifier).setTitle('Edited');

    late BuildContext ctx;
    late WidgetRef ref0;
    await _pumpHarness(tester, container, (c, r) {
      ctx = c;
      ref0 = r;
    });

    final future = handleFilesDropped(ctx, ref0, const ['/new.m4b']);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Discard'));
    await future;
    await tester.pumpAndSettle();

    expect(fake.writeCount, 0);
    expect(fake.readPaths, ['/old.m4b', '/new.m4b']);
    expect(container.read(editorProvider).path, '/new.m4b');
  });

  testWidgets('dirty + Save saves then opens new file', (tester) async {
    final fake = _RecordingBookbinder(_book());
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/old.m4b');
    container.read(editorProvider.notifier).setTitle('Edited');

    late BuildContext ctx;
    late WidgetRef ref0;
    await _pumpHarness(tester, container, (c, r) {
      ctx = c;
      ref0 = r;
    });

    final future = handleFilesDropped(ctx, ref0, const ['/new.m4b']);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await future;
    await tester.pumpAndSettle();

    expect(fake.writeCount, 1);
    expect(container.read(editorProvider).path, '/new.m4b');
  });

  testWidgets('dirty + Cancel keeps current book', (tester) async {
    final fake = _RecordingBookbinder(_book());
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/old.m4b');
    container.read(editorProvider.notifier).setTitle('Edited');

    late BuildContext ctx;
    late WidgetRef ref0;
    await _pumpHarness(tester, container, (c, r) {
      ctx = c;
      ref0 = r;
    });

    final future = handleFilesDropped(ctx, ref0, const ['/new.m4b']);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await future;
    await tester.pumpAndSettle();

    expect(fake.writeCount, 0);
    expect(fake.readPaths, ['/old.m4b']);
    expect(container.read(editorProvider).path, '/old.m4b');
  });
}
