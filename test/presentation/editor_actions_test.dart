import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/bookbinder.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
import 'package:m4b_chapterizer/presentation/keyboard/editor_actions.dart';
import 'package:m4b_chapterizer/presentation/providers/editor_state.dart';

class _StubBookbinder implements Bookbinder {
  _StubBookbinder(this._book);
  final Audiobook _book;
  String? lastWritten;

  @override
  Future<Audiobook> read(String sourcePath) async => _book;

  @override
  Future<void> write({
    required String sourcePath,
    required String destinationPath,
    required Audiobook audiobook,
  }) async {
    lastWritten = destinationPath;
  }
}

/// Minimal host that exposes a `BuildContext` and a `WidgetRef` so we can
/// construct an `EditorActions`. The save() path uses neither showDialog nor
/// FilePicker, so the host can be a plain Container.
class _HarnessHost extends ConsumerWidget {
  const _HarnessHost(this.onReady);
  final void Function(BuildContext context, WidgetRef ref) onReady;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    onReady(context, ref);
    return const SizedBox.shrink();
  }
}

void main() {
  testWidgets('save() is a no-op when no audiobook is loaded', (tester) async {
    final fake = _StubBookbinder(Audiobook.validated(
      chapters: const [Chapter(title: 'C', start: Duration.zero)],
      totalDuration: const Duration(seconds: 10),
    ));
    late EditorActions actions;
    await tester.pumpWidget(ProviderScope(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
      child: MaterialApp(
        home: _HarnessHost((context, ref) {
          actions = EditorActions(context, ref);
        }),
      ),
    ));

    // No `open` was called — audiobook stays null. save() must not throw and
    // must not call write.
    await actions.save();
    expect(fake.lastWritten, isNull);
  });

  testWidgets('save() writes the audiobook back to its loaded path',
      (tester) async {
    final fake = _StubBookbinder(Audiobook.validated(
      title: 'Test',
      chapters: const [Chapter(title: 'C', start: Duration.zero)],
      totalDuration: const Duration(seconds: 10),
    ));
    late EditorActions actions;
    late WidgetRef ref0;
    await tester.pumpWidget(ProviderScope(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
      child: MaterialApp(
        home: _HarnessHost((context, ref) {
          actions = EditorActions(context, ref);
          ref0 = ref;
        }),
      ),
    ));

    await ref0.read(editorProvider.notifier).open('/tmp/sample.m4b');
    ref0.read(editorProvider.notifier).setTitle('Edited');
    await actions.save();
    expect(fake.lastWritten, '/tmp/sample.m4b');
    expect(ref0.read(editorProvider).isDirty, isFalse);
  });
}
