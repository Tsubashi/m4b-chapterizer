import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/bookbinder.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
import 'package:m4b_chapterizer/presentation/exit_confirmation.dart';
import 'package:m4b_chapterizer/presentation/providers/editor_state.dart';

class _RecordingBookbinder implements Bookbinder {
  _RecordingBookbinder(this._book);
  final Audiobook _book;
  int writeCount = 0;
  Audiobook? lastWritten;

  @override
  Future<Audiobook> read(String sourcePath) async => _book;

  @override
  Future<void> write({
    required String sourcePath,
    required String destinationPath,
    required Audiobook audiobook,
  }) async {
    writeCount++;
    lastWritten = audiobook;
  }
}

Audiobook _book() => Audiobook.validated(
      title: 'Original',
      chapters: const [Chapter(title: 'C', start: Duration.zero)],
      totalDuration: const Duration(seconds: 10),
    );

/// Pumps a widget that exposes a button which calls [handleExitRequest] and
/// stores the result in a closure. Returns a getter so the test can read
/// the value after later interactions.
Future<bool? Function()> _pumpHarness(
  WidgetTester tester,
  ProviderContainer container,
) async {
  bool? captured;
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(builder: (context, ref, _) {
          return ElevatedButton(
            onPressed: () async {
              captured = await handleExitRequest(context, ref);
            },
            child: const Text('exit'),
          );
        }),
      ),
    ),
  ));
  return () => captured;
}

void main() {
  test('ExitDecision values are exhaustive', () {
    expect(ExitDecision.values,
        [ExitDecision.cancel, ExitDecision.discard, ExitDecision.save]);
  });

  testWidgets('returns true immediately when not dirty', (tester) async {
    final fake = _RecordingBookbinder(_book());
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/tmp/x.m4b');

    final getResult = await _pumpHarness(tester, container);
    await tester.tap(find.text('exit'));
    await tester.pumpAndSettle();

    expect(getResult(), isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    expect(fake.writeCount, 0);
  });

  testWidgets('returns false when user picks Cancel', (tester) async {
    final fake = _RecordingBookbinder(_book());
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/tmp/x.m4b');
    container.read(editorProvider.notifier).setTitle('Edited');
    expect(container.read(editorProvider).isDirty, isTrue);

    final getResult = await _pumpHarness(tester, container);
    await tester.tap(find.text('exit'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(getResult(), isFalse);
    expect(fake.writeCount, 0);
  });

  testWidgets('returns true and does NOT save when user picks Discard',
      (tester) async {
    final fake = _RecordingBookbinder(_book());
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/tmp/x.m4b');
    container.read(editorProvider.notifier).setTitle('Edited');

    final getResult = await _pumpHarness(tester, container);
    await tester.tap(find.text('exit'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Discard'));
    await tester.pumpAndSettle();

    expect(getResult(), isTrue);
    expect(fake.writeCount, 0);
  });

  testWidgets('returns true and saves once when user picks Save',
      (tester) async {
    final fake = _RecordingBookbinder(_book());
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/tmp/x.m4b');
    container.read(editorProvider.notifier).setTitle('Edited');

    final getResult = await _pumpHarness(tester, container);
    await tester.tap(find.text('exit'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(getResult(), isTrue);
    expect(fake.writeCount, 1);
    expect(fake.lastWritten?.title, 'Edited');
  });
}
