import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/presentation/dialogs/unsaved_changes_dialog.dart';

/// Pumps a harness that opens the dialog. Returns a getter the test can
/// call after dismissing the dialog to read the captured decision.
Future<UnsavedChangesDecision? Function()> _show(WidgetTester tester) async {
  UnsavedChangesDecision? result;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await showUnsavedChangesDialog(context);
          },
          child: const Text('go'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('go'));
  await tester.pump();
  return () => result;
}

void main() {
  test('UnsavedChangesDecision values are exhaustive', () {
    expect(UnsavedChangesDecision.values, [
      UnsavedChangesDecision.cancel,
      UnsavedChangesDecision.discard,
      UnsavedChangesDecision.save,
    ]);
  });

  testWidgets('Cancel button returns cancel', (tester) async {
    final getResult = await _show(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(getResult(), UnsavedChangesDecision.cancel);
  });

  testWidgets('Discard button returns discard', (tester) async {
    final getResult = await _show(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Discard'));
    await tester.pumpAndSettle();
    expect(getResult(), UnsavedChangesDecision.discard);
  });

  testWidgets('Save button returns save', (tester) async {
    final getResult = await _show(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(getResult(), UnsavedChangesDecision.save);
  });
}
